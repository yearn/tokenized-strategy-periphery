// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.18;

import {BaseHealthCheck, ERC20} from "../../Bases/HealthCheck/BaseHealthCheck.sol";

contract MockHealthCheck is BaseHealthCheck {
    bool public healthy = true;

    constructor(address _asset) BaseHealthCheck(_asset, "Mock Health Check") {}

    function _deployFunds(uint256) internal override {}

    function _freeFunds(uint256) internal override {}

    function _harvestAndReport()
        internal
        override
        returns (uint256 _totalAssets)
    {
        _totalAssets = asset.balanceOf(address(this));
    }
}

import {IBaseHealthCheck} from "../../Bases/HealthCheck/IBaseHealthCheck.sol";

interface IMockHealthCheck is IBaseHealthCheck {}
