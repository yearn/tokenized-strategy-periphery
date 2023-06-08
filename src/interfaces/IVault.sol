// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

interface IVault {
    struct StrategyParams {
        uint256 activation;
        uint256 lastReport;
        uint256 currentDebt;
        uint256 maxDebt;
    }

    function strategies(
        address _strategy
    ) external view returns (StrategyParams memory);

    function roles(address _address) external view returns (uint256);

    function profitMaxUnlockTime() external view returns (uint256);

    function shutdown() external view returns (bool);
}
