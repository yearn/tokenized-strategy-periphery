// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import "forge-std/Script.sol";

// Deploy a contract to a deterministic address with create2
contract DeployAprOracle is Script {

    Deployer public deployer = Deployer(0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed);

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Encode constructor arguments
        bytes memory construct = abi.encode(0x33333333D5eFb92f19a5F94a43456b3cec2797AE);

        // Get the bytecode
        bytes memory bytecode =  abi.encodePacked(vm.getCode("AprOracle.sol:AprOracle"), construct);

        // Pick an unique salt
        bytes32 salt = keccak256("APR Oracle");

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