// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

import {IStrategy} from "@tokenized-strategy/interfaces/IStrategy.sol";

interface IBaseHealthCheck is IStrategy {
    function doHealthCheck() external view returns (bool);

    function profitLimitRatio() external view returns (uint256);

    function lossLimitRatio() external view returns (uint256);

    function setProfitLimitRatio(uint256 _newProfitLimitRatio) external;

    function setLossLimitRatio(uint256 _newLossLimitRatio) external;

    function setDoHealthCheck(bool _doHealthCheck) external;
}
