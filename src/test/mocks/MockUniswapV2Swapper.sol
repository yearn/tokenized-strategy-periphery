// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {UniswapV2Swapper} from "../../swappers/UniswapV2Swapper.sol";
import {BaseTokenizedStrategy} from "@tokenized-strategy/BaseTokenizedStrategy.sol";

contract MockUniswapV2Swapper is BaseTokenizedStrategy, UniswapV2Swapper {
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
import {IUniswapV2Swapper} from "../../swappers/interfaces/IUniswapV2Swapper.sol";

interface IMockUniswapV2Swapper is IStrategy, IUniswapV2Swapper {
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
