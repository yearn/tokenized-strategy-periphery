// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import {IBaseConvertor} from "./IBaseConvertor.sol";

interface IBaseConvertor4626 is IBaseConvertor {
    function vault() external view returns (address);

    function deployLooseWant() external returns (uint256);

    function freeWant(uint256 _wantAmount) external;

    function freeWantFromVault(uint256 _wantAmount) external;

    function balanceOfVault() external view returns (uint256);

    function valueOfVault() external view returns (uint256);

    function vaultsMaxWithdraw() external view returns (uint256);
}
