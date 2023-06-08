// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

import {IStrategy} from "../interfaces/IStrategy.sol";

interface IVault {
    function totalAssets() external view returns (uint256);

    function profitUnlockingRate() external view returns (uint256);

    function fullProfitUnlockDate() external view returns (uint256);

    function convertToAssets(uint256) external view returns (uint256);
}

interface IOracle {
    function aprAfterDebtChange(
        address _asset,
        int256 _delta
    ) external view returns (uint256);
}

contract AprOacle {
    mapping(address => address) public oracles;

    uint256 internal constant MAX_BPS_EXTENDED = 1_000_000_000_000;
    uint256 internal constant SECONDS_PER_YEAR = 31_556_952;

    function getExpectedApr(
        address _strategy,
        int256 _debtChange
    ) public view returns (uint256) {
        address oracle = oracles[_strategy];

        // Will revert if a oracle is not set.
        return IOracle(oracle).aprAfterDebtChange(_strategy, _debtChange);
    }

    function weightedApr(address _strategy) external view returns (uint256) {
        return
            IStrategy(_strategy).totalAssets() * getExpectedApr(_strategy, 0);
    }

    function setOracle(address _strategy, address _oracle) external {
        require(msg.sender == IStrategy(_strategy).management(), "!authorized");

        oracles[_strategy] = _oracle;
    }

    /**
     * @notice Get the expected APR for a V3 vault or strategy.
     * @dev This returns the expected APR based off the current
     * rate of profit unlocking for either a vault or strategy.
     *
     * Will return 0 if there is no profit unlocking or no assets.
     *
     * @param _vault The address of the vault or strategy.
     * @return apr The expected current apr expressed as 1e18.
     */
    function getVaultApr(address _vault) external view returns (uint256 apr) {
        IVault vault = IVault(_vault);

        // Need the total assets in the vault.
        uint256 assets = vault.totalAssets();

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
