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
        0xE6aB098E8582178A76DC80d55ca304d1Dec11AD8;

    /// @notice Address of the specific Auction this strategy uses.
    address public auction;

    /*//////////////////////////////////////////////////////////////
                    AUCTION STARTING AND STOPPING
    //////////////////////////////////////////////////////////////*/

    function _enableAuction(
        address _from,
        address _want
    ) internal virtual returns (bytes32) {
        return _enableAuction(_from, _want, 1 days, 3 days, 1e6);
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
     * @return .The auction ID.
     */
    function _enableAuction(
        address _from,
        address _want,
        uint256 _auctionLength,
        uint256 _auctionCooldown,
        uint256 _startingPrice
    ) internal virtual returns (bytes32) {
        address _auction = auction;

        // If this is the first auction.
        if (_auction == address(0)) {
            // Deploy a new auction
            _auction = AuctionFactory(auctionFactory).createNewAuction(
                _want,
                address(this),
                address(this),
                _auctionLength,
                _auctionCooldown,
                _startingPrice
            );
            // Store it for future use.
            auction = _auction;
        } else {
            // Can only use one `want` per auction contract.
            require(Auction(_auction).want() == _want, "wrong want");
        }

        // Enable new auction for `_from` token.
        return Auction(_auction).enable(_from);
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
    function kickable(address _token) public view virtual returns (uint256) {
        return ERC20(_token).balanceOf(address(this));
    }

    /**
     * @dev To override if something other than just sending the loose balance
     *  of `_token` to the auction is desired, such as accruing and and claiming rewards.
     *
     * @param _token Address of the token being auctioned off
     */
    function _auctionKicked(address _token) internal virtual returns (uint256) {
        // Send any loose balance to the auction.
        uint256 balance = ERC20(_token).balanceOf(address(this));
        if (balance != 0) ERC20(_token).safeTransfer(auction, balance);
        return ERC20(_token).balanceOf(auction);
    }

    /**
     * @dev To override if something needs to be done before a take is completed.
     *   This can be used if the auctioned token only will be freed up when a `take`
     *   occurs.
     * @param _token Address of the token being taken.
     * @param _amountToTake Amount of `_token` needed.
     * @param _amountToPay Amount of `want` that will be payed.
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

    /**
     * @notice External hook for the auction to call before a `take`.
     * @dev Will call the internal version for the strategist to override.
     * @param _token Token being taken in the auction.
     * @param _amountToTake The amount of `_token` to be sent to the taker.
     * @param _amountToPay Amount of `want` that will be payed.
     */
    function preTake(
        address _token,
        uint256 _amountToTake,
        uint256 _amountToPay
    ) external virtual onlyAuction {
        _preTake(_token, _amountToTake, _amountToPay);
    }

    /**
     * @notice External hook for the auction to call after a `take` completed.
     * @dev Will call the internal version for the strategist to override.
     * @param _token The `want` token that was sent to the strategy.
     * @param _amountTaken Amount of the from token taken.
     * @param _amountPayed Amount of `_token` that was sent to the strategy.
     */
    function postTake(
        address _token,
        uint256 _amountTaken,
        uint256 _amountPayed
    ) external virtual onlyAuction {
        _postTake(_token, _amountTaken, _amountPayed);
    }
}
