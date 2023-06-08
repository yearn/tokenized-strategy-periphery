// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

/**
 *   @title Custom Strategy Trigger Base.
 *   @author Yearn.finance
 */
abstract contract CustomStrategyTriggerBase {
    /**
     * @notice Returns if a strategy should report any accrued profits/losses.
     * @dev This can be used to implement a custom trigger if the default
     * flow is not desired by a strategies managent.
     *
     * Should complete any needed checks and then return `true` if the strategy
     * should report and `false` if not.
     *
     * @param _strategy The address of the strategy to check.
     * @return . Bool repersenting if the strategy is ready to report.
     */
    function reportTrigger(
        address _strategy
    ) external view virtual returns (bool);
}
