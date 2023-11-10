// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {ISolidly} from "../interfaces/Solidly/ISolidly.sol";

/**
 *   @title SolidlySwapper
 *   @author Yearn.finance
 *   @dev This is a simple contract that can be inherited by any tokenized
 *   strategy that would like to use a Solidly fork for swaps. It holds all needed
 *   logic to perform exact input swaps.
 *
 *   The global address variables default to the ETH mainnet addresses but
 *   remain settable by the inheriting contract to allow for customization
 *   based on needs or chain its used on.
 *
 *   This will default to only use volatile pools and the `_setStable`
 *   will need to be set for any token pairs that should use a stable pool.
 */
contract SolidlySwapper {
    // Optional Variable to be set to not sell dust.
    uint256 public minAmountToSell;
    // Defaults to WETH on mainnet.
    address public base = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    // Will need to set the router to use.
    address public router;

    // Mapping to determine if a stable or volatile pool should be used.
    // This defaults to volatile for all pools and will need to be set
    // if a stable pool should be used.
    mapping(address => mapping(address => bool)) public stable;

    /**
     * @dev Internal function to set the `stable` mapping for any
     * pair of tokens if a the route should go through a stable pool.
     * This function is to help set the mapping. It can be called
     * internally during initialization, through permissioned functions etc.
     */
    function _setStable(
        address _token0,
        address _token1,
        bool _stable
    ) internal virtual {
        stable[_token0][_token1] = _stable;
        stable[_token1][_token0] = _stable;
    }

    /**
     * @dev Used to swap a specific amount of `_from` to `_to`.
     * This will check and handle all allowances as well as not swapping
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
    ) internal virtual {
        if (_amountIn > minAmountToSell) {
            _checkAllowance(router, _from, _amountIn);

            ISolidly(router).swapExactTokensForTokens(
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
    ) internal view virtual returns (uint256) {
        uint256[] memory amounts = ISolidly(router).getAmountsOut(
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
    ) internal view virtual returns (ISolidly.route[] memory _path) {
        bool isBase = _tokenIn == base || _tokenOut == base;
        _path = new ISolidly.route[](isBase ? 1 : 2);

        if (isBase) {
            _path[0] = ISolidly.route(
                _tokenIn,
                _tokenOut,
                stable[_tokenIn][_tokenOut]
            );
        } else {
            _path[0] = ISolidly.route(_tokenIn, base, stable[_tokenIn][base]);
            _path[1] = ISolidly.route(base, _tokenOut, stable[base][_tokenOut]);
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
    ) internal virtual {
        if (ERC20(_token).allowance(address(this), _contract) < _amount) {
            ERC20(_token).approve(_contract, 0);
            ERC20(_token).approve(_contract, _amount);
        }
    }
}
