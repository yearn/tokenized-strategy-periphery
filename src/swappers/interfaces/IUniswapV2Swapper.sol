// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import "./IBaseSwapper.sol";

interface IUniswapV2Swapper is IBaseSwapper {
    function base() external view returns (address);

    function router() external view returns (address);
}
