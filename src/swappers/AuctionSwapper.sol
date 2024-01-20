// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice To inherit by strategy to use auctions for rewards.
abstract contract AuctionSwapper {
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

    struct Auction {
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
    uint256 public auctionWindow = 2 days;

    /// @notice The minimum time to wait between auction 'kicks'.
    uint256 public auctionInterval = 5 days;

    /// @notice The amount to multiply fromToken by to start the auction.
    uint256 public startingMultiplier = 1_000_000_000;

    mapping(bytes32 => Auction) public auctions;

    /*//////////////////////////////////////////////////////////////
                         VIEW METHODS
    //////////////////////////////////////////////////////////////*/

    function getAuctionId(
        address _from,
        address _to
    ) public pure virtual returns (bytes32) {
        return keccak256(abi.encodePacked(_from, _to));
    }

    function getAuction(
        address _from,
        address _to
    ) public view virtual returns (Auction memory) {
        return auctions[getAuctionId(_from, _to)];
    }

    function getAmountNeeded(
        bytes32 _id,
        uint256 _amountToTake
    ) public view virtual returns (uint256) {
        Auction memory auction = auctions[_id];
        return
            (_amountToTake *
                _getPrice(
                    auction.kicked,
                    auction.initialAvailable * auction.fromScaler
                )) /
            1e18 /
            auction.toScaler;
    }

    function getPrice(bytes32 _id) public view virtual returns (uint256) {
        // Get unscaled price and scale it down.
        return
            _getPrice(
                auctions[_id].kicked,
                auctions[_id].initialAvailable * auctions[_id].fromScaler
            ) / auctions[_id].toScaler;
    }

    // TODO: Do an Exponential decay
    function _getPrice(
        uint256 _kicked,
        uint256 _unscaledAvailable
    ) public view virtual returns (uint256) {
        if (_kicked == 0 || _unscaledAvailable == 0) return 0;

        uint256 secondsElapsed = block.timestamp - _kicked;
        uint256 _window = auctionWindow;

        if (secondsElapsed > _window) return 0;

        uint256 initialPrice = (startingMultiplier * 1e18) / _unscaledAvailable;

        return initialPrice - ((initialPrice * secondsElapsed) / _window);
    }

    /*//////////////////////////////////////////////////////////////
                            SETTERS
    //////////////////////////////////////////////////////////////*/

    function _enableAuction(
        address _from,
        address _to,
        uint256 _minimumPrice
    ) internal virtual {
        require(_from != address(0) && _to != address(0), "ZERO ADDRESS");
        require(_from != address(this) && _to != address(this), "SELF");

        bytes32 id = getAuctionId(_from, _to);
        require(auctions[id].active = false, "already active");

        auctions[id] = Auction({
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

        emit AuctionEnabled(id, _from, _to, address(this));
    }

    function _disableAuction(address _from, address _to) internal virtual {
        bytes32 id = getAuctionId(_from, _to);
        require(auctions[id].active = true, "not active");

        delete auctions[id];

        emit AuctionDisabled(id, _from, _to, address(this));
    }

    /*//////////////////////////////////////////////////////////////
                      PARTICIPATE IN AUCTION
    //////////////////////////////////////////////////////////////*/

    function kickAuction(
        bytes32 _id
    ) external virtual returns (uint256 available) {
        Auction memory auction = auctions[_id];
        require(auction.active, "not active");
        require(block.timestamp > auction.kicked + auctionInterval, "too soon");

        // Let do anything needed to account for the amount to auction.
        available = _amountToKick(auction.fromToken);

        require(available != 0, "nothing to kick");

        // Update the auctions status.
        auctions[_id].kicked = block.timestamp;
        auctions[_id].initialAvailable = available;
        auctions[_id].currentAvailable = available;

        emit AuctionKicked(_id, available);
    }

    function takeAuction(
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
        Auction memory auction = auctions[_id];
        require(auction.active, "not active");
        // Make sure the auction was kicked and is still active
        require(
            auction.kicked != 0 &&
                auction.kicked + auctionWindow >= block.timestamp,
            "too soon"
        );

        // Max amount that can be taken.
        _amountTaken = auction.currentAvailable > _maxAmount
            ? _maxAmount
            : auction.currentAvailable;

        // Pre take hook.
        _preTake(_amountTaken);

        // The current price.
        uint256 price = _getPrice(
            auction.kicked,
            auction.initialAvailable * auction.fromScaler
        );

        // Check the minimum price
        require(
            price / auction.toScaler >= auction.minimumPrice,
            "minimum price"
        );

        // Need to scale correctly.
        uint256 needed = (_amountTaken * price) / 1e18 / auction.toScaler;

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
        _postTake(needed);
    }

    /*//////////////////////////////////////////////////////////////
                        OPTIONAL AUCTION HOOKS
    //////////////////////////////////////////////////////////////*/

    function _amountToKick(address _token) internal virtual returns (uint256) {
        return ERC20(_token).balanceOf(address(this));
    }

    function _preTake(uint256 _amountToTake) internal virtual {}

    function _postTake(uint256 _newAmount) internal virtual {}
}
