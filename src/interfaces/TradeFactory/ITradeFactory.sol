// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

interface ITradeFactory {
    function enable(address, address) external;

    function disable(address, address) external;
}
