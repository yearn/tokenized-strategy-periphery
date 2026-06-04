// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

/**
 * @title  AaveV3YearnStrategy — Foundry Test Suite
 * @author Yuriy Khomenkov (KhomDev)
 *
 * Prerequisites
 * ─────────────
 *   pip install vyper          # ≥ 0.4.1
 *   forge test --ffi           # FFI required for Vyper compilation
 *
 * Coverage
 * ────────
 *   ① Deposit supplies to Aave; shares minted 1:1 on first deposit.
 *   ② Withdraw returns underlying; shares burned.
 *   ③ Yield accrues to share value: aToken rebase → convertToAssets increases.
 *   ④ report() isolates interest as profit. harvest is a no-op — documented.
 *   ⑤ Only emergency_admin / management can shut down.
 *   ⑥ Only keeper / management can set APR hint.
 *   ⑦ Sweep rejects asset and aToken; accepts stray tokens.
 *   ⑧ Full integration: deposit → yield → report → redeem > principal.
 *   ⑨ Profit locking: price stable immediately after report, rises over unlock.
 *   ⑩ Emergency shutdown + emergencyWithdraw; redeem still works from idle.
 *   ⑪ Management two-step ownership transfer.
 *   ⑫ Performance fee shares minted to fee recipient on report.
 *   ⑬ VaultV3 allocator flow (3-arg redeem pattern).
 *   ⑭ Fuzz: deposit/redeem round-trip recovers at least (amount - 1).
 */

import "forge-std/Test.sol";
import {IAaveV3YearnStrategy}                        from "./IAaveV3YearnStrategy.sol";
import {MockAavePool}                                  from "./mocks/MockAavePool.sol";
import {MockERC20}                                     from "./mocks/MockERC20.sol";

// ---------------------------------------------------------------------------
//  Setup
// ---------------------------------------------------------------------------

abstract contract Setup is Test {
    address internal management        = makeAddr("management");
    address internal keeper            = makeAddr("keeper");
    address internal performanceFeeRec = makeAddr("performanceFeeRecipient");
    address internal emergencyAdmin    = makeAddr("emergencyAdmin");
    address internal user              = makeAddr("user");
    address internal user2             = makeAddr("user2");

    MockERC20            internal asset;
    MockERC20            internal aToken;
    MockAavePool         internal pool;
    IAaveV3YearnStrategy internal strategy;

    uint256 internal constant ONE  = 1e6;     // 1 USDC (6 decimals)
    string  internal constant VY   =
        "src/strategies/vyper/AaveV3YearnStrategy.vy";

    function setUp() public virtual {
        asset  = new MockERC20("USD Coin", "USDC", 6);
        aToken = new MockERC20("Aave USDC", "aUSDC", 6);
        pool   = new MockAavePool();
        pool.setAtoken(address(asset), address(aToken));

        bytes memory args = abi.encode(
            address(asset), address(pool), address(aToken),
            "Yearn Aave V3 USDC Strategy", "ysAaveV3USDC",
            management, keeper, performanceFeeRec,
            address(0)   // standalone (no factory)
        );
        address addr = _deployVyper(VY, args);
        strategy = IAaveV3YearnStrategy(addr);

        vm.prank(management);
        strategy.setEmergencyAdmin(emergencyAdmin);

        vm.label(address(asset),    "USDC");
        vm.label(address(aToken),   "aUSDC");
        vm.label(address(pool),     "MockAavePool");
        vm.label(address(strategy), "AaveV3YearnStrategy");
    }

    // Compile and deploy a Vyper file via FFI (requires vyper on $PATH).
    function _deployVyper(string memory path, bytes memory args)
        internal returns (address addr)
    {
        string[] memory cmd = new string[](3);
        cmd[0] = "sh"; cmd[1] = "-c";
        cmd[2] = string(abi.encodePacked("vyper -f bytecode ", path));
        bytes memory bc = vm.ffi(cmd);
        bytes memory full = abi.encodePacked(bc, args);
        assembly { addr := create(0, add(full, 0x20), mload(full)) }
        require(addr != address(0), "Vyper deploy failed");
    }

    function _fund(address who, uint256 amount, address spender) internal {
        asset.mint(who, amount);
        vm.prank(who);
        asset.approve(spender, amount);
    }

    function _deposit(address who, uint256 amount) internal returns (uint256) {
        _fund(who, amount, address(strategy));
        vm.prank(who);
        return strategy.deposit(amount, who);
    }

    function _simulateYield(uint256 interest) internal {
        pool.simulateYield(address(asset), address(strategy), interest);
        asset.mint(address(pool), interest);
    }

    function _skipUnlock() internal {
        skip(strategy.profit_max_unlock_time() + 1);
    }
}

