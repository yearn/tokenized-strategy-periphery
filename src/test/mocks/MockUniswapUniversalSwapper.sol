// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.18;

import {UniswapUniversalSwapper} from "../../swappers/UniswapUniversalSwapper.sol";
import {BaseStrategy, ERC20} from "@tokenized-strategy/BaseStrategy.sol";

contract MockUniswapUniversalSwapper is BaseStrategy, UniswapUniversalSwapper {
    // Mainnet WETH address
    address public constant WETH_ADDR =
        0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    constructor(
        address _asset
    )
        BaseStrategy(_asset, "Mock Uniswap Universal Swapper")
        UniswapUniversalSwapper(WETH_ADDR)
    {
        // base stays as WETH (default)
    }

    function _deployFunds(uint256) internal override {}

    function _freeFunds(uint256) internal override {}

    function _harvestAndReport()
        internal
        override
        returns (uint256 _totalAssets)
    {
        _totalAssets = asset.balanceOf(address(this));
    }

    // Expose internal setters for testing

    function setMinAmountToSell(uint256 _minAmountToSell) external {
        minAmountToSell = _minAmountToSell;
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

    function setV4Pool(
        address _token0,
        address _token1,
        bytes32 _poolId
    ) external {
        _setV4Pool(_token0, _token1, _poolId);
    }

    function setV4Pool(
        address _token0,
        address _token1,
        uint24 _fee,
        int24 _tickSpacing,
        address _hooks
    ) external {
        _setV4Pool(_token0, _token1, _fee, _tickSpacing, _hooks);
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

import {IStrategy} from "@tokenized-strategy/interfaces/IStrategy.sol";
import {IUniswapUniversalSwapper} from "../../swappers/interfaces/IUniswapUniversalSwapper.sol";

interface IMockUniswapUniversalSwapper is IStrategy, IUniswapUniversalSwapper {
    function setMinAmountToSell(uint256 _minAmountToSell) external;

    function setBase(address _base) external;

    function setUniFees(address _token0, address _token1, uint24 _fee) external;

    function setV4Pool(
        address _token0,
        address _token1,
        bytes32 _poolId
    ) external;

    function setV4Pool(
        address _token0,
        address _token1,
        uint24 _fee,
        int24 _tickSpacing,
        address _hooks
    ) external;

    function swapFrom(
        address _from,
        address _to,
        uint256 _amountIn,
        uint256 _minAmountOut
    ) external returns (uint256);
}
