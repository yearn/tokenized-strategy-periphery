// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.18;

import {CurveSwapper} from "../../swappers/CurveSwapper.sol";

contract MockCurveSwapper is CurveSwapper {
    function setMinAmountToSell(uint256 _minAmountToSell) external {
        minAmountToSell = _minAmountToSell;
    }

    function setRouter(address _router) external {
        curveRouter = _router;
    }

    function setCurveRoute(
        address _from,
        address _to,
        address[11] memory _route,
        uint256[5][5] memory _swapParams,
        address[5] memory _pools
    ) external {
        _setCurveRoute(_from, _to, _route, _swapParams, _pools);
    }

    function swapFrom(
        address _from,
        address _to,
        uint256 _amountIn,
        uint256 _minAmountOut
    ) external returns (uint256) {
        return _swapFrom(_from, _to, _amountIn, _minAmountOut);
    }
}
