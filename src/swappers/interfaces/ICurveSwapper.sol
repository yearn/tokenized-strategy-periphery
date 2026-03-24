// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import "./IBaseSwapper.sol";

interface ICurveSwapper is IBaseSwapper {
    function curveRouter() external view returns (address);
}
