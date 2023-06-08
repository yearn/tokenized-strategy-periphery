// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {HealthCheck} from "../HealthCheck/HealthCheck.sol";
import {BaseTokenizedStrategy} from "@tokenized-strategy/BaseTokenizedStrategy.sol";

contract MockHealthCheck is BaseTokenizedStrategy, HealthCheck {
    constructor(
        address _asset
    ) BaseTokenizedStrategy(_asset, "Mock Health Check") {}

    function _deployFunds(uint256) internal override {}

    function _freeFunds(uint256) internal override {}

    function _harvestAndReport()
        internal
        override
        returns (uint256 _totalAssets)
    {
        _totalAssets = ERC20(asset).balanceOf(address(this));

        if (doHealthCheck) {
            require(_executHealthCheck(_totalAssets), "!healthcheck");
        }
    }

    function setProfitLimitRatio(
        uint256 _profitLimitRatio
    ) external onlyManagement {
        _setProfitLimitRatio(_profitLimitRatio);
    }

    function setLossLimitRatio(
        uint256 _lossLimitRatio
    ) external onlyManagement {
        _setLossLimitRatio(_lossLimitRatio);
    }

    function setDoHealthCheck(bool _doHealthCheck) external onlyManagement {
        doHealthCheck = _doHealthCheck;
    }
}

import {IStrategy} from "@tokenized-strategy/interfaces/IStrategy.sol";
import {IHealthCheck} from "../HealthCheck/IHealthCheck.sol";

interface IMockHealthCheck is IStrategy, IHealthCheck {
    function setProfitLimitRatio(uint256 _profitLimitRatio) external;

    function setLossLimitRatio(uint256 _lossLimitRatio) external;

    function setDoHealthCheck(bool _doHealthCheck) external;
}
