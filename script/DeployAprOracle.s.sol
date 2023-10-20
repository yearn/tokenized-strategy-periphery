// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

import "forge-std/Script.sol";

// Deploy a contract to a deterministic address with create2
contract DeployAprOracle is Script {

    Deployer public deployer = Deployer(0x8D85e7c9A4e369E53Acc8d5426aE1568198b0112);

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Get the bytecode
        bytes memory bytecode = abi.encodePacked(vm.getCode("AprOracle.sol:AprOracle"));

        // Pick an unique salt
        uint256 salt = uint256(keccak256("APR Oracle"));

        address contractAddress = deployer.deploy(bytecode, salt);

        console.log("Address is ", contractAddress);

        vm.stopBroadcast();
    }
}

contract Deployer {
    event Deployed(address addr, uint256 salt);

    function deploy(bytes memory code, uint256 salt) external  returns (address) {
        address addr;
        assembly {
            addr := create2(0, add(code, 0x20), mload(code), salt)
            if iszero(extcodesize(addr)) {
                revert(0, 0)
            }
        }
        emit Deployed(addr, salt);
        return addr;
    }
}