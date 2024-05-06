// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import {Maths} from "../../libraries/Maths.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {ITaker} from "../../interfaces/ITaker.sol";
import {BaseHealthCheck} from "../HealthCheck/BaseHealthCheck.sol";

/**
 *   @title Base Auctioneer
 *   @author yearn.fi
 *   @notice General use dutch auction contract for token sales.
 */
abstract contract BaseAuctioneer is BaseHealthCheck, ReentrancyGuard {
    using SafeERC20 for ERC20;

    /// @notice Emitted when a new auction is enabled
    event AuctionEnabled(
        bytes32 auctionId,
        address indexed from,
        address indexed to,
        address indexed auctionAddress
    );

    /// @notice Emitted when an auction is disabled.
    event AuctionDisabled(
        bytes32 auctionId,
        address indexed from,
        address indexed to,
        address indexed auctionAddress
    );

    /// @notice Emitted when auction has been kicked.
    event AuctionKicked(bytes32 auctionId, uint256 available);

    /// @notice Emitted when any amount of an active auction was taken.
    event AuctionTaken(
        bytes32 auctionId,
        uint256 amountTaken,
        uint256 amountLeft
    );

    /// @dev Store address and scaler in one slot.
    struct TokenInfo {
        address tokenAddress;
        uint96 scaler;
    }

    /// @notice Store all the auction specific information.
    struct AuctionInfo {
        TokenInfo fromInfo;
        uint96 kicked;
        uint128 initialAvailable;
        uint128 currentAvailable;
    }

    uint256 internal constant WAD = 1e18;

    /// @notice Used for the price decay.
    uint256 internal constant MINUTE_HALF_LIFE =
        0.988514020352896135_356867505 * 1e27; // 0.5^(1/60)

    /// @notice Struct to hold the info for `auctionWant`.
    TokenInfo internal auctionWantInfo;

    /// @notice Mapping from an auction ID to its struct.
    mapping(bytes32 => AuctionInfo) public auctions;

    /// @notice Array of all the enabled auction for this contract.
    bytes32[] public enabledAuctions;

    /// @notice The amount to start the auction at.
    uint256 public auctionStartingPrice;

    /// @notice The time that each auction lasts.
    uint32 public auctionLength;

    /// @notice The minimum time to wait between auction 'kicks'.
    uint32 public auctionCooldown;

    /**
     * @notice Initializes the Auction contract with initial parameters.
     * @param _auctionWant Address this auction is selling to.
     * @param _auctionLength Duration of each auction in seconds.
     * @param _auctionCooldown Cooldown period between auctions in seconds.
     * @param _auctionStartingPrice Starting price for each auction.
     */
    constructor(
        address _asset,
        string memory _name,
        address _auctionWant,
        uint32 _auctionLength,
        uint32 _auctionCooldown,
        uint256 _auctionStartingPrice
    ) BaseHealthCheck(_asset, _name) {
        require(auctionLength == 0, "initialized");
        require(_auctionWant != address(0), "ZERO ADDRESS");
        require(_auctionLength != 0, "length");
        require(_auctionLength <= _auctionCooldown, "cooldown");
        require(_auctionStartingPrice != 0, "starting price");

        // Cannot have more than 18 decimals.
        uint256 decimals = ERC20(_auctionWant).decimals();
        require(decimals <= 18, "unsupported decimals");

        // Set variables
        auctionWantInfo = TokenInfo({
            tokenAddress: _auctionWant,
            scaler: uint96(WAD / 10 ** decimals)
        });

        auctionLength = _auctionLength;
        auctionCooldown = _auctionCooldown;
        auctionStartingPrice = _auctionStartingPrice;
    }

    /*//////////////////////////////////////////////////////////////
                         VIEW METHODS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get the address of this auctions want token.
     * @return . The want token.
     */
    function auctionWant() public view virtual returns (address) {
        return auctionWantInfo.tokenAddress;
    }

    /**
     * @notice Get the length of the enabled auctions array.
     */
    function numberOfEnabledAuctions() external view virtual returns (uint256) {
        return enabledAuctions.length;
    }

    /**
     * @notice Get the unique auction identifier.
     * @param _from The address of the token to sell.
     * @return bytes32 A unique auction identifier.
     */
    function getAuctionId(address _from) public view virtual returns (bytes32) {
        return keccak256(abi.encodePacked(_from, auctionWant(), address(this)));
    }

    /**
     * @notice Retrieves information about a specific auction.
     * @param _auctionId The unique identifier of the auction.
     * @return _from The address of the token to sell.
     * @return _to The address of the token to buy.
     * @return _kicked The timestamp of the last kick.
     * @return _available The current available amount for the auction.
     */
    function auctionInfo(
        bytes32 _auctionId
    )
        public
        view
        virtual
        returns (
            address _from,
            address _to,
            uint256 _kicked,
            uint256 _available
        )
    {
        AuctionInfo memory auction = auctions[_auctionId];

        return (
            auction.fromInfo.tokenAddress,
            auctionWant(),
            auction.kicked,
            auction.kicked + uint256(auctionLength) > block.timestamp
                ? auction.currentAvailable
                : 0
        );
    }

    /**
     * @notice Get the pending amount available for the next auction.
     * @dev Defaults to the auctions balance of the from token if no hook.
     * @param _auctionId The unique identifier of the auction.
     * @return uint256 The amount that can be kicked into the auction.
     */
    function kickable(
        bytes32 _auctionId
    ) public view virtual returns (uint256) {
        // If not enough time has passed then `kickable` is 0.
        if (
            auctions[_auctionId].kicked + uint256(auctionCooldown) >
            block.timestamp
        ) {
            return 0;
        }

        return _kickable(auctions[_auctionId].fromInfo.tokenAddress);
    }

    /**
     * @notice Gets the amount of `auctionWant` needed to buy a specific amount of `from`.
     * @param _auctionId The unique identifier of the auction.
     * @param _amountToTake The amount of `from` to take in the auction.
     * @return . The amount of `auctionWant` needed to fulfill the take amount.
     */
    function getAmountNeeded(
        bytes32 _auctionId,
        uint256 _amountToTake
    ) external view virtual returns (uint256) {
        return
            _getAmountNeeded(
                auctions[_auctionId],
                _amountToTake,
                block.timestamp
            );
    }

    /**
     * @notice Gets the amount of `auctionWant` needed to buy a specific amount of `from` at a specific timestamp.
     * @param _auctionId The unique identifier of the auction.
     * @param _amountToTake The amount `from` to take in the auction.
     * @param _timestamp The specific timestamp for calculating the amount needed.
     * @return . The amount of `auctionWant` needed to fulfill the take amount.
     */
    function getAmountNeeded(
        bytes32 _auctionId,
        uint256 _amountToTake,
        uint256 _timestamp
    ) external view virtual returns (uint256) {
        return
            _getAmountNeeded(auctions[_auctionId], _amountToTake, _timestamp);
    }

    /**
     * @dev Return the amount of `auctionWant` needed to buy `_amountToTake`.
     */
    function _getAmountNeeded(
        AuctionInfo memory _auction,
        uint256 _amountToTake,
        uint256 _timestamp
    ) internal view virtual returns (uint256) {
        return
            // Scale _amountToTake to 1e18
            (_amountToTake *
                _auction.fromInfo.scaler *
                // Price is always 1e18
                _price(
                    _auction.kicked,
                    _auction.initialAvailable * _auction.fromInfo.scaler,
                    _timestamp
                )) /
            1e18 /
            // Scale back down to auctionWant.
            auctionWantInfo.scaler;
    }

    /**
     * @notice Gets the price of the auction at the current timestamp.
     * @param _auctionId The unique identifier of the auction.
     * @return . The price of the auction.
     */
    function price(bytes32 _auctionId) external view virtual returns (uint256) {
        return price(_auctionId, block.timestamp);
    }

    /**
     * @notice Gets the price of the auction at a specific timestamp.
     * @param _auctionId The unique identifier of the auction.
     * @param _timestamp The specific timestamp for calculating the price.
     * @return . The price of the auction.
     */
    function price(
        bytes32 _auctionId,
        uint256 _timestamp
    ) public view virtual returns (uint256) {
        // Get unscaled price and scale it down.
        return
            _price(
                auctions[_auctionId].kicked,
                auctions[_auctionId].initialAvailable *
                    auctions[_auctionId].fromInfo.scaler,
                _timestamp
            ) / auctionWantInfo.scaler;
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

        // Exponential decay from https://github.com/ajna-finance/ajna-core/blob/master/src/libraries/helpers/PoolHelper.sol
        uint256 hoursComponent = 1e27 >> (secondsElapsed / 3600);
        uint256 minutesComponent = Maths.rpow(
            MINUTE_HALF_LIFE,
            (secondsElapsed % 3600) / 60
        );
        uint256 initialPrice = Maths.wdiv(
            auctionStartingPrice * 1e18,
            _available
        );

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
     * @return _auctionId The unique identifier of the enabled auction.
     */
    function enableAuction(
        address _from
    ) public virtual onlyManagement returns (bytes32 _auctionId) {
        address _auctionWant = auctionWant();
        require(_from != address(0) && _from != _auctionWant, "ZERO ADDRESS");
        // Cannot have more than 18 decimals.
        uint256 decimals = ERC20(_from).decimals();
        require(decimals <= 18, "unsupported decimals");

        // Calculate the id.
        _auctionId = getAuctionId(_from);

        require(
            auctions[_auctionId].fromInfo.tokenAddress == address(0),
            "already enabled"
        );

        // Store all needed info.
        auctions[_auctionId].fromInfo = TokenInfo({
            tokenAddress: _from,
            scaler: uint96(WAD / 10 ** decimals)
        });

        // Add to the array.
        enabledAuctions.push(_auctionId);

        emit AuctionEnabled(_auctionId, _from, _auctionWant, address(this));
    }

    /**
     * @notice Disables an existing auction.
     * @dev Only callable by governance.
     * @param _from The address of the token being sold.
     */
    function disableAuction(address _from) external virtual {
        disableAuction(_from, 0);
    }

    /**
     * @notice Disables an existing auction.
     * @dev Only callable by governance.
     * @param _from The address of the token being sold.
     * @param _index The index the auctionId is at in the array.
     */
    function disableAuction(
        address _from,
        uint256 _index
    ) public virtual onlyEmergencyAuthorized {
        bytes32 _auctionId = getAuctionId(_from);

        // Make sure the auction was enabled.
        require(
            auctions[_auctionId].fromInfo.tokenAddress != address(0),
            "not enabled"
        );

        // Remove the struct.
        delete auctions[_auctionId];

        // Remove the auction ID from the array.
        bytes32[] memory _enabledAuctions = enabledAuctions;
        if (_enabledAuctions[_index] != _auctionId) {
            // If the _index given is not the id find it.
            for (uint256 i = 0; i < _enabledAuctions.length; ++i) {
                if (_enabledAuctions[i] == _auctionId) {
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

        emit AuctionDisabled(_auctionId, _from, auctionWant(), address(this));
    }

    /*//////////////////////////////////////////////////////////////
                      PARTICIPATE IN AUCTION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Kicks off an auction, updating its status and making funds available for bidding.
     * @param _auctionId The unique identifier of the auction.
     * @return available The available amount for bidding on in the auction.
     */
    function kick(
        bytes32 _auctionId
    ) external virtual nonReentrant returns (uint256 available) {
        address _fromToken = auctions[_auctionId].fromInfo.tokenAddress;
        require(_fromToken != address(0), "not enabled");
        require(
            block.timestamp >
                auctions[_auctionId].kicked + uint256(auctionCooldown),
            "too soon"
        );

        available = _auctionKicked(_fromToken);

        require(available != 0, "nothing to kick");

        // Update the auctions status.
        auctions[_auctionId].kicked = uint96(block.timestamp);
        auctions[_auctionId].initialAvailable = uint128(available);
        auctions[_auctionId].currentAvailable = uint128(available);

        emit AuctionKicked(_auctionId, available);
    }

    /**
     * @notice Take the token being sold in a live auction.
     * @dev Defaults to taking the full amount and sending to the msg sender.
     * @param _auctionId The unique identifier of the auction.
     * @return . The amount of fromToken taken in the auction.
     */
    function take(bytes32 _auctionId) external virtual returns (uint256) {
        return _take(_auctionId, type(uint256).max, msg.sender, new bytes(0));
    }

    /**
     * @notice Take the token being sold in a live auction with a specified maximum amount.
     * @dev Uses the sender's address as the receiver.
     * @param _auctionId The unique identifier of the auction.
     * @param _maxAmount The maximum amount of fromToken to take in the auction.
     * @return . The amount of fromToken taken in the auction.
     */
    function take(
        bytes32 _auctionId,
        uint256 _maxAmount
    ) external virtual returns (uint256) {
        return _take(_auctionId, _maxAmount, msg.sender, new bytes(0));
    }

    /**
     * @notice Take the token being sold in a live auction.
     * @param _auctionId The unique identifier of the auction.
     * @param _maxAmount The maximum amount of fromToken to take in the auction.
     * @param _receiver The address that will receive the fromToken.
     * @return _amountTaken The amount of fromToken taken in the auction.
     */
    function take(
        bytes32 _auctionId,
        uint256 _maxAmount,
        address _receiver
    ) external virtual returns (uint256) {
        return _take(_auctionId, _maxAmount, _receiver, new bytes(0));
    }

    /**
     * @notice Take the token being sold in a live auction.
     * @param _auctionId The unique identifier of the auction.
     * @param _maxAmount The maximum amount of fromToken to take in the auction.
     * @param _receiver The address that will receive the fromToken.
     * @param _data The data signify the callback should be used and sent with it.
     * @return _amountTaken The amount of fromToken taken in the auction.
     */
    function take(
        bytes32 _auctionId,
        uint256 _maxAmount,
        address _receiver,
        bytes calldata _data
    ) external virtual returns (uint256) {
        return _take(_auctionId, _maxAmount, _receiver, _data);
    }

    /// @dev Implements the take of the auction.
    function _take(
        bytes32 _auctionId,
        uint256 _maxAmount,
        address _receiver,
        bytes memory _data
    ) internal virtual nonReentrant returns (uint256 _amountTaken) {
        AuctionInfo memory auction = auctions[_auctionId];
        // Make sure the auction is active.
        require(
            auction.kicked + uint256(auctionLength) >= block.timestamp,
            "not kicked"
        );

        // Max amount that can be taken.
        _amountTaken = auction.currentAvailable > _maxAmount
            ? _maxAmount
            : auction.currentAvailable;

        // Get the amount needed
        uint256 needed = _getAmountNeeded(
            auction,
            _amountTaken,
            block.timestamp
        );

        require(needed != 0, "zero needed");

        // How much is left in this auction.
        uint256 left;
        unchecked {
            left = auction.currentAvailable - _amountTaken;
        }
        auctions[_auctionId].currentAvailable = uint128(left);

        _preTake(auction.fromInfo.tokenAddress, _amountTaken, needed);

        // Send `from`.
        ERC20(auction.fromInfo.tokenAddress).safeTransfer(
            _receiver,
            _amountTaken
        );

        // If the caller has specified data.
        if (_data.length != 0) {
            // Do the callback.
            ITaker(_receiver).auctionTakeCallback(
                _auctionId,
                msg.sender,
                _amountTaken,
                needed,
                _data
            );
        }

        // Cache the auctionWant address.
        address _auctionWant = auctionWant();

        // Pull `auctionWant`.
        ERC20(_auctionWant).safeTransferFrom(msg.sender, address(this), needed);

        _postTake(_auctionWant, _amountTaken, needed);

        emit AuctionTaken(_auctionId, _amountTaken, left);
    }

    /**
     * @notice Return how much `_token` could currently be kicked into auction.
     * @dev This can be overridden by a strategist to implement custom logic.
     * @param _token Address of the `_from` token.
     * @return . The amount of `_token` ready to be auctioned off.
     */
    function _kickable(address _token) internal view virtual returns (uint256) {
        return ERC20(_token).balanceOf(address(this));
    }

    /**
     * @dev To override if something other than just sending the loose balance
     *  of `_token` to the auction is desired, such as accruing and and claiming rewards.
     *
     * @param _token Address of the token being auctioned off
     */
    function _auctionKicked(address _token) internal virtual returns (uint256) {
        return ERC20(_token).balanceOf(address(this));
    }

    /**
     * @dev To override if something needs to be done before a take is completed.
     *   This can be used if the auctioned token only will be freed up when a `take`
     *   occurs.
     * @param _token Address of the token being taken.
     * @param _amountToTake Amount of `_token` needed.
     * @param _amountToPay Amount of `auctionWant` that will be payed.
     */
    function _preTake(
        address _token,
        uint256 _amountToTake,
        uint256 _amountToPay
    ) internal virtual {}

    /**
     * @dev To override if a post take action is desired.
     *
     * This could be used to re-deploy the bought token back into the yield source,
     * or in conjunction with {_preTake} to check that the price sold at was within
     * some allowed range.
     *
     * @param _token Address of the token that the strategy was sent.
     * @param _amountTaken Amount of the from token taken.
     * @param _amountPayed Amount of `_token` that was sent to the strategy.
     */
    function _postTake(
        address _token,
        uint256 _amountTaken,
        uint256 _amountPayed
    ) internal virtual {}
}
