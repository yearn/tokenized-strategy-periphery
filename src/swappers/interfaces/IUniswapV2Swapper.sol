// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

interface IUniswapV2Swapper {
    function minAmountToSell() external view returns (uint256);

    function base() external view returns (address);

    function router() external view returns (address);
}
