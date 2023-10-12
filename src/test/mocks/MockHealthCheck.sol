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
        checkHealth
        returns (uint256 _totalAssets)
    {
        _totalAssets = ERC20(asset).balanceOf(address(this));

        _executeHealthCheck(_totalAssets);
    }

    // Can't deposit if its not healthy
    function availableDepositLimit(
        address _owner
    ) public view override returns (uint256) {
        if (!_healthy()) return 0;

        return super.availableDepositLimit(_owner);
    }

    // Can't Withdraw if not healthy.
    function availableWithdrawLimit(
        address _owner
    ) public view override returns (uint256) {
        if (!_healthy()) return 0;

        return super.availableWithdrawLimit(_owner);
    }

    function _checkHealth() internal view override {
        require(_healthy(), "unhealthy");
    }

    function _healthy() internal view returns (bool) {
        return healthy;
    }

    function setHealthy(bool _health) external {
        healthy = _health;
    }
}

import {IBaseHealthCheck} from "../../HealthCheck/IBaseHealthCheck.sol";

interface IMockHealthCheck is IBaseHealthCheck {
    function healthy() external view returns (bool);

    function setHealthy(bool _health) external;
}
