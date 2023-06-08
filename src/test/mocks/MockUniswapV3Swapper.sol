// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {UniswapV3Swapper} from "../swappers/UniswapV3Swapper.sol";
import {BaseTokenizedStrategy} from "@tokenized-strategy/BaseTokenizedStrategy.sol";

contract MockUniswapV3Swapper is BaseTokenizedStrategy, UniswapV3Swapper {
    constructor(address _asset) BaseTokenizedStrategy(_asset, "Mock Uni V3") {}

    function _deployFunds(uint256) internal override {}

    function _freeFunds(uint256) internal override {}

    function _harvestAndReport()
        internal
        override
        returns (uint256 _totalAssets)
    {
        _totalAssets = ERC20(asset).balanceOf(address(this));
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

    function setUniFees(
        address _token0,
        address _token1,
        uint24 _fee
    ) external {
        _setUniFees(_token0, _token1, _fee);
    }

    function swapFrom(
        address _from,
        address _to,
        uint256 _amountIn,
        uint256 _minAmountOut
    ) external returns (uint256) {
        return _swapFrom(_from, _to, _amountIn, _minAmountOut);
    }

    function swapTo(
        address _from,
        address _to,
        uint256 _amountTo,
        uint256 _maxAmountFrom
    ) external returns (uint256) {
        return _swapTo(_from, _to, _amountTo, _maxAmountFrom);
    }
}

import {IStrategy} from "@tokenized-strategy/interfaces/IStrategy.sol";
import {IUniswapV3Swapper} from "../swappers/interfaces/IUniswapV3Swapper.sol";

interface IMockUniswapV3Swapper is IStrategy, IUniswapV3Swapper {
    function setMinAmountToSell(uint256 _minAmountToSell) external;

    function setRouter(address _router) external;

    function setBase(address _base) external;

    function swapTo(
        address _from,
        address _to,
        uint256 _amountTo,
        uint256 _maxAmountFrom
    ) external returns (uint256);

    function swapFrom(
        address _from,
        address _to,
        uint256 _amountIn,
        uint256 _minAmountOut
    ) external returns (uint256);

    function setUniFees(address _token0, address _token1, uint24 _fee) external;
}
