// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import {BaseHooksUpgradeable, ERC20} from "../../Bases/Upgradeable/BaseHooksUpgradeable.sol";

contract HookEvents {
    event PreDepositHook(uint256 assets, uint256 shares, address receiver);

    event PostDepositHook(uint256 assets, uint256 shares, address receiver);

    event PreWithdrawHook(
        uint256 assets,
        uint256 shares,
        address receiver,
        address owner,
        uint256 maxLoss
    );

    event PostWithdrawHook(
        uint256 assets,
        uint256 shares,
        address receiver,
        address owner,
        uint256 maxLoss
    );

    event PreTransferHook(address from, address to, uint256 amount);

    event PostTransferHook(
        address from,
        address to,
        uint256 amount,
        bool success
    );
}

contract MockHooksUpgradeable is BaseHooksUpgradeable, HookEvents {
    constructor() BaseHooksUpgradeable() {}
    
    function initialize(
        address _asset,
        string memory _name,
        address _management,
        address _performanceFeeRecipient,
        address _keeper
    ) public initializer {
        __BaseHooks_init(_asset, _name, _management, _performanceFeeRecipient, _keeper);
    }

    function _preDepositHook(
        uint256 assets,
        uint256 shares,
        address receiver
    ) internal override {
        emit PreDepositHook(assets, shares, receiver);
    }

    function _postDepositHook(
        uint256 assets,
        uint256 shares,
        address receiver
    ) internal override {
        emit PostDepositHook(assets, shares, receiver);
    }

    function _preWithdrawHook(
        uint256 assets,
        uint256 shares,
        address receiver,
        address owner,
        uint256 maxLoss
    ) internal override {
        emit PreWithdrawHook(assets, shares, receiver, owner, maxLoss);
    }

    function _postWithdrawHook(
        uint256 assets,
        uint256 shares,
        address receiver,
        address owner,
        uint256 maxLoss
    ) internal override {
        emit PostWithdrawHook(assets, shares, receiver, owner, maxLoss);
    }

    function _preTransferHook(
        address from,
        address to,
        uint256 amount
    ) internal override {
        emit PreTransferHook(from, to, amount);
    }

    function _postTransferHook(
        address from,
        address to,
        uint256 amount,
        bool success
    ) internal override {
        emit PostTransferHook(from, to, amount, success);
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
    
    // Upgrade function to initialize health check values when upgrading from a non-health check strategy
    // Hooks inherits from HealthCheck, so we need to ensure health check values are set
    function initializeHealthCheck() external onlyManagement {
        // Initialize health check variables if they haven't been set
        if (!doHealthCheck) {
            doHealthCheck = true;
            _setProfitLimitRatio(10_000);
            _setLossLimitRatio(0);
        }
    }
}