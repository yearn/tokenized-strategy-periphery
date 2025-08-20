// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {AuctionFactory, Auction} from "../Auctions/AuctionFactory.sol";

/**
 *   @title AuctionSwapper
 *   @author yearn.fi
 *   @dev Helper contract for a strategy to use dutch auctions for token sales.
 *
 *   This contract is meant to be inherited by a V3 strategy in order
 *   to easily integrate dutch auctions into a contract for token swaps.
 *
 *   The strategist will need to implement a way to call `_enableAuction`
 *   for an token pair they want to use, or a setter to manually set the
 *   `auction` contract.
 *
 *   The contract comes with all of the needed function to act as a `hook`
 *   contract for the specific auction contract with the ability to override
 *   any of the functions to implement custom hooks.
 *
 *   NOTE: If any hooks are not desired, the strategist should also
 *   implement a way to call the {setHookFlags} on the auction contract
 *   to avoid unnecessary gas for unused functions.
 */
contract AuctionSwapper {
    using SafeERC20 for ERC20;

    event AuctionSet(address indexed auction);
    event UseAuctionSet(bool indexed useAuction);

    /// @notice Address of the specific Auction this strategy uses.
    address public auction;

    /// @notice Whether to use the auction. Default is false.
    bool public useAuction;

    /*//////////////////////////////////////////////////////////////
                    AUCTION STARTING AND STOPPING
    //////////////////////////////////////////////////////////////*/

    /// @notice Set the auction contract to use.
    function _setAuction(address _auction) internal virtual {
        if (_auction != address(0)) {
            require(
                Auction(_auction).receiver() == address(this),
                "wrong receiver"
            );
        }
        auction = _auction;
        emit AuctionSet(_auction);
    }

    /// @notice Set whether to use the auction.
    function _setUseAuction(bool _useAuction) internal virtual {
        useAuction = _useAuction;
        emit UseAuctionSet(_useAuction);
    }

    /**
     * @dev Return how much `_token` could currently be kicked into auction.
     * @param _token The token that was being sold.
     * @return The amount of `_token` ready to be auctioned off.
     */
    function kickable(address _token) public view virtual returns (uint256) {
        if (!useAuction) return 0;
        return ERC20(_token).balanceOf(address(this)) + ERC20(_token).balanceOf(auction);
    }

    /**
     * @dev Kick an auction for a given token.
     * @param _from The token that was being sold.
     */
    function _kickAuction(address _from) internal virtual returns (uint256) {
        require(useAuction, "useAuction is false");

        if (Auction(auction).isActive(_from)) {
            if (Auction(auction).available(_from) > 0) {
                return 0;
            }

            Auction(auction).settle(_from);
        }

        uint256 _balance = ERC20(_from).balanceOf(address(this));
        if (_balance > 0) {
            ERC20(_from).safeTransfer(auction, _balance);
        }

        return Auction(auction).kick(_from);

    }
}
