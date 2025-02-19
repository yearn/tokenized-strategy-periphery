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

        // test out notifying; user should fail
        uint256 rewardAmount = 100e18;
        airdrop(rewardToken, user, rewardAmount);
        vm.startPrank(user);
        rewardToken.approve(address(staker), rewardAmount);
        vm.expectRevert("!authorized");
        staker.notifyRewardAmount(address(rewardToken), rewardAmount);
        vm.stopPrank();

        // management should succeed
        airdrop(rewardToken, management, rewardAmount);
        vm.startPrank(management);
        rewardToken.approve(address(staker), rewardAmount);
        staker.notifyRewardAmount(address(rewardToken), rewardAmount);
        vm.stopPrank();

        rewardData = staker.rewardData(address(rewardToken));
        assertEq(rewardData.lastUpdateTime, block.timestamp);
        assertEq(rewardData.periodFinish, block.timestamp + duration);
        assertEq(rewardData.rewardRate, rewardAmount / duration);

        skip(duration / 2);

        assertEq(staker.earned(user, address(rewardToken)), rewardAmount / 2);

        // Add more rewards mid-period
        airdrop(rewardToken, management, rewardAmount);
        vm.startPrank(management);
        rewardToken.approve(address(staker), rewardAmount);
        staker.notifyRewardAmount(address(rewardToken), rewardAmount);
        vm.stopPrank();

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
        airdrop(rewardToken, management, rewardAmount);
        airdrop(rewardToken2, management, rewardAmount);

        vm.startPrank(management);
        rewardToken.approve(address(staker), rewardAmount);
        staker.notifyRewardAmount(address(rewardToken), rewardAmount);
        rewardToken2.approve(address(staker), rewardAmount);
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
        airdrop(rewardToken, management, rewardAmount);
        airdrop(rewardToken2, management, rewardAmount);

        vm.startPrank(management);
        rewardToken.approve(address(staker), rewardAmount);
        staker.notifyRewardAmount(address(rewardToken), rewardAmount);
        rewardToken2.approve(address(staker), rewardAmount);
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

    function test_feesAndRewards() public {
        uint256 amount = 1_000e6;
        uint16 performanceFee = 1_000;
        uint16 protocolFee = 1_000;
        setFees(protocolFee, performanceFee);

        mintAndDepositIntoStrategy(IStrategy(address(staker)), user, amount);

        uint256 rewardAmount = 100e18;
        airdrop(rewardToken, management, rewardAmount);
        vm.startPrank(management);
        rewardToken.approve(address(staker), rewardAmount);
        staker.notifyRewardAmount(address(rewardToken), rewardAmount);
        vm.stopPrank();

        // Simulate yield on underlying asset
        uint256 profit = 100e6;
        airdrop(asset, address(staker), profit);

        // Skip half the reward duration
        skip(duration / 2);

        // Process report which should accrue fees
        vm.prank(management);
        staker.report();

        // Check reward token accrual for fee recipients
        uint256 expectedPerformanceFeeShares = (profit * performanceFee) /
            MAX_BPS;
        uint256 expectedProtocolFeeShares = (expectedPerformanceFeeShares *
            protocolFee) / MAX_BPS;
        expectedPerformanceFeeShares =
            expectedPerformanceFeeShares -
            expectedProtocolFeeShares;

        // Get the effective totalSupply minus locked profit shares
        uint256 realShares = amount +
            expectedPerformanceFeeShares +
            expectedProtocolFeeShares;

        assertEq(
            staker.balanceOf(performanceFeeRecipient),
            expectedPerformanceFeeShares
        );
        assertEq(
            staker.balanceOf(protocolFeeRecipient),
            expectedProtocolFeeShares
        );

        // Should have no rewards yet
        assertApproxEqRel(
            staker.earned(performanceFeeRecipient, address(rewardToken)),
            0,
            0.001e18 // 0.1% tolerance
        );
        assertApproxEqRel(
            staker.earned(protocolFeeRecipient, address(rewardToken)),
            0,
            0.001e18 // 0.1% tolerance
        );
        assertApproxEqRel(
            staker.earned(user, address(rewardToken)),
            rewardAmount / 2,
            0.001e18 // 0.1% tolerance
        );

        // Skip the rest of the reward period
        skip(duration / 2);

        uint256 expectedPerformanceFeeReward = ((rewardAmount / 2) *
            expectedPerformanceFeeShares) / realShares;
        uint256 expectedProtocolFeeReward = ((rewardAmount / 2) *
            expectedProtocolFeeShares) / realShares;

        assertApproxEqRel(
            staker.earned(performanceFeeRecipient, address(rewardToken)),
            expectedPerformanceFeeReward,
            0.001e18 // 0.1% tolerance
        );

        assertApproxEqRel(
            staker.earned(protocolFeeRecipient, address(rewardToken)),
            expectedProtocolFeeReward,
            0.001e18 // 0.1% tolerance
        );

        // Claim rewards for fee recipients
        vm.prank(performanceFeeRecipient);
        staker.getReward();

        vm.prank(protocolFeeRecipient);
        staker.getReward();

        vm.prank(user);
        staker.getReward();

        // Verify reward token balances
        assertApproxEqRel(
            rewardToken.balanceOf(performanceFeeRecipient),
            expectedPerformanceFeeReward,
            0.001e18
        );

        assertApproxEqRel(
            rewardToken.balanceOf(protocolFeeRecipient),
            expectedProtocolFeeReward,
            0.001e18
        );

        assertApproxEqRel(
            rewardToken.balanceOf(user),
            rewardAmount -
                expectedPerformanceFeeReward -
                expectedProtocolFeeReward,
            0.001e18
        );

        // Verify rewards were properly distributed
        assertEq(
            staker.rewards(performanceFeeRecipient, address(rewardToken)),
            0
        );
        assertEq(
            staker.earned(performanceFeeRecipient, address(rewardToken)),
            0
        );
        assertEq(staker.rewards(protocolFeeRecipient, address(rewardToken)), 0);
        assertEq(staker.earned(protocolFeeRecipient, address(rewardToken)), 0);

        // All rewards should be gone minus precision loss
        assertLt(rewardToken.balanceOf(address(staker)), 10);
    }
}
