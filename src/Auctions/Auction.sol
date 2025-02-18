// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import {Maths} from "../libraries/Maths.sol";
import {ITaker} from "../interfaces/ITaker.sol";
import {GPv2Order} from "../libraries/GPv2Order.sol";
import {Governance2Step} from "../utils/Governance2Step.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

interface ICowSettlement {
    function domainSeparator() external view returns (bytes32);
}

/**
 *   @title Auction
 *   @author yearn.fi
 *   @notice General use dutch auction contract for token sales.
 */
contract Auction is Governance2Step, ReentrancyGuard {
    using GPv2Order for GPv2Order.Data;
    using SafeERC20 for ERC20;

    /// @notice Emitted when a new auction is enabled
    event AuctionEnabled(address indexed from, address indexed to);

    /// @notice Emitted when an auction is disabled.
    event AuctionDisabled(address indexed from, address indexed to);

    /// @notice Emitted when auction has been kicked.
    event AuctionKicked(address indexed from, uint256 available);

    /// @notice Emitted when the starting price is updated.
    event UpdatedStartingPrice(uint256 startingPrice);

    /// @dev Store address and scaler in one slot.
    struct TokenInfo {
        address tokenAddress;
        uint96 scaler;
    }

    /// @notice Store all the auction specific information.
    struct AuctionInfo {
        uint64 kicked;
        uint64 scaler;
        uint128 initialAvailable;
    }

    uint256 internal constant WAD = 1e18;

    /// @notice Used for the price decay.
    uint256 internal constant MINUTE_HALF_LIFE =
        0.988514020352896135_356867505 * 1e27; // 0.5^(1/60)

    address internal constant COW_SETTLEMENT =
        0x9008D19f58AAbD9eD0D60971565AA8510560ab41;

    address internal constant VAULT_RELAYER =
        0xC92E8bdf79f0507f65a392b0ab4667716BFE0110;

    bytes32 internal immutable COW_DOMAIN_SEPARATOR;

    /// @notice Struct to hold the info for `want`.
    TokenInfo internal wantInfo;

    /// @notice The address that will receive the funds in the auction.
    address public receiver;

    /// @notice The amount to start the auction at.
    uint256 public startingPrice;

    /// @notice The time that each auction lasts.
    uint256 public auctionLength;

    /// @notice Mapping from `from` token to its struct.
    mapping(address => AuctionInfo) public auctions;

    /// @notice Array of all the enabled auction for this contract.
    address[] public enabledAuctions;

    constructor() Governance2Step(msg.sender) {
        bytes32 domainSeparator;
        if (COW_SETTLEMENT.code.length > 0) {
            domainSeparator = ICowSettlement(COW_SETTLEMENT).domainSeparator();
        } else {
            domainSeparator = bytes32(0);
        }

        COW_DOMAIN_SEPARATOR = domainSeparator;
    }

    /**
     * @notice Initializes the Auction contract with initial parameters.
     * @param _want Address this auction is selling to.
     * @param _receiver Address that will receive the funds from the auction.
     * @param _governance Address of the contract governance.
     * @param _auctionLength Duration of each auction in seconds.
     * @param _startingPrice Starting price for each auction.
     */
    function initialize(
        address _want,
        address _receiver,
        address _governance,
        uint256 _auctionLength,
        uint256 _startingPrice
    ) public virtual {
        require(auctionLength == 0, "initialized");
        require(_want != address(0), "ZERO ADDRESS");
        require(_auctionLength != 0, "length");
        require(_startingPrice != 0, "starting price");
        require(_receiver != address(0), "receiver");
        // Cannot have more than 18 decimals.
        uint256 decimals = ERC20(_want).decimals();
        require(decimals <= 18, "unsupported decimals");

        // Set variables
        wantInfo = TokenInfo({
            tokenAddress: _want,
            scaler: uint96(WAD / 10 ** decimals)
        });

        receiver = _receiver;
        governance = _governance;
        auctionLength = _auctionLength;
        startingPrice = _startingPrice;
        emit UpdatedStartingPrice(_startingPrice);
    }

    /*//////////////////////////////////////////////////////////////
                         VIEW METHODS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get the address of this auctions want token.
     * @return . The want token.
     */
    function want() public view virtual returns (address) {
        return wantInfo.tokenAddress;
    }

    /**
     * @notice Get the available amount for the auction.
     * @param _from The address of the token to be auctioned.
     * @return . The available amount for the auction.
     */
    function available(address _from) public view virtual returns (uint256) {
        if (!isActive(_from)) return 0;

        return
            Maths.min(
                auctions[_from].initialAvailable,
                ERC20(_from).balanceOf(address(this))
            );
    }

    /**
     * @notice Get the kicked timestamp for the auction.
     * @param _from The address of the token to be auctioned.
     * @return . The kicked timestamp for the auction.
     */
    function kicked(address _from) external view virtual returns (uint256) {
        return auctions[_from].kicked;
    }

    /**
     * @notice Check if the auction is active.
     * @param _from The address of the token to be auctioned.
     * @return . Whether the auction is active.
     */
    function isActive(address _from) public view virtual returns (bool) {
        return auctions[_from].kicked + auctionLength >= block.timestamp;
    }

    /**
     * @notice Get all the enabled auctions.
     */
    function getAllEnabledAuctions()
        external
        view
        virtual
        returns (address[] memory)
    {
        return enabledAuctions;
    }

    /**
     * @notice Get the pending amount available for the next auction.
     * @dev Defaults to the auctions balance of the from token if no hook.
     * @param _from The address of the token to be auctioned.
     * @return uint256 The amount that can be kicked into the auction.
     */
    function kickable(address _from) external view virtual returns (uint256) {
        // If not enough time has passed then `kickable` is 0.
        if (isActive(_from)) return 0;

        // Use the full balance of this contract.
        return ERC20(_from).balanceOf(address(this));
    }

    /**
     * @notice Gets the amount of `want` needed to buy the available amount of `from`.
     * @param _from The address of the token to be auctioned.
     * @return . The amount of `want` needed to fulfill the take amount.
     */
    function getAmountNeeded(
        address _from
    ) external view virtual returns (uint256) {
        return
            _getAmountNeeded(
                auctions[_from],
                available(_from),
                block.timestamp
            );
    }

    /**
     * @notice Gets the amount of `want` needed to buy a specific amount of `from`.
     * @param _from The address of the token to be auctioned.
     * @param _amountToTake The amount of `from` to take in the auction.
     * @return . The amount of `want` needed to fulfill the take amount.
     */
    function getAmountNeeded(
        address _from,
        uint256 _amountToTake
    ) external view virtual returns (uint256) {
        return
            _getAmountNeeded(auctions[_from], _amountToTake, block.timestamp);
    }

    /**
     * @notice Gets the amount of `want` needed to buy a specific amount of `from` at a specific timestamp.
     * @param _from The address of the token to be auctioned.
     * @param _amountToTake The amount `from` to take in the auction.
     * @param _timestamp The specific timestamp for calculating the amount needed.
     * @return . The amount of `want` needed to fulfill the take amount.
     */
    function getAmountNeeded(
        address _from,
        uint256 _amountToTake,
        uint256 _timestamp
    ) external view virtual returns (uint256) {
        return _getAmountNeeded(auctions[_from], _amountToTake, _timestamp);
    }

    /**
     * @dev Return the amount of `want` needed to buy `_amountToTake`.
     */
    function _getAmountNeeded(
        AuctionInfo memory _auction,
        uint256 _amountToTake,
        uint256 _timestamp
    ) internal view virtual returns (uint256) {
        return
            // Scale _amountToTake to 1e18
            (_amountToTake *
                _auction.scaler *
                // Price is always 1e18
                _price(
                    _auction.kicked,
                    _auction.initialAvailable * _auction.scaler,
                    _timestamp
                )) /
            1e18 /
            // Scale back down to want.
            wantInfo.scaler;
    }

    /**
     * @notice Gets the price of the auction at the current timestamp.
     * @param _from The address of the token to be auctioned.
     * @return . The price of the auction.
     */
    function price(address _from) external view virtual returns (uint256) {
        return price(_from, block.timestamp);
    }

    /**
     * @notice Gets the price of the auction at a specific timestamp.
     * @param _from The address of the token to be auctioned.
     * @param _timestamp The specific timestamp for calculating the price.
     * @return . The price of the auction.
     */
    function price(
        address _from,
        uint256 _timestamp
    ) public view virtual returns (uint256) {
        // Get unscaled price and scale it down.
        return
            _price(
                auctions[_from].kicked,
                auctions[_from].initialAvailable * auctions[_from].scaler,
                _timestamp
            ) / wantInfo.scaler;
    }

    /**
     * @dev Internal function to calculate the scaled price based on auction parameters.
     * @param _kicked The timestamp the auction was kicked.
     * @param _available The initial available amount scaled 1e18.
     * @param _timestamp The specific timestamp for calculating the price.
     * @return . The calculated price scaled to 1e18.
     */
    function _price(
        uint256 _kicked,
        uint256 _available,
        uint256 _timestamp
    ) internal view virtual returns (uint256) {
        if (_available == 0) return 0;

        uint256 secondsElapsed = _timestamp - _kicked;

        if (secondsElapsed > auctionLength) return 0;

        // Exponential step decay from https://github.com/ajna-finance/ajna-core/blob/master/src/libraries/helpers/PoolHelper.sol
        uint256 hoursComponent = 1e27 >> (secondsElapsed / 3600);
        uint256 minutesComponent = Maths.rpow(
            MINUTE_HALF_LIFE,
            (secondsElapsed % 3600) / 60
        );
        uint256 initialPrice = Maths.wdiv(startingPrice * 1e18, _available);

        return
            (initialPrice * Maths.rmul(hoursComponent, minutesComponent)) /
            1e27;
    }

    /*//////////////////////////////////////////////////////////////
                            SETTERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Enables a new auction.
     * @param _from The address of the token to be auctioned.
     */
    function enable(address _from) external virtual onlyGovernance {
        address _want = want();
        require(_from != address(0) && _from != _want, "ZERO ADDRESS");
        require(auctions[_from].scaler == 0, "already enabled");

        // Cannot have more than 18 decimals.
        uint256 decimals = ERC20(_from).decimals();
        require(decimals <= 18, "unsupported decimals");

        // Store all needed info.
        auctions[_from].scaler = uint64(WAD / 10 ** decimals);

        ERC20(_from).safeApprove(VAULT_RELAYER, type(uint256).max);

        // Add to the array.
        enabledAuctions.push(_from);

        emit AuctionEnabled(_from, _want);
    }

    /**
     * @notice Disables an existing auction.
     * @dev Only callable by governance.
     * @param _from The address of the token being sold.
     */
    function disable(address _from) external virtual {
        disable(_from, 0);
    }

    /**
     * @notice Disables an existing auction.
     * @dev Only callable by governance.
     * @param _from The address of the token being sold.
     * @param _index The index the auctionId is at in the array.
     */
    function disable(
        address _from,
        uint256 _index
    ) public virtual onlyGovernance {
        // Make sure the auction was enabled.
        require(auctions[_from].scaler != 0, "not enabled");

        // Remove the struct.
        delete auctions[_from];

        ERC20(_from).safeApprove(VAULT_RELAYER, 0);

        // Remove the auction ID from the array.
        address[] memory _enabledAuctions = enabledAuctions;
        if (_enabledAuctions[_index] != _from) {
            // If the _index given is not the id find it.
            for (uint256 i = 0; i < _enabledAuctions.length; ++i) {
                if (_enabledAuctions[i] == _from) {
                    _index = i;
                    break;
                }
            }
        }

        // Move the id to the last spot if not there.
        if (_index < _enabledAuctions.length - 1) {
            _enabledAuctions[_index] = _enabledAuctions[
                _enabledAuctions.length - 1
            ];
            // Update the array.
            enabledAuctions = _enabledAuctions;
        }

        // Pop the id off the array.
        enabledAuctions.pop();

        emit AuctionDisabled(_from, want());
    }

    /**
     * @notice Sets the starting price for the auction.
     * @param _startingPrice The new starting price for the auction.
     */
    function setStartingPrice(
        uint256 _startingPrice
    ) external virtual onlyGovernance {
        require(_startingPrice != 0, "starting price");

        // Don't change the price when an auction is active.
        address[] memory _enabledAuctions = enabledAuctions;
        for (uint256 i = 0; i < _enabledAuctions.length; ++i) {
            require(!isActive(_enabledAuctions[i]), "active auction");
        }

        startingPrice = _startingPrice;

        emit UpdatedStartingPrice(_startingPrice);
    }

    /*//////////////////////////////////////////////////////////////
                      PARTICIPATE IN AUCTION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Kicks off an auction, updating its status and making funds available for bidding.
     * @param _from The address of the token to be auctioned.
     * @return _available The available amount for bidding on in the auction.
     */
    function kick(
        address _from
    ) external virtual nonReentrant returns (uint256 _available) {
        require(auctions[_from].scaler != 0, "not enabled");
        require(
            block.timestamp > auctions[_from].kicked + auctionLength,
            "too soon"
        );

        // Just use current balance.
        _available = ERC20(_from).balanceOf(address(this));

        require(_available != 0, "nothing to kick");

        // Update the auctions status.
        auctions[_from].kicked = uint64(block.timestamp);
        auctions[_from].initialAvailable = uint128(_available);

        emit AuctionKicked(_from, _available);
    }

    /**
     * @notice Take the token being sold in a live auction.
     * @dev Defaults to taking the full amount and sending to the msg sender.
     * @param _from The address of the token to be auctioned.
     * @return . The amount of fromToken taken in the auction.
     */
    function take(address _from) external virtual returns (uint256) {
        return _take(_from, type(uint256).max, msg.sender, new bytes(0));
    }

    /**
     * @notice Take the token being sold in a live auction with a specified maximum amount.
     * @dev Will send the funds to the msg sender.
     * @param _from The address of the token to be auctioned.
     * @param _maxAmount The maximum amount of fromToken to take in the auction.
     * @return . The amount of fromToken taken in the auction.
     */
    function take(
        address _from,
        uint256 _maxAmount
    ) external virtual returns (uint256) {
        return _take(_from, _maxAmount, msg.sender, new bytes(0));
    }

    /**
     * @notice Take the token being sold in a live auction.
     * @param _from The address of the token to be auctioned.
     * @param _maxAmount The maximum amount of fromToken to take in the auction.
     * @param _receiver The address that will receive the fromToken.
     * @return _amountTaken The amount of fromToken taken in the auction.
     */
    function take(
        address _from,
        uint256 _maxAmount,
        address _receiver
    ) external virtual returns (uint256) {
        return _take(_from, _maxAmount, _receiver, new bytes(0));
    }

    /**
     * @notice Take the token being sold in a live auction.
     * @param _from The address of the token to be auctioned.
     * @param _maxAmount The maximum amount of fromToken to take in the auction.
     * @param _receiver The address that will receive the fromToken.
     * @param _data The data signify the callback should be used and sent with it.
     * @return _amountTaken The amount of fromToken taken in the auction.
     */
    function take(
        address _from,
        uint256 _maxAmount,
        address _receiver,
        bytes calldata _data
    ) external virtual returns (uint256) {
        return _take(_from, _maxAmount, _receiver, _data);
    }

    /// @dev Implements the take of the auction.
    function _take(
        address _from,
        uint256 _maxAmount,
        address _receiver,
        bytes memory _data
    ) internal virtual nonReentrant returns (uint256 _amountTaken) {
        AuctionInfo memory auction = auctions[_from];
        // Make sure the auction is active.
        require(
            auction.kicked + auctionLength >= block.timestamp,
            "not kicked"
        );

        // Max amount that can be taken.
        uint256 _available = available(_from);
        _amountTaken = _available > _maxAmount ? _maxAmount : _available;

        // Get the amount needed
        uint256 needed = _getAmountNeeded(
            auction,
            _amountTaken,
            block.timestamp
        );

        require(needed != 0, "zero needed");

        // Send `from`.
        ERC20(_from).safeTransfer(_receiver, _amountTaken);

        // If the caller has specified data.
        if (_data.length != 0) {
            // Do the callback.
            ITaker(_receiver).auctionTakeCallback(
                _from,
                msg.sender,
                _amountTaken,
                needed,
                _data
            );
        }

        // Cache the want address.
        address _want = want();

        // Pull `want`.
        ERC20(_want).safeTransferFrom(msg.sender, receiver, needed);
    }

    /// @dev Validates a COW order signature.
    function isValidSignature(
        bytes32 _hash,
        bytes calldata signature
    ) external view returns (bytes4) {
        // Make sure `_take` has not already been entered.
        require(!_reentrancyGuardEntered(), "ReentrancyGuard: reentrant call");

        // Decode the signature to get the order.
        GPv2Order.Data memory order = abi.decode(signature, (GPv2Order.Data));

        AuctionInfo memory auction = auctions[address(order.sellToken)];

        // Get the current amount needed for the auction.
        uint256 paymentAmount = _getAmountNeeded(
            auction,
            order.sellAmount,
            block.timestamp
        );

        // Verify the order details.
        require(_hash == order.hash(COW_DOMAIN_SEPARATOR), "bad order");
        require(paymentAmount != 0, "zero amount");
        require(available(address(order.sellToken)) != 0, "zero available");
        require(order.feeAmount == 0, "fee");
        require(order.partiallyFillable, "partial fill");
        require(order.validTo < auction.kicked + auctionLength, "expired");
        require(order.appData == bytes32(0), "app data");
        require(order.buyAmount >= paymentAmount, "bad price");
        require(address(order.buyToken) == want(), "bad token");
        require(order.receiver == receiver, "bad receiver");
        require(order.sellAmount <= auction.initialAvailable, "bad amount");

        // If all checks pass, return the magic value
        return this.isValidSignature.selector;
    }

    /**
     * @notice Allows the auction to be stopped if the full amount is taken.
     * @param _from The address of the token to be auctioned.
     */
    function settle(address _from) external virtual {
        require(isActive(_from), "!active");
        require(ERC20(_from).balanceOf(address(this)) == 0, "!empty");

        auctions[_from].kicked = uint64(0);
    }

    function sweep(address _token) external virtual onlyGovernance {
        ERC20(_token).safeTransfer(
            msg.sender,
            ERC20(_token).balanceOf(address(this))
        );
    }
}
