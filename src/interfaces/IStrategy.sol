// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

interface IStrategy {
    function asset() external view returns (address);

    function management() external view returns (address);

    function totalAssets() external view returns (uint256);

    function lastReport() external view returns (uint256);

    function profitMaxUnlockTime() external view returns (uint256);

    function isShutdown() external view returns (bool);
}
