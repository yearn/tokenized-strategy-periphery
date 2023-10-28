// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

import {BaseHealthCheck, ERC20} from "../../HealthCheck/BaseHealthCheck.sol";

contract MockHealthCheck is BaseHealthCheck {
    bool public healthy = true;

    constructor(address _asset) BaseHealthCheck(_asset, "Mock Health Check") {}

    // `healthy` is already implemented in deposit limit so
    // doesn't need to be checked again.
    function _deployFunds(uint256) internal override {}

    // `healthy` is already implemented in withdraw limit so
    // doesn't need to be checked again.
    function _freeFunds(uint256) internal override {}

    // Uses `checkHealth` modifier
    function _harvestAndReport()
        internal
        override
        returns (uint256 _totalAssets)
    {
        _totalAssets = asset.balanceOf(address(this));
    }
}

import {IBaseHealthCheck} from "../../HealthCheck/IBaseHealthCheck.sol";

interface IMockHealthCheck is IBaseHealthCheck {}
