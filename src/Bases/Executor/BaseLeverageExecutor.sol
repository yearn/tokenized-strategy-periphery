// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import {BaseExecutor} from "./BaseExecutor.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title BaseLeverageExecutor
 * @author Yearn.fi
 * @notice Base contract for leverage strategies with position tracking and health monitoring
 * @dev Extends BaseExecutor with leverage-specific functionality like health factors,
 *      rebalancing, and emergency deleveraging. Still keeps most logic abstract.
 */
abstract contract BaseLeverageExecutor is BaseExecutor {
    using Math for uint256;

    struct LastKnownTotalAssets {
        uint256 estimatedTotalAssets;
        uint256 timestamp;
    }

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice Maximum allowed leverage ratio (in basis points, e.g., 300% = 30000)
    uint256 public maxLeverageRatioBps = 60_000; // Default 3x

    /// @notice Target leverage ratio for the strategy (in basis points)
    uint256 public targetLeverageRatioBps = 50_000; // Default 5x

    /// @notice Threshold for triggering rebalancing (in basis points)
    uint256 public rebalancingThresholdBps = 100; // Default 1%

    uint256 public maxExecutionLossBps = 0; // Default 0%

    /// @notice Minimum asset balance required for rebalancing (in asset units)
    uint256 public minAssetBalance = MAX_BPS; // Default to dust amount

    /// @notice Last known total assets stuct to compare against current total assets
    LastKnownTotalAssets public lastKnownTotalAssets;

    /*//////////////////////////////////////////////////////////////
                            EVENTS
    //////////////////////////////////////////////////////////////*/

    event MaxLeverageRatioUpdated(uint256 newRatio);
    event TargetLeverageRatioUpdated(uint256 newRatio);
    event MaxExecutionLossUpdated(uint256 newLoss);
    event MinAssetBalanceUpdated(uint256 newBalance);

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(
        address _asset,
        string memory _name
    ) BaseExecutor(_asset, _name) {}

    /*//////////////////////////////////////////////////////////////
                        VERIFICATION HOOKS
    //////////////////////////////////////////////////////////////*/

    function _beforeBatch(Call[] calldata calls) internal virtual override {
        require(_needsRebalancing(), "rebalancing not needed");
        _cacheTotalAssets();
    }

    /**
     * @notice Hook to verify leverage after batch execution
     */
    function _afterBatch(
        Call[] calldata calls,
        bytes[] memory results
    ) internal virtual override {
        require(!_needsRebalancing(), "rebalancing still needed");
        _verifyLeverage();
        _verifyTotalAssets();
    }

    function _cacheTotalAssets() internal virtual {
        if (block.timestamp > lastKnownTotalAssets.timestamp) {
            lastKnownTotalAssets = LastKnownTotalAssets({
                estimatedTotalAssets: estimateTotalAssets(),
                timestamp: block.timestamp
            });
        }
    }

    // Can deplete the strategy by maxExecutionLossBps at a time.
    function _verifyTotalAssets() internal view virtual {
        uint256 currentTotalAssets = estimateTotalAssets();
        require(
            currentTotalAssets >=
                (lastKnownTotalAssets.estimatedTotalAssets *
                    (MAX_BPS - maxExecutionLossBps)) /
                    MAX_BPS,
            "total assets decreased"
        );
    }

    function _verifyLeverage() internal view virtual {
        uint256 currentLeverage = leverageRatio();
        require(currentLeverage <= maxLeverageRatioBps, "leverage too high");
    }

    /*//////////////////////////////////////////////////////////////
                    LEVERAGE CALCULATION FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Calculate current leverage ratio
     * @param collateral Current collateral value
     * @param debt Current debt value
     * @return leverageRatio Leverage ratio in basis points
     */
    function _calculateLeverageRatio(
        uint256 collateral,
        uint256 debt
    ) internal pure virtual returns (uint256 leverageRatio) {
        if (collateral == 0) return 0;

        // Leverage = collateral / (collateral - debt)
        // In basis points for precision
        uint256 netValue = collateral > debt ? collateral - debt : 0;
        if (netValue == 0) return type(uint256).max;

        leverageRatio = collateral.mulDiv(MAX_BPS, netValue);
    }

    /**
     * @notice Get current leverage ratio
     * @return leverageRatio Current leverage in basis points
     */
    function leverageRatio() public view virtual returns (uint256) {
        return _calculateLeverageRatio(getCollateralValue(), getDebtValue());
    }

    /**
     * @notice Check if position needs rebalancing
     * @return needsRebalance Whether rebalancing is needed
     */
    function _needsRebalancing()
        internal
        view
        virtual
        returns (bool needsRebalance)
    {
        if (balanceOfAsset() > minAssetBalance) return true;

        uint256 currentLeverage = leverageRatio();

        // Check if leverage has deviated from target
        uint256 deviation = currentLeverage > targetLeverageRatioBps
            ? currentLeverage - targetLeverageRatioBps
            : targetLeverageRatioBps - currentLeverage;

        needsRebalance = deviation > rebalancingThresholdBps;
    }

    /*//////////////////////////////////////////////////////////////
                    REBALANCING FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Decrease leverage to target ratio
     * @dev Must be implemented by strategies
     */
    function _manualLeverageDown(uint256 _amount) internal virtual;

    /*//////////////////////////////////////////////////////////////
                    EMERGENCY FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Emergency deleverage the position
     * @dev Can be called by emergency authorized or management
     */
    function emergencyDeleverage()
        external
        virtual
        onlyEmergencyAuthorized
        nonReentrant
    {
        _manualLeverageDown(type(uint256).max);
    }

    /**
     * @notice Emergency withdraw override
     * @param _amount Amount to withdraw
     */
    function _emergencyWithdraw(uint256 _amount) internal virtual override {
        _manualLeverageDown(_amount);
    }

    /*//////////////////////////////////////////////////////////////
                    MANAGEMENT FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Set maximum leverage ratio
     * @param _maxLeverageRatioBps New maximum leverage in basis points
     */
    function setMaxLeverageRatio(
        uint256 _maxLeverageRatioBps
    ) external virtual onlyManagement {
        require(_maxLeverageRatioBps >= MAX_BPS, "leverage too low");
        require(_maxLeverageRatioBps <= 100000, "leverage too high"); // Max 10x
        maxLeverageRatioBps = _maxLeverageRatioBps;
        emit MaxLeverageRatioUpdated(_maxLeverageRatioBps);
    }

    /**
     * @notice Set target leverage ratio
     * @param _targetLeverageRatioBps New target leverage in basis points
     */
    function setTargetLeverageRatio(
        uint256 _targetLeverageRatioBps
    ) external virtual onlyManagement {
        require(_targetLeverageRatioBps >= MAX_BPS, "leverage too low");
        require(
            _targetLeverageRatioBps <= maxLeverageRatioBps,
            "exceeds max leverage"
        );
        targetLeverageRatioBps = _targetLeverageRatioBps;
        emit TargetLeverageRatioUpdated(_targetLeverageRatioBps);
    }

    /**
     * @notice Set rebalancing threshold
     * @param _rebalancingThresholdBps New threshold in basis points
     */
    function setRebalancingThreshold(
        uint256 _rebalancingThresholdBps
    ) external virtual onlyManagement {
        require(_rebalancingThresholdBps > 0, "threshold too low");
        require(_rebalancingThresholdBps <= 5000, "threshold too high"); // Max 50%
        rebalancingThresholdBps = _rebalancingThresholdBps;
    }

    /**
     * @notice Set maximum execution loss
     * @param _maxExecutionLossBps New maximum execution loss in basis points
     */
    function setMaxExecutionLoss(
        uint256 _maxExecutionLossBps
    ) external virtual onlyManagement {
        require(_maxExecutionLossBps <= MAX_BPS, "loss too high");
        maxExecutionLossBps = _maxExecutionLossBps;
        emit MaxExecutionLossUpdated(_maxExecutionLossBps);
    }

    /**
     * @notice Set minimum asset balance
     * @param _minAssetBalance New minimum asset balance
     */
    function setMinAssetBalance(
        uint256 _minAssetBalance
    ) external virtual onlyManagement {
        minAssetBalance = _minAssetBalance;
        emit MinAssetBalanceUpdated(_minAssetBalance);
    }

    /*//////////////////////////////////////////////////////////////
                    REPORTING FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Report total assets accounting for leverage
     * @dev Overrides _harvestAndReport to include position accounting
     */
    function _harvestAndReport()
        internal
        virtual
        override
        returns (uint256 _totalAssets)
    {
        _totalAssets = estimateTotalAssets();
    }

    /*//////////////////////////////////////////////////////////////
                    ABSTRACT FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Estimate total assets
     * @return _totalAssets Estimated total assets
     */
    function estimateTotalAssets()
        public
        view
        virtual
        returns (uint256 _totalAssets)
    {
        // Base calculation: balance + collateral - debt
        _totalAssets = balanceOfAsset() + getCollateralValue();

        uint256 debt = getDebtValue();
        _totalAssets = _totalAssets > debt ? _totalAssets - debt : 0;
    }

    /**
     * @notice Get current balance of asset
     * @return balance Balance of asset
     */
    function balanceOfAsset() public view virtual returns (uint256) {
        return ERC20(asset).balanceOf(address(this));
    }

    /**
     * @notice Get current collateral value in asset terms
     * @return value Collateral value
     */
    function getCollateralValue() internal view virtual returns (uint256 value);

    /**
     * @notice Get current debt value in asset terms
     * @return value Debt value
     */
    function getDebtValue() internal view virtual returns (uint256 value);
}
