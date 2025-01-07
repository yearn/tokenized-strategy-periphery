// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import "forge-std/console.sol";
import {BaseHooks, ERC20} from "../Hooks/BaseHooks.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

// TODO dont update values twice in the same block
abstract contract TokenizedStaker is BaseHooks, ReentrancyGuard {
    using SafeERC20 for ERC20;

    /* ========== EVENTS ========== */

    event RewardAdded(uint256 reward);
    event RewardPaid(address indexed user, uint256 reward);
    event RewardsDurationUpdated(uint256 newDuration);

    /* ========== MODIFIERS ========== */

    modifier updateReward(address account) {
        _updateReward(account);
        _;
    }

    function _updateReward(address account) internal virtual {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = lastTimeRewardApplicable();
        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
    }

    ERC20 public immutable rewardToken;

    uint256 public periodFinish;

    /// @notice The distribution rate of rewardToken per second.
    uint256 public rewardRate;

    /// @notice The duration of our rewards distribution for staking, default is 7 days.
    uint256 public rewardsDuration = 7 days;

    /// @notice The last time rewards were updated, triggered by updateReward() or notifyRewardAmount().
    /// @dev Will be the timestamp of the update or the end of the period, whichever is earlier.
    uint256 public lastUpdateTime;

    /// @notice The most recent stored amount for rewardPerToken().
    /// @dev Updated every time anyone calls the updateReward() modifier.
    uint256 public rewardPerTokenStored;

    // @notice The amount of rewards allocated to a user per whole token staked.
    /// @dev Note that this is not the same as amount of rewards claimed.
    mapping(address => uint256) public userRewardPerTokenPaid;

    /// @notice The amount of unclaimed rewards an account is owed.
    mapping(address => uint256) public rewards;

    constructor(
        address _asset,
        string memory _name,
        address _rewardToken
    ) BaseHooks(_asset, _name) {
        rewardToken = ERC20(_rewardToken);
    }

    function _preDepositHook(
        uint256 /* assets */,
        uint256 /* shares */,
        address receiver
    ) internal virtual override {
        _updateReward(receiver);
    }

    function _preWithdrawHook(
        uint256 /* assets */,
        uint256 /* shares */,
        address /* receiver */,
        address owner,
        uint256 /* maxLoss */
    ) internal virtual override {
        _updateReward(owner);
    }

    function _preTransferHook(
        address from,
        address to,
        uint256 /* amount */
    ) internal virtual override {
        _updateReward(from);
        _updateReward(to);
    }

    /// @notice Either the current timestamp or end of the most recent period.
    function lastTimeRewardApplicable() public view virtual returns (uint256) {
        return block.timestamp < periodFinish ? block.timestamp : periodFinish;
    }

    /// @notice Reward paid out per whole token.
    function rewardPerToken() public view virtual returns (uint256) {
        uint256 _totalSupply = TokenizedStrategy.totalSupply();
        if (_totalSupply == 0) {
            return rewardPerTokenStored;
        }

        if (TokenizedStrategy.isShutdown()) {
            return 0;
        }

        return
            rewardPerTokenStored +
            (((lastTimeRewardApplicable() - lastUpdateTime) *
                rewardRate *
                1e18) / _totalSupply);
    }

    /// @notice Amount of reward token pending claim by an account.
    function earned(address account) public view virtual returns (uint256) {
        if (TokenizedStrategy.isShutdown()) {
            return 0;
        }

        return
            (TokenizedStrategy.balanceOf(account) *
                (rewardPerToken() - userRewardPerTokenPaid[account])) /
            1e18 +
            rewards[account];
    }

    /// @notice Reward tokens emitted over the entire rewardsDuration.
    function getRewardForDuration() external view virtual returns (uint256) {
        return rewardRate * rewardsDuration;
    }

    function notifyRewardAmount(
        uint256 reward
    ) external virtual onlyManagement {
        _notifyRewardAmount(reward);
    }

    /// @notice Notify staking contract that it has more reward to account for.
    /// @dev Reward tokens must be sent to contract before notifying. May only be called
    ///  by rewards distribution role.
    /// @param reward Amount of reward tokens to add.
    function _notifyRewardAmount(
        uint256 reward
    ) internal virtual updateReward(address(0)) {
        if (block.timestamp >= periodFinish) {
            rewardRate = reward / rewardsDuration;
        } else {
            uint256 remaining = periodFinish - block.timestamp;
            uint256 leftover = remaining * rewardRate;
            console.log("leftover", leftover);
            rewardRate = reward + leftover / rewardsDuration;
        }

        // Ensure the provided reward amount is not more than the balance in the contract.
        // This keeps the reward rate in the right range, preventing overflows due to
        // very high values of rewardRate in the earned and rewardsPerToken functions;
        // Reward + leftover must be less than 2^256 / 10^18 to avoid overflow.
        uint256 balance = rewardToken.balanceOf(address(this));
        console.log("balance", balance);
        console.log("rewardRate", rewardRate);
        console.log("rewardsDuration", rewardsDuration);
        require(
            true, // rewardRate <= balance / rewardsDuration,
            "Provided reward too high"
        );

        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp + rewardsDuration;
        emit RewardAdded(reward);
    }

    /// @notice Claim any earned reward tokens.
    /// @dev Can claim rewards even if no tokens still staked.
    function getReward() public virtual nonReentrant updateReward(msg.sender) {
        uint256 reward = rewards[msg.sender];
        if (reward > 0) {
            rewards[msg.sender] = 0;
            rewardToken.safeTransfer(msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
        }
    }

    /// @notice Unstake all of the sender's tokens and claim any outstanding rewards.
    function exit() external virtual {
        redeem(
            TokenizedStrategy.balanceOf(msg.sender),
            msg.sender,
            msg.sender,
            10_000
        );
        getReward();
    }

    /// @notice Set the duration of our rewards period.
    /// @dev May only be called by owner, and must be done after most recent period ends.
    /// @param _rewardsDuration New length of period in seconds.
    function setRewardsDuration(
        uint256 _rewardsDuration
    ) external virtual onlyManagement {
        _setRewardsDuration(_rewardsDuration);
    }

    function _setRewardsDuration(uint256 _rewardsDuration) internal virtual {
        require(
            block.timestamp > periodFinish,
            "Previous rewards period must be complete before changing the duration for the new period"
        );
        rewardsDuration = _rewardsDuration;
        emit RewardsDurationUpdated(rewardsDuration);
    }
}
