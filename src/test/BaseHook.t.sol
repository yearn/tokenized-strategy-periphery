// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import {Setup, IStrategy, SafeERC20, ERC20} from "./utils/Setup.sol";

import {MockHooks, HookEvents} from "./mocks/MockHooks.sol";

contract BaseHookTest is Setup, HookEvents {
    using SafeERC20 for ERC20;
    using SafeERC20 for IStrategy;

    function setUp() public override {
        super.setUp();

        mockStrategy = IStrategy(address(new MockHooks(address(asset))));

        mockStrategy.setKeeper(keeper);
        mockStrategy.setPerformanceFeeRecipient(performanceFeeRecipient);
        mockStrategy.setPendingManagement(management);
        // Accept management.
        vm.prank(management);
        mockStrategy.acceptManagement();
    }

    function test_depositHooks(uint256 _amount) public {
        vm.assume(_amount >= minFuzzAmount && _amount <= maxFuzzAmount);

        airdrop(asset, user, _amount);

        vm.startPrank(user);
        asset.safeApprove(address(mockStrategy), _amount);
        vm.stopPrank();

        // Make sure we get both events with the correct amounts.
        vm.expectEmit(true, true, true, true, address(mockStrategy));
        // Pre deposit wont have a shares amount yet
        emit PreDepositHook(_amount, 0, user);

        vm.expectEmit(true, true, true, true, address(mockStrategy));
        emit PostDepositHook(_amount, _amount, user);

        vm.prank(user);
        mockStrategy.deposit(_amount, user);

        assertEq(mockStrategy.balanceOf(user), _amount);
    }

    function test_mintHooks(uint256 _amount) public {
        vm.assume(_amount >= minFuzzAmount && _amount <= maxFuzzAmount);

        airdrop(asset, user, _amount);

        vm.startPrank(user);
        asset.safeApprove(address(mockStrategy), _amount);
        vm.stopPrank();

        // Make sure we get both events with the correct amounts.
        vm.expectEmit(true, true, true, true, address(mockStrategy));
        // Pre mint wont have a assets amount yet
        emit PreDepositHook(0, _amount, user);

        vm.expectEmit(true, true, true, true, address(mockStrategy));
        emit PostDepositHook(_amount, _amount, user);

        vm.prank(user);
        mockStrategy.mint(_amount, user);

        assertEq(mockStrategy.balanceOf(user), _amount);
        checkStrategyTotals(mockStrategy, _amount, 0, _amount);
    }

    function test_withdrawHooks(uint256 _amount) public {
        vm.assume(_amount >= minFuzzAmount && _amount <= maxFuzzAmount);

        mintAndDepositIntoStrategy(mockStrategy, user, _amount);
        assertEq(mockStrategy.balanceOf(user), _amount);
        checkStrategyTotals(mockStrategy, _amount, 0, _amount);

        // Make sure we get both events with the correct amounts.
        vm.expectEmit(true, true, true, true, address(mockStrategy));
        // Pre withdraw wont have a shares amount yet
        emit PreWithdrawHook(_amount, 0, user, user, 0);

        vm.expectEmit(true, true, true, true, address(mockStrategy));
        emit PostWithdrawHook(_amount, _amount, user, user, 0);

        vm.prank(user);
        mockStrategy.withdraw(_amount, user, user);

        checkStrategyTotals(mockStrategy, 0, 0, 0);

        // Deposit back in
        mintAndDepositIntoStrategy(mockStrategy, user, _amount);
        assertEq(mockStrategy.balanceOf(user), _amount);
        checkStrategyTotals(mockStrategy, _amount, 0, _amount);

        // Make sure works on both withdraw versions.
        vm.expectEmit(true, true, true, true, address(mockStrategy));
        // Pre withdraw wont have a shares amount yet
        emit PreWithdrawHook(_amount, 0, user, user, 8);

        vm.expectEmit(true, true, true, true, address(mockStrategy));
        emit PostWithdrawHook(_amount, _amount, user, user, 8);

        vm.prank(user);
        mockStrategy.withdraw(_amount, user, user, 8);

        checkStrategyTotals(mockStrategy, 0, 0, 0);
    }

    function test_redeemHooks(uint256 _amount) public {
        vm.assume(_amount >= minFuzzAmount && _amount <= maxFuzzAmount);

        mintAndDepositIntoStrategy(mockStrategy, user, _amount);
        assertEq(mockStrategy.balanceOf(user), _amount);
        checkStrategyTotals(mockStrategy, _amount, 0, _amount);

        // Make sure we get both events with the correct amounts.
        vm.expectEmit(true, true, true, true, address(mockStrategy));
        // Pre withdraw wont have a shares amount yet
        emit PreWithdrawHook(0, _amount, user, user, MAX_BPS);

        vm.expectEmit(true, true, true, true, address(mockStrategy));
        emit PostWithdrawHook(_amount, _amount, user, user, MAX_BPS);

        vm.prank(user);
        mockStrategy.redeem(_amount, user, user);
        checkStrategyTotals(mockStrategy, 0, 0, 0);

        // Deposit back in
        mintAndDepositIntoStrategy(mockStrategy, user, _amount);
        assertEq(mockStrategy.balanceOf(user), _amount);
        checkStrategyTotals(mockStrategy, _amount, 0, _amount);

        // Make sure works on both withdraw versions.
        vm.expectEmit(true, true, true, true, address(mockStrategy));
        // Pre withdraw wont have a shares amount yet
        emit PreWithdrawHook(0, _amount, user, user, 8);

        vm.expectEmit(true, true, true, true, address(mockStrategy));
        emit PostWithdrawHook(_amount, _amount, user, user, 8);

        vm.prank(user);
        mockStrategy.redeem(_amount, user, user, 8);

        checkStrategyTotals(mockStrategy, 0, 0, 0);
    }

    function test_transferHooks(uint256 _amount) public {
        vm.assume(_amount >= minFuzzAmount && _amount <= maxFuzzAmount);

        mintAndDepositIntoStrategy(mockStrategy, user, _amount);

        assertEq(mockStrategy.balanceOf(user), _amount);
        assertEq(mockStrategy.balanceOf(management), 0);
        checkStrategyTotals(mockStrategy, _amount, 0, _amount);

        // Make sure we get both events with the correct amounts.
        vm.expectEmit(true, true, true, true, address(mockStrategy));
        // Pre withdraw wont have a shares amount yet
        emit PreTransferHook(user, management, _amount);

        vm.expectEmit(true, true, true, true, address(mockStrategy));
        emit PostTransferHook(user, management, _amount, true);

        vm.prank(user);
        mockStrategy.transfer(management, _amount);

        assertEq(mockStrategy.balanceOf(user), 0);
        assertEq(mockStrategy.balanceOf(management), _amount);
        checkStrategyTotals(mockStrategy, _amount, 0, _amount);
    }

    function test_transferFromHooks(uint256 _amount) public {
        vm.assume(_amount >= minFuzzAmount && _amount <= maxFuzzAmount);

        mintAndDepositIntoStrategy(mockStrategy, user, _amount);

        assertEq(mockStrategy.balanceOf(user), _amount);
        assertEq(mockStrategy.balanceOf(management), 0);
        checkStrategyTotals(mockStrategy, _amount, 0, _amount);

        // Approve daddy to move funds
        vm.startPrank(user);
        mockStrategy.safeApprove(daddy, _amount);
        vm.stopPrank();

        // Make sure we get both events with the correct amounts.
        vm.expectEmit(true, true, true, true, address(mockStrategy));
        // Pre withdraw wont have a shares amount yet
        emit PreTransferHook(user, management, _amount);

        vm.expectEmit(true, true, true, true, address(mockStrategy));
        emit PostTransferHook(user, management, _amount, true);

        vm.prank(daddy);
        mockStrategy.transferFrom(user, management, _amount);

        assertEq(mockStrategy.balanceOf(user), 0);
        assertEq(mockStrategy.balanceOf(management), _amount);
        checkStrategyTotals(mockStrategy, _amount, 0, _amount);
    }
}
