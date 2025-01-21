// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Setup, IStrategy, SafeERC20, ERC20} from "./utils/Setup.sol";

import {MockTokenizedStaker, IMockTokenizedStaker} from "./mocks/MockTokenizedStaker.sol";

contract TokenizedStakerTest is Setup {
    IMockTokenizedStaker public staker;

    ERC20 public rewardToken;
    ERC20 public rewardToken2;
    uint256 public duration = 10_000;

    function setUp() public override {
        super.setUp();

        rewardToken = ERC20(tokenAddrs["YFI"]);
        rewardToken2 = ERC20(tokenAddrs["WETH"]);

        staker = IMockTokenizedStaker(
            address(
                new MockTokenizedStaker(address(asset), "MockTokenizedStaker")
            )
        );

        staker.setKeeper(keeper);
        staker.setPerformanceFeeRecipient(performanceFeeRecipient);
        staker.setPendingManagement(management);
        // Accept management.
        vm.prank(management);
        staker.acceptManagement();

        // Add initial reward token
        vm.prank(management);
        staker.addReward(address(rewardToken), management, duration);
    }

    function test_TokenizedStakerSetup() public {
        assertEq(staker.asset(), address(asset));
        assertEq(staker.rewardTokens(0), address(rewardToken));
        assertEq(staker.rewardPerToken(address(rewardToken)), 0);
        assertEq(staker.lastTimeRewardApplicable(address(rewardToken)), 0);
        assertEq(
            staker.userRewardPerTokenPaid(address(0), address(rewardToken)),
            0
        );
        assertEq(staker.userRewardPerTokenPaid(user, address(rewardToken)), 0);
        assertEq(staker.rewards(address(0), address(rewardToken)), 0);
        assertEq(staker.rewards(user, address(rewardToken)), 0);
        assertEq(staker.earned(user, address(rewardToken)), 0);

        IMockTokenizedStaker.Reward memory rewardData = staker.rewardData(
            address(rewardToken)
        );
        assertEq(rewardData.periodFinish, 0);
        assertEq(rewardData.rewardRate, 0);
        assertEq(rewardData.rewardsDuration, duration);
        assertEq(rewardData.rewardsDistributor, management);
    }

    function test_addReward() public {
        vm.prank(management);
        staker.addReward(address(rewardToken2), management, duration);

        assertEq(staker.rewardTokens(1), address(rewardToken2));

        IMockTokenizedStaker.Reward memory rewardData = staker.rewardData(
            address(rewardToken2)
        );
        assertEq(rewardData.rewardsDuration, duration);
        assertEq(rewardData.rewardsDistributor, management);

        // Can't add same token twice
        vm.expectRevert("Reward already added");
        vm.prank(management);
        staker.addReward(address(rewardToken2), management, duration);

        // Can't add zero address
        vm.expectRevert("No zero address");
        vm.prank(management);
        staker.addReward(address(0), management, duration);
    }

    function test_TokenizedStaker_notifyRewardAmount() public {
        uint256 amount = 1_000e18;
        mintAndDepositIntoStrategy(IStrategy(address(staker)), user, amount);

        assertEq(staker.rewardPerToken(address(rewardToken)), 0);
        assertEq(staker.lastTimeRewardApplicable(address(rewardToken)), 0);

        IMockTokenizedStaker.Reward memory rewardData = staker.rewardData(
            address(rewardToken)
        );
        assertEq(rewardData.periodFinish, 0);
        assertEq(rewardData.rewardRate, 0);
        assertEq(rewardData.rewardsDuration, duration);

        uint256 rewardAmount = 100e18;

        vm.expectRevert("!management");
        staker.notifyRewardAmount(address(rewardToken), rewardAmount);

        airdrop(rewardToken, address(staker), rewardAmount);

        vm.prank(management);
        staker.notifyRewardAmount(address(rewardToken), rewardAmount);

        rewardData = staker.rewardData(address(rewardToken));
        assertEq(rewardData.lastUpdateTime, block.timestamp);
        assertEq(rewardData.periodFinish, block.timestamp + duration);
        assertEq(rewardData.rewardRate, rewardAmount / duration);

        skip(duration / 2);

        assertEq(staker.earned(user, address(rewardToken)), rewardAmount / 2);

        // Add more rewards mid-period
        airdrop(rewardToken, address(staker), rewardAmount);
        vm.prank(management);
        staker.notifyRewardAmount(address(rewardToken), rewardAmount);

        rewardData = staker.rewardData(address(rewardToken));
        assertEq(rewardData.lastUpdateTime, block.timestamp);
        assertEq(rewardData.periodFinish, block.timestamp + duration);
        assertEq(
            rewardData.rewardRate,
            (rewardAmount + (rewardAmount / 2)) / duration
        );
    }

    function test_TokenizedStaker_getReward() public {
        uint256 amount = 1_000e18;
        mintAndDepositIntoStrategy(IStrategy(address(staker)), user, amount);

        // Add multiple reward tokens
        vm.prank(management);
        staker.addReward(address(rewardToken2), management, duration);

        uint256 rewardAmount = 100e18;
        // Add rewards for both tokens
        airdrop(rewardToken, address(staker), rewardAmount);
        airdrop(rewardToken2, address(staker), rewardAmount);

        vm.startPrank(management);
        staker.notifyRewardAmount(address(rewardToken), rewardAmount);
        staker.notifyRewardAmount(address(rewardToken2), rewardAmount);
        vm.stopPrank();

        skip(duration / 2);

        assertEq(staker.earned(user, address(rewardToken)), rewardAmount / 2);
        assertEq(staker.earned(user, address(rewardToken2)), rewardAmount / 2);

        vm.prank(user);
        staker.getReward();

        assertEq(rewardToken.balanceOf(user), rewardAmount / 2);
        assertEq(rewardToken2.balanceOf(user), rewardAmount / 2);
        assertEq(staker.rewards(user, address(rewardToken)), 0);
        assertEq(staker.rewards(user, address(rewardToken2)), 0);
    }

    function test_TokenizedStaker_getOneReward() public {
        uint256 amount = 1_000e18;
        mintAndDepositIntoStrategy(IStrategy(address(staker)), user, amount);

        // Add multiple reward tokens
        vm.prank(management);
        staker.addReward(address(rewardToken2), management, duration);

        uint256 rewardAmount = 100e18;
        // Add rewards for both tokens
        airdrop(rewardToken, address(staker), rewardAmount);
        airdrop(rewardToken2, address(staker), rewardAmount);

        vm.startPrank(management);
        staker.notifyRewardAmount(address(rewardToken), rewardAmount);
        staker.notifyRewardAmount(address(rewardToken2), rewardAmount);
        vm.stopPrank();

        skip(duration / 2);

        vm.prank(user);
        staker.getOneReward(address(rewardToken));

        assertEq(rewardToken.balanceOf(user), rewardAmount / 2);
        assertEq(rewardToken2.balanceOf(user), 0);
        assertEq(staker.rewards(user, address(rewardToken)), 0);
        assertEq(staker.rewards(user, address(rewardToken2)), rewardAmount / 2);
    }
}
