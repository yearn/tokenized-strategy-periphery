// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.18;

import {BaseHealthCheckUpgradeable, ERC20} from "../../Bases/Upgradeable/BaseHealthCheckUpgradeable.sol";
import {IBaseHealthCheck} from "../../Bases/HealthCheck/IBaseHealthCheck.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract MockHealthCheckUpgradeable is BaseHealthCheckUpgradeable {
    using SafeERC20 for ERC20;
    
    bool public healthy = true;
    // Keep deployedFunds for storage layout compatibility
    // But don't use it in _harvestAndReport to avoid double-counting
    uint256 public deployedFunds;

    constructor() BaseHealthCheckUpgradeable() {}
    
    function initialize(
        address _asset,
        string memory _name,
        address _management,
        address _performanceFeeRecipient,
        address _keeper
    ) public initializer {
        __BaseHealthCheck_init(_asset, _name, _management, _performanceFeeRecipient, _keeper);
    }

    function _deployFunds(uint256 _amount) internal override {
        // Track for storage layout compatibility
        deployedFunds += _amount;
    }

    function _freeFunds(uint256 _amount) internal override {
        // Track for storage layout compatibility
        if (_amount > deployedFunds) {
            deployedFunds = 0;
        } else {
            deployedFunds -= _amount;
        }
    }

    function _harvestAndReport()
        internal
        override
        returns (uint256 _totalAssets)
    {
        // Simple mock - just return the balance
        // This matches the non-upgradeable MockHealthCheck behavior
        _totalAssets = asset.balanceOf(address(this));
    }
    
    // Upgrade function to initialize health check values when upgrading from a non-health check strategy
    function initializeHealthCheck() external onlyManagement {
        // Initialize health check variables if they haven't been set
        // This is safe to call even if already initialized
        if (!doHealthCheck) {
            doHealthCheck = true;
            _setProfitLimitRatio(10_000);
            _setLossLimitRatio(0);
        }
    }
    
    // Function to simulate losses for testing
    function simulateLoss(uint256 _amount) external onlyManagement {
        uint256 available = asset.balanceOf(address(this));
        uint256 toLose = _amount > available ? available : _amount;
        if (toLose > 0) {
            // Transfer funds to a burn address to simulate loss
            asset.safeTransfer(address(0xdead), toLose);
        }
    }
}

interface IMockHealthCheckUpgradeable is IBaseHealthCheck {}