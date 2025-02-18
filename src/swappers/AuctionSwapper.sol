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

    modifier onlyAuction() {
        _isAuction();
        _;
    }

    /**
     * @dev Check the caller is the auction contract for hooks.
     */
    function _isAuction() internal view virtual {
        require(msg.sender == auction, "!auction");
    }

    /// @notice The pre-deployed Auction factory for cloning.
    address public constant auctionFactory =
        0xCfA510188884F199fcC6e750764FAAbE6e56ec40;

    /// @notice Address of the specific Auction this strategy uses.
    address public auction;

    /*//////////////////////////////////////////////////////////////
                    AUCTION STARTING AND STOPPING
    //////////////////////////////////////////////////////////////*/

    function _enableAuction(address _from, address _want) internal virtual {
        _enableAuction(_from, _want, 1 days, 1e6);
    }

    /**
     * @dev Used to enable a new Auction to sell `_from` to `_want`.
     *   If this is the first auction enabled it will deploy a new `auction`
     *   contract to use from the factory.
     *
     * NOTE: This only supports one `_want` token per strategy.
     *
     * @param _from Token to sell
     * @param _want Token to buy.
     */
    function _enableAuction(
        address _from,
        address _want,
        uint256 _auctionLength,
        uint256 _startingPrice
    ) internal virtual {
        address _auction = auction;

        // If this is the first auction.
        if (_auction == address(0)) {
            // Deploy a new auction
            _auction = AuctionFactory(auctionFactory).createNewAuction(
                _want,
                address(this),
                address(this),
                _auctionLength,
                _startingPrice
            );
            // Store it for future use.
            auction = _auction;
        } else {
            // Can only use one `want` per auction contract.
            require(Auction(_auction).want() == _want, "wrong want");
        }

        // Enable new auction for `_from` token.
        Auction(_auction).enable(_from);
    }

    /**
     * @dev Disable an auction for a given token.
     * @param _from The token that was being sold.
     */
    function _disableAuction(address _from) internal virtual {
        Auction(auction).disable(_from);
    }

    /**
     * @dev Return how much `_token` could currently be kicked into auction.
     * @param _token The token that was being sold.
     * @return The amount of `_token` ready to be auctioned off.
     */
    function kickable(address _token) public view virtual returns (uint256) {
        return ERC20(_token).balanceOf(address(this));
    }

    /**
     * @dev Kick an auction for a given token.
     * @param _from The token that was being sold.
     */
    function _kickAuction(address _from) internal virtual returns (uint256) {
        uint256 _balance = ERC20(_from).balanceOf(address(this));
        ERC20(_from).safeTransfer(auction, _balance);
        return Auction(auction).kick(_from);
    }
}
