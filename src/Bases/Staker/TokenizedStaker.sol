// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {BaseHooks, ERC20} from "../Hooks/BaseHooks.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

abstract contract TokenizedStaker is BaseHooks, ReentrancyGuard {
    using SafeERC20 for ERC20;

    struct Reward {
        /// @notice The only address able to top up rewards for a token (aka notifyRewardAmount()).
        address rewardsDistributor;
        /// @notice The duration of our rewards distribution for staking, default is 7 days.
        uint256 rewardsDuration;
        /// @notice The end (timestamp) of our current or most recent reward period.
        uint256 periodFinish;
        /// @notice The distribution rate of reward token per second.
        uint256 rewardRate;
        /**
         * @notice The last time rewards were updated, triggered by updateReward() or notifyRewardAmount().
         * @dev  Will be the timestamp of the update or the end of the period, whichever is earlier.
         */
        uint256 lastUpdateTime;
        /**
         * @notice The most recent stored amount for rewardPerToken().
         * @dev Updated every time anyone calls the updateReward() modifier.
         */
        uint256 rewardPerTokenStored;
        /**
         * @notice The last time a notifyRewardAmount was called.
         * @dev Used for lastRewardRate, a rewardRate equivalent for instant reward releases.
         */
        uint256 lastNotifyTime;
        /// @notice The last rewardRate before a notifyRewardAmount was called
        uint256 lastRewardRate;
    }

    /* ========== EVENTS ========== */

    event RewardAdded(address rewardToken, uint256 reward);
    event RewardPaid(address indexed user, address rewardToken, uint256 reward);
    event RewardsDurationUpdated(address rewardToken, uint256 newDuration);
    event NotifiedWithZeroSupply(address rewardToken, uint256 reward);

    /* ========== MODIFIERS ========== */

    modifier updateReward(address account) {
        _updateReward(account);
        _;
    }

    function _updateReward(address account) internal virtual {
        for (uint256 i = 0; i < rewardTokens.length; i++) {
            address rewardToken = rewardTokens[i];
            rewardData[rewardToken].rewardPerTokenStored = rewardPerToken(
                rewardToken
            );
            rewardData[rewardToken].lastUpdateTime = lastTimeRewardApplicable(
                rewardToken
            );
            if (account != address(0)) {
                rewards[account][rewardToken] = earned(account, rewardToken);
                userRewardPerTokenPaid[account][rewardToken] = rewardData[
                    rewardToken
                ].rewardPerTokenStored;
            }
        }
    }

    /// @notice Array containing the addresses of all of our reward tokens.
    address[] public rewardTokens;

    /// @notice The address of our reward token => reward info.
    mapping(address => Reward) public rewardData;

    /**
     * @notice The amount of rewards allocated to a user per whole token staked.
     * @dev Note that this is not the same as amount of rewards claimed. Mapping order is user -> reward token -> amount
     */
    mapping(address => mapping(address => uint256))
        public userRewardPerTokenPaid;

    /**
     * @notice The amount of unclaimed rewards an account is owed.
     * @dev Mapping order is user -> reward token -> amount
     */
    mapping(address => mapping(address => uint256)) public rewards;

    constructor(address _asset, string memory _name) BaseHooks(_asset, _name) {}

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
    function lastTimeRewardApplicable(
        address rewardToken
    ) public view virtual returns (uint256) {
        return
            block.timestamp < rewardData[rewardToken].periodFinish
                ? block.timestamp
                : rewardData[rewardToken].periodFinish;
    }

    /// @notice Reward paid out per whole token.
    function rewardPerToken(
        address rewardToken
    ) public view virtual returns (uint256) {
        uint256 _totalSupply = TokenizedStrategy.totalSupply();
        if (_totalSupply == 0 || rewardData[rewardToken].rewardsDuration == 1) {
            return rewardData[rewardToken].rewardPerTokenStored;
        }

        if (TokenizedStrategy.isShutdown()) {
            return 0;
        }

        return
            rewardData[rewardToken].rewardPerTokenStored +
            (((lastTimeRewardApplicable(rewardToken) -
                rewardData[rewardToken].lastUpdateTime) *
                rewardData[rewardToken].rewardRate *
                1e18) / _totalSupply);
    }

    /// @notice Amount of reward token pending claim by an account.
    function earned(
        address account,
        address rewardToken
    ) public view virtual returns (uint256) {
        if (TokenizedStrategy.isShutdown()) {
            return 0;
        }

        return
            (TokenizedStrategy.balanceOf(account) *
                (rewardPerToken(rewardToken) -
                    userRewardPerTokenPaid[account][rewardToken])) /
            1e18 +
            rewards[account][rewardToken];
    }

    /// @notice Reward tokens emitted over the entire rewardsDuration.
    function getRewardForDuration(
        address rewardToken
    ) external view virtual returns (uint256) {
        return
            rewardData[rewardToken].rewardRate *
            rewardData[rewardToken].rewardsDuration;
    }

    /// @notice Notify staking contract that it has more reward to account for.
    /// @dev Reward tokens must be sent to contract before notifying. May only be called
    ///  by rewards distribution role.
    /// @param rewardToken Address of the reward token.
    /// @param reward Amount of reward tokens to add.
    function notifyRewardAmount(
        address rewardToken,
        uint256 reward
    ) external virtual onlyManagement {
        _notifyRewardAmount(rewardToken, reward);
    }

    /// @notice Notify staking contract that it has more reward to account for.
    /// @dev Reward tokens must be sent to contract before notifying. May only be called
    ///  by rewards distribution role.
    /// @param rewardToken Address of the reward token.
    /// @param reward Amount of reward tokens to add.
    function _notifyRewardAmount(
        address rewardToken,
        uint256 reward
    ) internal virtual updateReward(address(0)) {
        /// @dev A rewardsDuration of 1 dictates instant release of rewards
        if (rewardData[rewardToken].rewardsDuration == 1) {
            _notifyRewardInstant(rewardToken, reward);
            return;
        }

        rewardData[rewardToken].lastRewardRate = rewardData[rewardToken]
            .rewardRate;
        rewardData[rewardToken].lastNotifyTime = block.timestamp;

        if (block.timestamp >= rewardData[rewardToken].periodFinish) {
            rewardData[rewardToken].rewardRate =
                reward /
                rewardData[rewardToken].rewardsDuration;
        } else {
            uint256 remaining = rewardData[rewardToken].periodFinish -
                block.timestamp;
            uint256 leftover = remaining * rewardData[rewardToken].rewardRate;
            rewardData[rewardToken].rewardRate =
                reward +
                leftover /
                rewardData[rewardToken].rewardsDuration;
        }

        rewardData[rewardToken].lastUpdateTime = block.timestamp;
        rewardData[rewardToken].periodFinish =
            block.timestamp +
            rewardData[rewardToken].rewardsDuration;
        emit RewardAdded(rewardToken, reward);
    }

    function _notifyRewardInstant(
        address rewardToken,
        uint256 reward
    ) internal {
        // Update lastNotifyTime and lastRewardRate if needed
        uint256 lastNotifyTime = rewardData[rewardToken].lastNotifyTime;
        if (block.timestamp != lastNotifyTime) {
            rewardData[rewardToken].lastRewardRate =
                reward /
                (block.timestamp - lastNotifyTime);
            rewardData[rewardToken].lastNotifyTime = block.timestamp;
        }

        // Update rewardRate, lastUpdateTime, periodFinish
        rewardData[rewardToken].rewardRate = 0;
        rewardData[rewardToken].lastUpdateTime = block.timestamp;
        rewardData[rewardToken].periodFinish = block.timestamp;

        uint256 _totalSupply = TokenizedStrategy.totalSupply();

        // If total supply is 0, send tokens to management instead of reverting.
        // Prevent footguns if _notifyRewardInstant() is part of predeposit hooks.
        if (_totalSupply == 0) {
            address management = TokenizedStrategy.management();

            ERC20(rewardToken).safeTransfer(management, reward);
            emit NotifiedWithZeroSupply(rewardToken, reward);
            return;
        }

        // Instantly release rewards by modifying rewardPerTokenStored
        rewardData[rewardToken].rewardPerTokenStored =
            rewardData[rewardToken].rewardPerTokenStored +
            (reward * 1e18) /
            _totalSupply;

        emit RewardAdded(rewardToken, reward);
    }

    /// @notice Claim any earned reward tokens.
    /// @dev Can claim rewards even if no tokens still staked.
    function getReward() public virtual nonReentrant updateReward(msg.sender) {
        for (uint256 i = 0; i < rewardTokens.length; i++) {
            address rewardToken = rewardTokens[i];
            uint256 reward = rewards[msg.sender][rewardToken];
            if (reward > 0) {
                rewards[msg.sender][rewardToken] = 0;
                ERC20(rewardToken).safeTransfer(msg.sender, reward);
                emit RewardPaid(msg.sender, rewardToken, reward);
            }
        }
    }

    /**
     * @notice Claim any one earned reward token.
     * @dev Can claim rewards even if no tokens still staked.
     * @param _rewardsToken Address of the rewards token to claim.
     */
    function getOneReward(
        address _rewardsToken
    ) external nonReentrant updateReward(msg.sender) {
        uint256 reward = rewards[msg.sender][_rewardsToken];
        if (reward > 0) {
            rewards[msg.sender][_rewardsToken] = 0;
            ERC20(_rewardsToken).safeTransfer(msg.sender, reward);
            emit RewardPaid(msg.sender, _rewardsToken, reward);
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

    /**
     * @notice Add a new reward token to the staking contract.
     * @dev May only be called by owner, and can't be set to zero address. Add reward tokens sparingly, as each new one
     *  will increase gas costs. This must be set before notifyRewardAmount can be used.
     * @dev A rewardsDuration of 1 dictates instant release of rewards.
     * @param _rewardsToken Address of the rewards token.
     * @param _rewardsDistributor Address of the rewards distributor.
     * @param _rewardsDuration The duration of our rewards distribution for staking in seconds.
     */
    function addReward(
        address _rewardsToken,
        address _rewardsDistributor,
        uint256 _rewardsDuration
    ) external onlyManagement {
        _addReward(_rewardsToken, _rewardsDistributor, _rewardsDuration);
    }

    /// @dev Internal function to add a new reward token to the staking contract.
    function _addReward(
        address _rewardsToken,
        address _rewardsDistributor,
        uint256 _rewardsDuration
    ) internal {
        require(
            _rewardsToken != address(0) && _rewardsDistributor != address(0),
            "No zero address"
        );
        require(_rewardsDuration > 0, "Must be >0");
        require(
            rewardData[_rewardsToken].rewardsDuration == 0,
            "Reward already added"
        );

        rewardTokens.push(_rewardsToken);
        rewardData[_rewardsToken].rewardsDistributor = _rewardsDistributor;
        rewardData[_rewardsToken].rewardsDuration = _rewardsDuration;
    }

    /// @notice Set the duration of our rewards period.
    /// @dev May only be called by owner, and must be done after most recent period ends.
    /// @dev A rewardsDuration of 1 dictates instant release of rewards.
    /// @param _rewardsDuration New length of period in seconds.
    function setRewardsDuration(
        address rewardToken,
        uint256 _rewardsDuration
    ) external virtual onlyManagement {
        _setRewardsDuration(rewardToken, _rewardsDuration);
    }

    function _setRewardsDuration(
        address rewardToken,
        uint256 _rewardsDuration
    ) internal virtual {
        require(
            block.timestamp > rewardData[rewardToken].periodFinish,
            "Previous rewards period must be complete before changing the duration for the new period"
        );
        rewardData[rewardToken].rewardsDuration = _rewardsDuration;
        emit RewardsDurationUpdated(rewardToken, _rewardsDuration);
    }
}