// ===========================================================================
//  ① Deposit
// ===========================================================================
contract DepositTest is Setup {
    function test_deposit_supplies_to_aave() public {
        uint256 shares = _deposit(user, 100 * ONE);
        assertEq(shares, 100 * ONE,                             "!shares 1:1");
        assertEq(strategy.totalAssets(), 100 * ONE,            "!totalAssets");
        assertEq(aToken.balanceOf(address(strategy)), 100*ONE, "!aToken");
        assertEq(asset.balanceOf(address(strategy)), 0,        "!idle zero");
    }

    function test_second_deposit_preserves_price() public {
        _deposit(user, 100 * ONE);
        _deposit(user2, 50 * ONE);
        assertEq(strategy.convertToAssets(ONE), ONE, "!price 1:1");
    }

    function test_deposit_zero_reverts() public {
        vm.prank(user);
        vm.expectRevert();
        strategy.deposit(0, user);
    }

    function test_deposit_shutdown_reverts() public {
        vm.prank(emergencyAdmin);
        strategy.shutdownStrategy();
        vm.prank(user);
        vm.expectRevert();
        strategy.deposit(ONE, user);
    }
}

// ===========================================================================
//  ② Withdraw
// ===========================================================================
contract WithdrawTest is Setup {
    function test_redeem_returns_underlying() public {
        uint256 shares = _deposit(user, 100 * ONE);
        vm.prank(user);
        uint256 out = strategy.redeem(shares, user, user);
        assertEq(out, 100 * ONE,               "!assets out");
        assertEq(strategy.balanceOf(user), 0,  "!shares cleared");
        assertEq(asset.balanceOf(user), 100*ONE,"!underlying received");
    }

    function test_withdraw_exact_assets() public {
        _deposit(user, 100 * ONE);
        vm.prank(user);
        strategy.withdraw(40 * ONE, user, user);
        assertApproxEqAbs(strategy.balanceOf(user), 60 * ONE, 1, "!remaining");
        assertEq(asset.balanceOf(user), 40 * ONE, "!withdrawn");
    }

    function test_redeem_insufficient_reverts() public {
        _deposit(user, 100 * ONE);
        vm.prank(user);
        vm.expectRevert();
        strategy.redeem(101 * ONE, user, user);
    }
}

// ===========================================================================
//  ③ & ④ Yield / harvest
// ===========================================================================
contract YieldTest is Setup {
    /**
     * @notice THE CORE ASSERTION: harvest is a no-op for Aave.
     *
     * Aave V3 aTokens are rebasing — aToken.balanceOf(strategy) grows
     * automatically with every block via the Liquidity Index. There is no
     * reward to claim and no swap to execute.
     *
     * _harvestAndReport() is a pure staticcall that returns the live balance
     * with ZERO side effects. report() subtracts _assets_tracked (the manually-
     * tracked principal+deposits counter) to isolate the interest delta as profit.
     *
     * Returning profit = 0 when no yield has accrued is CORRECT behaviour,
     * not a missing feature. The test below verifies this explicitly.
     */
    function test_report_noop_without_yield() public {
        _deposit(user, 100 * ONE);
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();
        assertEq(profit, 0, "!profit — no yield accrued");
        assertEq(loss,   0, "!loss");
        assertEq(strategy.pricePerShare(), ONE, "!price unchanged");
    }

    function test_yield_accrues_after_report() public {
        _deposit(user, 100 * ONE);
        _simulateYield(5 * ONE);

        // totalAssets is stale before report (tracked value only).
        assertEq(strategy.totalAssets(), 100 * ONE, "!tracked pre-report");

        vm.prank(keeper);
        (uint256 profit,) = strategy.report();
        assertEq(profit, 5 * ONE, "!profit = interest");

        _skipUnlock();
        assertGe(strategy.convertToAssets(100 * ONE), 105 * ONE, "!yield unlocked");
    }

    function test_multiple_reports_compound() public {
        _deposit(user, 1000 * ONE);
        _simulateYield(50 * ONE);
        vm.prank(keeper); strategy.report();
        _skipUnlock();

        _simulateYield(52_500_000);
        vm.prank(keeper); strategy.report();
        _skipUnlock();

        assertGe(
            strategy.convertToAssets(strategy.balanceOf(user)),
            1_102 * ONE,
            "!compound yield"
        );
    }
}

