// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import "./IBaseSwapper.sol";

interface IPendleSwapper is IBaseSwapper {
    function pendleRouter() external view returns (address);

    function markets(address pt) external view returns (address market);

    function guessMaxMultiplier() external view returns (uint256);
}
