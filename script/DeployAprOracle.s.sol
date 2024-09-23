// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import "./BaseScript.s.sol";

// Deploy a contract to a deterministic address with create2
contract DeployAprOracle is BaseScript {

    function run() external {
        vm.startBroadcast();

        // Encode constructor arguments
        bytes memory construct = abi.encode(v3Safe);

        // Get the bytecode
        bytes memory bytecode =  abi.encodePacked(vm.getCode("AprOracle.sol:AprOracle"), construct);

        // Pick an unique salt
        bytes32 salt = keccak256("APR Oracle");

        address contractAddress = deployer.deployCreate2(salt, bytecode);

        console.log("Address is ", contractAddress);

        vm.stopBroadcast();
    }
}