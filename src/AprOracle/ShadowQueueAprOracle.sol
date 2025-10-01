// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import {Governance} from "../utils/Governance.sol";
import {IVault} from "@yearn-vaults/interfaces/IVault.sol";
import {IStrategy} from "@tokenized-strategy/interfaces/IStrategy.sol";

interface IOracle {
    function getStrategyApr(address, int256) external view returns (uint256);
}

/**
 *  @title Shadow Queue APR Oracle
 *  @author Yearn.finance
 *  @dev Contract to retrieve the expected APRs of V3 vaults with strategies outside of the default queue.
 *
 *  NOTE: All values are just at the specific time called and subject
 *  to change.
 */

contract ShadowQueueAprOracle is Governance {
    /// @notice Mapping of a vault to the strategies outside its queue.
    /// @dev Strategies must be manually updated here if they change on the vault.
    mapping(address vault => address[] strategiesOutsideQueue)
        public extraStrategies;

    IOracle public constant CORE_ORACLE =
        IOracle(0x1981AD9F44F2EA9aDd2dC4AD7D075c102C70aF92);

    uint256 internal constant MAX_BPS = 10_000;

    constructor(address _governance) Governance(_governance) {}

    /**
     * @notice Get the current APR a vault is earning, including strategies outside of the default queue.
     *
     * This will return the APR the vault is currently earning from strategies that
     * has yet to be reported.
     *
     * @param _vault Address of the vault to check.
     * @param _debtChange Positive or negative change in debt.
     * @return apr The expected APR it will be earning represented as 1e18.
     */
    function aprAfterDebtChange(
        address _vault,
        int256 _debtChange
    ) external view virtual returns (uint256 apr) {
        // Get the shadow queue set for this specific strategy.
        address[] memory strategiesOutsideQueue = extraStrategies[_vault];
        address[] memory strategies = IVault(_vault).get_default_queue();

        uint256 totalAssets = IVault(_vault).totalAssets();
        uint256 totalApr = 0;
        for (uint256 i = 0; i < strategies.length; i++) {
            // make sure we're not double-counting, compare our two arrays for duplicates
            for (uint256 j; j < strategiesOutsideQueue.length; ++j) {
                require(
                    strategies[i] != strategiesOutsideQueue[j],
                    "Duplicate strategy"
                );
            }

            uint256 debt = IVault(_vault)
                .strategies(strategies[i])
                .current_debt;

            if (debt == 0) continue;

            // Get a performance fee if the strategy has one.
            (bool success, bytes memory fee) = strategies[i].staticcall(
                abi.encodeWithSelector(
                    IStrategy(strategies[i]).performanceFee.selector
                )
            );

            uint256 performanceFee;
            if (success) {
                performanceFee = abi.decode(fee, (uint256));
            }

            // Get the effective debt change for the strategy.
            int256 debtChange = (_debtChange * int256(debt)) /
                int256(totalAssets);

            // Add the weighted apr of the strategy to the total apr.
            totalApr +=
                (CORE_ORACLE.getStrategyApr(strategies[i], debtChange) *
                    uint256(int256(debt) + debtChange) *
                    (MAX_BPS - performanceFee)) /
                MAX_BPS;
        }

        for (uint256 i = 0; i < strategiesOutsideQueue.length; i++) {
            uint256 debt = IVault(_vault)
                .strategies(strategiesOutsideQueue[i])
                .current_debt;

            if (debt == 0) continue;

            // Get a performance fee if the strategy has one.
            (bool success, bytes memory fee) = strategiesOutsideQueue[i]
                .staticcall(
                    abi.encodeWithSelector(
                        IStrategy(strategiesOutsideQueue[i])
                            .performanceFee
                            .selector
                    )
                );

            uint256 performanceFee;
            if (success) {
                performanceFee = abi.decode(fee, (uint256));
            }

            // Get the effective debt change for the strategy.
            int256 debtChange = (_debtChange * int256(debt)) /
                int256(totalAssets);

            // Add the weighted apr of the strategy to the total apr.
            totalApr +=
                (CORE_ORACLE.getStrategyApr(
                    strategiesOutsideQueue[i],
                    debtChange
                ) *
                    uint256(int256(debt) + debtChange) *
                    (MAX_BPS - performanceFee)) /
                MAX_BPS;
        }

        // Divide by the total assets to get apr as 1e18.
        return totalApr / uint256(int256(totalAssets) + _debtChange);
    }

    /**
     * @notice Set the array of strategies outside the default queue for a given vault.
     * @dev Can only be called by the oracle's `governance`.
     *
     * @param _vault Address of the vault.
     * @param _shadowQueue Array of attached strategies that are outside of the default queue.
     */
    function setExtraStrategies(
        address _vault,
        address[] memory _shadowQueue
    ) external virtual onlyGovernance {
        // make sure each strategy is attached to the vault
        IVault vault = IVault(_vault);
        for (uint256 i = 0; i < _shadowQueue.length; i++) {
            require(
                vault.strategies(_shadowQueue[i]).activation > 0,
                "!activated"
            );
        }
        extraStrategies[_vault] = _shadowQueue;
    }
}
