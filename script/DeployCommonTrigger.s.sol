// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import "./BaseScript.s.sol";

// Deploy a contract to a deterministic address with create2
contract DeployCommonTrigger is BaseScript {

    function run() external {
        vm.startBroadcast();

        // Encode constructor arguments
        bytes memory construct = abi.encode(initGov);
        
        // Append constructor args to the bytecode
        bytes memory bytecode = abi.encodePacked(vm.getCode("src/ReportTrigger/CommonTrigger.sol:CommonTrigger"), construct);

        // Use 0 as salt.
        bytes32 salt;

        address contractAddress = deployer.deployCreate2(salt, bytecode);

        console.log("Address is ", contractAddress);

        vm.stopBroadcast();
    }
}