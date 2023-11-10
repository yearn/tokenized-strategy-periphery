// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

import {IVault} from "@yearn-vaults/interfaces/IVault.sol";
import {IStrategy} from "@tokenized-strategy/interfaces/IStrategy.sol";

interface IOracle {
    function aprAfterDebtChange(
        address _asset,
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
contract AprOracle {
    // Mapping of a strategy to its specific apr oracle.
    mapping(address => address) public oracles;

    // Used to get the Current and Expected APR'S.
    uint256 internal constant MAX_BPS_EXTENDED = 1_000_000_000_000;
    uint256 internal constant SECONDS_PER_YEAR = 31_556_952;

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
     * @return . The expected APR it will be earning represented as 1e18.
     */
    function getStrategyApr(
        address _strategy,
        int256 _debtChange
    ) public view virtual returns (uint256) {
        // Get the oracle set for this specific strategy.
        address oracle = oracles[_strategy];

        // Will revert if a oracle is not set.
        return IOracle(oracle).aprAfterDebtChange(_strategy, _debtChange);
    }

    /**
     * @notice Get the current weighted APR of a strategy.
     * @dev Gives the apr weighted by its `totalAssets`. This can be used
     * to get the combined expected return of a collection of strategies.
     *
     * @param _strategy Address of the strategy.
     * @return . The current weighted APR of the strategy.
     */
    function weightedApr(
        address _strategy
    ) external view virtual returns (uint256) {
        return
            IStrategy(_strategy).totalAssets() * getStrategyApr(_strategy, 0);
    }

    /**
     * @notice Set a custom APR `_oracle` for a `_strategy`.
     * @dev Can only be called by the management of the `_strategy`.
     *
     * The `_oracle` will need to implement the IOracle interface.
     *
     * @param _strategy Address of the strategy.
     * @param _oracle Address of the APR Oracle.
     */
    function setOracle(address _strategy, address _oracle) external virtual {
        require(msg.sender == IStrategy(_strategy).management(), "!authorized");

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
}
