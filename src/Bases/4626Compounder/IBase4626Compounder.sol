// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import {IBaseHealthCheck} from "../HealthCheck/IBaseHealthCheck.sol";

interface IBase4626Compounder is IBaseHealthCheck {
    function vault() external view returns (address);

    function balanceOfAsset() external view returns (uint256);

    function balanceOfVault() external view returns (uint256);

    function balanceOfStake() external view returns (uint256);

    function valueOfVault() external view returns (uint256);

    function vaultsMaxWithdraw() external view returns (uint256);
}