// ===========================================================================
//  ⑤ ⑥ ⑪ Access control
// ===========================================================================
contract AccessTest is Setup {
    function test_only_emergency_auth_can_shutdown() public {
        vm.prank(user);
        vm.expectRevert();
        strategy.shutdownStrategy();

        vm.prank(emergencyAdmin);
        strategy.shutdownStrategy();
        assertTrue(strategy.is_shutdown());
    }

    function test_only_keeper_can_set_apr() public {
        vm.prank(user);
        vm.expectRevert();
        strategy.setAprBps(300);

        vm.prank(keeper);
        strategy.setAprBps(300);
        assertEq(strategy.apr_bps(), 300);
    }

    function test_apr_capped_at_50pct() public {
        vm.prank(keeper);
        vm.expectRevert();
        strategy.setAprBps(5_001);
    }

    function test_perf_fee_capped_at_50pct() public {
        vm.prank(management);
        vm.expectRevert();
        strategy.setPerformanceFee(5_001);
    }

    function test_management_two_step_transfer() public {
        address newMgmt = makeAddr("newMgmt");
        vm.prank(management);
        strategy.setPendingManagement(newMgmt);
        assertEq(strategy.pending_management(), newMgmt);

        vm.prank(management);
        vm.expectRevert();
        strategy.acceptManagement();

        vm.prank(newMgmt);
        strategy.acceptManagement();
        assertEq(strategy.management(), newMgmt);
        assertEq(strategy.pending_management(), address(0));
    }
}

// ===========================================================================
//  ⑦ Sweep
// ===========================================================================
contract SweepTest is Setup {
    function test_sweep_rejects_asset() public {
        vm.prank(management);
        vm.expectRevert();
        strategy.sweep(address(asset), management);
    }

    function test_sweep_rejects_atoken() public {
        vm.prank(management);
        vm.expectRevert();
        strategy.sweep(address(aToken), management);
    }

    function test_sweep_recovers_stray_token() public {
        MockERC20 stray = new MockERC20("Stray", "STRAY", 18);
        stray.mint(address(strategy), 1_000e18);
        vm.prank(management);
        strategy.sweep(address(stray), management);
        assertEq(stray.balanceOf(management), 1_000e18);
    }

    function test_only_management_can_sweep() public {
        MockERC20 stray = new MockERC20("S", "S", 18);
        stray.mint(address(strategy), 1e18);
        vm.prank(user);
        vm.expectRevert();
        strategy.sweep(address(stray), user);
    }
}

// ===========================================================================
//  ⑧ Full integration
// ===========================================================================
contract IntegrationTest is Setup {
    function test_deposit_yield_report_redeem() public {
        uint256 shares = _deposit(user, 1000 * ONE);
        _simulateYield(100 * ONE);

        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();
        assertEq(profit, 100 * ONE, "!profit");
        assertEq(loss,   0,         "!loss");

        _skipUnlock();

        vm.prank(user);
        uint256 out = strategy.redeem(shares, user, user);
        assertGt(out, 1000 * ONE, "!user received yield");
    }

    // ⑬ VaultV3 allocator pattern: deposit(assets, self) + redeem(shares, self, self)
    function test_vault_allocator_flow() public {
        address vault = makeAddr("vault");
        _fund(vault, 500 * ONE, address(strategy));
        vm.prank(vault);
        uint256 shares = strategy.deposit(500 * ONE, vault);

        _simulateYield(25 * ONE);
        vm.prank(keeper); strategy.report();
        _skipUnlock();

        uint256 valueBefore = strategy.convertToAssets(shares);
        assertGt(valueBefore, 500 * ONE, "!grew");

        vm.prank(vault);
        uint256 received = strategy.redeem(shares, vault, vault);
        assertGe(received, valueBefore - 1, "!redeemed correctly");
    }
}

