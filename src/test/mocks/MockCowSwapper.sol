// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.18;

import {CowSwapper} from "../../swappers/CowSwapper.sol";
import {BaseStrategy} from "@tokenized-strategy/BaseStrategy.sol";

contract MockCowSwapper is BaseStrategy, CowSwapper {
    constructor(address _asset) BaseStrategy(_asset, "Mock Cow Swapper") {}

    function _deployFunds(uint256) internal override {}

    function _freeFunds(uint256) internal override {}

    function _harvestAndReport()
        internal
        override
        returns (uint256 _totalAssets)
    {
        _totalAssets = asset.balanceOf(address(this));
    }

    function setMinAmountToSell(
        uint256 _minAmountToSell
    ) external onlyManagement {
        _setMinAmountToSell(_minAmountToSell);
    }

    function setCowOrderDuration(
        uint32 _cowOrderDuration
    ) external onlyManagement {
        _setCowOrderDuration(_cowOrderDuration);
    }

    function setCowAppData(bytes32 _cowAppData) external onlyManagement {
        _setCowAppData(_cowAppData);
    }

    function setCowSettlement(address _cowSettlement) external onlyManagement {
        _setCowSettlement(_cowSettlement);
    }

    function setCowVaultRelayer(
        address _cowVaultRelayer
    ) external onlyManagement {
        _setCowVaultRelayer(_cowVaultRelayer);
    }

    function requestCowSwap(
        address _from,
        address _to,
        uint256 _amountIn,
        uint256 _minAmountOut
    ) external onlyKeepers returns (bytes32) {
        return _cowSwapFrom(_from, _to, _amountIn, _minAmountOut);
    }

    function requestCowSwap(
        address _from,
        address _to,
        uint256 _amountIn,
        uint256 _minAmountOut,
        uint32 _validTo
    ) external onlyKeepers returns (bytes32) {
        return _cowSwapFrom(_from, _to, _amountIn, _minAmountOut, _validTo);
    }

    function cancelCowSwap(
        address _from
    ) external onlyManagement returns (bytes32) {
        return _cancelCowSwap(_from);
    }
}

import {IStrategy} from "@tokenized-strategy/interfaces/IStrategy.sol";
import {ICowSwapper} from "../../swappers/interfaces/ICowSwapper.sol";

interface IMockCowSwapper is IStrategy, ICowSwapper {
    function setMinAmountToSell(uint256 _minAmountToSell) external;

    function setCowOrderDuration(uint32 _cowOrderDuration) external;

    function setCowAppData(bytes32 _cowAppData) external;

    function setCowSettlement(address _cowSettlement) external;

    function setCowVaultRelayer(address _cowVaultRelayer) external;

    function requestCowSwap(
        address _from,
        address _to,
        uint256 _amountIn,
        uint256 _minAmountOut
    ) external returns (bytes32);

    function requestCowSwap(
        address _from,
        address _to,
        uint256 _amountIn,
        uint256 _minAmountOut,
        uint32 _validTo
    ) external returns (bytes32);

    function cancelCowSwap(address _from) external returns (bytes32);
}
