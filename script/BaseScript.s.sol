// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import "forge-std/Script.sol";

interface Deployer {
    event ContractCreation(address indexed newContract, bytes32 indexed salt);

    function deployCreate3(
        bytes32 salt,
        bytes memory initCode
    ) external payable returns (address newContract);

    function deployCreate2(
        bytes32 salt,
        bytes memory initCode
    ) external payable returns (address newContract);
}

// Deploy a contract to a deterministic address with create2
abstract contract BaseScript is Script {

    Deployer public deployer = Deployer(0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed);

    address public initGov = 0x6f3cBE2ab3483EC4BA7B672fbdCa0E9B33F88db8;
}
