// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

// We use the Tokenized Strategy interface.
import {IStrategy} from "@tokenized-strategy/interfaces/IStrategy.sol";
import {BaseHealthCheck, ERC20} from "../HealthCheck/BaseHealthCheck.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title Base4626Compounder
 * @dev Can be used to make a simple strategy that compounds
 *   rewards for any 4626 vault.
 */
contract Base4626Compounder is BaseHealthCheck {
    using SafeERC20 for ERC20;

    IStrategy public immutable vault;

    constructor(
        address _asset,
        string memory _name,
        address _vault
    ) BaseHealthCheck(_asset, _name) {
        require(IStrategy(_vault).asset() == _asset, "wrong vault");
        vault = IStrategy(_vault);

        asset.safeApprove(_vault, type(uint256).max);
    }

    /*//////////////////////////////////////////////////////////////
                NEEDED TO BE OVERRIDDEN BY STRATEGIST
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Should deploy up to '_amount' of 'asset' in the yield source.
     *
     * This function is called at the end of a {deposit} or {mint}
     * call. Meaning that unless a whitelist is implemented it will
     * be entirely permissionless and thus can be sandwiched or otherwise
     * manipulated.
     *
     * @param _amount The amount of 'asset' that the strategy should attempt
     * to deposit in the yield source.
     */
    function _deployFunds(uint256 _amount) internal virtual override {
        vault.deposit(_amount, address(this));
        _stake();
    }

    /**
     * @dev Will attempt to free the '_amount' of 'asset'.
     *
     * The amount of 'asset' that is already loose has already
     * been accounted for.
     *
     * This function is called during {withdraw} and {redeem} calls.
     * Meaning that unless a whitelist is implemented it will be
     * entirely permissionless and thus can be sandwiched or otherwise
     * manipulated.
     *
     * Should not rely on asset.balanceOf(address(this)) calls other than
     * for diff accounting purposes.
     *
     * Any difference between `_amount` and what is actually freed will be
     * counted as a loss and passed on to the withdrawer. This means
     * care should be taken in times of illiquidity. It may be better to revert
     * if withdraws are simply illiquid so not to realize incorrect losses.
     *
     * @param _amount, The amount of 'asset' to be freed.
     */
    function _freeFunds(uint256 _amount) internal virtual override {
        // Use previewWithdraw to round up.
        uint256 shares = vault.previewWithdraw(_amount);

        uint256 vaultBalance = balanceOfVault();
        if (shares > vaultBalance) {
            unchecked {
                _unStake(shares - vaultBalance);
            }
            shares = Math.min(shares, balanceOfVault());
        }

        vault.redeem(shares, address(this), address(this));
    }

    /**
     * @dev Internal function to harvest all rewards, redeploy any idle
     * funds and return an accurate accounting of all funds currently
     * held by the Strategy.
     *
     * This should do any needed harvesting, rewards selling, accrual,
     * redepositing etc. to get the most accurate view of current assets.
     *
     * NOTE: All applicable assets including loose assets should be
     * accounted for in this function.
     *
     * Care should be taken when relying on oracles or swap values rather
     * than actual amounts as all Strategy profit/loss accounting will
     * be done based on this returned value.
     *
     * This can still be called post a shutdown, a strategist can check
     * `TokenizedStrategy.isShutdown()` to decide if funds should be
     * redeployed or simply realize any profits/losses.
     *
     * @return _totalAssets A trusted and accurate account for the total
     * amount of 'asset' the strategy currently holds including idle funds.
     */
    function _harvestAndReport()
        internal
        virtual
        override
        returns (uint256 _totalAssets)
    {
        // Claim and sell any rewards.
        _claimAndSellRewards();

        // Return total balance
        _totalAssets = balanceOfAsset() + valueOfVault();
    }

    /**
     * @dev Override to stake loose vault tokens after they
     *   are deposited to the `vault`.
     */
    function _stake() internal virtual {}

    /**
     * @dev If vault tokens are staked, override to unstake them before
     *   any withdraw or redeems.
     * @param _amount The amount of vault tokens to unstake.
     */
    function _unStake(uint256 _amount) internal virtual {}

    /**
     * @dev Called during reports to do any harvesting of rewards needed.
     */
    function _claimAndSellRewards() internal virtual {}

    /**
     * @notice Return the current loose balance of this strategies `asset`.
     */
    function balanceOfAsset() public view virtual returns (uint256) {
        return asset.balanceOf(address(this));
    }

    /**
     * @notice Return the current balance of the strategies vault shares.
     */
    function balanceOfVault() public view virtual returns (uint256) {
        return vault.balanceOf(address(this));
    }

    /**
     * @notice If the vaults tokens are staked. To override and return the
     *  amount of vault tokens the strategy has staked.
     */
    function balanceOfStake() public view virtual returns (uint256) {}

    /**
     * @notice The full value denominated in `asset` of the strategies vault
     *   tokens held both in the contract and staked.
     */
    function valueOfVault() public view virtual returns (uint256) {
        return vault.convertToAssets(balanceOfVault() + balanceOfStake());
    }

    /**
     * @notice The max amount of `asset` than can be redeemed from the vault.
     * @dev If the vault tokens are staked this needs to include the
     *  vault.maxRedeem(stakingContract) to be accurate.
     *
     *  NOTE: This should use vault.convertToAssets(vault.maxRedeem(address));
     *    rather than vault.maxWithdraw(address);
     */
    function vaultsMaxWithdraw() public view virtual returns (uint256) {
        return vault.convertToAssets(vault.maxRedeem(address(this)));
    }

    /**
     * @notice Gets the max amount of `asset` that an address can deposit.
     * @dev Defaults to an unlimited amount for any address. But can
     * be overridden by strategists.
     *
     * This function will be called before any deposit or mints to enforce
     * any limits desired by the strategist. This can be used for either a
     * traditional deposit limit or for implementing a whitelist etc.
     *
     *   EX:
     *      if(isAllowed[_owner]) return super.availableDepositLimit(_owner);
     *
     * This does not need to take into account any conversion rates
     * from shares to assets. But should know that any non max uint256
     * amounts may be converted to shares. So it is recommended to keep
     * custom amounts low enough as not to cause overflow when multiplied
     * by `totalSupply`.
     *
     * @param . The address that is depositing into the strategy.
     * @return . The available amount the `_owner` can deposit in terms of `asset`
     */
    function availableDepositLimit(
        address
    ) public view virtual override returns (uint256) {
        // Return the max amount the vault will allow for deposits.
        return vault.maxDeposit(address(this));
    }

    /**
     * @notice Gets the max amount of `asset` that can be withdrawn.
     * @dev Defaults to an unlimited amount for any address. But can
     * be overridden by strategists.
     *
     * This function will be called before any withdraw or redeem to enforce
     * any limits desired by the strategist. This can be used for illiquid
     * or sandwichable strategies. It should never be lower than `totalIdle`.
     *
     *   EX:
     *       return TokenIzedStrategy.totalIdle();
     *
     * This does not need to take into account the `_owner`'s share balance
     * or conversion rates from shares to assets.
     *
     * @param . The address that is withdrawing from the strategy.
     * @return . The available amount that can be withdrawn in terms of `asset`
     */
    function availableWithdrawLimit(
        address
    ) public view virtual override returns (uint256) {
        // Return the loose balance of asset and the max we can withdraw from the vault
        return balanceOfAsset() + vaultsMaxWithdraw();
    }

    /**
     * @dev Optional function for a strategist to override that will
     * allow management to manually withdraw deployed funds from the
     * yield source if a strategy is shutdown.
     *
     * This should attempt to free `_amount`, noting that `_amount` may
     * be more than is currently deployed.
     *
     * NOTE: This will not realize any profits or losses. A separate
     * {report} will be needed in order to record any profit/loss. If
     * a report may need to be called after a shutdown it is important
     * to check if the strategy is shutdown during {_harvestAndReport}
     * so that it does not simply re-deploy all funds that had been freed.
     *
     * EX:
     *   if(freeAsset > 0 && !TokenizedStrategy.isShutdown()) {
     *       depositFunds...
     *    }
     *
     * @param _amount The amount of asset to attempt to free.
     */
    function _emergencyWithdraw(uint256 _amount) internal virtual override {
        _freeFunds(Math.min(_amount, vaultsMaxWithdraw()));
    }
}
