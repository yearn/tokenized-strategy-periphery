// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Setup, IStrategy, SafeERC20, ERC20} from "./utils/Setup.sol";

import {MockTokenizedStaker, IMockTokenizedStaker} from "./mocks/MockTokenizedStaker.sol";

contract TokenizedStakerTest is Setup {
    IMockTokenizedStaker public staker;

    ERC20 public rewardToken;

    uint256 public duration = 10_000;

    function setUp() public override {
        super.setUp();

        rewardToken = ERC20(tokenAddrs["YFI"]);

        staker = IMockTokenizedStaker(
            address(
                new MockTokenizedStaker(
                    address(asset),
                    "MockTokenizedStaker",
                    address(rewardToken)
                )
            )
        );

        staker.setKeeper(keeper);
        staker.setPerformanceFeeRecipient(performanceFeeRecipient);
        staker.setPendingManagement(management);
        // Accept management.
        vm.prank(management);
        staker.acceptManagement();

        vm.prank(management);
        staker.setRewardsDuration(duration);
    }

    function test_TokenizedStakerSetup() public {
        assertEq(staker.asset(), address(asset));
        assertEq(staker.rewardToken(), address(rewardToken));
        assertEq(staker.rewardPerToken(), 0);
        assertEq(staker.lastUpdateTime(), 0);
        assertEq(staker.rewardPerTokenStored(), 0);
        assertEq(staker.userRewardPerTokenPaid(address(0)), 0);
        assertEq(staker.userRewardPerTokenPaid(user), 0);
        assertEq(staker.rewards(address(0)), 0);
        assertEq(staker.rewards(user), 0);
        assertEq(staker.earned(address(0)), 0);
        assertEq(staker.earned(user), 0);
        assertEq(staker.periodFinish(), 0);
        assertEq(staker.rewardRate(), 0);
        assertEq(staker.rewardsDuration(), duration);
    }

    function test_TokenizedStaker_notifyRewardAmount() public {
        uint256 amount = 1_000e18;
        mintAndDepositIntoStrategy(IStrategy(address(staker)), user, amount);

        assertEq(staker.rewardPerToken(), 0);
        assertEq(staker.lastUpdateTime(), 0);
        assertEq(staker.rewardPerTokenStored(), 0);
        assertEq(staker.lastTimeRewardApplicable(), 0);
        assertEq(staker.periodFinish(), 0);
        assertEq(staker.rewardRate(), 0);
        assertEq(staker.rewardsDuration(), duration);

        uint256 rewardAmount = 100e18;

        vm.expectRevert("!management");
        staker.notifyRewardAmount(rewardAmount);

        assertEq(staker.rewardPerToken(), 0);

        //vm.expectRevert("Provided reward too high");
        //vm.prank(management);
        //staker.notifyRewardAmount(rewardAmount);

        assertEq(staker.rewardPerToken(), 0);

        airdrop(rewardToken, address(staker), rewardAmount);

        vm.prank(management);
        staker.notifyRewardAmount(rewardAmount);

        assertEq(staker.rewardPerToken(), 0);
        assertEq(staker.lastUpdateTime(), block.timestamp);
        assertEq(staker.rewardPerTokenStored(), 0);
        assertEq(staker.lastTimeRewardApplicable(), block.timestamp);
        assertEq(staker.periodFinish(), block.timestamp + duration);
        assertEq(staker.rewardRate(), rewardAmount / duration);
        assertEq(staker.rewardsDuration(), duration);

        skip(duration / 2);

        assertEq(staker.rewardPerToken(), (rewardAmount * 1e18) / amount / 2);
        assertEq(staker.lastUpdateTime(), block.timestamp - (duration / 2));
        assertEq(staker.rewardPerTokenStored(), 0);
        assertEq(staker.lastTimeRewardApplicable(), block.timestamp);
        assertEq(staker.periodFinish(), block.timestamp + (duration / 2));
        assertEq(staker.rewardRate(), rewardAmount / duration);
        assertEq(staker.rewardsDuration(), duration);
        assertEq(staker.earned(user), rewardAmount / 2);

        airdrop(rewardToken, address(staker), rewardAmount);

        vm.prank(management);
        staker.notifyRewardAmount(rewardAmount);

        assertEq(staker.lastUpdateTime(), block.timestamp);
        assertEq(staker.lastTimeRewardApplicable(), block.timestamp);
        assertEq(staker.periodFinish(), block.timestamp + duration);
        assertEq(
            staker.rewardRate(),
            rewardAmount + (rewardAmount / 2) / duration
        );
        assertEq(staker.rewardsDuration(), duration);
        assertEq(staker.earned(user), rewardAmount / 2);
    }

    function test_TokenizedStaker_getReward() public {
        uint256 amount = 1_000e18;
        mintAndDepositIntoStrategy(IStrategy(address(staker)), user, amount);

        // Add rewards
        uint256 rewardAmount = 100e18;
        airdrop(rewardToken, address(staker), rewardAmount);
        vm.prank(management);
        staker.notifyRewardAmount(rewardAmount);

        // Skip half the duration
        skip(duration / 2);

        // Check earned amount
        assertEq(staker.earned(user), rewardAmount / 2);

        // Get reward
        vm.prank(user);
        staker.getReward();

        // Verify rewards were paid
        assertEq(rewardToken.balanceOf(user), rewardAmount / 2);
        assertEq(staker.rewards(user), 0);
    }

    function test_TokenizedStaker_exit() public {
        uint256 amount = 1_000e18;
        mintAndDepositIntoStrategy(IStrategy(address(staker)), user, amount);

        // Add rewards
        uint256 rewardAmount = 100e18;
        airdrop(rewardToken, address(staker), rewardAmount);
        vm.prank(management);
        staker.notifyRewardAmount(rewardAmount);

        // Skip half the duration
        skip(duration / 2);

        // Exit
        uint256 balanceBefore = asset.balanceOf(user);
        vm.prank(user);
        staker.exit();

        // Verify all tokens returned and rewards paid
        assertEq(asset.balanceOf(user), balanceBefore + amount);
        assertEq(rewardToken.balanceOf(user), rewardAmount / 2);
        assertEq(staker.balanceOf(user), 0);
        assertEq(staker.rewards(user), 0);
    }

    function test_TokenizedStaker_earned_multipleUsers() public {
        uint256 amount = 1_000e18;
        address user2 = address(0x2);

        // User 1 deposits
        mintAndDepositIntoStrategy(IStrategy(address(staker)), user, amount);

        // Add initial rewards
        uint256 rewardAmount = 100e18;
        airdrop(rewardToken, address(staker), rewardAmount);
        vm.prank(management);
        staker.notifyRewardAmount(rewardAmount);

        // Skip quarter duration
        skip(duration / 4);

        // User 2 deposits
        mintAndDepositIntoStrategy(IStrategy(address(staker)), user2, amount);

        // Skip to end
        skip((3 * duration) / 4);

        // User 1 should have earned 75% of first quarter plus 37.5% of remaining
        uint256 user1Earned = staker.earned(user);
        assertApproxEqRel(
            user1Earned,
            ((rewardAmount * 25) / 100) + ((rewardAmount * 75) / 100 / 2),
            1
        );

        // User 2 should have earned 37.5% of remaining rewards
        uint256 user2Earned = staker.earned(user2);
        assertApproxEqRel(user2Earned, ((rewardAmount * 75) / 100 / 2), 1);
    }

    function test_TokenizedStaker_setRewardsDuration() public {
        uint256 newDuration = 20_000;

        // Can't change duration while rewards are active
        uint256 rewardAmount = 100e18;
        airdrop(rewardToken, address(staker), rewardAmount);
        vm.prank(management);
        staker.notifyRewardAmount(rewardAmount);

        vm.expectRevert(
            "Previous rewards period must be complete before changing the duration for the new period"
        );
        vm.prank(management);
        staker.setRewardsDuration(newDuration);

        // Skip to end of period
        skip(duration + 1);

        // Now we can change duration
        vm.prank(management);
        staker.setRewardsDuration(newDuration);
        assertEq(staker.rewardsDuration(), newDuration);
    }
}
