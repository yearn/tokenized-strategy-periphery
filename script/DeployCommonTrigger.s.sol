// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import "forge-std/Script.sol";

// Deploy a contract to a deterministic address with create2
contract DeployCommonTrigger is Script {

    Deployer public deployer = Deployer(0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed);

    function run() external {
        vm.startBroadcast();

        // Encode constructor arguments
        bytes memory construct = abi.encode(0x6f3cBE2ab3483EC4BA7B672fbdCa0E9B33F88db8);
        
        // Append constructor args to the bytecode
        bytes memory bytecode = abi.encodePacked(vm.getCode("CommonReportTrigger.sol:CommonReportTrigger"), construct);

        // Use 0 as salt.
        bytes32 salt;

        address contractAddress = deployer.deployCreate2(salt, bytecode);

        console.log("Address is ", contractAddress);

        vm.stopBroadcast();
    }
}

contract Deployer {
    event ContractCreation(address indexed newContract, bytes32 indexed salt);

    function deployCreate2(
        bytes32 salt,
        bytes memory initCode
    ) public payable returns (address newContract) {}
}