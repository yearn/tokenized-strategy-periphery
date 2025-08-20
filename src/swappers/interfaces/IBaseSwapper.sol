// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

interface IBaseSwapper {
    function minAmountToSell() external view returns (uint256);
}
