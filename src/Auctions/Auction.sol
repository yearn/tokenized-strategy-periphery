// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

import {Governance} from "../utils/Governance.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

interface IHook {
    function kickable(bytes32 _auctionId) external view returns (uint256);

    function auctionKicked(bytes32 _auctionId) external returns (uint256);

    function preTake(bytes32 _auctionId, uint256 _amountToTake) external;

    function postTake(bytes32 _auctionId, uint256 _newAmount) external;
}

contract Auction is Governance {
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
        bool active;
    }

    uint256 internal constant WAD = 1e18;

    /// @notice The time that each auction lasts.
    uint256 public auctionCooldown;

    /// @notice The minimum time to wait between auction 'kicks'.
    uint256 public auctionLength;

    /// @notice The amount to start the auction with.
    uint256 public startingPrice;

    mapping(bytes32 => AuctionInfo) public auctions;

    address public hook;

    constructor() Governance(msg.sender) {
        auctionLength = 1;
    }

    function initialize(
        address _owner,
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
        governance = _owner;
        auctionLength = _auctionLength;
        auctionCooldown = _auctionCooldown;
        startingPrice = _startingPrice;
        hook = _hook;
    }

    /*//////////////////////////////////////////////////////////////
                         VIEW METHODS
    //////////////////////////////////////////////////////////////*/

    function getAuctionId(
        address _from,
        address _to
    ) public view virtual returns (bytes32) {
        return keccak256(abi.encodePacked(_from, _to, address(this)));
    }

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

    function kickable(bytes32 _auctionId) external view returns (uint256) {
        if (auctions[_auctionId].kicked + auctionCooldown > block.timestamp)
            return 0;
        address _hook = hook;
        if (_hook != address(0)) {
            return IHook(_hook).kickable(_auctionId);
        } else {
            return
                ERC20(auctions[_auctionId].fromToken).balanceOf(address(this));
        }
    }

    function getAmountNeeded(
        bytes32 _id,
        uint256 _amountToTake
    ) external view virtual returns (uint256) {
        return getAmountNeeded(_id, _amountToTake, block.timestamp);
    }

    function getAmountNeeded(
        bytes32 _id,
        uint256 _amountToTake,
        uint256 _timestamp
    ) public view virtual returns (uint256) {
        AuctionInfo memory auction = auctions[_id];
        return
            (_amountToTake * price(_id, _timestamp)) / 1e18 / auction.toScaler;
    }

    function price(bytes32 _id) external view virtual returns (uint256) {
        return price(_id, block.timestamp);
    }

    function price(
        bytes32 _id,
        uint256 _timestamp
    ) public view virtual returns (uint256) {
        // Get unscaled price and scale it down.
        return
            _price(
                auctions[_id].kicked,
                auctions[_id].initialAvailable * auctions[_id].fromScaler,
                _timestamp
            ) / auctions[_id].toScaler;
    }

    // TODO: Do an Exponential decay
    function _price(
        uint256 _kicked,
        uint256 _unscaledAvailable,
        uint256 _timestamp
    ) public view virtual returns (uint256) {
        if (_kicked == 0 || _unscaledAvailable == 0) return 0;

        uint256 secondsElapsed = _timestamp - _kicked;
        uint256 _window = auctionLength;

        if (secondsElapsed > _window) return 0;

        uint256 initialPrice = (startingPrice * 1e18) / _unscaledAvailable;

        return initialPrice - ((initialPrice * secondsElapsed) / _window);
    }

    /*//////////////////////////////////////////////////////////////
                            SETTERS
    //////////////////////////////////////////////////////////////*/

    function enableAuction(
        address _from,
        address _to,
        uint256 _minimumPrice
    ) external virtual onlyGovernance returns (bytes32 _auctionId) {
        require(_from != address(0) && _to != address(0), "ZERO ADDRESS");
        require(_from != address(this) && _to != address(this), "SELF");

        _auctionId = getAuctionId(_from, _to);
        require(auctions[_auctionId].active = false, "already active");

        auctions[_auctionId] = AuctionInfo({
            fromToken: _from,
            fromScaler: uint96(WAD / 10 ** ERC20(_from).decimals()),
            toToken: _to,
            toScaler: uint96(WAD / 10 ** ERC20(_to).decimals()),
            kicked: 0,
            initialAvailable: 0,
            currentAvailable: 0,
            minimumPrice: _minimumPrice,
            active: true
        });

        emit AuctionEnabled(_auctionId, _from, _to, address(this));
    }

    function disableAuction(
        address _from,
        address _to
    ) external virtual onlyGovernance {
        bytes32 _auctionId = getAuctionId(_from, _to);
        require(auctions[_auctionId].active = true, "not active");

        delete auctions[_auctionId];

        emit AuctionDisabled(_auctionId, _from, _to, address(this));
    }

    /*//////////////////////////////////////////////////////////////
                      PARTICIPATE IN AUCTION
    //////////////////////////////////////////////////////////////*/

    function kick(bytes32 _id) external virtual returns (uint256 available) {
        AuctionInfo memory auction = auctions[_id];
        require(auction.active, "not active");
        require(block.timestamp > auction.kicked + auctionCooldown, "too soon");

        // Let do anything needed to account for the amount to auction.
        available = _amountKicked(_id);

        require(available != 0, "nothing to kick");

        // Update the auctions status.
        auctions[_id].kicked = block.timestamp;
        auctions[_id].initialAvailable = available;
        auctions[_id].currentAvailable = available;

        emit AuctionKicked(_id, available);
    }

    function take(
        bytes32 _id,
        uint256 _maxAmount
    ) external virtual returns (uint256) {
        return takeAuction(_id, _maxAmount, msg.sender);
    }

    function takeAuction(
        bytes32 _id,
        uint256 _maxAmount,
        address _receiver
    ) public virtual returns (uint256 _amountTaken) {
        AuctionInfo memory auction = auctions[_id];
        require(auction.active, "not active");
        // Make sure the auction was kicked and is still active
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
        _preTake(_id, _amountTaken);

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
        auctions[_id].currentAvailable = left;

        // Pull token in.
        ERC20(auction.toToken).transferFrom(msg.sender, address(this), needed);

        // Transfer from token out.
        ERC20(auction.fromToken).transfer(_receiver, _amountTaken);

        emit AuctionTaken(_id, _amountTaken, left);

        // Post take hook.
        _postTake(_id, needed);
    }

    /*//////////////////////////////////////////////////////////////
                        OPTIONAL AUCTION HOOKS
    //////////////////////////////////////////////////////////////*/

    function _amountKicked(
        bytes32 _auctionId
    ) internal virtual returns (uint256) {
        address _hook = hook;

        if (_hook != address(0)) {
            return IHook(_hook).auctionKicked(_auctionId);
        } else {
            return
                ERC20(auctions[_auctionId].fromToken).balanceOf(address(this));
        }
    }

    function _preTake(
        bytes32 _auctionId,
        uint256 _amountToTake
    ) internal virtual {
        address _hook = hook;

        if (_hook != address(0)) {
            IHook(_hook).preTake(_auctionId, _amountToTake);
        }
    }

    function _postTake(
        bytes32 _auctionId,
        uint256 _newAmount
    ) internal virtual {
        address _hook = hook;

        if (_hook != address(0)) {
            IHook(_hook).postTake(_auctionId, _newAmount);
        }
    }
}
