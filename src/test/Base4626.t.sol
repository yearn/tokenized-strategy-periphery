// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.18;

import "forge-std/console.sol";
import {Setup, ERC20, IStrategy} from "./utils/Setup.sol";

import {Base4626Compounder} from "../Bases/4626Compounder/Base4626Compounder.sol";
import {IBase4626Compounder} from "../Bases/4626Compounder/IBase4626Compounder.sol";

contract Base4626CompounderTest is Setup {
    IBase4626Compounder public compounder;

    function setUp() public virtual override {
        super.setUp();

        // we save the compounder as a IStrategyInterface to give it the needed interface
        // Use the compounder as the vault to use.
        IStrategy _compounder = IStrategy(
            address(
                new Base4626Compounder(
                    address(asset),
                    "Tokenized Strategy",
                    address(mockStrategy)
                )
            )
        );

        // set keeper
        _compounder.setKeeper(keeper);
        // set treasury
        _compounder.setPerformanceFeeRecipient(performanceFeeRecipient);
        // set management of the compounder
        _compounder.setPendingManagement(management);

        vm.prank(management);
        _compounder.acceptManagement();

        compounder = IBase4626Compounder(address(_compounder));
    }

    function test_setupStrategyOK() public {
        console.log("address of compounder", address(compounder));
        assertTrue(address(0) != address(compounder));
        assertEq(compounder.asset(), address(asset));
        assertEq(compounder.management(), management);
        assertEq(compounder.performanceFeeRecipient(), performanceFeeRecipient);
        assertEq(compounder.keeper(), keeper);
        // TODO: add additional check on strat params
    }

    function test_operation(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        // Deposit into compounder
        mintAndDepositIntoStrategy(compounder, user, _amount);

        assertEq(compounder.totalAssets(), _amount, "!totalAssets");

        // Earn Interest
        skip(1 days);

        // Report profit
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = compounder.report();

        // Check return Values
        assertGe(profit, 0, "!profit");
        assertEq(loss, 0, "!loss");

        skip(compounder.profitMaxUnlockTime());

        uint256 balanceBefore = asset.balanceOf(user);

        // Withdraw all funds
        vm.prank(user);
        compounder.redeem(_amount, user, user);

        assertGe(
            asset.balanceOf(user),
            balanceBefore + _amount,
            "!final balance"
        );
    }

    function test_profitableReport(
        uint256 _amount,
        uint16 _profitFactor
    ) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);
        _profitFactor = uint16(
            bound(uint256(_profitFactor), 10, MAX_BPS - 100)
        );

        // Deposit into compounder
        mintAndDepositIntoStrategy(compounder, user, _amount);

        assertEq(compounder.totalAssets(), _amount, "!totalAssets");

        // Earn Interest
        skip(1 days);

        // TODO: implement logic to simulate earning interest.
        uint256 toAirdrop = (_amount * _profitFactor) / MAX_BPS;
        airdrop(asset, address(compounder), toAirdrop);

        // Report profit
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = compounder.report();

        // Check return Values
        assertGe(profit, toAirdrop, "!profit");
        assertEq(loss, 0, "!loss");

        skip(compounder.profitMaxUnlockTime());

        uint256 balanceBefore = asset.balanceOf(user);

        // Withdraw all funds
        vm.prank(user);
        compounder.redeem(_amount, user, user);

        assertGe(
            asset.balanceOf(user),
            balanceBefore + _amount,
            "!final balance"
        );
    }

    function test_profitableReport_withFees(
        uint256 _amount,
        uint16 _profitFactor
    ) public virtual {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);
        _profitFactor = uint16(
            bound(uint256(_profitFactor), 10, MAX_BPS - 100)
        );

        // Set protocol fee to 0 and perf fee to 10%
        setFees(0, 1_000);

        // Deposit into compounder
        mintAndDepositIntoStrategy(compounder, user, _amount);

        assertEq(compounder.totalAssets(), _amount, "!totalAssets");

        // Earn Interest
        skip(1 days);

        // TODO: implement logic to simulate earning interest.
        uint256 toAirdrop = (_amount * _profitFactor) / MAX_BPS;
        airdrop(asset, address(compounder), toAirdrop);

        // Report profit
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = compounder.report();

        // Check return Values
        assertGe(profit, toAirdrop, "!profit");
        assertEq(loss, 0, "!loss");

        skip(compounder.profitMaxUnlockTime());

        // Get the expected fee
        uint256 expectedShares = (profit * 1_000) / MAX_BPS;

        assertEq(compounder.balanceOf(performanceFeeRecipient), expectedShares);

        uint256 balanceBefore = asset.balanceOf(user);

        // Withdraw all funds
        vm.prank(user);
        compounder.redeem(_amount, user, user);

        assertGe(
            asset.balanceOf(user),
            balanceBefore + _amount,
            "!final balance"
        );

        vm.prank(performanceFeeRecipient);
        compounder.redeem(
            expectedShares,
            performanceFeeRecipient,
            performanceFeeRecipient
        );

        checkStrategyTotals(compounder, 0, 0, 0);

        assertGe(
            asset.balanceOf(performanceFeeRecipient),
            expectedShares,
            "!perf fee out"
        );
    }

    function test_tendTrigger(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        (bool trigger, ) = compounder.tendTrigger();
        assertTrue(!trigger);

        // Deposit into compounder
        mintAndDepositIntoStrategy(compounder, user, _amount);

        (trigger, ) = compounder.tendTrigger();
        assertTrue(!trigger);

        // Skip some time
        skip(1 days);

        (trigger, ) = compounder.tendTrigger();
        assertTrue(!trigger);

        vm.prank(keeper);
        compounder.report();

        (trigger, ) = compounder.tendTrigger();
        assertTrue(!trigger);

        // Unlock Profits
        skip(compounder.profitMaxUnlockTime());

        (trigger, ) = compounder.tendTrigger();
        assertTrue(!trigger);

        vm.prank(user);
        compounder.redeem(_amount, user, user);

        (trigger, ) = compounder.tendTrigger();
        assertTrue(!trigger);
    }
}
