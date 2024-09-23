// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import "./BaseScript.sol";

// Deploy a contract to a deterministic address with create2
contract DeployAuctionFactory is BaseScript {

    function run() external {
        vm.startBroadcast();

        // Get the bytecode
        bytes memory bytecode =  abi.encodePacked(vm.getCode("AuctionFactory.sol:AuctionFactory"));

        // Pick an unique salt
        bytes32 salt = keccak256("Auction Factory");

        address contractAddress = deployer.deployCreate3(salt, bytecode);

        console.log("Address is ", contractAddress);

        vm.stopBroadcast();
    }
}