// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import {Governance} from "../utils/Governance.sol";
import {IVault} from "@yearn-vaults/interfaces/IVault.sol";
import {IStrategy} from "@tokenized-strategy/interfaces/IStrategy.sol";

interface IOracle {
    function aprAfterDebtChange(
        address _strategy,
        int256 _delta
    ) external view returns (uint256);
}

/**
 *  @title APR Oracle
 *  @author Yearn.finance
 *  @dev Contract to easily retrieve the APR's of V3 vaults and
 *  strategies.
 *
 *  Can be used to check the current APR of any vault or strategy
 *  based on the current profit unlocking rate. As well as the
 *  expected APR given some change in totalAssets.
 *
 *  This can also be used to retrieve the expected APR a strategy
 *  is making, thats yet to be reported, if a strategy specific
 *  oracle has been added.
 *
 *  NOTE: All values are just at the specific time called and subject
 *  to change.
 */
contract AprOracle is Governance {
    // Mapping of a strategy to its specific apr oracle.
    mapping(address => address) public oracles;

    // Used to get the Current and Expected APR'S.
    uint256 internal constant MAX_BPS = 10_000;
    uint256 internal constant MAX_BPS_EXTENDED = 1_000_000_000_000;
    uint256 internal constant SECONDS_PER_YEAR = 31_556_952;

    address internal constant LEGACY_ORACLE =
        0x27aD2fFc74F74Ed27e1C0A19F1858dD0963277aE;

    constructor(address _governance) Governance(_governance) {}

    /**
     * @notice Get the current APR a strategy is earning.
     * @dev Will revert if an oracle has not been set for that strategy.
     *
     * This will be different than the {getExpectedApr()} which returns
     * the current APR based off of previously reported profits that
     * are currently unlocking.
     *
     * This will return the APR the strategy is currently earning that
     * has yet to be reported.
     *
     * @param _strategy Address of the strategy to check.
     * @param _debtChange Positive or negative change in debt.
     * @return apr The expected APR it will be earning represented as 1e18.
     */
    function getStrategyApr(
        address _strategy,
        int256 _debtChange
    ) public view virtual returns (uint256 apr) {
        // Get the oracle set for this specific strategy.
        address oracle = oracles[_strategy];

        // If not set, check the legacy oracle.
        if (oracle == address(0)) {
            // Do a low level call in case the legacy oracle is not deployed.
            (bool success, bytes memory data) = LEGACY_ORACLE.staticcall(
                abi.encodeWithSelector(
                    AprOracle(LEGACY_ORACLE).oracles.selector,
                    _strategy
                )
            );
            if (success && data.length > 0) {
                oracle = abi.decode(data, (address));
            }
        }

        // Don't revert if a oracle is not set.
        if (oracle != address(0)) {
            return IOracle(oracle).aprAfterDebtChange(_strategy, _debtChange);
        } else {
            // If the strategy is a V3 Multi strategy vault user weighted average.
            try IVault(_strategy).role_manager() returns (address) {
                return getWeightedAverageApr(_strategy, _debtChange);
            } catch {
                // If the strategy is a v3 TokenizedStrategy, we can default to the expected apr.
                try IStrategy(_strategy).fullProfitUnlockDate() returns (
                    uint256
                ) {
                    return getExpectedApr(_strategy, _debtChange);
                } catch {
                    // Else just return 0.
                    return 0;
                }
            }
        }
    }

    /**
     * @notice Set a custom APR `_oracle` for a `_strategy`.
     * @dev Can only be called by the Apr Oracle's `governance` or
     *  management of the `_strategy`.
     *
     * The `_oracle` will need to implement the IOracle interface.
     *
     * @param _strategy Address of the strategy.
     * @param _oracle Address of the APR Oracle.
     */
    function setOracle(address _strategy, address _oracle) external virtual {
        if (governance != msg.sender) {
            require(
                msg.sender == IStrategy(_strategy).management(),
                "!authorized"
            );
        }

        oracles[_strategy] = _oracle;
    }

    /**
     * @notice Get the current APR for a V3 vault or strategy.
     * @dev This returns the current APR based off the current
     * rate of profit unlocking for either a vault or strategy.
     *
     * Will return 0 if there is no profit unlocking or no assets.
     *
     * @param _vault The address of the vault or strategy.
     * @return apr The current apr expressed as 1e18.
     */
    function getCurrentApr(
        address _vault
    ) external view virtual returns (uint256 apr) {
        return getExpectedApr(_vault, 0);
    }

    /**
     * @notice Get the expected APR for a V3 vault or strategy based on `_delta`.
     * @dev This returns the expected APR based off the current
     * rate of profit unlocking for either a vault or strategy
     * given some change in the total assets.
     *
     * Will return 0 if there is no profit unlocking or no assets.
     *
     * This can be used to predict the change in current apr given some
     * deposit or withdraw to the vault.
     *
     * @param _vault The address of the vault or strategy.
     * @param _delta The positive or negative change in `totalAssets`.
     * @return apr The expected apr expressed as 1e18.
     */
    function getExpectedApr(
        address _vault,
        int256 _delta
    ) public view virtual returns (uint256 apr) {
        IVault vault = IVault(_vault);

        // Check if the full profit has already been unlocked.
        if (vault.fullProfitUnlockDate() <= block.timestamp) return 0;

        // Need the total assets in the vault post delta.
        uint256 assets = uint256(int256(vault.totalAssets()) + _delta);

        // No apr if there are no assets.
        if (assets == 0) return 0;

        // We need to get the amount of assets that are unlocking per second.
        // `profitUnlockingRate` is in shares so we convert it to assets.
        uint256 assetUnlockingRate = vault.convertToAssets(
            vault.profitUnlockingRate()
        );

        // APR = assets unlocking per second * seconds per year / the total assets.
        apr =
            (1e18 * assetUnlockingRate * SECONDS_PER_YEAR) /
            MAX_BPS_EXTENDED /
            assets;
    }

    /**
     * @notice Get the current weighted average APR for a V3 vault.
     * @dev This is the sum of all the current APR's of the strategies in the vault.
     * @param _vault The address of the vault.
     * @return apr The weighted average apr expressed as 1e18.
     */
    function getWeightedAverageApr(
        address _vault,
        int256 _delta
    ) public view virtual returns (uint256) {
        address[] memory strategies = IVault(_vault).get_default_queue();
        uint256 totalAssets = IVault(_vault).totalAssets();

        uint256 totalApr = 0;
        for (uint256 i = 0; i < strategies.length; i++) {
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
            int256 debtChange = (_delta * int256(debt)) / int256(totalAssets);

            // Add the weighted apr of the strategy to the total apr.
            totalApr +=
                (getStrategyApr(strategies[i], debtChange) *
                    uint256(int256(debt) + debtChange) *
                    (MAX_BPS - performanceFee)) /
                MAX_BPS;
        }

        // Divide by the total assets to get apr as 1e18.
        return totalApr / uint256(int256(totalAssets) + _delta);
    }
}
