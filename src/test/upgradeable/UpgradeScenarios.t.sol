// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import {UpgradeableSetup, IStrategy, SafeERC20, ERC20} from "../utils/UpgradeableSetup.sol";
import {MockUpgradeableStrategy, MockUpgradeableStrategyV2} from "../mocks/MockUpgradeableStrategy.sol";
import {MockHealthCheckUpgradeable} from "../mocks/MockHealthCheckUpgradeable.sol";
import {MockHooksUpgradeable} from "../mocks/MockHooksUpgradeable.sol";
import {TransparentUpgradeableProxy, ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract UpgradeScenariosTest is UpgradeableSetup {
    using SafeERC20 for ERC20;

    function test_deployAndUpgradeV1ToV2() public {
        // Deploy V1
        address implV1 = address(new MockUpgradeableStrategy());
        address proxy = deployUpgradeableStrategy(
            implV1,
            address(asset),
            "Strategy V1"
        );
        
        MockUpgradeableStrategy strategyV1 = MockUpgradeableStrategy(proxy);
        
        // Use V1
        uint256 depositAmount = maxFuzzAmount / 2;
        mintAndDepositIntoStrategy(IStrategy(proxy), user, depositAmount);
        
        assertEq(strategyV1.deployedFunds(), depositAmount);
        assertEq(IStrategy(proxy).balanceOf(user), depositAmount);
        
        // Store state before upgrade
        uint256 totalAssets = IStrategy(proxy).totalAssets();
        uint256 userBalance = IStrategy(proxy).balanceOf(user);
        uint256 deployedFunds = strategyV1.deployedFunds();
        
        // Deploy V2 implementation
        address implV2 = address(new MockUpgradeableStrategyV2());
        
        // Upgrade to V2
        upgradeProxy(proxy, implV2);
        
        MockUpgradeableStrategyV2 strategyV2 = MockUpgradeableStrategyV2(proxy);
        
        // Verify state preserved
        assertEq(IStrategy(proxy).totalAssets(), totalAssets, "totalAssets changed");
        assertEq(IStrategy(proxy).balanceOf(user), userBalance, "user balance changed");
        assertEq(strategyV2.deployedFunds(), deployedFunds, "deployedFunds changed");
        
        // Test new V2 functionality
        vm.prank(management);
        strategyV2.setNewVariable(42);
        assertEq(strategyV2.newVariable(), 42);
        
        vm.prank(management);
        strategyV2.setUserBalance(user, 100);
        assertEq(strategyV2.userBalances(user), 100);
        
        // Verify old functionality still works
        uint256 balanceBefore = asset.balanceOf(user);
        vm.prank(user);
        IStrategy(proxy).redeem(depositAmount, user, user);
        assertEq(asset.balanceOf(user), balanceBefore + depositAmount);
    }

    function test_upgradeChain_Strategy_HealthCheck_Hooks() public {
        uint256 depositAmount = maxFuzzAmount / 2;
        
        // Step 1: Deploy as basic strategy
        address strategyImpl = address(new MockUpgradeableStrategy());
        address proxy = deployUpgradeableStrategy(
            strategyImpl,
            address(asset),
            "Basic Strategy"
        );
        
        mintAndDepositIntoStrategy(IStrategy(proxy), user, depositAmount);
        
        // Step 2: Upgrade to HealthCheck
        address healthCheckImpl = address(new MockHealthCheckUpgradeable());
        upgradeProxy(proxy, healthCheckImpl);
        
        MockHealthCheckUpgradeable healthCheck = MockHealthCheckUpgradeable(proxy);
        
        // Initialize health check values after upgrade
        vm.prank(management);
        healthCheck.initializeHealthCheck();
        
        // Verify health check functionality
        assertEq(healthCheck.doHealthCheck(), true);
        assertEq(healthCheck.profitLimitRatio(), 10_000);
        assertEq(healthCheck.lossLimitRatio(), 0);
        
        // Set health check parameters
        vm.prank(management);
        healthCheck.setProfitLimitRatio(5_000);
        
        // Step 3: Upgrade to Hooks
        address hooksImpl = address(new MockHooksUpgradeable());
        upgradeProxy(proxy, hooksImpl);
        
        MockHooksUpgradeable hooks = MockHooksUpgradeable(proxy);
        
        // Verify health check settings preserved
        assertEq(hooks.doHealthCheck(), true);
        assertEq(hooks.profitLimitRatio(), 5_000);
        
        // Verify all functionality works
        assertEq(IStrategy(proxy).totalAssets(), depositAmount);
        assertEq(IStrategy(proxy).balanceOf(user), depositAmount);
        
        // Test withdrawal with hooks
        uint256 balanceBefore = asset.balanceOf(user);
        vm.prank(user);
        IStrategy(proxy).withdraw(depositAmount, user, user);
        
        assertEq(asset.balanceOf(user), balanceBefore + depositAmount);
    }

    function test_storageGapUsage() public {
        // Deploy V1 with basic storage
        address implV1 = address(new MockUpgradeableStrategy());
        address proxy = deployUpgradeableStrategy(
            implV1,
            address(asset),
            "Gap Test"
        );
        
        // Add some data
        mintAndDepositIntoStrategy(IStrategy(proxy), user, maxFuzzAmount / 2);
        
        // Deploy V2 that uses storage from the gap
        address implV2 = address(new MockUpgradeableStrategyV2());
        upgradeProxy(proxy, implV2);
        
        MockUpgradeableStrategyV2 v2 = MockUpgradeableStrategyV2(proxy);
        
        // Use new storage variables
        vm.startPrank(management);
        v2.setNewVariable(123);
        v2.setUserBalance(user, 456);
        v2.setUserBalance(keeper, 789);
        vm.stopPrank();
        
        // Verify new storage works
        assertEq(v2.newVariable(), 123);
        assertEq(v2.userBalances(user), 456);
        assertEq(v2.userBalances(keeper), 789);
        
        // Verify old functionality unaffected
        assertEq(IStrategy(proxy).totalAssets(), maxFuzzAmount / 2);
    }

    function test_implementationProtection() public {
        // Deploy implementations
        MockUpgradeableStrategy strategyImpl = new MockUpgradeableStrategy();
        MockHealthCheckUpgradeable healthCheckImpl = new MockHealthCheckUpgradeable();
        MockHooksUpgradeable hooksImpl = new MockHooksUpgradeable();
        
        // Try to initialize implementations directly - should all revert
        vm.expectRevert("Initializable: contract is already initialized");
        strategyImpl.initialize(address(asset), "Direct", management, performanceFeeRecipient, keeper);
        
        vm.expectRevert("Initializable: contract is already initialized");
        healthCheckImpl.initialize(address(asset), "Direct", management, performanceFeeRecipient, keeper);
        
        vm.expectRevert("Initializable: contract is already initialized");
        hooksImpl.initialize(address(asset), "Direct", management, performanceFeeRecipient, keeper);
    }

    function test_proxyAdminControl() public {
        // Deploy strategy
        address impl = address(new MockUpgradeableStrategy());
        address proxy = deployUpgradeableStrategy(
            impl,
            address(asset),
            "Admin Test"
        );
        
        // Deploy new implementation
        address newImpl = address(new MockUpgradeableStrategyV2());
        
        // Try to upgrade without admin - should revert
        vm.expectRevert();
        vm.prank(user);
        proxyAdmin.upgrade(
            ITransparentUpgradeableProxy(payable(proxy)),
            newImpl
        );
        
        // Admin can upgrade
        upgradeProxy(proxy, newImpl);
        
        // Verify upgrade succeeded
        MockUpgradeableStrategyV2 v2 = MockUpgradeableStrategyV2(proxy);
        vm.prank(management);
        v2.setNewVariable(999);
        assertEq(v2.newVariable(), 999);
    }

    function test_emergencyUpgrade() public {
        // Deploy and use strategy
        address impl = address(new MockUpgradeableStrategy());
        address proxy = deployUpgradeableStrategy(
            impl,
            address(asset),
            "Emergency Test"
        );
        
        mintAndDepositIntoStrategy(IStrategy(proxy), user, maxFuzzAmount);
        
        // Simulate emergency - shutdown strategy
        vm.prank(management);
        IStrategy(proxy).shutdownStrategy();
        assertTrue(IStrategy(proxy).isShutdown());
        
        // Deploy emergency fix implementation
        address emergencyImpl = address(new MockUpgradeableStrategyV2());
        
        // Upgrade during emergency
        upgradeProxy(proxy, emergencyImpl);
        
        // Verify strategy still shutdown but functional
        assertTrue(IStrategy(proxy).isShutdown());
        
        // Users can still withdraw
        uint256 balanceBefore = asset.balanceOf(user);
        uint256 shares = IStrategy(proxy).balanceOf(user);
        
        vm.prank(user);
        IStrategy(proxy).redeem(shares, user, user);
        
        // User should get back at least 99% of their deposit
        assertGe(asset.balanceOf(user) - balanceBefore, maxFuzzAmount * 99 / 100);
    }

    function test_crossVersionCompatibility() public {
        // Deploy multiple versions of strategies
        address[] memory proxies = new address[](3);
        
        // V1 Strategy
        proxies[0] = deployUpgradeableStrategy(
            address(new MockUpgradeableStrategy()),
            address(asset),
            "V1"
        );
        
        // HealthCheck version
        proxies[1] = deployUpgradeableStrategy(
            address(new MockHealthCheckUpgradeable()),
            address(asset),
            "HealthCheck"
        );
        
        // Hooks version
        proxies[2] = deployUpgradeableStrategy(
            address(new MockHooksUpgradeable()),
            address(asset),
            "Hooks"
        );
        
        // All should be able to operate simultaneously
        for (uint256 i = 0; i < proxies.length; i++) {
            mintAndDepositIntoStrategy(
                IStrategy(proxies[i]),
                user,
                minFuzzAmount
            );
            
            assertEq(IStrategy(proxies[i]).totalAssets(), minFuzzAmount);
        }
        
        // Upgrade first one to V2
        upgradeProxy(
            proxies[0],
            address(new MockUpgradeableStrategyV2())
        );
        
        // All should still work
        for (uint256 i = 0; i < proxies.length; i++) {
            vm.prank(user);
            IStrategy(proxies[i]).withdraw(minFuzzAmount, user, user);
        }
    }
}