// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.18;

import {PendleSwapper} from "../../swappers/PendleSwapper.sol";
import {PendleSwapperWithAggregator} from "../../swappers/PendleSwapperWithAggregator.sol";
import {SwapData} from "../../interfaces/Pendle/IPendle.sol";
import {BaseStrategy, ERC20} from "@tokenized-strategy/BaseStrategy.sol";

contract MockPendleSwapper is BaseStrategy, PendleSwapper {
    constructor(address _asset) BaseStrategy(_asset, "Mock Pendle Swapper") {}

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

    function setMarket(address _pt, address _market) external {
        _setMarket(_pt, _market);
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

contract MockPendleSwapperWithAggregator is
    BaseStrategy,
    PendleSwapperWithAggregator
{
    constructor(
        address _asset
    ) BaseStrategy(_asset, "Mock Pendle Swapper With Aggregator") {}

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

    function setMarket(address _pt, address _market) external {
        _setMarket(_pt, _market);
    }

    function swapFrom(
        address _from,
        address _to,
        uint256 _amountIn,
        uint256 _minAmountOut
    ) external returns (uint256) {
        return _swapFrom(_from, _to, _amountIn, _minAmountOut);
    }

    function swapFromWithAggregator(
        address _tokenIn,
        address _pt,
        uint256 _amountIn,
        uint256 _minPtOut,
        address _tokenMintSy,
        SwapData calldata _swapData
    ) external returns (uint256) {
        return
            _swapFromWithAggregator(
                _tokenIn,
                _pt,
                _amountIn,
                _minPtOut,
                _tokenMintSy,
                _swapData
            );
    }

    function swapToWithAggregator(
        address _pt,
        address _tokenOut,
        uint256 _amountIn,
        uint256 _minTokenOut,
        address _tokenRedeemSy,
        SwapData calldata _swapData
    ) external returns (uint256) {
        return
            _swapToWithAggregator(
                _pt,
                _tokenOut,
                _amountIn,
                _minTokenOut,
                _tokenRedeemSy,
                _swapData
            );
    }
}

import {IStrategy} from "@tokenized-strategy/interfaces/IStrategy.sol";
import {IPendleSwapper} from "../../swappers/interfaces/IPendleSwapper.sol";

interface IMockPendleSwapper is IStrategy, IPendleSwapper {
    function setMinAmountToSell(uint256 _minAmountToSell) external;

    function setMarket(address _pt, address _market) external;

    function swapFrom(
        address _from,
        address _to,
        uint256 _amountIn,
        uint256 _minAmountOut
    ) external returns (uint256);
}

interface IMockPendleSwapperWithAggregator is IMockPendleSwapper {
    function swapFromWithAggregator(
        address _tokenIn,
        address _pt,
        uint256 _amountIn,
        uint256 _minPtOut,
        address _tokenMintSy,
        SwapData calldata _swapData
    ) external returns (uint256);

    function swapToWithAggregator(
        address _pt,
        address _tokenOut,
        uint256 _amountIn,
        uint256 _minTokenOut,
        address _tokenRedeemSy,
        SwapData calldata _swapData
    ) external returns (uint256);
}
