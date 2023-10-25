// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

interface ISolidlySwapper {
    function minAmountToSell() external view returns (uint256);

    function base() external view returns (address);

    function router() external view returns (address);

    function stable(address, address) external view returns (bool);
}
