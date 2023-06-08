// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

interface ITradeFactorySwapper {
    function tradeFactory() external view returns (address);

    function rewardTokens() external view returns (address[] memory);

    function claimRewards() external;
}
