// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import "./BaseScript.s.sol";

// Deploy a contract to a deterministic address with create2
contract DeployInitGov is BaseScript {

    function run() external {
        vm.startBroadcast();

        // Get the bytecode
        bytes memory bytecode =  abi.encodePacked(vm.getCode("InitGov.sol:InitGov"));

        // Pick an unique salt
        bytes32 salt = keccak256("Init Gov");

        address contractAddress = deployer.deployCreate2(salt, bytecode);

        console.log("Address is ", contractAddress);

        vm.stopBroadcast();
    }
}
