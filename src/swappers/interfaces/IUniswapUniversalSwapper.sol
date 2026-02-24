// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import "./IBaseSwapper.sol";

interface IUniswapUniversalSwapper is IBaseSwapper {
    function weth() external view returns (address);

    function base() external view returns (address);

    function router() external view returns (address);

    function positionManager() external view returns (address);

    function uniFees(address, address) external view returns (uint24);

    function v4Pools(
        address,
        address
    ) external view returns (uint24 fee, int24 tickSpacing, address hooks);
}
