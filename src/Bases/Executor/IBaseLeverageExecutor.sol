// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import {IBaseExecutor} from "./IBaseExecutor.sol";

/**
 * @title IBaseLeverageExecutor
 * @notice Interface for the BaseLeverageExecutor contract
 * @dev Extends IBaseExecutor with leverage-specific functionality
 */
interface IBaseLeverageExecutor is IBaseExecutor {
    /*//////////////////////////////////////////////////////////////
                            EVENTS
    //////////////////////////////////////////////////////////////*/

    event MaxLeverageRatioUpdated(uint256 newRatio);
    event TargetLeverageRatioUpdated(uint256 newRatio);
    event MaxExecutionLossUpdated(uint256 newLoss);
    event MinAssetBalanceUpdated(uint256 newBalance);

    /*//////////////////////////////////////////////////////////////
                        VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get maximum allowed leverage ratio
     * @return ratio Maximum leverage in basis points
     */
    function maxLeverageRatioBps() external view returns (uint256 ratio);

    /**
     * @notice Get target leverage ratio
     * @return ratio Target leverage in basis points
     */
    function targetLeverageRatioBps() external view returns (uint256 ratio);

    /**
     * @notice Get rebalancing threshold
     * @return threshold Rebalancing threshold in basis points
     */
    function rebalancingThresholdBps()
        external
        view
        returns (uint256 threshold);

    /**
     * @notice Get current leverage ratio
     * @return leverageRatio Current leverage in basis points
     */
    function leverageRatio() external view returns (uint256);

    /**
     * @notice Get maximum execution loss allowed
     * @return lossBps Maximum execution loss in basis points
     */
    function maxExecutionLossBps() external view returns (uint256 lossBps);

    /**
     * @notice Get minimum asset balance for rebalancing
     * @return balance Minimum asset balance
     */
    function minAssetBalance() external view returns (uint256 balance);

    /**
     * @notice Estimate total assets including leverage positions
     * @return totalAssets Estimated total assets
     */
    function estimateTotalAssets() external view returns (uint256 totalAssets);

    /**
     * @notice Get current balance of asset
     * @return balance Balance of asset
     */
    function balanceOfAsset() external view returns (uint256 balance);

    /*//////////////////////////////////////////////////////////////
                    MANAGEMENT FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Set maximum leverage ratio
     * @param _maxLeverageRatioBps New maximum leverage in basis points
     */
    function setMaxLeverageRatio(uint256 _maxLeverageRatioBps) external;

    /**
     * @notice Set target leverage ratio
     * @param _targetLeverageRatioBps New target leverage in basis points
     */
    function setTargetLeverageRatio(uint256 _targetLeverageRatioBps) external;

    /**
     * @notice Set rebalancing threshold
     * @param _rebalancingThresholdBps New threshold in basis points
     */
    function setRebalancingThreshold(uint256 _rebalancingThresholdBps) external;

    /**
     * @notice Set maximum execution loss
     * @param _maxExecutionLossBps New maximum execution loss in basis points
     */
    function setMaxExecutionLoss(uint256 _maxExecutionLossBps) external;

    /**
     * @notice Set minimum asset balance
     * @param _minAssetBalance New minimum asset balance
     */
    function setMinAssetBalance(uint256 _minAssetBalance) external;

    /*//////////////////////////////////////////////////////////////
                    OPERATIONAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Emergency deleverage the position
     * @dev Can be called by emergency authorized or management
     */
    function emergencyDeleverage() external;
}
