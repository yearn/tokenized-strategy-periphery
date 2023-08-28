// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

interface IHealthCheck {
    function doHealthCheck() external view returns (bool);

    function profitLimitRatio() external view returns (uint256);

    function lossLimitRatio() external view returns (uint256);

    function setProfitLimitRatio(uint256 _newProfitLimitRatio) external;

    function setLossLimitRatio(uint256 _newLossLimitRatio) external;

    function setDoHealthCheck(bool _doHealthCheck) external;
}
