// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {BaseHooks, ERC20} from "../Hooks/BaseHooks.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IVaultFactory} from "@yearn-vaults/interfaces/IVaultFactory.sol";

abstract contract TokenizedStaker is BaseHooks, ReentrancyGuard {
    using SafeERC20 for ERC20;

    struct Reward {
        /// @notice The only address able to top up rewards for a token (aka notifyRewardAmount()).
        address rewardsDistributor;
        /// @notice The duration of our rewards distribution for staking, default is 7 days.
        uint96 rewardsDuration;
        /// @notice The end (timestamp) of our current or most recent reward period.
        uint96 periodFinish;
        /**
         * @notice The last time rewards were updated, triggered by updateReward() or notifyRewardAmount().
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

    /* ========== MODIFIERS ========== */

    modifier updateReward(address _account) {
        _updateReward(_account);
        _;
    }

    function _updateReward(address _account) internal virtual {
        for (uint256 i; i < rewardTokens.length; ++i) {
            address rewardToken = rewardTokens[i];
            rewardData[rewardToken].rewardPerTokenStored = uint128(
                rewardPerToken(rewardToken)
            );
            rewardData[rewardToken].lastUpdateTime = uint96(
                lastTimeRewardApplicable(rewardToken)
            );
            if (_account != address(0)) {
                rewards[_account][rewardToken] = earned(_account, rewardToken);
                userRewardPerTokenPaid[_account][rewardToken] = rewardData[
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
     * @notice Mapping for staker address => address that can claim+receive tokens for them.
     * @dev This mapping can only be updated by management.
     */
    mapping(address => address) public claimForRecipient;

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

    uint256 internal constant PRECISION = 1e18;

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

    // Need to update fee recipients before reporting to ensure accurate accounting
    // since fees are issued as shares to the recipients outside normal functionality.
    function _preReportHook() internal virtual override {
        _updateReward(TokenizedStrategy.performanceFeeRecipient());
        (uint16 feeBps, address protocolFeeRecipient) = IVaultFactory(
            TokenizedStrategy.FACTORY()
        ).protocol_fee_config();
        if (feeBps > 0) {
            _updateReward(protocolFeeRecipient);
        }
    }

    /// @notice Either the current timestamp or end of the most recent period.
    function lastTimeRewardApplicable(
        address _rewardToken
    ) public view virtual returns (uint256) {
        return
            block.timestamp < rewardData[_rewardToken].periodFinish
                ? block.timestamp
                : rewardData[_rewardToken].periodFinish;
    }

    /// @notice Reward paid out per whole token.
    function rewardPerToken(
        address _rewardToken
    ) public view virtual returns (uint256) {
        // store in memory to save gas
        Reward memory _rewardData = rewardData[_rewardToken];
        uint256 totalSupply = _totalSupply();

        if (totalSupply == 0 || _rewardData.rewardsDuration == 1) {
            return _rewardData.rewardPerTokenStored;
        }

        return
            _rewardData.rewardPerTokenStored +
            (((lastTimeRewardApplicable(_rewardToken) -
                _rewardData.lastUpdateTime) *
                _rewardData.rewardRate *
                PRECISION) / totalSupply);
    }

    /// @notice Amount of reward token pending claim by an account.
    function earned(
        address _account,
        address _rewardToken
    ) public view virtual returns (uint256) {
        return
            (TokenizedStrategy.balanceOf(_account) *
                (rewardPerToken(_rewardToken) -
                    userRewardPerTokenPaid[_account][_rewardToken])) /
            PRECISION +
            rewards[_account][_rewardToken];
    }

    /**
     * @notice Amount of reward token(s) pending claim by an account.
     * @dev Checks for all rewardTokens.
     * @param _account Account to check earned balance for.
     * @return pending Amount of reward token(s) pending claim.
     */
    function earnedMulti(
        address _account
    ) public view virtual returns (uint256[] memory pending) {
        address[] memory _rewardTokens = rewardTokens;
        uint256 length = _rewardTokens.length;
        pending = new uint256[](length);

        for (uint256 i; i < length; ++i) {
            pending[i] = earned(_account, _rewardTokens[i]);
        }
    }

    /// @notice Reward tokens emitted over the entire rewardsDuration.
    function getRewardForDuration(
        address _rewardToken
    ) external view virtual returns (uint256) {
        // note that if rewards are instant released, this will always return zero
        return
            rewardData[_rewardToken].rewardRate *
            rewardData[_rewardToken].rewardsDuration;
    }

    /// @notice Correct Total supply for the locked shares from profits
    function _totalSupply() internal view virtual returns (uint256) {
        return
            TokenizedStrategy.totalSupply() -
            TokenizedStrategy.balanceOf(address(this));
    }

    /**
     * @notice Notify staking contract that it has more reward to account for.
     * @dev May only be called by rewards distribution role or management. Set up token first via addReward().
     * @param _rewardToken Address of the rewards token.
     * @param _rewardAmount Amount of reward tokens to add.
     */
    function notifyRewardAmount(
        address _rewardToken,
        uint256 _rewardAmount
    ) external virtual {
        require(
            rewardData[_rewardToken].rewardsDistributor == msg.sender ||
                msg.sender == TokenizedStrategy.management(),
            "!authorized"
        );

        // handle the transfer of reward tokens via `transferFrom` to reduce the number
        // of transactions required and ensure correctness of the reward amount
        ERC20(_rewardToken).safeTransferFrom(
            msg.sender,
            address(this),
            _rewardAmount
        );

        _notifyRewardAmount(_rewardToken, _rewardAmount);
    }

    function _notifyRewardAmount(
        address _rewardToken,
        uint256 _rewardAmount
    ) internal virtual updateReward(address(0)) {
        Reward memory _rewardData = rewardData[_rewardToken];
        require(_rewardAmount > 0 && _rewardAmount < 1e30, "bad reward value");

        // If total supply is 0, send tokens to management instead of reverting.
        // Prevent footguns if _notifyRewardInstant() is part of predeposit hooks.
        uint256 totalSupply = _totalSupply();
        if (totalSupply == 0) {
            address management = TokenizedStrategy.management();

            ERC20(_rewardToken).safeTransfer(management, _rewardAmount);
            emit NotifiedWithZeroSupply(_rewardToken, _rewardAmount);
            return;
        }

        // this is the only part of the struct that will be the same for instant or normal
        _rewardData.lastUpdateTime = uint96(block.timestamp);

        /// @dev A rewardsDuration of 1 dictates instant release of rewards
        if (_rewardData.rewardsDuration == 1) {
            // Update lastNotifyTime and lastRewardRate if needed (would revert if in the same block otherwise)
            if (uint96(block.timestamp) != _rewardData.lastNotifyTime) {
                _rewardData.lastRewardRate = uint128(
                    _rewardAmount /
                        (block.timestamp - _rewardData.lastNotifyTime)
                );
                _rewardData.lastNotifyTime = uint96(block.timestamp);
            }

            // Update rewardRate, lastUpdateTime, periodFinish
            _rewardData.rewardRate = 0;
            _rewardData.periodFinish = uint96(block.timestamp);

            // Instantly release rewards by modifying rewardPerTokenStored
            _rewardData.rewardPerTokenStored = uint128(
                _rewardData.rewardPerTokenStored +
                    (_rewardAmount * PRECISION) /
                    totalSupply
            );
        } else {
            // store current rewardRate
            _rewardData.lastRewardRate = _rewardData.rewardRate;
            _rewardData.lastNotifyTime = uint96(block.timestamp);

            // update our rewardData with our new rewardRate
            if (block.timestamp >= _rewardData.periodFinish) {
                _rewardData.rewardRate = uint128(
                    _rewardAmount / _rewardData.rewardsDuration
                );
            } else {
                _rewardData.rewardRate = uint128(
                    (_rewardAmount +
                        (_rewardData.periodFinish - block.timestamp) *
                        _rewardData.rewardRate) / _rewardData.rewardsDuration
                );
            }

            // update time-based struct fields
            _rewardData.periodFinish = uint96(
                block.timestamp + _rewardData.rewardsDuration
            );
        }

        // make sure we have enough reward token for our new rewardRate
        require(
            _rewardData.rewardRate <=
                (ERC20(_rewardToken).balanceOf(address(this)) /
                    _rewardData.rewardsDuration),
            "Not enough balance"
        );

        // write to storage
        rewardData[_rewardToken] = _rewardData;
        emit RewardAdded(_rewardToken, _rewardAmount);
    }

    /**
     * @notice Claim any (and all) earned reward tokens.
     * @dev Can claim rewards even if no tokens still staked.
     */
    function getReward() external nonReentrant updateReward(msg.sender) {
        _getRewardFor(msg.sender, msg.sender);
    }

    /**
     * @notice Claim any (and all) earned reward tokens for another user.
     * @dev Mapping must be manually updated via management. Must be called by recipient.
     * @param _staker Address of the user to claim rewards for.
     */
    function getRewardFor(
        address _staker
    ) external nonReentrant updateReward(_staker) {
        require(claimForRecipient[_staker] == msg.sender, "!recipient");
        _getRewardFor(_staker, msg.sender);
    }

    // internal function to get rewards.
    function _getRewardFor(address _staker, address _recipient) internal {
        for (uint256 i; i < rewardTokens.length; ++i) {
            address _rewardToken = rewardTokens[i];
            uint256 reward = rewards[_staker][_rewardToken];
            if (reward > 0) {
                rewards[_staker][_rewardToken] = 0;
                ERC20(_rewardToken).safeTransfer(_recipient, reward);
                emit RewardPaid(_staker, _rewardToken, reward);
            }
        }
    }

    /**
     * @notice Claim any one earned reward token.
     * @dev Can claim rewards even if no tokens still staked.
     * @param _rewardToken Address of the rewards token to claim.
     */
    function getOneReward(
        address _rewardToken
    ) external virtual nonReentrant updateReward(msg.sender) {
        uint256 reward = rewards[msg.sender][_rewardToken];
        if (reward > 0) {
            rewards[msg.sender][_rewardToken] = 0;
            ERC20(_rewardToken).safeTransfer(msg.sender, reward);
            emit RewardPaid(msg.sender, _rewardToken, reward);
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
        _getRewardFor(msg.sender, msg.sender);
    }

    /**
     * @notice Add a new reward token to the staking contract.
     * @dev May only be called by management, and can't be set to zero address. Add reward tokens sparingly, as each new
     *  one will increase gas costs. This must be set before notifyRewardAmount can be used. A rewardsDuration of 1
     *  dictates instant release of rewards.
     * @param _rewardToken Address of the rewards token.
     * @param _rewardsDistributor Address of the rewards distributor.
     * @param _rewardsDuration The duration of our rewards distribution for staking in seconds. Set to 1 for instant
     *  rewards distribution.
     */
    function addReward(
        address _rewardToken,
        address _rewardsDistributor,
        uint256 _rewardsDuration
    ) external virtual onlyManagement {
        _addReward(_rewardToken, _rewardsDistributor, _rewardsDuration);
    }

    /// @dev Internal function to add a new reward token to the staking contract.
    function _addReward(
        address _rewardToken,
        address _rewardsDistributor,
        uint256 _rewardsDuration
    ) internal virtual {
        require(
            _rewardToken != address(0) && _rewardsDistributor != address(0),
            "No zero address"
        );
        require(_rewardsDuration > 0, "Must be >0");
        require(
            rewardData[_rewardToken].rewardsDuration == 0,
            "Reward already added"
        );

        rewardTokens.push(_rewardToken);
        rewardData[_rewardToken].rewardsDistributor = _rewardsDistributor;
        rewardData[_rewardToken].rewardsDuration = uint96(_rewardsDuration);
    }

    /**
     * @notice Set the duration of our rewards period.
     * @dev May only be called by management, and must be done after most recent period ends.
     * @param _rewardToken Address of the rewards token.
     * @param _rewardsDuration New length of period in seconds. Set to 1 for instant rewards release.
     */
    function setRewardsDuration(
        address _rewardToken,
        uint256 _rewardsDuration
    ) external virtual onlyManagement {
        _setRewardsDuration(_rewardToken, _rewardsDuration);
    }

    function _setRewardsDuration(
        address _rewardToken,
        uint256 _rewardsDuration
    ) internal virtual {
        // Previous rewards period must be complete before changing the duration for the new period
        require(
            block.timestamp > rewardData[_rewardToken].periodFinish,
            "!period"
        );
        require(_rewardsDuration > 0, "Must be >0");
        rewardData[_rewardToken].rewardsDuration = uint96(_rewardsDuration);
        emit RewardsDurationUpdated(_rewardToken, _rewardsDuration);
    }

    /**
     * @notice Setup a staker-recipient pair.
     * @dev May only be called by management. Useful for contracts that can't handle extra reward tokens to direct
     *  rewards elsewhere.
     * @param _staker Address that holds the vault tokens.
     * @param _recipient Address to claim and receive extra rewards on behalf of _staker.
     */
    function setClaimFor(
        address _staker,
        address _recipient
    ) external virtual onlyManagement {
        _setClaimFor(_staker, _recipient);
    }

    /**
     * @notice Give another address permission to claim (and receive!) your rewards.
     * @dev Useful if we want to add in complex logic following rewards claim such as staking.
     * @param _recipient Address to claim and receive extra rewards on behalf of msg.sender.
     */
    function setClaimForSelf(address _recipient) external virtual {
        _setClaimFor(msg.sender, _recipient);
    }

    function _setClaimFor(
        address _staker,
        address _recipient
    ) internal virtual {
        require(_staker != address(0), "No zero address");
        claimForRecipient[_staker] = _recipient;
    }

    /**
     * @notice Sweep out tokens accidentally sent here.
     * @dev May only be called by management. If a pool has multiple tokens to sweep out, call this once for each.
     * @param _tokenAddress Address of token to sweep.
     * @param _tokenAmount Amount of tokens to sweep.
     */
    function recoverERC20(
        address _tokenAddress,
        uint256 _tokenAmount
    ) external onlyManagement {
        require(_tokenAddress != address(asset), "!asset");

        // can only recover reward tokens 90 days after last reward token ends
        bool isRewardToken;
        address[] memory _rewardTokens = rewardTokens;
        uint256 maxPeriodFinish;

        for (uint256 i; i < _rewardTokens.length; ++i) {
            uint256 rewardPeriodFinish = rewardData[_rewardTokens[i]]
                .periodFinish;
            if (rewardPeriodFinish > maxPeriodFinish) {
                maxPeriodFinish = rewardPeriodFinish;
            }

            if (_rewardTokens[i] == _tokenAddress) {
                isRewardToken = true;
            }
        }

        if (isRewardToken) {
            require(
                block.timestamp > maxPeriodFinish + 90 days,
                "wait >90 days"
            );

            // if we do this, automatically sweep all reward token
            _tokenAmount = ERC20(_tokenAddress).balanceOf(address(this));
        }

        ERC20(_tokenAddress).safeTransfer(
            TokenizedStrategy.management(),
            _tokenAmount
        );
        emit Recovered(_tokenAddress, _tokenAmount);
    }
}
