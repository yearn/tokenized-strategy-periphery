// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

import {Maths} from "../libraries/Maths.sol";
import {Governance} from "../utils/Governance.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface IHook {
    function kickable(address _fromToken) external view returns (uint256);

    function auctionKicked(address _fromToken) external returns (uint256);

    function preTake(address _fromToken, uint256 _amountToTake) external;

    function postTake(address _toToken, uint256 _newAmount) external;
}

contract Auction is Governance {
    using SafeERC20 for ERC20;

    event AuctionEnabled(
        bytes32 auctionId,
        address indexed from,
        address indexed to,
        address indexed strategy
    );

    event AuctionDisabled(
        bytes32 auctionId,
        address indexed from,
        address indexed to,
        address indexed strategy
    );

    event AuctionKicked(bytes32 auctionId, uint256 available);

    event AuctionTaken(
        bytes32 auctionId,
        uint256 amountTaken,
        uint256 amountLeft
    );

    struct AuctionInfo {
        address fromToken;
        uint96 fromScaler;
        address toToken;
        uint96 toScaler;
        uint256 kicked;
        uint256 initialAvailable;
        uint256 currentAvailable;
        uint256 minimumPrice;
        address receiver;
    }

    uint256 internal constant WAD = 1e18;

    /// @notice Used for the price decay.
    uint256 constant MINUTE_HALF_LIFE = 0.988514020352896135_356867505 * 1e27; // 0.5^(1/60)

    /// @notice Contract to call during write functions.
    address public hook;

    /// @notice The amount to start the auction at.
    uint256 public startingPrice;

    /// @notice The time that each auction lasts.
    uint256 public auctionLength;

    /// @notice The minimum time to wait between auction 'kicks'.
    uint256 public auctionCooldown;

    /// @notice Mapping from an auction ID to its struct.
    mapping(bytes32 => AuctionInfo) public auctions;

    // Original deployment does nothing.
    constructor() Governance(msg.sender) {
        auctionLength = 1;
    }

    /**
     * @notice Initializes the Auction contract with initial parameters.
     * @param _governance Address of the contract governance.
     * @param _auctionLength Duration of each auction in seconds.
     * @param _auctionCooldown Cooldown period between auctions in seconds.
     * @param _startingPrice Starting price for each auction.
     * @param _hook Address of the hook contract (optional).
     */
    function initialize(
        address _governance,
        uint256 _auctionLength,
        uint256 _auctionCooldown,
        uint256 _startingPrice,
        address _hook
    ) external {
        require(auctionLength != 0, "initialized");
        require(_auctionLength != 0, "length");
        require(_auctionLength < _auctionCooldown, "cooldown");
        require(_startingPrice != 0, "starting price");

        // Set variables
        governance = _governance;
        auctionLength = _auctionLength;
        auctionCooldown = _auctionCooldown;
        startingPrice = _startingPrice;
        hook = _hook;
    }

    /*//////////////////////////////////////////////////////////////
                         VIEW METHODS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get the unique auction identifier.
     * @param _from The address of the token to sell.
     * @param _to The address of the to buy.
     * @return bytes32 A unique auction identifier.
     */
    function getAuctionId(
        address _from,
        address _to
    ) public view virtual returns (bytes32) {
        return keccak256(abi.encodePacked(_from, _to, address(this)));
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
            auction.fromToken,
            auction.toToken,
            auction.kicked,
            auction.kicked + auctionLength > block.timestamp
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
    ) external view virtual returns (uint256) {
        // If not enough time has passed then `kickable` is 0.
        if (auctions[_auctionId].kicked + auctionCooldown > block.timestamp) {
            return 0;
        }

        // Check if we have a hook to call.
        address _hook = hook;
        if (_hook != address(0)) {
            // If so default to the hooks logic.
            return IHook(_hook).kickable(auctions[_auctionId].fromToken);
        } else {
            // Else just use the full balance of this contract.
            return
                ERC20(auctions[_auctionId].fromToken).balanceOf(address(this));
        }
    }

    /**
     * @notice Gets the amount needed to fulfill a given take amount in an auction.
     * @param _auctionId The unique identifier of the auction.
     * @param _amountToTake The amount to take in the auction.
     * @return . The amount needed to fulfill the take amount.
     */
    function getAmountNeeded(
        bytes32 _auctionId,
        uint256 _amountToTake
    ) external view virtual returns (uint256) {
        return getAmountNeeded(_auctionId, _amountToTake, block.timestamp);
    }

    /**
     * @notice Gets the amount needed to fulfill a given take amount in an auction at a specific timestamp.
     * @param _auctionId The unique identifier of the auction.
     * @param _amountToTake The amount to take in the auction.
     * @param _timestamp The specific timestamp for calculating the amount needed.
     * @return . The amount needed to fulfill the take amount.
     */
    function getAmountNeeded(
        bytes32 _auctionId,
        uint256 _amountToTake,
        uint256 _timestamp
    ) public view virtual returns (uint256) {
        return
            (_amountToTake *
                _price(
                    auctions[_auctionId].kicked,
                    auctions[_auctionId].initialAvailable *
                        auctions[_auctionId].fromScaler,
                    _timestamp
                )) /
            1e18 /
            auctions[_auctionId].toScaler;
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
                    auctions[_auctionId].fromScaler,
                _timestamp
            ) / auctions[_auctionId].toScaler;
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
        if (_kicked == 0 || _available == 0) return 0;

        uint256 secondsElapsed = _timestamp - _kicked;
        uint256 _window = auctionLength;

        if (secondsElapsed > _window) return 0;

        // Exponential decay from https://github.com/ajna-finance/ajna-core/blob/master/src/libraries/helpers/PoolHelper.sol
        uint256 hoursComponent = 1e27 >> (secondsElapsed / 3600);
        uint256 minutesComponent = Maths.rpow(
            MINUTE_HALF_LIFE,
            (secondsElapsed % 3600) / 60
        );
        uint256 initialPrice = _available == 0
            ? 0
            : Maths.wdiv(1_000_000_000 * 1e18, _available);

        return
            (initialPrice * Maths.rmul(hoursComponent, minutesComponent)) /
            1e27;
    }

    /*//////////////////////////////////////////////////////////////
                            SETTERS
    //////////////////////////////////////////////////////////////*/

    // TODO: Approvals?

    /**
     * @notice Enables a new auction.
     * @dev Uses 0 as minimum price and governance as the receiver.
     * @param _from The address of the token to be auctioned.
     * @param _to The address of the token to receive in the auction.
     * @return . The unique identifier of the enabled auction.
     */
    function enable(
        address _from,
        address _to
    ) external virtual returns (bytes32) {
        return enable(_from, _to, 0, governance);
    }

    /**
     * @notice Enables a new auction with a specified minimum price.
     * @dev Uses governance as the receiver.
     * @param _from The address of the token to be auctioned.
     * @param _to The address of the token to receive in the auction.
     * @param _minimumPrice The minimum price for the auction.
     * @return . The unique identifier of the enabled auction.
     */
    function enable(
        address _from,
        address _to,
        uint256 _minimumPrice
    ) external virtual returns (bytes32) {
        return enable(_from, _to, _minimumPrice, governance);
    }

    /**
     * @notice Enables a new auction.
     * @param _from The address of the token to be auctioned.
     * @param _to The address of the token to receive in the auction.
     * @param _minimumPrice The minimum price for the auction.
     * @param _receiver The address that will receive the funds in the auction.
     * @return _auctionId The unique identifier of the enabled auction.
     */
    function enable(
        address _from,
        address _to,
        uint256 _minimumPrice,
        address _receiver
    ) public virtual onlyGovernance returns (bytes32 _auctionId) {
        require(_from != address(0) && _to != address(0), "ZERO ADDRESS");
        require(_receiver != address(0), "receiver");

        _auctionId = getAuctionId(_from, _to);

        require(
            auctions[_auctionId].fromToken == address(0),
            "already enabled"
        );

        auctions[_auctionId] = AuctionInfo({
            fromToken: _from,
            fromScaler: uint96(WAD / 10 ** ERC20(_from).decimals()),
            toToken: _to,
            toScaler: uint96(WAD / 10 ** ERC20(_to).decimals()),
            kicked: 0,
            initialAvailable: 0,
            currentAvailable: 0,
            minimumPrice: _minimumPrice,
            receiver: _receiver
        });

        emit AuctionEnabled(_auctionId, _from, _to, address(this));
    }

    /**
     * @notice Disables an existing auction.
     * @dev Only callable by governance.
     * @param _from The address of the token being sold.
     * @param _to The address of the buying.
     */
    function disable(
        address _from,
        address _to
    ) external virtual onlyGovernance {
        bytes32 _auctionId = getAuctionId(_from, _to);

        // Make sure the auction was enables.
        require(auctions[_auctionId].fromToken != address(0), "not enabled");

        // Remove the struct.
        delete auctions[_auctionId];

        emit AuctionDisabled(_auctionId, _from, _to, address(this));
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
    ) external virtual returns (uint256 available) {
        address _fromToken = auctions[_auctionId].fromToken;
        require(_fromToken != address(0), "not enabled");
        require(
            block.timestamp > auctions[_auctionId].kicked + auctionCooldown,
            "too soon"
        );

        // Let do anything needed to account for the amount to auction.
        available = _amountKicked(_fromToken);

        require(available != 0, "nothing to kick");

        // Update the auctions status.
        auctions[_auctionId].kicked = block.timestamp;
        auctions[_auctionId].initialAvailable = available;
        auctions[_auctionId].currentAvailable = available;

        emit AuctionKicked(_auctionId, available);
    }

    /**
     * @notice Take the token being sold in a live auction.
     * @dev Defaults to taking the full amount and sending to the msg sender.
     * @param _auctionId The unique identifier of the auction.
     * @return . The amount of fromToken taken in the auction.
     */
    function take(bytes32 _auctionId) external virtual returns (uint256) {
        return take(_auctionId, type(uint256).max, msg.sender);
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
        return take(_auctionId, _maxAmount, msg.sender);
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
    ) public virtual returns (uint256 _amountTaken) {
        AuctionInfo memory auction = auctions[_auctionId];
        // Make sure the auction was kicked.
        require(
            auction.kicked != 0 &&
                auction.kicked + auctionLength >= block.timestamp,
            "too soon"
        );

        // Max amount that can be taken.
        _amountTaken = auction.currentAvailable > _maxAmount
            ? _maxAmount
            : auction.currentAvailable;

        // Pre take hook.
        _preTake(auction.fromToken, _amountTaken);

        // The current price.
        uint256 currentPrice = _price(
            auction.kicked,
            auction.initialAvailable * auction.fromScaler,
            block.timestamp
        );

        // Check the minimum price
        require(
            currentPrice / auction.toScaler >= auction.minimumPrice,
            "minimum price"
        );

        // Need to scale correctly.
        uint256 needed = (_amountTaken * currentPrice) /
            1e18 /
            auction.toScaler;

        require(needed != 0, "zero needed");

        // How much is left in this auction.
        uint256 left = auction.currentAvailable - _amountTaken;
        auctions[_auctionId].currentAvailable = left;

        // Pull token in.
        ERC20(auction.toToken).safeTransferFrom(
            msg.sender,
            auction.receiver,
            needed
        );

        // Transfer from token out.
        ERC20(auction.fromToken).safeTransfer(_receiver, _amountTaken);

        emit AuctionTaken(_auctionId, _amountTaken, left);

        // Post take hook.
        _postTake(auction.toToken, needed);
    }

    /*//////////////////////////////////////////////////////////////
                        OPTIONAL AUCTION HOOKS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Called when an auction is kicked to get the amount to sell.
     *
     *  If no `hook` is set it will default to the balance of this contract.
     *
     * @param _fromToken The address of the token to calculate the kicked amount.
     * @return . The amount kicked for the specified token.
     */
    function _amountKicked(
        address _fromToken
    ) internal virtual returns (uint256) {
        address _hook = hook;

        if (_hook != address(0)) {
            return IHook(_hook).auctionKicked(_fromToken);
        } else {
            return ERC20(_fromToken).balanceOf(address(this));
        }
    }

    /**
     * @dev Optional hook to use during a `take` call.
     * @param _fromToken The address of the token to be taken.
     * @param _amountToTake The amount of the token to be taken.
     */
    function _preTake(
        address _fromToken,
        uint256 _amountToTake
    ) internal virtual {
        address _hook = hook;

        if (_hook != address(0)) {
            IHook(_hook).preTake(_fromToken, _amountToTake);
        }
    }

    /**
     * @dev Optional hook to use at the end of a `take` call.
     * @param _toToken The address of the token received.
     * @param _newAmount The new amount of the received token.
     */
    function _postTake(address _toToken, uint256 _newAmount) internal virtual {
        address _hook = hook;

        if (_hook != address(0)) {
            IHook(_hook).postTake(_toToken, _newAmount);
        }
    }
}
