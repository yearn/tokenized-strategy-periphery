// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.18;

import {FluidSwapper} from "../../swappers/FluidSwapper.sol";
import {BaseStrategy, ERC20} from "@tokenized-strategy/BaseStrategy.sol";

contract MockFluidSwapper is BaseStrategy, FluidSwapper {
    constructor(address _asset) BaseStrategy(_asset, "Mock Fluid") {}

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

    function setBase(address _base) external {
        base = _base;
    }

    function setFluidDex(
        address _token0,
        address _token1,
        address _dex
    ) external {
        _setFluidDex(_token0, _token1, _dex);
    }

    function setFluidDex(
        address _from,
        address _to,
        address _dex,
        bool _swap0to1
    ) external {
        _setFluidDex(_from, _to, _dex, _swap0to1);
    }

    function fluidSwapFrom(
        address _from,
        address _to,
        uint256 _amountIn,
        uint256 _minAmountOut
    ) external returns (uint256) {
        return _fluidSwapFrom(_from, _to, _amountIn, _minAmountOut);
    }

    function swapFrom(
        address _from,
        address _to,
        uint256 _amountIn,
        uint256 _minAmountOut
    ) external returns (uint256) {
        return _fluidSwapFrom(_from, _to, _amountIn, _minAmountOut);
    }
}

import {IStrategy} from "@tokenized-strategy/interfaces/IStrategy.sol";
import {IFluidSwapper} from "../../swappers/interfaces/IFluidSwapper.sol";

interface IMockFluidSwapper is IStrategy, IFluidSwapper {
    function setMinAmountToSell(uint256 _minAmountToSell) external;

    function setBase(address _base) external;

    function setFluidDex(
        address _token0,
        address _token1,
        address _dex
    ) external;

    function setFluidDex(
        address _from,
        address _to,
        address _dex,
        bool _swap0to1
    ) external;

    function fluidSwapFrom(
        address _from,
        address _to,
        uint256 _amountIn,
        uint256 _minAmountOut
    ) external returns (uint256);

    function swapFrom(
        address _from,
        address _to,
        uint256 _amountIn,
        uint256 _minAmountOut
    ) external returns (uint256);
}
