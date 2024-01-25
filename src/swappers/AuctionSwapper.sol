// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {Auction} from "../Auctions/Auction.sol";

interface IAuctionFactory {
    function createNewAuction(
        address _owner,
        address _hook
    ) external returns (address);
}

/// @notice To inherit by strategy to use auctions for rewards.
contract AuctionSwapper {
    modifier onlyAuction() {
        _isAuction();
        _;
    }

    function _isAuction() internal view {
        require(msg.sender == auction, "!auction");
    }

    address public constant auctionFactory = address(69);

    address public auction;

    function _enableAuction(
        address _from,
        address _to,
        uint256 _minimumPrice
    ) internal virtual {
        address _auction = auction;
        if (_auction == address(0)) {
            // Deploy a new auction
            _auction = IAuctionFactory(auctionFactory).createNewAuction(
                address(this),
                address(this)
            );
            // Store it for future use.
            auction = _auction;
        }
        // Enable new auction.
        Auction(_auction).enableAuction(_from, _to, _minimumPrice);
    }

    function _disableAuction(address _from, address _to) internal virtual {
        Auction(auction).disableAuction(_from, _to);
    }

    /*//////////////////////////////////////////////////////////////
                            AUCTION HOOKS
    //////////////////////////////////////////////////////////////*/

    function kickable(address _token) external view virtual returns (uint256) {
        return ERC20(_token).balanceOf(address(this));
    }

    function auctionKicked(
        address _token
    ) external virtual onlyAuction returns (uint256) {
        return _auctionKicked(_token);
    }

    function preTake(
        address _token,
        uint256 _amountToTake
    ) external virtual onlyAuction {
        _preTake(_token, _amountToTake);
        ERC20(_token).transfer(auction, _amountToTake);
    }

    function postTake(
        address _token,
        uint256 _newAmount
    ) external virtual onlyAuction {
        ERC20(_token).transferFrom(auction, address(this), _newAmount);
        _postTake(_token, _newAmount);
    }

    /*//////////////////////////////////////////////////////////////
                            AUCTION HOOKS
    //////////////////////////////////////////////////////////////*/

    function _auctionKicked(
        address _token
    ) internal virtual returns (uint256 _available) {
        _available = ERC20(_token).balanceOf(address(this));
    }

    function _preTake(address _token, uint256 _amountToTake) internal virtual {}

    function _postTake(address _token, uint256 _newAmount) internal virtual {}
}
