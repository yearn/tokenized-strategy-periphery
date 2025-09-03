// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import "forge-std/Test.sol";
import {ClonableCreate2} from "../utils/ClonableCreate2.sol";

// Mock implementation contract for testing
contract MockImplementation {
    uint256 public value;
    address public initializer;

    function initialize(uint256 _value) external {
        require(initializer == address(0), "Already initialized");
        value = _value;
        initializer = msg.sender;
    }
}

// Test factory using ClonableCreate2
contract TestFactory is ClonableCreate2 {
    event CloneDeployed(address indexed clone, bytes32 salt);

    constructor(address _original) {
        original = _original;
    }

    function deployClone(bytes32 salt) external returns (address) {
        address clone = _cloneCreate2(salt);
        emit CloneDeployed(clone, salt);
        return clone;
    }

    function deployClone(
        address _original,
        bytes32 salt
    ) external returns (address) {
        address clone = _cloneCreate2(_original, salt);
        emit CloneDeployed(clone, salt);
        return clone;
    }

    function predictAddress(bytes32 salt) external view returns (address) {
        return computeCreate2Address(original, salt, msg.sender);
    }

    function predictAddress(
        address _original,
        bytes32 salt
    ) external view returns (address) {
        return computeCreate2Address(_original, salt, msg.sender);
    }
}

contract ClonableCreate2Test is Test {
    MockImplementation public implementation;
    TestFactory public factory;

    address public user1 = address(0x1);
    address public user2 = address(0x2);

    event CloneDeployed(address indexed clone, bytes32 salt);

    function setUp() public {
        implementation = new MockImplementation();
        factory = new TestFactory(address(implementation));
    }

    function testBasicCreate2Clone() public {
        bytes32 salt = bytes32(uint256(1));

        // Predict the address
        address predicted = factory.predictAddress(salt);

        // Deploy the clone
        address clone = factory.deployClone(salt);

        // Verify the address matches prediction
        assertEq(clone, predicted, "Clone address should match prediction");

        // Verify the clone is functional
        MockImplementation(clone).initialize(100);
        assertEq(MockImplementation(clone).value(), 100);
        assertEq(MockImplementation(clone).initializer(), address(this));
    }

    function testSameSaltDifferentCallers() public {
        bytes32 salt = bytes32(uint256(42));

        // Deploy from factory directly
        address clone1 = factory.deployClone(salt);

        // Deploy from user1
        vm.prank(user1);
        address clone2 = factory.deployClone(salt);

        // Deploy from user2
        vm.prank(user2);
        address clone3 = factory.deployClone(salt);

        // All clones should have different addresses due to msg.sender protection
        assertTrue(
            clone1 != clone2,
            "Clone1 and Clone2 should have different addresses"
        );
        assertTrue(
            clone2 != clone3,
            "Clone2 and Clone3 should have different addresses"
        );
        assertTrue(
            clone1 != clone3,
            "Clone1 and Clone3 should have different addresses"
        );

        // All clones should be functional
        MockImplementation(clone1).initialize(1);
        MockImplementation(clone2).initialize(2);
        MockImplementation(clone3).initialize(3);

        assertEq(MockImplementation(clone1).value(), 1);
        assertEq(MockImplementation(clone2).value(), 2);
        assertEq(MockImplementation(clone3).value(), 3);
    }

    function testPredictedAddressMatchesDeployed() public {
        bytes32 salt = bytes32(uint256(999));

        // Predict from user1
        vm.prank(user1);
        address predicted = factory.predictAddress(salt);

        // Deploy from user1
        vm.prank(user1);
        address deployed = factory.deployClone(salt);

        assertEq(
            predicted,
            deployed,
            "Predicted and deployed addresses should match"
        );
    }

    function testCannotDeploySameSaltTwice() public {
        bytes32 salt = bytes32(uint256(123));

        // First deployment should succeed
        factory.deployClone(salt);

        // Second deployment with same salt from same caller should fail
        vm.expectRevert("ClonableCreate2: create2 failed");
        factory.deployClone(salt);
    }

    function testCloneWithDifferentImplementation() public {
        // Deploy a second implementation
        MockImplementation implementation2 = new MockImplementation();

        bytes32 salt = bytes32(uint256(777));

        // Deploy clone of implementation2
        address clone = factory.deployClone(address(implementation2), salt);

        // Verify it works
        MockImplementation(clone).initialize(777);
        assertEq(MockImplementation(clone).value(), 777);
    }

    function testPredictWithDifferentImplementation() public {
        MockImplementation implementation2 = new MockImplementation();
        bytes32 salt = bytes32(uint256(888));

        // Predict address
        address predicted = factory.predictAddress(
            address(implementation2),
            salt
        );

        // Deploy
        address deployed = factory.deployClone(address(implementation2), salt);

        assertEq(
            predicted,
            deployed,
            "Predicted and deployed should match for custom implementation"
        );
    }

    function testFuzzSaltAndValue(bytes32 salt, uint256 value) public {
        // Limit value to reasonable range
        value = value % 1e18;

        // Deploy clone
        address clone = factory.deployClone(salt);

        // Initialize with value
        MockImplementation(clone).initialize(value);

        assertEq(MockImplementation(clone).value(), value);
    }

    function testEventEmission() public {
        bytes32 salt = bytes32(uint256(555));

        // Expect the event
        vm.expectEmit(true, false, false, true);
        emit CloneDeployed(factory.predictAddress(salt), salt);

        factory.deployClone(salt);
    }
}
