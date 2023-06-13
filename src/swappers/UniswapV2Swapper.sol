// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {IUniswapV2Router02} from "../interfaces/Uniswap/V2/IUniswapV2Router02.sol";

/**
 *   @title UniswapV2Swapper
 *   @author Yearn.finance
 *   @dev This is a simple contract that can be inherited by any tokenized
 *   strategy that would like to use Uniswap V2 for swaps. It holds all needed
 *   logic to perform exact input swaps.
 *
 *   The global addres variables defualt to the ETH mainnet addresses but
 *   remain settable by the inheriting contract to allow for customization
 *   based on needs or chain its used on.
 */
contract UniswapV2Swapper {
    // Optional Variable to be set to not sell dust.
    uint256 public minAmountToSell;
    // Defualts to WETH on mainnet.
    address public base = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    // Defualts to Uniswap V2 router on mainnet.
    address public router = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    /**
     * @dev Used to swap a specific amount of `_from` to `_to`.
     * This will check and handle all allownaces as well as not swapping
     * unless `_amountIn` is greater than the set `_minAmountToSell`
     *
     * If one of the tokens matches with the `base` token it will do only
     * one jump, otherwise will do two jumps.
     *
     * @param _from The token we are swapping from.
     * @param _to The token we are swapping to.
     * @param _amountIn The amount of `_from` we will swap.
     * @param _minAmountOut The min of `_to` to get out.
     */
    function _swapFrom(
        address _from,
        address _to,
        uint256 _amountIn,
        uint256 _minAmountOut
    ) internal {
        if (_amountIn > minAmountToSell) {
            _checkAllowance(router, _from, _amountIn);

            IUniswapV2Router02(router).swapExactTokensForTokens(
                _amountIn,
                _minAmountOut,
                _getTokenOutPath(_from, _to),
                address(this),
                block.timestamp
            );
        }
    }

    /**\
     * @dev Internal function to get a quoted amount out of token sale.
     *
     * NOTE: This can be easily manipulated and should not be relied on
     * for anything other than estimations.
     *
     * @param _from The token to sell.
     * @param _to The token to buy.
     * @param _amountIn The amount of `_from` to sell.
     * @return . The expected amount of `_to` to buy.
     */
    function _getAmountOut(
        address _from,
        address _to,
        uint256 _amountIn
    ) internal view returns (uint256) {
        uint256[] memory amounts = IUniswapV2Router02(router).getAmountsOut(
            _amountIn,
            _getTokenOutPath(_from, _to)
        );

        return amounts[amounts.length - 1];
    }

    /**
     * @notice Internal function used to easily get the path
     * to be used for any given tokens.
     *
     * @param _tokenIn The token to swap from.
     * @param _tokenOut The token to swap to.
     * @return _path Ordered array of the path to swap through.
     */
    function _getTokenOutPath(
        address _tokenIn,
        address _tokenOut
    ) internal view returns (address[] memory _path) {
        bool isBase = _tokenIn == base || _tokenOut == base;
        _path = new address[](isBase ? 2 : 3);
        _path[0] = _tokenIn;

        if (isBase) {
            _path[1] = _tokenOut;
        } else {
            _path[1] = base;
            _path[2] = _tokenOut;
        }
    }

    /**
     * @dev Internal safe function to make sure the contract you want to
     * interact with has enough allowance to pull the desired tokens.
     *
     * @param _contract The address of the contract that will move the token.
     * @param _token The ERC-20 token that will be getting spent.
     * @param _amount The amount of `_token` to be spent.
     */
    function _checkAllowance(
        address _contract,
        address _token,
        uint256 _amount
    ) internal {
        if (ERC20(_token).allowance(address(this), _contract) < _amount) {
            ERC20(_token).approve(_contract, 0);
            ERC20(_token).approve(_contract, _amount);
        }
    }
}