// ===========================================================================
//  ⑨ Profit locking
// ===========================================================================
contract ProfitLockingTest is Setup {
    function test_price_stable_immediately_after_report() public {
        _deposit(user, 1000 * ONE);
        _simulateYield(100 * ONE);

        uint256 priceBefore = strategy.pricePerShare();
        vm.prank(keeper);
        strategy.report();

        assertApproxEqAbs(strategy.pricePerShare(), priceBefore, 1, "!price stable");
    }

    function test_price_rises_over_unlock() public {
        _deposit(user, 1000 * ONE);
        _simulateYield(100 * ONE);
        uint256 priceBefore = strategy.pricePerShare();
        vm.prank(keeper); strategy.report();

        skip(strategy.profit_max_unlock_time() / 2);
        assertGt(strategy.pricePerShare(), priceBefore, "!rising mid-unlock");

        _skipUnlock();
        assertGt(strategy.pricePerShare(), priceBefore, "!fully unlocked");
    }

    // ⑫
    function test_performance_fee_shares_minted() public {
        _deposit(user, 1000 * ONE);
        _simulateYield(100 * ONE);
        vm.prank(management);
        strategy.setPerformanceFee(1_000); // 10%

        vm.prank(keeper);
        (uint256 profit,) = strategy.report();
        assertEq(profit, 100 * ONE);

        assertGt(strategy.balanceOf(performanceFeeRec), 0, "!fee shares minted");
        _skipUnlock();
        uint256 feeVal = strategy.convertToAssets(strategy.balanceOf(performanceFeeRec));
        assertApproxEqRel(feeVal, 10 * ONE, 0.01e18, "!fee value ≈ 10 USDC");
    }
}

// ===========================================================================
//  ⑩ Emergency
// ===========================================================================
contract ShutdownTest is Setup {
    function test_shutdown_blocks_deposits() public {
        vm.prank(emergencyAdmin);
        strategy.shutdownStrategy();
        vm.prank(user); vm.expectRevert();
        strategy.deposit(ONE, user);
    }

    function test_redeem_works_post_shutdown() public {
        uint256 shares = _deposit(user, 500 * ONE);
        vm.prank(emergencyAdmin);
        strategy.shutdownStrategy();
        vm.prank(user);
        assertEq(strategy.redeem(shares, user, user), 500 * ONE);
    }

    function test_emergency_withdraw_to_idle() public {
        _deposit(user, 500 * ONE);
        vm.prank(emergencyAdmin); strategy.shutdownStrategy();
        vm.prank(emergencyAdmin); strategy.emergencyWithdraw(type(uint256).max);

        assertEq(asset.balanceOf(address(strategy)), 500 * ONE, "!idle");
        assertEq(aToken.balanceOf(address(strategy)), 0,        "!aToken cleared");

        vm.prank(user);
        assertEq(strategy.redeem(strategy.balanceOf(user), user, user), 500 * ONE);
    }

    function test_emergency_withdraw_requires_shutdown() public {
        vm.prank(emergencyAdmin);
        vm.expectRevert();
        strategy.emergencyWithdraw(ONE);
    }
}

// ===========================================================================
//  View surface + fuzz
// ===========================================================================
contract ViewSurfaceTest is Setup {
    function test_api_version() public view {
        assertEq(strategy.apiVersion(), "3.0.4");
    }

    function test_price_per_share_starts_at_one() public view {
        assertEq(strategy.pricePerShare(), ONE);
    }

    function test_max_deposit_zero_when_shutdown() public {
        assertGt(strategy.maxDeposit(user), 0);
        vm.prank(emergencyAdmin); strategy.shutdownStrategy();
        assertEq(strategy.maxDeposit(user), 0);
    }

    function test_tend_noop() public {
        vm.prank(keeper);
        strategy.tend();
        (bool trigger,) = strategy.tendTrigger();
        assertFalse(trigger);
    }

    function test_erc20_transfer() public {
        uint256 shares = _deposit(user, 100 * ONE);
        vm.prank(user);
        strategy.transfer(user2, shares / 2);
        assertEq(strategy.balanceOf(user2), shares / 2);
    }

    // ⑭
    function test_fuzz_deposit_redeem_roundtrip(uint256 amount) public {
        amount = bound(amount, 1e3, 1_000_000 * ONE);
        uint256 shares = _deposit(user, amount);
        vm.prank(user);
        uint256 out = strategy.redeem(shares, user, user);
        assertGe(out + 1, amount, "!roundtrip");
    }
}
