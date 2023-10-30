// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

import {Setup, IStrategy} from "./utils/Setup.sol";

import {MockHealthCheck, IMockHealthCheck} from "./mocks/MockHealthCheck.sol";

contract HealthCheckTest is Setup {
    IMockHealthCheck public healthCheck;

    function setUp() public override {
        super.setUp();

        healthCheck = IMockHealthCheck(
            address(new MockHealthCheck(address(asset)))
        );

        healthCheck.setKeeper(keeper);
        healthCheck.setPerformanceFeeRecipient(performanceFeeRecipient);
        healthCheck.setPendingManagement(management);
        // Accept management.
        vm.prank(management);
        healthCheck.acceptManagement();
    }

    function test_setup_healthCheck(uint256 _amount) public {
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

    function test_limits() public {
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

        // Test setProfitLimitRatio with zero limit
        vm.expectRevert("!zero profit");
        vm.prank(management);
        healthCheck.setProfitLimitRatio(0);

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

        uint256 max = 10_000;

        // Test setLossLimitRatio with max limit
        vm.expectRevert("!loss limit");
        vm.prank(management);
        healthCheck.setLossLimitRatio(max);

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

    function test_reportTurnsHealthCheckBackOn(uint256 _amount) public {
        vm.assume(_amount >= minFuzzAmount && _amount <= maxFuzzAmount);

        // deposit
        mintAndDepositIntoStrategy(
            IStrategy(address(healthCheck)),
            user,
            _amount
        );

        // Turn off HealthCheck
        vm.prank(management);
        healthCheck.setDoHealthCheck(false);

        assertEq(
            healthCheck.doHealthCheck(),
            false,
            "doHealthCheck should be false"
        );

        vm.prank(keeper);
        healthCheck.report();

        // Should be true again
        assertEq(
            healthCheck.doHealthCheck(),
            true,
            "doHealthCheck should be true"
        );
    }

    function test__normalHealthCheck(uint256 _amount) public {
        vm.assume(_amount >= minFuzzAmount && _amount <= maxFuzzAmount);

        // deposit
        mintAndDepositIntoStrategy(
            IStrategy(address(healthCheck)),
            user,
            _amount
        );

        uint256 profit = _amount / 10;

        // simulate earning a profit
        airdrop(asset, address(healthCheck), profit);

        assertEq(
            healthCheck.doHealthCheck(),
            true,
            "doHealthCheck should be true"
        );

        vm.prank(keeper);
        (uint256 realProfit, ) = healthCheck.report();

        // Make sure we reported the correct profit
        assertEq(profit, realProfit, "Reported profit mismatch");

        // Health Check should still be on
        assertEq(
            healthCheck.doHealthCheck(),
            true,
            "doHealthCheck should be true"
        );

        skip(healthCheck.profitMaxUnlockTime());

        vm.prank(user);
        healthCheck.redeem(_amount, user, user);

        assertGe(asset.balanceOf(user), _amount);
    }

    function test__toMuchProfit_reverts__increaseLimit(uint256 _amount) public {
        vm.assume(_amount >= minFuzzAmount && _amount <= maxFuzzAmount);

        // deposit
        mintAndDepositIntoStrategy(
            IStrategy(address(healthCheck)),
            user,
            _amount
        );

        // Defaults to 100% so should revert if over amount
        uint256 profit = _amount + 1;

        // simulate earning the profit
        airdrop(asset, address(healthCheck), profit);

        assertEq(
            healthCheck.doHealthCheck(),
            true,
            "doHealthCheck should be true"
        );

        vm.expectRevert("healthCheck");
        vm.prank(keeper);
        healthCheck.report();

        assertEq(
            healthCheck.doHealthCheck(),
            true,
            "doHealthCheck should be true"
        );

        // Increase the limit enough to allow profit
        vm.prank(management);
        healthCheck.setProfitLimitRatio(10_001);

        vm.prank(management);
        (uint256 realProfit, ) = healthCheck.report();

        assertEq(profit, realProfit, "Reported profit mismatch");

        assertEq(
            healthCheck.doHealthCheck(),
            true,
            "doHealthCheck should be true"
        );
    }

    function test_loss_reverts_increaseLimit(uint256 _amount) public {
        vm.assume(_amount >= minFuzzAmount && _amount <= maxFuzzAmount);

        // deposit
        mintAndDepositIntoStrategy(
            IStrategy(address(healthCheck)),
            user,
            _amount
        );

        // Loose .01%
        uint256 loss = _amount / 10000;

        // simulate loss
        vm.prank(address(healthCheck));
        asset.transfer(management, loss);

        assertEq(
            healthCheck.doHealthCheck(),
            true,
            "doHealthCheck should be true"
        );

        vm.expectRevert("healthCheck");
        vm.prank(keeper);
        healthCheck.report();

        assertEq(
            healthCheck.doHealthCheck(),
            true,
            "doHealthCheck should be true"
        );

        // Increase the limit enough to allow 1% loss
        vm.prank(management);
        healthCheck.setLossLimitRatio(1);

        vm.prank(keeper);
        (, uint256 realLoss) = healthCheck.report();

        assertEq(loss, realLoss, "Reported loss mismatch");

        assertEq(
            healthCheck.doHealthCheck(),
            true,
            "doHealthCheck should be true"
        );
    }

    function test_toMuchProfit_reverts_turnOffCheck(uint256 _amount) public {
        vm.assume(_amount >= minFuzzAmount && _amount <= maxFuzzAmount);

        // deposit
        mintAndDepositIntoStrategy(
            IStrategy(address(healthCheck)),
            user,
            _amount
        );

        // Defaults to 100% so should revert if over amount
        uint256 profit = _amount + 1;

        // simulate earning the profit
        airdrop(asset, address(healthCheck), profit);

        assertEq(
            healthCheck.doHealthCheck(),
            true,
            "doHealthCheck should be true"
        );

        vm.expectRevert("healthCheck");
        vm.prank(management);
        healthCheck.report();

        assertEq(
            healthCheck.doHealthCheck(),
            true,
            "doHealthCheck should be true"
        );

        // Turn off the health check
        vm.prank(management);
        healthCheck.setDoHealthCheck(false);

        vm.prank(keeper);
        (uint256 realProfit, ) = healthCheck.report();

        assertEq(profit, realProfit, "Reported profit mismatch");

        assertEq(
            healthCheck.doHealthCheck(),
            true,
            "doHealthCheck should be true"
        );
    }

    function test_loss_reverts_turnOffCheck(uint256 _amount) public {
        vm.assume(_amount >= minFuzzAmount && _amount <= maxFuzzAmount);

        // deposit
        mintAndDepositIntoStrategy(
            IStrategy(address(healthCheck)),
            user,
            _amount
        );

        // Loose .01%
        uint256 loss = _amount / 10_000;

        // simulate loss
        vm.prank(address(healthCheck));
        asset.transfer(management, loss);

        assertEq(
            healthCheck.doHealthCheck(),
            true,
            "doHealthCheck should be true"
        );

        vm.expectRevert("healthCheck");
        vm.prank(management);
        healthCheck.report();

        assertEq(
            healthCheck.doHealthCheck(),
            true,
            "doHealthCheck should be true"
        );

        // Turn off the health check
        vm.prank(management);
        healthCheck.setDoHealthCheck(false);

        vm.prank(management);
        (, uint256 realLoss) = healthCheck.report();

        assertEq(loss, realLoss, "Reported loss mismatch");

        assertEq(
            healthCheck.doHealthCheck(),
            true,
            "doHealthCheck should be true"
        );
    }
}
