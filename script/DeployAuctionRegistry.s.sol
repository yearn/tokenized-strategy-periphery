// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import "./BaseScript.s.sol";
import {AuctionRegistry} from "../src/Auctions/AuctionRegistry.sol";

// Deploy the AuctionRegistry contract with known factory addresses
contract DeployAuctionRegistry is BaseScript {

    function run() external {
        vm.startBroadcast();

        // Prepare arrays for known factories
        // These would be the deployed AuctionFactory addresses on various chains
        // You can add actual deployed addresses here
        address[] memory knownFactories = new address[](4);
        string[] memory versions = new string[](4);

        // Example: If you have deployed factories, add them like this:
        // knownFactories[0] = 0x...; // AuctionFactory v1.0.0
        // versions[0] = "1.0.0";
        knownFactories[0] = 0xE6aB098E8582178A76DC80d55ca304d1Dec11AD8;
        versions[0] = "0.0.1";
        knownFactories[1] = 0xa076c247AfA44f8F006CA7f21A4EF59f7e4dc605;
        versions[1] = "1.0.1";
        knownFactories[2] = 0xCfA510188884F199fcC6e750764FAAbE6e56ec40;
        versions[2] = "1.0.2";
        knownFactories[3] = 0xbC587a495420aBB71Bbd40A0e291B64e80117526;
        versions[3] = "1.0.3";

        // Get the bytecode with constructor arguments
        bytes memory bytecode = abi.encodePacked(
            vm.getCode("AuctionRegistry.sol:AuctionRegistry"),
            abi.encode(initGov, knownFactories, versions)
        );

        // Use a consistent salt for deterministic deployment
        bytes32 salt = keccak256("AuctionRegistry.v1");

        address registryAddress = deployer.deployCreate2(salt, bytecode);

        AuctionRegistry registry = AuctionRegistry(registryAddress);

        console.log("AuctionRegistry deployed at:", registryAddress);
        console.log("Latest factory is ", registry.getLatestFactory());
        console.log("Number of factories registered:", uint256(registry.numberOfFactories()));

        vm.stopBroadcast();
    }

}