// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.18;

import {SolidlySwapper} from "../../swappers/SolidlySwapper.sol";
import {BaseStrategy, ERC20} from "@tokenized-strategy/BaseStrategy.sol";

contract MockSolidlySwapper is BaseStrategy, SolidlySwapper {
    constructor(address _asset) BaseStrategy(_asset, "Mock Uni V3") {}

    function _deployFunds(uint256) internal override {}

    function _freeFunds(uint256) internal override {}

    function _harvestAndReport()
        internal
        override
        returns (uint256 _totalAssets)
    {
        _totalAssets = asset.balanceOf(address(this));
    }

    function setMinAmountToSell(uint256 _minAmountToSell) external {
        minAmountToSell = _minAmountToSell;
    }

    function setRouter(address _router) external {
        router = _router;
    }

    function setBase(address _base) external {
        base = _base;
    }

    function setStable(
        address _token0,
        address _token1,
        bool _stable
    ) external {
        _setStable(_token0, _token1, _stable);
    }

    function swapFrom(
        address _from,
        address _to,
        uint256 _amountIn,
        uint256 _minAmountOut
    ) external {
        _swapFrom(_from, _to, _amountIn, _minAmountOut);
    }
}

import {IStrategy} from "@tokenized-strategy/interfaces/IStrategy.sol";
import {ISolidlySwapper} from "../../swappers/interfaces/ISolidlySwapper.sol";

interface IMockSolidlySwapper is IStrategy, ISolidlySwapper {
    function setMinAmountToSell(uint256 _minAmountToSell) external;

    function setRouter(address _router) external;

    function setBase(address _base) external;

    function swapFrom(
        address _from,
        address _to,
        uint256 _amountIn,
        uint256 _minAmountOut
    ) external;

    function setStable(address _token0, address _token1, bool _stable) external;
}
