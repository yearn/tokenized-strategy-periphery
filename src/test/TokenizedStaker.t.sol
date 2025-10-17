// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Setup, IStrategy, SafeERC20, ERC20, IVaultFactory} from "./utils/Setup.sol";

import {MockTokenizedStaker, IMockTokenizedStaker} from "./mocks/MockTokenizedStaker.sol";

contract TokenizedStakerTest is Setup {
    IMockTokenizedStaker public staker;

    ERC20 public rewardToken;
    ERC20 public rewardToken2;
    uint256 public duration = 7 days;

    function setUp() public virtual override {
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
        uint256 amount = 1_000 * (10 ** asset.decimals());
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
        uint256 rewardAmount = 100 * (10 ** rewardToken.decimals());
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
        assertEq(rewardData.rewardRate, (rewardAmount * WAD) / duration);

        skip(duration / 2);

        assertApproxEqRel(
            staker.earned(user, address(rewardToken)),
            rewardAmount / 2,
            0.0001e18
        );

        // Add more rewards mid-period
        airdrop(rewardToken, management, rewardAmount);
        vm.startPrank(management);
        rewardToken.approve(address(staker), rewardAmount);
        staker.notifyRewardAmount(address(rewardToken), rewardAmount);
        vm.stopPrank();

        rewardData = staker.rewardData(address(rewardToken));
        assertEq(rewardData.lastUpdateTime, block.timestamp);
        assertEq(rewardData.periodFinish, block.timestamp + duration);
        assertApproxEqRel(
            rewardData.rewardRate,
            ((rewardAmount + (rewardAmount / 2)) * WAD) / duration,
            0.0001e18
        );
    }

    function test_TokenizedStaker_getReward() public {
        uint256 amount = 1_000 * (10 ** asset.decimals());
        mintAndDepositIntoStrategy(IStrategy(address(staker)), user, amount);

        // Add multiple reward tokens
        vm.prank(management);
        staker.addReward(address(rewardToken2), management, duration);

        uint256 rewardAmount = 100 * (10 ** rewardToken.decimals());
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

        assertApproxEqRel(
            staker.earned(user, address(rewardToken)),
            rewardAmount / 2,
            0.0001e18
        );
        assertApproxEqRel(
            staker.earned(user, address(rewardToken2)),
            rewardAmount / 2,
            0.0001e18
        );

        uint256 preBalance = rewardToken.balanceOf(user);
        uint256 preBalance2 = rewardToken2.balanceOf(user);

        vm.prank(user);
        staker.getReward();

        assertApproxEqRel(
            rewardToken.balanceOf(user),
            preBalance + rewardAmount / 2,
            0.0001e18
        );
        assertApproxEqRel(
            rewardToken2.balanceOf(user),
            preBalance2 + rewardAmount / 2,
            0.0001e18
        );
        assertEq(staker.rewards(user, address(rewardToken)), 0);
        assertEq(staker.rewards(user, address(rewardToken2)), 0);
    }

    function test_TokenizedStaker_getOneReward() public {
        uint256 amount = 1_000 * (10 ** asset.decimals());
        mintAndDepositIntoStrategy(IStrategy(address(staker)), user, amount);

        // Add multiple reward tokens
        vm.prank(management);
        staker.addReward(address(rewardToken2), management, duration);

        uint256 rewardAmount = 100 * (10 ** rewardToken.decimals());
        uint256 rewardAmount2 = 100 * (10 ** rewardToken2.decimals());
        // Add rewards for both tokens
        airdrop(rewardToken, management, rewardAmount);
        airdrop(rewardToken2, management, rewardAmount2);

        vm.startPrank(management);
        rewardToken.approve(address(staker), rewardAmount);
        staker.notifyRewardAmount(address(rewardToken), rewardAmount);
        rewardToken2.approve(address(staker), rewardAmount2);
        staker.notifyRewardAmount(address(rewardToken2), rewardAmount2);
        vm.stopPrank();

        skip(duration / 2);

        uint256 preBalance = rewardToken.balanceOf(user);
        uint256 preBalance2 = rewardToken2.balanceOf(user);

        vm.prank(user);
        staker.getOneReward(address(rewardToken));

        assertApproxEqRel(
            rewardToken.balanceOf(user),
            preBalance + rewardAmount / 2,
            0.0001e18
        );
        assertEq(rewardToken2.balanceOf(user), preBalance2);
        assertEq(staker.rewards(user, address(rewardToken)), 0);
        assertApproxEqRel(
            staker.rewards(user, address(rewardToken2)),
            rewardAmount2 / 2,
            0.0001e18
        );
    }

    function test_feesAndRewards() public {
        uint256 amount = 1_000 * (10 ** asset.decimals());
        uint16 performanceFee = 1_000;
        uint16 protocolFee = 1_000;
        setFees(protocolFee, performanceFee);

        mintAndDepositIntoStrategy(IStrategy(address(staker)), user, amount);

        uint256 rewardAmount = 100 * (10 ** rewardToken.decimals());
        airdrop(rewardToken, management, rewardAmount);
        vm.startPrank(management);
        rewardToken.approve(address(staker), rewardAmount);
        staker.notifyRewardAmount(address(rewardToken), rewardAmount);
        vm.stopPrank();

        // Simulate yield on underlying asset
        uint256 profit = 100 * (10 ** asset.decimals());
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
        assertEq(
            staker.earned(performanceFeeRecipient, address(rewardToken)),
            0
        );
        assertEq(staker.earned(protocolFeeRecipient, address(rewardToken)), 0);
        assertApproxEqRel(
            staker.earned(user, address(rewardToken)),
            rewardAmount / 2,
            0.0001e18 // 0.01% tolerance
        );

        // Skip the rest of the reward period
        skip(duration / 2);

        uint256 expectedPerformanceFeeReward = (((rewardAmount * WAD) / 2) *
            expectedPerformanceFeeShares) /
            realShares /
            WAD;
        uint256 expectedProtocolFeeReward = (((rewardAmount * WAD) / 2) *
            expectedProtocolFeeShares) /
            realShares /
            WAD;

        assertApproxEqRel(
            staker.earned(performanceFeeRecipient, address(rewardToken)),
            expectedPerformanceFeeReward,
            0.0001e18 // 0.01% tolerance
        );

        assertApproxEqRel(
            staker.earned(protocolFeeRecipient, address(rewardToken)),
            expectedProtocolFeeReward,
            0.0001e18 // 0.01% tolerance
        );

        uint256 prePerformanceFeeBalance = rewardToken.balanceOf(
            performanceFeeRecipient
        );
        uint256 preProtocolFeeBalance = rewardToken.balanceOf(
            protocolFeeRecipient
        );
        uint256 preUserBalance = rewardToken.balanceOf(user);

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
            prePerformanceFeeBalance + expectedPerformanceFeeReward,
            0.0001e18
        );

        assertApproxEqRel(
            rewardToken.balanceOf(protocolFeeRecipient),
            preProtocolFeeBalance + expectedProtocolFeeReward,
            0.0001e18
        );

        assertApproxEqRel(
            rewardToken.balanceOf(user),
            preUserBalance +
                rewardAmount -
                expectedPerformanceFeeReward -
                expectedProtocolFeeReward,
            0.0001e18
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

contract TokenizedStakerTestLowerDecimals is TokenizedStakerTest {
    function setUp() public override {
        _setTokenAddrs();

        // Make sure everything works with USDT
        asset = ERC20(tokenAddrs["YFI"]);

        minFuzzAmount = 1e12;
        maxFuzzAmount = 1e24;

        // Set decimals
        decimals = asset.decimals();

        mockStrategy = setUpStrategy();

        vaultFactory = IVaultFactory(mockStrategy.FACTORY());

        rewardToken = ERC20(tokenAddrs["USDC"]);
        rewardToken2 = ERC20(tokenAddrs["WBTC"]);

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

        // label all the used addresses for traces
        vm.label(user, "user");
        vm.label(daddy, "daddy");
        vm.label(keeper, "keeper");
        vm.label(address(asset), "asset");
        vm.label(management, "management");
        vm.label(address(mockStrategy), "strategy");
        vm.label(vaultManagement, "vault management");
        vm.label(address(vaultFactory), " vault factory");
        vm.label(performanceFeeRecipient, "performanceFeeRecipient");
    }
}
