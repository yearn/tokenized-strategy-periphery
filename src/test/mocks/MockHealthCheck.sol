// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {BaseHealthCheck} from "../../HealthCheck/BaseHealthCheck.sol";

contract MockHealthCheck is BaseHealthCheck {
    constructor(address _asset) BaseHealthCheck(_asset, "Mock Health Check") {}

    function _deployFunds(uint256) internal override checkHealth {}

    function _freeFunds(uint256) internal override checkHealth {}

    function _harvestAndReport()
        internal
        override
        checkHealth
        returns (uint256 _totalAssets)
    {
        _totalAssets = ERC20(asset).balanceOf(address(this));

        _executeHealthCheck(_totalAssets);
    }
}

import {IBaseHealthCheck} from "../../HealthCheck/IBaseHealthCheck.sol";

interface IMockHealthCheck is IBaseHealthCheck {}
