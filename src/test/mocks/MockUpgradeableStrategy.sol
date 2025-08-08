// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import {BaseStrategyUpgradeable, ERC20} from "../../Bases/Upgradeable/BaseStrategyUpgradeable.sol";

/**
 * @title MockUpgradeableStrategy
 * @notice Basic implementation of BaseStrategyUpgradeable for testing
 */
contract MockUpgradeableStrategy is BaseStrategyUpgradeable {
    
    // Track deployed funds for testing
    uint256 public deployedFunds;
    
    constructor() BaseStrategyUpgradeable() {}
    
    function initialize(
        address _asset,
        string memory _name,
        address _management,
        address _performanceFeeRecipient,
        address _keeper
    ) public initializer {
        __BaseStrategy_init(_asset, _name, _management, _performanceFeeRecipient, _keeper);
    }
    
    function _deployFunds(uint256 _amount) internal override {
        // In a real strategy, this would deploy funds somewhere
        // For testing, we just track the amount
        deployedFunds += _amount;
    }
    
    function _freeFunds(uint256 _amount) internal override {
        uint256 toFree = _amount > deployedFunds ? deployedFunds : _amount;
        deployedFunds -= toFree;
    }
    
    function _harvestAndReport() internal override returns (uint256) {
        // Return the total - both idle (in contract) and deployed
        // For testing purposes, deployedFunds represents funds that are "deployed"
        return asset.balanceOf(address(this)) + deployedFunds;
    }
    
    function _emergencyWithdraw(uint256 _amount) internal override {
        uint256 toWithdraw = _amount > deployedFunds ? deployedFunds : _amount;
        deployedFunds -= toWithdraw;
    }
}

/**
 * @title MockUpgradeableStrategyV2
 * @notice Version 2 with additional storage for upgrade testing
 */
contract MockUpgradeableStrategyV2 is BaseStrategyUpgradeable {
    
    // Original storage
    uint256 public deployedFunds;
    
    // New storage added in V2 (using the gap)
    uint256 public newVariable;
    mapping(address => uint256) public userBalances;
    
    constructor() BaseStrategyUpgradeable() {}
    
    function initialize(
        address _asset,
        string memory _name,
        address _management,
        address _performanceFeeRecipient,
        address _keeper
    ) public initializer {
        __BaseStrategy_init(_asset, _name, _management, _performanceFeeRecipient, _keeper);
    }
    
    function _deployFunds(uint256 _amount) internal override {
        // In a real strategy, this would deploy funds somewhere
        // For testing, we just track the amount
        deployedFunds += _amount;
    }
    
    function _freeFunds(uint256 _amount) internal override {
        uint256 toFree = _amount > deployedFunds ? deployedFunds : _amount;
        deployedFunds -= toFree;
    }
    
    function _harvestAndReport() internal override returns (uint256) {
        // Return the total - both idle (in contract) and deployed
        // For testing purposes, deployedFunds represents funds that are "deployed"
        return asset.balanceOf(address(this)) + deployedFunds;
    }
    
    // New function in V2
    function setNewVariable(uint256 _value) external onlyManagement {
        newVariable = _value;
    }
    
    // New function to test mapping
    function setUserBalance(address _user, uint256 _amount) external onlyManagement {
        userBalances[_user] = _amount;
    }
    
    function _emergencyWithdraw(uint256 _amount) internal override {
        uint256 toWithdraw = _amount > deployedFunds ? deployedFunds : _amount;
        deployedFunds -= toWithdraw;
    }
}