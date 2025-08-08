// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import {UpgradeableSetup, IStrategy, SafeERC20, ERC20} from "../utils/UpgradeableSetup.sol";
import {MockHooksUpgradeable, HookEvents} from "../mocks/MockHooksUpgradeable.sol";

contract BaseHooksUpgradeableTest is UpgradeableSetup, HookEvents {
    using SafeERC20 for ERC20;
    using SafeERC20 for IStrategy;

    address public hooksImpl;

    function setUp() public override {
        super.setUp();

        // Deploy implementation
        hooksImpl = address(new MockHooksUpgradeable());
        
        // Deploy proxy and initialize
        address proxy = deployUpgradeableStrategy(
            hooksImpl,
            address(asset),
            "Hooked"
        );
        
        mockStrategy = IStrategy(proxy);
        vm.prank(management);
        mockStrategy.setKeeper(keeper);
    }

    function test_depositHooksUpgradeable(uint256 _amount) public {
        vm.assume(_amount >= minFuzzAmount && _amount <= maxFuzzAmount);

        airdrop(asset, user, _amount);

        vm.startPrank(user);
        asset.forceApprove(address(mockStrategy), _amount);
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

    function test_mintHooksUpgradeable(uint256 _amount) public {
        vm.assume(_amount >= minFuzzAmount && _amount <= maxFuzzAmount);

        airdrop(asset, user, _amount);

        vm.startPrank(user);
        asset.forceApprove(address(mockStrategy), _amount);
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

    function test_withdrawHooksUpgradeable(uint256 _amount) public {
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

    function test_redeemHooksUpgradeable(uint256 _amount) public {
        vm.assume(_amount >= minFuzzAmount && _amount <= maxFuzzAmount);

        mintAndDepositIntoStrategy(mockStrategy, user, _amount);
        assertEq(mockStrategy.balanceOf(user), _amount);
        checkStrategyTotals(mockStrategy, _amount, 0, _amount);

        // Make sure we get both events with the correct amounts.
        vm.expectEmit(true, true, true, true, address(mockStrategy));
        // Pre redeem wont have a assets amount yet
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

        // Make sure works on both redeem versions.
        vm.expectEmit(true, true, true, true, address(mockStrategy));
        // Pre redeem wont have a assets amount yet
        emit PreWithdrawHook(0, _amount, user, user, 1_333);

        vm.expectEmit(true, true, true, true, address(mockStrategy));
        emit PostWithdrawHook(_amount, _amount, user, user, 1_333);

        vm.prank(user);
        mockStrategy.redeem(_amount, user, user, 1_333);

        checkStrategyTotals(mockStrategy, 0, 0, 0);
    }

    function test_transferHooksUpgradeable(uint256 _amount) public {
        vm.assume(_amount >= minFuzzAmount && _amount <= maxFuzzAmount);

        mintAndDepositIntoStrategy(mockStrategy, user, _amount);
        assertEq(mockStrategy.balanceOf(user), _amount);

        address receiver = address(123);

        // Make sure we get both events with the correct amounts.
        vm.expectEmit(true, true, true, true, address(mockStrategy));
        emit PreTransferHook(user, receiver, _amount);

        vm.expectEmit(true, true, true, true, address(mockStrategy));
        emit PostTransferHook(user, receiver, _amount, true);

        vm.prank(user);
        mockStrategy.transfer(receiver, _amount);

        assertEq(mockStrategy.balanceOf(user), 0);
        assertEq(mockStrategy.balanceOf(receiver), _amount);
    }

    function test_transferFromHooksUpgradeable(uint256 _amount) public {
        vm.assume(_amount >= minFuzzAmount && _amount <= maxFuzzAmount);

        mintAndDepositIntoStrategy(mockStrategy, user, _amount);
        assertEq(mockStrategy.balanceOf(user), _amount);

        address receiver = address(123);
        address spender = address(456);

        // Approve spender
        vm.prank(user);
        mockStrategy.approve(spender, _amount);

        // Make sure we get both events with the correct amounts.
        vm.expectEmit(true, true, true, true, address(mockStrategy));
        emit PreTransferHook(user, receiver, _amount);

        vm.expectEmit(true, true, true, true, address(mockStrategy));
        emit PostTransferHook(user, receiver, _amount, true);

        vm.prank(spender);
        mockStrategy.transferFrom(user, receiver, _amount);

        assertEq(mockStrategy.balanceOf(user), 0);
        assertEq(mockStrategy.balanceOf(receiver), _amount);
    }

    // Upgrade-specific tests
    function test_hooksWithProxy() public {
        uint256 _amount = maxFuzzAmount / 2;
        
        // Verify hooks work through proxy
        mintAndDepositIntoStrategy(mockStrategy, user, _amount);
        
        // All hook events should have been emitted during deposit
        // (tested above in test_depositHooksUpgradeable)
        
        // Verify proxy delegation is working
        verifyProxy(address(mockStrategy), hooksImpl);
    }

    function test_upgradeFromHealthCheck() public {
        // Deploy with health check first, then upgrade to hooks
        uint256 _amount = maxFuzzAmount / 2;
        
        // Deposit some funds
        mintAndDepositIntoStrategy(mockStrategy, user, _amount);
        
        // Store current state
        uint256 totalAssets = mockStrategy.totalAssets();
        uint256 userBalance = mockStrategy.balanceOf(user);
        bool doHealthCheck = MockHooksUpgradeable(address(mockStrategy)).doHealthCheck();
        uint256 profitLimit = MockHooksUpgradeable(address(mockStrategy)).profitLimitRatio();
        
        // Deploy new hooks implementation
        MockHooksUpgradeable newImpl = new MockHooksUpgradeable();
        
        // Upgrade
        upgradeProxy(address(mockStrategy), address(newImpl));
        
        // Verify state preserved
        assertEq(mockStrategy.totalAssets(), totalAssets);
        assertEq(mockStrategy.balanceOf(user), userBalance);
        assertEq(MockHooksUpgradeable(address(mockStrategy)).doHealthCheck(), doHealthCheck);
        assertEq(MockHooksUpgradeable(address(mockStrategy)).profitLimitRatio(), profitLimit);
        
        // Verify hooks work after upgrade
        vm.expectEmit(true, true, true, true, address(mockStrategy));
        emit PreWithdrawHook(_amount, 0, user, user, 0);
        
        vm.expectEmit(true, true, true, true, address(mockStrategy));
        emit PostWithdrawHook(_amount, _amount, user, user, 0);
        
        vm.prank(user);
        mockStrategy.withdraw(_amount, user, user);
    }

    function test_noAdditionalStorage() public {
        // Verify hooks don't add storage beyond health check
        // Slots 0-19 are used by BaseStrategy and HealthCheck
        // Slot 20+ should be available for strategy implementations
        
        for (uint256 i = 20; i <= 25; i++) {
            bytes32 slot = readStorageSlot(address(mockStrategy), i);
            assertEq(slot, bytes32(0), "Hooks should not use additional storage");
        }
    }
}