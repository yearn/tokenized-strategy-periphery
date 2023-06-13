// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

import {UniswapV2Swapper, IUniswapV2Router02} from "./UniswapV2Swapper.sol";

/**
 *   @title UniswapV2Extended
 *   @author Yearn.finance
 *   @dev This is a simple contract that can be inherited by any tokenized
 *   strategy that would like to use more Uniswap V2 functions than just
 *   an exact swap from of erc-20 tokens.
 *
 *   This contract will give access to all other Uni V2 functionality
 *   with the ease of one internal function call.
 */
contract UniswapV2Extended is UniswapV2Swapper {
    /**
     * @dev Used to swap a specific amount of `_to` from `_from` unless
     * it takes more than `_maxAmountFrom`.
     *
     * This will check and handle all allownaces as well as not swapping
     * unless `_maxAmountFrom` is greater than the set `minAmountToSell`
     *
     * If one of the tokens matches with the `base` token it will do only
     * one jump, otherwise will do two jumps.
     *
     * The corresponding uniFees for each token pair will need to be set
     * other wise this function will revert.
     *
     * @param _from The token we are swapping from.
     * @param _to The token we are swapping to.
     * @param _amountTo The amount of `_to` we need out.
     * @param _maxAmountFrom The max of `_from` we will swap.
     * @return _amountIn The actual amouont of `_from` swapped.
     */
    function _swapTo(
        address _from,
        address _to,
        uint256 _amountTo,
        uint256 _maxAmountFrom
    ) internal {
        if (_maxAmountFrom > minAmountToSell) {
            _checkAllowance(router, _from, _amountIn);

            IUniswapV2Router02(router).swapTokensForExactTokens(
                _amountTo,
                _maxAmountFrom,
                _getTokenOutPath(_from, _to),
                address(this),
                block.timestamp
            );
        }
    }
}
