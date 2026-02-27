// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import "./IBaseSwapper.sol";

interface IFluidSwapper is IBaseSwapper {
    function base() external view returns (address);

    function fluidDexes(
        address,
        address
    ) external view returns (address dex, bool swap0to1);
}
