// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {AuctionFactory, Auction} from "../Auctions/AuctionFactory.sol";

/// @title AuctionSwapper
/// @author yearn.fi
/// @dev Helper contract for a strategy to use dutch auctions for reward sales.
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
    address public constant auctionFactory = address(69);

    /// @notice Address of the specific Auction this strategy uses.
    address public auction;

    /*//////////////////////////////////////////////////////////////
                    AUCTION STARTING AND STOPPING
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Used to enable a new Auction to sell `_from` to `_want`.
     *   If this is the first auction enabled it will deploy a new `auction`
     *   contract to use from the factory.
     *
     * NOTE: This only supports one `_want` token per strategy.
     *
     * @param _from Token to sell
     * @param _want Token to buy.
     * @return .The auction ID.
     */
    function _enableAuction(
        address _from,
        address _want
    ) internal virtual returns (bytes32) {
        address _auction = auction;

        // If this is the first auction.
        if (_auction == address(0)) {
            // Deploy a new auction
            _auction = AuctionFactory(auctionFactory).createNewAuction(
                _want,
                address(this),
                address(this)
            );
            // Store it for future use.
            auction = _auction;
        } else {
            // Can only use one `want` per auction contract.
            require(Auction(_auction).want() == _want, "wrong want");
        }

        // Enable new auction with the strategy as the hook.
        return Auction(_auction).enable(_from, address(this));
    }

    /**
     * @dev Disable an auction for a given token.
     * @param _from The token that was being sold.
     */
    function _disableAuction(address _from) internal virtual {
        Auction(auction).disable(_from);
    }

    /*//////////////////////////////////////////////////////////////
                        OPTIONAL AUCTION HOOKS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Return how much `_token` could currently be kicked into auction.
     * @dev This can be overridden by a strategist to implement custom logic.
     * @param _token Address of the `_from` token.
     * @return . The amount of `_token` ready to be auctioned off.
     */
    function kickable(address _token) external view virtual returns (uint256) {
        return ERC20(_token).balanceOf(address(this));
    }

    function _auctionKicked(address _token) internal virtual returns (uint256) {
        return ERC20(_token).balanceOf(address(this));
    }

    function _preTake(address _token, uint256 _amountToTake) internal virtual {}

    function _postTake(address _token, uint256 _newAmount) internal virtual {}

    /*//////////////////////////////////////////////////////////////
                            AUCTION HOOKS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice External hook for the auction to call during a `kick`.
     * @dev Will call the internal version for the strategist to override.
     * @param _token Token being kicked into auction.
     * @return . The amount of `_token` to be auctioned off.
     */
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
        ERC20(_token).safeTransfer(auction, _amountToTake);
    }

    function postTake(
        address _token,
        uint256 _newAmount
    ) external virtual onlyAuction {
        _postTake(_token, _newAmount);
    }
}
