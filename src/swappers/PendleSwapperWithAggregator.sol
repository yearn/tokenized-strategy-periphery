// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {PendleSwapper} from "./PendleSwapper.sol";
import {
    IPendleRouter,
    IPMarket,
    IPYieldToken,
    TokenInput,
    TokenOutput,
    SwapData
} from "../interfaces/Pendle/IPendle.sol";

/**
 * @title PendleSwapperWithAggregator
 * @author yearn.fi
 * @dev Extension of PendleSwapper that allows swapping from arbitrary tokens
 *   by using an external swap aggregator (e.g., 1inch, Kyberswap) to first
 *   convert the input token to a token that the SY contract accepts.
 *
 *   This is useful when your strategy holds a token that is not directly
 *   accepted by the SY contract for minting.
 *
 *   Example flow for buying PT with USDC when SY only accepts stETH:
 *   1. USDC -> stETH (via aggregator specified in SwapData)
 *   2. stETH -> SY -> PT (via Pendle router)
 */
contract PendleSwapperWithAggregator is PendleSwapper {
    using SafeERC20 for ERC20;

    /**
     * @dev Buy PT tokens using an external aggregator to first swap the input token.
     *
     * @param _tokenIn The input token (can be any token).
     * @param _pt The PT token to buy (must be registered in markets).
     * @param _amountIn Amount of input token to spend.
     * @param _minPtOut Minimum PT to receive.
     * @param _tokenMintSy The token that SY accepts for minting (e.g., stETH).
     * @param _swapData Aggregator swap data for tokenIn -> tokenMintSy conversion.
     * @return _amountOut Amount of PT received.
     */
    function _swapFromWithAggregator(
        address _tokenIn,
        address _pt,
        uint256 _amountIn,
        uint256 _minPtOut,
        address _tokenMintSy,
        SwapData calldata _swapData
    ) internal virtual returns (uint256 _amountOut) {
        if (_amountIn == 0 || _amountIn < minAmountToSell) {
            return 0;
        }

        address market = markets[_pt];
        require(market != address(0), "PendleSwapper: unknown market");

        _checkAllowance(pendleRouter, _tokenIn, _amountIn);

        TokenInput memory input = TokenInput({
            tokenIn: _tokenIn,
            netTokenIn: _amountIn,
            tokenMintSy: _tokenMintSy,
            pendleSwap: _swapData.extRouter,
            swapData: _swapData
        });

        (uint256 netPtOut, , ) = IPendleRouter(pendleRouter).swapExactTokenForPt(
            address(this),
            market,
            _minPtOut,
            _getDefaultApproxParams(),
            input,
            _getEmptyLimitOrderData()
        );

        _amountOut = netPtOut;
    }

    /**
     * @dev Sell PT tokens and convert output via an external aggregator.
     *
     * @param _pt The PT token to sell (must be registered in markets).
     * @param _tokenOut The final output token (can be any token).
     * @param _amountIn Amount of PT to sell.
     * @param _minTokenOut Minimum output token to receive.
     * @param _tokenRedeemSy The token that SY redeems to (e.g., stETH).
     * @param _swapData Aggregator swap data for tokenRedeemSy -> tokenOut conversion.
     * @return _amountOut Amount of output token received.
     */
    function _swapToWithAggregator(
        address _pt,
        address _tokenOut,
        uint256 _amountIn,
        uint256 _minTokenOut,
        address _tokenRedeemSy,
        SwapData calldata _swapData
    ) internal virtual returns (uint256 _amountOut) {
        if (_amountIn == 0 || _amountIn < minAmountToSell) {
            return 0;
        }

        address market = markets[_pt];
        require(market != address(0), "PendleSwapper: unknown market");

        _checkAllowance(pendleRouter, _pt, _amountIn);

        TokenOutput memory output = TokenOutput({
            tokenOut: _tokenOut,
            minTokenOut: _minTokenOut,
            tokenRedeemSy: _tokenRedeemSy,
            pendleSwap: _swapData.extRouter,
            swapData: _swapData
        });

        if (IPMarket(market).isExpired()) {
            (, , IPYieldToken YT) = IPMarket(market).readTokens();

            (uint256 netTokenOut, ) = IPendleRouter(pendleRouter).redeemPyToToken(
                address(this),
                address(YT),
                _amountIn,
                output
            );
            _amountOut = netTokenOut;
        } else {
            (uint256 netTokenOut, , ) = IPendleRouter(pendleRouter)
                .swapExactPtForToken(
                    address(this),
                    market,
                    _amountIn,
                    output,
                    _getEmptyLimitOrderData()
                );
            _amountOut = netTokenOut;
        }
    }
}
