// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import {UpgradeableSetup, IStrategy, SafeERC20, ERC20} from "../utils/UpgradeableSetup.sol";
import {MockHealthCheckUpgradeable, IMockHealthCheckUpgradeable} from "../mocks/MockHealthCheckUpgradeable.sol";

contract BaseHealthCheckUpgradeableTest is UpgradeableSetup {
    using SafeERC20 for ERC20;

    IMockHealthCheckUpgradeable public healthCheck;
    address public healthCheckImpl;

    function setUp() public override {
        super.setUp();

        // Deploy implementation
        healthCheckImpl = address(new MockHealthCheckUpgradeable());
        
        // Deploy proxy and initialize
        address proxy = deployUpgradeableStrategy(
            healthCheckImpl,
            address(asset),
            "Mock Health Check"
        );
        
        healthCheck = IMockHealthCheckUpgradeable(proxy);
        vm.prank(management);
        healthCheck.setKeeper(keeper);
    }

    function test_setup_healthCheckUpgradeable(uint256 _amount) public {
        vm.assume(_amount >= minFuzzAmount && _amount <= maxFuzzAmount);

        // Defaults to true
        assertEq(
            healthCheck.doHealthCheck(),
            true,
            "doHealthCheck should be true"
        );
        // Defaults to 100%
        assertEq(
            healthCheck.profitLimitRatio(),
            10_000,
            "profitLimitRatio should be 10000"
        );
        // Defaults to 0%
        assertEq(healthCheck.lossLimitRatio(), 0, "lossLimitRatio should be 0");

        mintAndDepositIntoStrategy(
            IStrategy(address(healthCheck)),
            user,
            _amount
        );

        vm.prank(keeper);
        healthCheck.report();

        // Should still be true
        assertEq(
            healthCheck.doHealthCheck(),
            true,
            "doHealthCheck should be true"
        );
        // Should still be 100%
        assertEq(
            healthCheck.profitLimitRatio(),
            10_000,
            "profitLimitRatio should be 10000"
        );
        // Should still be 0%
        assertEq(healthCheck.lossLimitRatio(), 0, "lossLimitRatio should be 0");

        skip(healthCheck.profitMaxUnlockTime());

        // Should still be true
        assertEq(
            healthCheck.doHealthCheck(),
            true,
            "doHealthCheck should be true"
        );
        // Should still be 100%
        assertEq(
            healthCheck.profitLimitRatio(),
            10_000,
            "profitLimitRatio should be 10000"
        );
        // Should still be 0%
        assertEq(healthCheck.lossLimitRatio(), 0, "lossLimitRatio should be 0");

        vm.prank(user);
        healthCheck.redeem(_amount, user, user);

        assertGe(asset.balanceOf(user), _amount);

        // Should still be true
        assertEq(
            healthCheck.doHealthCheck(),
            true,
            "doHealthCheck should be true"
        );
        // Should still be 100%
        assertEq(
            healthCheck.profitLimitRatio(),
            10_000,
            "profitLimitRatio should be 10000"
        );
        // Should still be 0%
        assertEq(healthCheck.lossLimitRatio(), 0, "lossLimitRatio should be 0");
    }

    function test_limitsUpgradeable() public {
        // Test profit limit ratio bounds
        vm.prank(management);
        vm.expectRevert("!zero profit");
        healthCheck.setProfitLimitRatio(0);

        vm.prank(management);
        vm.expectRevert("!too high");
        healthCheck.setProfitLimitRatio(type(uint256).max);

        vm.prank(management);
        healthCheck.setProfitLimitRatio(5_000);
        assertEq(healthCheck.profitLimitRatio(), 5_000);

        // Test loss limit ratio bounds
        vm.prank(management);
        vm.expectRevert("!loss limit");
        healthCheck.setLossLimitRatio(10_000);

        vm.prank(management);
        healthCheck.setLossLimitRatio(5_000);
        assertEq(healthCheck.lossLimitRatio(), 5_000);

        // Test access control
        vm.expectRevert("!management");
        healthCheck.setProfitLimitRatio(1_000);

        vm.expectRevert("!management");
        healthCheck.setLossLimitRatio(1_000);

        vm.expectRevert("!management");
        healthCheck.setDoHealthCheck(false);
    }

    function test_reportTurnsHealthCheckBackOnUpgradeable(uint256 _amount) public {
        vm.assume(_amount >= minFuzzAmount && _amount <= maxFuzzAmount);

        mintAndDepositIntoStrategy(
            IStrategy(address(healthCheck)),
            user,
            _amount
        );

        assertEq(healthCheck.doHealthCheck(), true);

        // Turn off health check
        vm.prank(management);
        healthCheck.setDoHealthCheck(false);
        assertEq(healthCheck.doHealthCheck(), false);

        // Report should turn it back on
        vm.prank(keeper);
        healthCheck.report();

        assertEq(healthCheck.doHealthCheck(), true);
    }

    function test__normalHealthCheckUpgradeable(uint256 _amount) public {
        vm.assume(_amount >= minFuzzAmount && _amount <= maxFuzzAmount);

        mintAndDepositIntoStrategy(
            IStrategy(address(healthCheck)),
            user,
            _amount
        );

        // Set limits
        vm.startPrank(management);
        healthCheck.setProfitLimitRatio(5_000); // 50%
        healthCheck.setLossLimitRatio(5_000); // 50%
        vm.stopPrank();

        // Normal report should succeed
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = healthCheck.report();
        
        assertEq(profit, 0);
        assertEq(loss, 0);
    }

    function test__toMuchProfit_reverts__increaseLimitUpgradeable(uint256 _amount) public {
        vm.assume(_amount >= minFuzzAmount && _amount <= maxFuzzAmount);

        mintAndDepositIntoStrategy(
            IStrategy(address(healthCheck)),
            user,
            _amount
        );

        // Set very low profit limit
        vm.prank(management);
        healthCheck.setProfitLimitRatio(1); // 0.01%

        // Simulate profit
        airdrop(asset, address(healthCheck), _amount);

        // Report should revert due to health check
        vm.prank(keeper);
        vm.expectRevert("healthCheck");
        healthCheck.report();

        // Increase limit and try again
        vm.prank(management);
        healthCheck.setProfitLimitRatio(10_000); // 100%

        vm.prank(keeper);
        (uint256 profit, uint256 loss) = healthCheck.report();
        
        assertEq(profit, _amount);
        assertEq(loss, 0);
    }

    function test_loss_reverts_increaseLimitUpgradeable(uint256 _amount) public {
        vm.assume(_amount >= minFuzzAmount && _amount <= maxFuzzAmount);

        mintAndDepositIntoStrategy(
            IStrategy(address(healthCheck)),
            user,
            _amount
        );

        // Set loss limit to 0
        vm.prank(management);
        healthCheck.setLossLimitRatio(0);

        // Simulate loss
        vm.prank(management);
        MockHealthCheckUpgradeable(address(healthCheck)).simulateLoss(_amount / 2);

        // Report should revert due to health check
        vm.prank(keeper);
        vm.expectRevert("healthCheck");
        healthCheck.report();

        // Increase limit and try again
        vm.prank(management);
        healthCheck.setLossLimitRatio(5_000); // 50%

        vm.prank(keeper);
        (uint256 profit, uint256 loss) = healthCheck.report();
        
        assertEq(profit, 0);
        assertEq(loss, _amount / 2);
    }

    function test_toMuchProfit_reverts_turnOffCheckUpgradeable(uint256 _amount) public {
        vm.assume(_amount >= minFuzzAmount && _amount <= maxFuzzAmount);

        mintAndDepositIntoStrategy(
            IStrategy(address(healthCheck)),
            user,
            _amount
        );

        // Set very low profit limit
        vm.prank(management);
        healthCheck.setProfitLimitRatio(1); // 0.01%

        // Simulate profit
        airdrop(asset, address(healthCheck), _amount);

        // Report should revert
        vm.prank(keeper);
        vm.expectRevert("healthCheck");
        healthCheck.report();

        // Turn off health check
        vm.prank(management);
        healthCheck.setDoHealthCheck(false);

        // Now report should succeed
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = healthCheck.report();
        
        assertEq(profit, _amount);
        assertEq(loss, 0);
        
        // Health check should be back on
        assertEq(healthCheck.doHealthCheck(), true);
    }

    function test_loss_reverts_turnOffCheckUpgradeable(uint256 _amount) public {
        vm.assume(_amount >= minFuzzAmount && _amount <= maxFuzzAmount);

        mintAndDepositIntoStrategy(
            IStrategy(address(healthCheck)),
            user,
            _amount
        );

        // Set loss limit to 0
        vm.prank(management);
        healthCheck.setLossLimitRatio(0);

        // Simulate loss
        vm.prank(management);
        MockHealthCheckUpgradeable(address(healthCheck)).simulateLoss(_amount / 2);

        // Report should revert
        vm.prank(keeper);
        vm.expectRevert("healthCheck");
        healthCheck.report();

        // Turn off health check
        vm.prank(management);
        healthCheck.setDoHealthCheck(false);

        // Now report should succeed
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = healthCheck.report();
        
        assertEq(profit, 0);
        assertEq(loss, _amount / 2);
        
        // Health check should be back on
        assertEq(healthCheck.doHealthCheck(), true);
    }

    // Upgrade-specific tests
    function test_storageLayoutHealthCheck() public {
        // Verify storage slots
        // Slots 0-9: from BaseStrategyUpgradeable
        // Slot 10: doHealthCheck (bool) + _profitLimitRatio (uint16) + _lossLimitRatio (uint16)
        
        bytes32 slot10 = readStorageSlot(address(healthCheck), 10);
        
        // Extract values from packed slot
        bool doHealthCheck = uint8(uint256(slot10)) != 0;
        uint16 profitRatio = uint16(uint256(slot10) >> 8);
        uint16 lossRatio = uint16(uint256(slot10) >> 24);
        
        assertEq(doHealthCheck, true);
        assertEq(profitRatio, 10_000);
        assertEq(lossRatio, 0);
        
        // Verify gap slots are empty (11-19)
        for (uint256 i = 11; i <= 19; i++) {
            bytes32 gapSlot = readStorageSlot(address(healthCheck), i);
            assertEq(gapSlot, bytes32(0), "Gap slot should be empty");
        }
    }

    function test_upgradeFromBaseStrategy() public {
        // Deploy a basic strategy first
        MockHealthCheckUpgradeable newImpl = new MockHealthCheckUpgradeable();
        
        // Deposit some funds
        mintAndDepositIntoStrategy(
            IStrategy(address(healthCheck)),
            user,
            maxFuzzAmount
        );
        
        // Store current state
        uint256 totalAssets = healthCheck.totalAssets();
        uint256 userBalance = healthCheck.balanceOf(user);
        
        // Upgrade (would need admin access in real scenario)
        upgradeProxy(address(healthCheck), address(newImpl));
        
        // Verify state preserved
        assertEq(healthCheck.totalAssets(), totalAssets);
        assertEq(healthCheck.balanceOf(user), userBalance);
        
        // Verify health check functionality still works
        assertEq(healthCheck.doHealthCheck(), true);
        assertEq(healthCheck.profitLimitRatio(), 10_000);
    }
}