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
contract BaseScript is Script {

    Deployer public deployer = Deployer(0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed);

    address public v3Safe = 0x33333333D5eFb92f19a5F94a43456b3cec2797AE;

    address public initGov;
}
