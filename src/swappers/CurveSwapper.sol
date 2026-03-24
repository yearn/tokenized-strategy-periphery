// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {ICurveRouter} from "../interfaces/Curve/ICurveRouter.sol";
import {BaseSwapper} from "./BaseSwapper.sol";

/**
 *   @title CurveSwapper
 *   @author Yearn.finance
 *   @dev This is a simple contract that can be inherited by any tokenized
 *   strategy that would like to use the Curve Router NG for swaps.
 *
 *   The global address variable defaults to the ETH mainnet address but
 *   remains settable by the inheriting contract to allow for customization
 *   based on needs or chain its used on.
 *
 *   The inheriting contract must set the route config for each token pair
 *   using the {_setCurveRoute} function.
 */
contract CurveSwapper is BaseSwapper {
    using SafeERC20 for ERC20;

    // Defaults to Curve Router NG on mainnet.
    address public curveRouter = 0xF0d4c12A5768D806021F80a262B4d39d26C58b8D;

    // Route config per token pair: from => to => RouteParams
    struct CurveRouteParams {
        address[11] route;
        uint256[5][5] swapParams;
        address[5] pools;
    }

    mapping(address => mapping(address => CurveRouteParams))
        internal _curveRoutes;

    /**
     * @dev Set the Curve route for a token pair.
     * @param _from The input token.
     * @param _to The output token.
     * @param _route The route array [token_in, pool, token_out, pool, ...].
     * @param _swapParams The swap params array [i, j, swap_type, pool_type, n_coins] per step.
     * @param _pools Pool addresses (only needed for swap_type 3).
     */
    function _setCurveRoute(
        address _from,
        address _to,
        address[11] memory _route,
        uint256[5][5] memory _swapParams,
        address[5] memory _pools
    ) internal virtual {
        require(_route[0] == _from, "!route");
        _curveRoutes[_from][_to] = CurveRouteParams(
            _route,
            _swapParams,
            _pools
        );
    }

    /**
     * @dev Used to swap a specific amount of `_from` to `_to`.
     * This will check and handle all allowances as well as not swapping
     * unless `_amountIn` is greater than the set `minAmountToSell`.
     *
     * A route for the token pair must be set via {_setCurveRoute}
     * otherwise this function will revert.
     *
     * @param _from The token we are swapping from.
     * @param _to The token we are swapping to.
     * @param _amountIn The amount of `_from` we will swap.
     * @param _minAmountOut The min of `_to` to get out.
     * @return _amountOut The actual amount of `_to` that was swapped to.
     */
    function _curveSwapFrom(
        address _from,
        address _to,
        uint256 _amountIn,
        uint256 _minAmountOut
    ) internal virtual returns (uint256 _amountOut) {
        if (_amountIn != 0 && _amountIn >= minAmountToSell) {
            _checkAllowance(curveRouter, _from, _amountIn);

            CurveRouteParams storage params = _curveRoutes[_from][_to];

            _amountOut = ICurveRouter(curveRouter).exchange(
                params.route,
                params.swapParams,
                _amountIn,
                _minAmountOut,
                params.pools,
                address(this)
            );
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
            ERC20(_token).forceApprove(_contract, 0);
            ERC20(_token).forceApprove(_contract, _amount);
        }
    }
}
