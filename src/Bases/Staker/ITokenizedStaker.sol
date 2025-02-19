// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {IStrategy} from "@tokenized-strategy/interfaces/IStrategy.sol";

interface ITokenizedStaker is IStrategy {
    struct Reward {
        /// @notice The only address able to top up rewards for a token (aka notifyRewardAmount()).
        address rewardsDistributor;
        /// @notice The duration of our rewards distribution for staking, default is 7 days.
        uint96 rewardsDuration;
        /// @notice The end (timestamp) of our current or most recent reward period.
        uint96 periodFinish;
        /**
         * @notice The last time r  ewards were updated, triggered by updateReward() or notifyRewardAmount().
         * @dev  Will be the timestamp of the update or the end of the period, whichever is earlier.
         */
        uint96 lastUpdateTime;
        /// @notice The distribution rate of reward token per second.
        uint128 rewardRate;
        /**
         * @notice The most recent stored amount for rewardPerToken().
         * @dev Updated every time anyone calls the updateReward() modifier.
         */
        uint128 rewardPerTokenStored;
        /**
         * @notice The last time a notifyRewardAmount was called.
         * @dev Used for lastRewardRate, a rewardRate equivalent for instant reward releases.
         */
        uint96 lastNotifyTime;
        /// @notice The last rewardRate before a notifyRewardAmount was called
        uint128 lastRewardRate;
    }

    /* ========== EVENTS ========== */

    event RewardAdded(address indexed rewardToken, uint256 reward);
    event RewardPaid(
        address indexed user,
        address indexed rewardToken,
        uint256 reward
    );
    event RewardsDurationUpdated(
        address indexed rewardToken,
        uint256 newDuration
    );
    event NotifiedWithZeroSupply(address indexed rewardToken, uint256 reward);
    event Recovered(address token, uint256 amount);

    /* ========== STATE VARIABLES ========== */

    function rewardTokens(uint256 index) external view returns (address);

    function rewardToken(address) external view returns (address);

    function periodFinish(address) external view returns (uint256);

    function rewardRate(address) external view returns (uint256);

    function rewardsDuration(address) external view returns (uint256);

    function lastUpdateTime(address) external view returns (uint256);

    function rewardPerTokenStored(address) external view returns (uint256);

    function userRewardPerTokenPaid(
        address _account,
        address _rewardToken
    ) external view returns (uint256);

    function rewards(
        address _account,
        address _rewardToken
    ) external view returns (uint256);

    function claimForRecipient(address) external view returns (address);

    /* ========== FUNCTIONS ========== */
    function lastTimeRewardApplicable(
        address _rewardToken
    ) external view returns (uint256);

    function rewardPerToken(
        address _rewardToken
    ) external view returns (uint256);

    function earned(
        address _account,
        address _rewardToken
    ) external view returns (uint256);

    function earnedMulti(
        address _account
    ) external view returns (uint256[] memory);

    function getRewardForDuration(
        address _rewardToken
    ) external view returns (uint256);

    function notifyRewardAmount(
        address _rewardToken,
        uint256 _rewardAmount
    ) external;

    function getReward() external;

    function exit() external;

    function setRewardsDuration(
        address _rewardToken,
        uint256 _rewardsDuration
    ) external;

    function setClaimFor(address _staker, address _recipient) external;

    function setClaimForSelf(address _recipient) external;

    function rewardData(
        address rewardToken
    ) external view returns (Reward memory);

    function addReward(
        address _rewardToken,
        address _rewardsDistributor,
        uint256 _rewardsDuration
    ) external;

    function getOneReward(address _rewardToken) external;

    function recoverERC20(address _tokenAddress, uint256 _tokenAmount) external;
}
