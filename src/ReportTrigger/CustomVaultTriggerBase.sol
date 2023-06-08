// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

/**
 *   @title Custom Vault Trigger Base.
 *   @author Yearn.finance
 */
abstract contract CustomVaultTriggerBase {
    /**
     * @notice Returns if a strategy should report any accrued profits/losses
     * to a vault.
     * @dev This can be used to implement a custom trigger if the default
     * flow is not desired by a vaults managent.
     *
     * Should complete any needed checks and then return `true` if the strategy
     * should report and `false` if not.
     *
     * @param _vault The address of the vault.
     * @param _strategy The address of the strategy that would report.
     * @return . Bool repersenting if the strategy is ready to report.
     */
    function reportTrigger(
        address _vault,
        address _strategy
    ) external view virtual returns (bool);
}
