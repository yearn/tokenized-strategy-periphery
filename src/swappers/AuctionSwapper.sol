// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {AuctionFactory, Auction} from "../Auctions/AuctionFactory.sol";
import {BaseSwapper} from "./BaseSwapper.sol";

/**
 *   @title AuctionSwapper
 *   @author yearn.fi
 *   @dev Helper contract for a strategy to use dutch auctions for token sales.
 *
 *   This contract is meant to be inherited by a V3 strategy in order
 *   to easily integrate dutch auctions into a contract for token swaps.
 *
 *   AUCTION SETUP:
 *   - The strategist needs to implement a way to call `_setAuction()`
 *     to set the auction contract address for token sales
 *   - `useAuction` defaults to false but is automatically set to true
 *     when a non-zero auction address is set via `_setAuction()`
 *   - Auctions can be manually enabled/disabled using `_setUseAuction()`
 *
 *   PERMISSIONLESS OPERATIONS:
 *   - `kickAuction()` is public and permissionless - anyone can trigger
 *     auctions when conditions are met (sufficient balance, auctions enabled)
 *   - This allows for automated auction triggering by bots or external systems
 *
 *   AUCTION TRIGGER INTEGRATION:
 *   - Implements `auctionTrigger()` for integration with CommonAuctionTrigger
 *   - Returns encoded calldata for `kickAuction()` when conditions are met
 *   - Provides smart logic to prevent duplicate auctions and handle edge cases
 *
 *   HOOKS:
 *   - The contract can act as a `hook` contract for the auction with the
 *     ability to override functions to implement custom hooks
 *   - If hooks are not desired, call `setHookFlags()` on the auction contract
 *     to avoid unnecessary gas for unused functions
 */
contract AuctionSwapper is BaseSwapper {
    using SafeERC20 for ERC20;

    event AuctionSet(address indexed auction);
    event UseAuctionSet(bool indexed useAuction);

    /// @notice Address of the specific Auction contract this strategy uses for token sales.
    address public auction;

    /// @notice Whether to use auctions for token swaps.
    /// @dev Defaults to false but automatically set to true when setting a non-zero auction address.
    ///      Can be manually controlled via _setUseAuction() for fine-grained control.
    bool public useAuction;

    /*//////////////////////////////////////////////////////////////
                    AUCTION STARTING AND STOPPING
    //////////////////////////////////////////////////////////////*/

    /// @notice Set the auction contract to use.
    /// @dev Automatically enables auctions (useAuction = true) when setting a non-zero address.
    /// @param _auction The auction contract address. Must have this contract as receiver.
    function _setAuction(address _auction) internal virtual {
        if (_auction != address(0)) {
            require(
                Auction(_auction).receiver() == address(this),
                "wrong receiver"
            );
            // Automatically enable auctions when setting a non-zero auction address
            if (!useAuction) {
                useAuction = true;
                emit UseAuctionSet(true);
            }
        }
        auction = _auction;
        emit AuctionSet(_auction);
    }

    /// @notice Manually enable or disable auction usage.
    /// @dev Can be used to override the auto-enable behavior or temporarily disable auctions.
    /// @param _useAuction Whether to use auctions for token swaps.
    function _setUseAuction(bool _useAuction) internal virtual {
        useAuction = _useAuction;
        emit UseAuctionSet(_useAuction);
    }

    /**
     * @notice Return how much of a token could currently be kicked into auction.
     * @dev Includes both contract balance and tokens already in the auction contract.
     * @param _token The token that could be sold in auction.
     * @return The total amount of `_token` available for auction (0 if auctions disabled).
     */
    function kickable(address _token) public view virtual returns (uint256) {
        if (!useAuction) return 0;
        return
            ERC20(_token).balanceOf(address(this)) +
            ERC20(_token).balanceOf(auction);
    }

    /**
     * @notice Kick an auction for a given token (PERMISSIONLESS).
     * @dev Anyone can call this function to trigger auctions when conditions are met.
     *      Useful for automated systems, bots, or manual triggering.
     * @param _from The token to be sold in the auction.
     * @return The amount of tokens that were kicked into the auction.
     */
    function kickAuction(address _from) external virtual returns (uint256) {
        return _kickAuction(_from);
    }

    /**
     * @dev Internal function to kick an auction for a given token.
     * @param _from The token that was being sold.
     */
    function _kickAuction(address _from) internal virtual returns (uint256) {
        require(useAuction, "useAuction is false");
        address _auction = auction;

        if (Auction(_auction).isActive(_from)) {
            if (Auction(_auction).available(_from) > 0) {
                return 0;
            }

            Auction(_auction).settle(_from);
        }

        uint256 _balance = ERC20(_from).balanceOf(address(this));
        if (_balance > 0) {
            ERC20(_from).safeTransfer(_auction, _balance);
        }

        return Auction(_auction).kick(_from);
    }

    /*//////////////////////////////////////////////////////////////
                        AUCTION TRIGGER INTERFACE
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Default auction trigger implementation for CommonAuctionTrigger integration.
     * @dev Returns whether an auction should be kicked and the encoded calldata to do so.
     *      This enables automated auction triggering through external trigger systems.
     * @param _from The token that could be sold in an auction.
     * @return shouldKick True if an auction should be kicked for this token.
     * @return data Encoded calldata for `kickAuction(_from)` if shouldKick is true,
     *              otherwise a descriptive error message explaining why not.
     */
    function auctionTrigger(
        address _from
    ) external view virtual returns (bool shouldKick, bytes memory data) {
        address _auction = auction;
        if (_auction == address(0)) {
            return (false, bytes("No auction set"));
        }

        if (!useAuction) {
            return (false, bytes("Auctions disabled"));
        }

        uint256 kickableAmount = kickable(_from);

        if (kickableAmount == 0) {
            return (false, bytes("No kickable balance"));
        }

        // Check if auction is already active with available tokens
        if (
            Auction(_auction).isActive(_from) &&
            Auction(_auction).available(_from) > 0
        ) {
            return (false, bytes("Active auction with available tokens"));
        }

        return (true, abi.encodeCall(this.kickAuction, (_from)));
    }
}
