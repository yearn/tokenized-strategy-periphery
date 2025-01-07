// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {IStrategy} from "@tokenized-strategy/interfaces/IStrategy.sol";

interface ITokenizedStaker is IStrategy {
    /* ========== EVENTS ========== */
    event RewardAdded(uint256 reward);
    event RewardPaid(address indexed user, uint256 reward);
    event RewardsDurationUpdated(uint256 newDuration);

    /* ========== STATE VARIABLES ========== */
    function rewardToken() external view returns (address);

    function periodFinish() external view returns (uint256);

    function rewardRate() external view returns (uint256);

    function rewardsDuration() external view returns (uint256);

    function lastUpdateTime() external view returns (uint256);

    function rewardPerTokenStored() external view returns (uint256);

    function userRewardPerTokenPaid(
        address account
    ) external view returns (uint256);

    function rewards(address account) external view returns (uint256);

    /* ========== FUNCTIONS ========== */
    function lastTimeRewardApplicable() external view returns (uint256);

    function rewardPerToken() external view returns (uint256);

    function earned(address account) external view returns (uint256);

    function getRewardForDuration() external view returns (uint256);

    function notifyRewardAmount(uint256 reward) external;

    function getReward() external;

    function exit() external;

    function setRewardsDuration(uint256 _rewardsDuration) external;
}
