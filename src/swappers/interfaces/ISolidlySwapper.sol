// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import "./IBaseSwapper.sol";

interface ISolidlySwapper is IBaseSwapper {
    function base() external view returns (address);

    function router() external view returns (address);

    function stable(address, address) external view returns (bool);
}
