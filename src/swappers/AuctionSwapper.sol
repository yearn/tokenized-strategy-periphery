// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {Auction} from "../Auctions/Auction.sol";

interface IAuctionFactory {
    function createNewAuction(
        address _want,
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

    function _isAuction() internal view virtual {
        require(msg.sender == auction, "!auction");
    }

    address public constant auctionFactory = address(69);

    address public auction;

    /*//////////////////////////////////////////////////////////////
                    AUCTION STARTING AND STOPPING
    //////////////////////////////////////////////////////////////*/
    function _enableAuction(
        address _from,
        address _to,
        uint256 _minimumPrice
    ) internal virtual {
        address _auction = auction;
        if (_auction == address(0)) {
            // Deploy a new auction
            _auction = IAuctionFactory(auctionFactory).createNewAuction(
                _to,
                address(this),
                address(this)
            );
            // Store it for future use.
            auction = _auction;
        }
        // Enable new auction.
        Auction(_auction).enable(_from, _minimumPrice, address(this));
    }

    function _disableAuction(address _from) internal virtual {
        Auction(auction).disable(_from);
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
        _postTake(_token, _newAmount);
    }

    /*//////////////////////////////////////////////////////////////
                        OPTIONAL AUCTION HOOKS
    //////////////////////////////////////////////////////////////*/

    function _auctionKicked(
        address _token
    ) internal virtual returns (uint256 _available) {
        _available = ERC20(_token).balanceOf(address(this));
    }

    function _preTake(address _token, uint256 _amountToTake) internal virtual {}

    function _postTake(address _token, uint256 _newAmount) internal virtual {}
}
