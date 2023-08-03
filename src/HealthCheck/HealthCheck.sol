// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

interface IStrategy {
    function totalAssets() external view returns (uint256);
}

/**
 *   @title Health Check
 *   @author Yearn.finance
 *   @notice This contract can be inherited by any Yearn
 *   V3 strategy wishing to implement a health check during
 *   the `report` function in order to prevent any unexpected
 *   behavior from being permanently recorded.
 *
 *   A strategist simply needs to inherit this contract. Set
 *   the limit ratios to the desired amounts and then call
 *   `require(_executeHealthCheck(...), "!healthcheck)` during
 *   the  `_harvestAndReport()` execution. If the profit or loss
 *   that would be recorded is outside the acceptable bounds
 *   the tx will revert.
 *
 *   The healthcheck does not prevent a strategy from reporting
 *   losses, but rather can make sure manual intervention is
 *   needed before reporting an unexpected loss.
 *
 *   NOTE: Strategists should build in functionality to either
 *   check the `doHealthCheck` variable with the ability to manually
 *   turn if on/off as needed, or the ability to increase the limit
 *   ratios so that the strategy is able to report eventually in the
 *   case of a real loss.
 */
contract HealthCheck {
    // Can be used to determine if a healthcheck should be called.
    // Defaults to false and will need to be updated by strategist.
    bool public doHealthCheck;

    uint256 internal constant MAX_BPS = 10_000;

    // Default profit limit to 100%.
    uint256 private _profitLimitRatio = 10_000;

    // Defaults loss limti to 0.
    uint256 private _lossLimitRatio;

    /**
     * @notice Returns the current profit limit ratio.
     * @dev Use a getter function to keep the variable private.
     * @return . The current profit limit ratio.
     */
    function profitLimitRatio() public view returns (uint256) {
        return _profitLimitRatio;
    }

    /**
     * @notice Returns the current loss limit ratio.
     * @dev Use a getter function to keep the variable private.
     * @return . The current loss limit ratio.
     */
    function lossLimitRatio() public view returns (uint256) {
        return _lossLimitRatio;
    }

    /**
     * @dev Can be used to set the profit limit ratio. Denominated
     * in basis points. I.E. 1_000 == 10%.
     * @param _newProfitLimitRatio The mew profit limit ratio.
     */
    function _setProfitLimitRatio(uint256 _newProfitLimitRatio) internal {
        require(_newProfitLimitRatio > 0, "!zero profit");
        _profitLimitRatio = _newProfitLimitRatio;
    }

    /**
     * @dev Can be used to set the loss limit ratio. Denominated
     * in basis points. I.E. 1_000 == 10%.
     * @param _newLossLimitRatio The new loss limit ratio.
     */
    function _setLossLimitRatio(uint256 _newLossLimitRatio) internal {
        require(_newLossLimitRatio < MAX_BPS, "!loss limit");
        _lossLimitRatio = _newLossLimitRatio;
    }

    /**
     * @dev To be called during a report to make sure the profit
     * or loss being recorded is within the acceptable bound.
     *
     * Strategies using this healthcheck should implement either
     * a way to bypass the check or manually up the limits if needed.
     * Otherwise this could prevent reports from ever recording
     * properly.
     *
     * @param _newTotalAssets The amount that will be returned during `_harvestAndReport()`.
     * @return . Bool repersenting if the health check passed
     */
    function _executeHealthCheck(
        uint256 _newTotalAssets
    ) internal view returns (bool) {
        // Static call self to get the total assets from the implementation.
        uint256 currentTotalAssets = IStrategy(address(this)).totalAssets();

        if (_newTotalAssets > currentTotalAssets) {
            return
                !((_newTotalAssets - currentTotalAssets) >
                    (currentTotalAssets * _profitLimitRatio) / MAX_BPS);
        } else if (currentTotalAssets > _newTotalAssets) {
            return
                !(currentTotalAssets - _newTotalAssets >
                    ((currentTotalAssets * _lossLimitRatio) / MAX_BPS));
        }

        // Nothing to check
        return true;
    }
}
