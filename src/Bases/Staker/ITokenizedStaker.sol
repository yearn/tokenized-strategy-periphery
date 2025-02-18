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

    event RewardAdded(address rewardToken, uint256 reward);
    event RewardPaid(address indexed user, address rewardToken, uint256 reward);
    event RewardsDurationUpdated(address rewardToken, uint256 newDuration);
    event NotifiedWithZeroSupply(address rewardToken, uint256 reward);

    /* ========== STATE VARIABLES ========== */

    function rewardTokens(uint256 index) external view returns (address);

    function rewardToken(address) external view returns (address);

    function periodFinish(address) external view returns (uint256);

    function rewardRate(address) external view returns (uint256);

    function rewardsDuration(address) external view returns (uint256);

    function lastUpdateTime(address) external view returns (uint256);

    function rewardPerTokenStored(address) external view returns (uint256);

    function userRewardPerTokenPaid(
        address account,
        address rewardToken
    ) external view returns (uint256);

    function rewards(
        address account,
        address rewardToken
    ) external view returns (uint256);

    /* ========== FUNCTIONS ========== */
    function lastTimeRewardApplicable(
        address rewardToken
    ) external view returns (uint256);

    function rewardPerToken(
        address rewardToken
    ) external view returns (uint256);

    function earned(
        address account,
        address rewardToken
    ) external view returns (uint256);

    function getRewardForDuration(
        address rewardToken
    ) external view returns (uint256);

    function notifyRewardAmount(address rewardToken, uint256 reward) external;

    function getReward() external;

    function exit() external;

    function setRewardsDuration(
        address rewardToken,
        uint256 _rewardsDuration
    ) external;

    function rewardData(
        address rewardToken
    ) external view returns (Reward memory);

    function addReward(
        address rewardToken,
        address rewardsDistributor,
        uint256 rewardsDuration
    ) external;

    function getOneReward(address rewardToken) external;
}
