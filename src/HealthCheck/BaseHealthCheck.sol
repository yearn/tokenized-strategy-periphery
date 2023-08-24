// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {BaseTokenizedStrategy} from "@tokenized-strategy/BaseTokenizedStrategy.sol";

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
 *   `_executeHealthCheck(...)` during the  `_harvestAndReport()`
 *   execution. If the profit or loss that would be recorded is
 *   outside the acceptable bounds the tx will revert.
 *
 *   The healthcheck does not prevent a strategy from reporting
 *   losses, but rather can make sure manual intervention is
 *   needed before reporting an unexpected loss.
 */
abstract contract BaseHealthCheck is BaseTokenizedStrategy {
    modifier HealthCheck() {
        _healthCheck();
        _;
    }

    // Can be used to determine if a healthcheck should be called.
    // Defaults to true;
    bool public doHealthCheck = true;

    uint256 internal constant MAX_BPS = 10_000;

    // Default profit limit to 100%.
    uint256 private _profitLimitRatio = MAX_BPS;

    // Defaults loss limit to 0.
    uint256 private _lossLimitRatio;

    constructor(
        address _asset,
        string memory _name
    ) BaseTokenizedStrategy(_asset, _name) {}

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
     * @notice Set the `profitLimitRatio`.
     * @dev Denominated in basis points. I.E. 1_000 == 10%.
     * @param _newProfitLimitRatio The mew profit limit ratio.
     */
    function setProfitLimitRatio(
        uint256 _newProfitLimitRatio
    ) external onlyManagement {
        _setProfitLimitRatio(_newProfitLimitRatio);
    }

    /**
     * @dev Internally set the profit limit ratio. Denominated
     * in basis points. I.E. 1_000 == 10%.
     * @param _newProfitLimitRatio The mew profit limit ratio.
     */
    function _setProfitLimitRatio(uint256 _newProfitLimitRatio) internal {
        require(_newProfitLimitRatio > 0, "!zero profit");
        _profitLimitRatio = _newProfitLimitRatio;
    }

    /**
     * @notice Set the `lossLimitRatio`.
     * @dev Denominated in basis points. I.E. 1_000 == 10%.
     * @param _newLossLimitRatio The new loss limit ratio.
     */
    function setLossLimitRatio(
        uint256 _newLossLimitRatio
    ) external onlyManagement {
        _setLossLimitRatio(_newLossLimitRatio);
    }

    /**
     * @dev Internally set the loss limit ratio. Denominated
     * in basis points. I.E. 1_000 == 10%.
     * @param _newLossLimitRatio The new loss limit ratio.
     */
    function _setLossLimitRatio(uint256 _newLossLimitRatio) internal {
        require(_newLossLimitRatio < MAX_BPS, "!loss limit");
        _lossLimitRatio = _newLossLimitRatio;
    }

    /**
     * @notice Turns the healthcheck on and off.
     * @dev If turned off the next report will auto turn it back on.
     * @param _doHealthCheck Bool if healthCheck should be done.
     */
    function setDoHealthCheck(bool _doHealthCheck) public onlyManagement {
        doHealthCheck = _doHealthCheck;
    }

    /**
     * @notice Check important invariants for the strategy.
     * @dev This deafults to checking totalDebt but can be overriden
     * to check any important strategy specific invariants.
     */
    function _healthCheck() internal virtual {
        require(TokenizedStrategy.totalDebt() <= _currentDebt(), "healthCheck");
    }

    /**
     * @dev Return the current expected debt the strategy has for
     * the HealthCheck modifier.
     *
     * This can be set to type(uint256).max to bypass the check.
     * @param . Estimate of the current value of the strategies debt.
     */
    function _currentDebt() internal view virtual returns (uint256);

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
     */
    function _executeHealthCheck(uint256 _newTotalAssets) internal virtual {
        if (!doHealthCheck) {
            doHealthCheck = true;
            return;
        }

        // Get the curent total assets from the implementation.
        uint256 currentTotalAssets = TokenizedStrategy.totalAssets();

        if (_newTotalAssets > currentTotalAssets) {
            require(
                ((_newTotalAssets - currentTotalAssets) <=
                    (currentTotalAssets * _profitLimitRatio) / MAX_BPS),
                "healthCheck"
            );
        } else if (currentTotalAssets > _newTotalAssets) {
            require(
                (currentTotalAssets - _newTotalAssets <=
                    ((currentTotalAssets * _lossLimitRatio) / MAX_BPS)),
                "healthCheck"
            );
        }
    }
}
