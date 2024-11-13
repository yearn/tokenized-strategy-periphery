// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import "./BaseScript.s.sol";

// Deploy a contract to a deterministic address with create2
contract DeployAuction is BaseScript {

    function run() external {
        vm.startBroadcast();
    
        // Get the bytecode
        bytes memory bytecode = vm.getCode("AuctionFactory.sol:AuctionFactory");

        bytes32 salt;

        address contractAddress = deployer.deployCreate2(salt, bytecode);

        console.log("Address is ", contractAddress);

        vm.stopBroadcast();
    }
}