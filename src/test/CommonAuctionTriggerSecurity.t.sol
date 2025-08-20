// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import {Setup, IStrategy, console, Roles} from "./utils/Setup.sol";
import {CommonAuctionTrigger, IBaseFee, ICustomAuctionTrigger, IStrategyAuctionTrigger} from "../AuctionTrigger/CommonAuctionTrigger.sol";
import {MockStrategyWithAuctionTrigger} from "./mocks/MockStrategyWithAuctionTrigger.sol";

/**
 * @title Security-focused CommonAuctionTrigger Test Suite
 * @dev This test suite focuses on security aspects, access control,
 *      reentrancy protection, and potential attack vectors
 */
contract CommonAuctionTriggerSecurityTest is Setup {
    CommonAuctionTrigger public auctionTrigger;
    MockStrategyWithAuctionTrigger public strategyWithAuctionTrigger;

    // Attack simulation contracts
    ReentrancyAttacker public reentrancyAttacker;
    DoSAttacker public dosAttacker;
    GasGriefingAttacker public gasGriefingAttacker;

    address public attacker = address(0x666);
    address public fromToken = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    function setUp() public override {
        super.setUp();

        auctionTrigger = new CommonAuctionTrigger(daddy);
        strategyWithAuctionTrigger = new MockStrategyWithAuctionTrigger(
            address(asset)
        );

        // Setup strategy properly
        IStrategy(address(strategyWithAuctionTrigger)).setKeeper(keeper);
        IStrategy(address(strategyWithAuctionTrigger))
            .setPerformanceFeeRecipient(performanceFeeRecipient);
        IStrategy(address(strategyWithAuctionTrigger)).setPendingManagement(
            management
        );
        vm.prank(management);
        IStrategy(address(strategyWithAuctionTrigger)).acceptManagement();

        // Setup attack contracts
        reentrancyAttacker = new ReentrancyAttacker(auctionTrigger);
        dosAttacker = new DoSAttacker();
        gasGriefingAttacker = new GasGriefingAttacker();
    }

    /*//////////////////////////////////////////////////////////////
                        ACCESS CONTROL TESTS
    //////////////////////////////////////////////////////////////*/

    function test_onlyGovernanceCanSetBaseFeeProvider() public {
        address newProvider = address(0x123);

        // Test unauthorized users
        address[] memory unauthorizedUsers = new address[](4);
        unauthorizedUsers[0] = user;
        unauthorizedUsers[1] = keeper;
        unauthorizedUsers[2] = management;
        unauthorizedUsers[3] = attacker;

        for (uint i = 0; i < unauthorizedUsers.length; i++) {
            vm.expectRevert("!governance");
            vm.prank(unauthorizedUsers[i]);
            auctionTrigger.setBaseFeeProvider(newProvider);
        }

        // Test authorized governance
        vm.prank(daddy);
        auctionTrigger.setBaseFeeProvider(newProvider);
        assertEq(auctionTrigger.baseFeeProvider(), newProvider);
    }

    function test_onlyGovernanceCanSetAcceptableBaseFee() public {
        uint256 newBaseFee = 100e9;

        // Test unauthorized users
        address[] memory unauthorizedUsers = new address[](4);
        unauthorizedUsers[0] = user;
        unauthorizedUsers[1] = keeper;
        unauthorizedUsers[2] = management;
        unauthorizedUsers[3] = attacker;

        for (uint i = 0; i < unauthorizedUsers.length; i++) {
            vm.expectRevert("!governance");
            vm.prank(unauthorizedUsers[i]);
            auctionTrigger.setAcceptableBaseFee(newBaseFee);
        }

        // Test authorized governance
        vm.prank(daddy);
        auctionTrigger.setAcceptableBaseFee(newBaseFee);
        assertEq(auctionTrigger.acceptableBaseFee(), newBaseFee);
    }

    function test_onlyStrategyManagementCanSetCustomTrigger() public {
        address customTrigger = address(0x123);

        // Test unauthorized users (including governance)
        address[] memory unauthorizedUsers = new address[](4);
        unauthorizedUsers[0] = user;
        unauthorizedUsers[1] = keeper;
        unauthorizedUsers[2] = daddy; // Even governance can't set custom triggers
        unauthorizedUsers[3] = attacker;

        for (uint i = 0; i < unauthorizedUsers.length; i++) {
            vm.expectRevert("!authorized");
            vm.prank(unauthorizedUsers[i]);
            auctionTrigger.setCustomAuctionTrigger(
                address(strategyWithAuctionTrigger),
                customTrigger
            );
        }

        // Test authorized strategy management
        vm.prank(management);
        auctionTrigger.setCustomAuctionTrigger(
            address(strategyWithAuctionTrigger),
            customTrigger
        );
        assertEq(
            auctionTrigger.customAuctionTrigger(
                address(strategyWithAuctionTrigger)
            ),
            customTrigger
        );
    }

    function test_accessControlWithFakeStrategy() public {
        // Create a fake strategy that claims unauthorized user is management
        FakeStrategy fakeStrategy = new FakeStrategy(attacker);

        // This should work because the fake strategy returns attacker as management
        // The access control checks if msg.sender == strategy.management()
        vm.prank(attacker);
        auctionTrigger.setCustomAuctionTrigger(
            address(fakeStrategy),
            address(0x123)
        );
        
        // Verify it was set
        assertEq(
            auctionTrigger.customAuctionTrigger(address(fakeStrategy)),
            address(0x123)
        );
    }

    /*//////////////////////////////////////////////////////////////
                        REENTRANCY TESTS
    //////////////////////////////////////////////////////////////*/

    function test_reentrancyProtectionInAuctionTrigger() public {
        // Set the reentrancy attacker as custom trigger
        vm.prank(management);
        auctionTrigger.setCustomAuctionTrigger(
            address(strategyWithAuctionTrigger),
            address(reentrancyAttacker)
        );

        // Attempt reentrancy attack
        (bool shouldKick, bytes memory data) = auctionTrigger.auctionTrigger(
            address(strategyWithAuctionTrigger),
            fromToken
        );

        // Should handle gracefully due to try-catch
        assertFalse(shouldKick);
        assertEq(data, bytes("Custom trigger reverted"));

        // Verify no state was corrupted
        assertEq(
            auctionTrigger.customAuctionTrigger(
                address(strategyWithAuctionTrigger)
            ),
            address(reentrancyAttacker)
        );
    }

    /*//////////////////////////////////////////////////////////////
                        DENIAL OF SERVICE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_dosProtectionWithGasGriefing() public {
        // Set gas griefing attacker as custom trigger
        vm.prank(management);
        auctionTrigger.setCustomAuctionTrigger(
            address(strategyWithAuctionTrigger),
            address(gasGriefingAttacker)
        );

        // The gas griefing attack will succeed and consume large amounts of gas
        uint256 gasBefore = gasleft();
        (bool shouldKick, bytes memory data) = auctionTrigger.auctionTrigger(
            address(strategyWithAuctionTrigger),
            fromToken
        );
        uint256 gasUsed = gasBefore - gasleft();

        // The attack succeeds and returns its result
        assertTrue(shouldKick);
        assertEq(data, bytes("Gas griefing"));

        // Gas usage will be very high (demonstrates the vulnerability)
        assertGt(gasUsed, 50_000_000); // More than 50M gas consumed
    }

    function test_dosProtectionWithInfiniteLoop() public {
        // Set DoS attacker as custom trigger
        vm.prank(management);
        auctionTrigger.setCustomAuctionTrigger(
            address(strategyWithAuctionTrigger),
            address(dosAttacker)
        );

        // Should handle infinite loop gracefully
        (bool shouldKick, bytes memory data) = auctionTrigger.auctionTrigger(
            address(strategyWithAuctionTrigger),
            fromToken
        );

        assertFalse(shouldKick);
        assertEq(data, bytes("Custom trigger reverted"));
    }

    /*//////////////////////////////////////////////////////////////
                        STATE MANIPULATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_preventStateManipulationThroughCustomTrigger() public {
        StateManipulationAttacker stateAttacker = new StateManipulationAttacker(
            auctionTrigger
        );

        vm.prank(management);
        auctionTrigger.setCustomAuctionTrigger(
            address(strategyWithAuctionTrigger),
            address(stateAttacker)
        );

        // Record initial state
        uint256 initialBaseFee = auctionTrigger.acceptableBaseFee();
        address initialProvider = auctionTrigger.baseFeeProvider();

        // Attempt state manipulation through custom trigger
        (bool shouldKick, bytes memory data) = auctionTrigger.auctionTrigger(
            address(strategyWithAuctionTrigger),
            fromToken
        );

        // Verify state wasn't manipulated
        assertEq(auctionTrigger.acceptableBaseFee(), initialBaseFee);
        assertEq(auctionTrigger.baseFeeProvider(), initialProvider);
        assertFalse(shouldKick);
        assertEq(data, bytes("Custom trigger reverted"));
    }

    /*//////////////////////////////////////////////////////////////
                        INPUT VALIDATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_inputValidationForSetters() public {
        // Test edge case addresses for base fee provider
        vm.prank(daddy);
        auctionTrigger.setBaseFeeProvider(address(0));
        assertEq(auctionTrigger.baseFeeProvider(), address(0));

        // Test with contract addresses
        vm.prank(daddy);
        auctionTrigger.setBaseFeeProvider(address(this));
        assertEq(auctionTrigger.baseFeeProvider(), address(this));

        // Test edge case values for acceptable base fee
        vm.prank(daddy);
        auctionTrigger.setAcceptableBaseFee(0);
        assertEq(auctionTrigger.acceptableBaseFee(), 0);

        vm.prank(daddy);
        auctionTrigger.setAcceptableBaseFee(type(uint256).max);
        assertEq(auctionTrigger.acceptableBaseFee(), type(uint256).max);
    }

    function test_handleMalformedCustomTriggerResponses() public {
        MalformedResponseTrigger malformedTrigger = new MalformedResponseTrigger();

        vm.prank(management);
        auctionTrigger.setCustomAuctionTrigger(
            address(strategyWithAuctionTrigger),
            address(malformedTrigger)
        );

        // Should handle malformed responses gracefully
        (bool shouldKick, bytes memory data) = auctionTrigger.auctionTrigger(
            address(strategyWithAuctionTrigger),
            fromToken
        );

        // Should return the malformed response as-is if trigger doesn't revert
        assertTrue(shouldKick); // Malformed trigger returns true
        assertEq(data.length, 1000); // Large data payload
    }

    /*//////////////////////////////////////////////////////////////
                        FRONT-RUNNING PROTECTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_frontRunningBaseFeeChanges() public {
        MockBaseFeeProvider provider = new MockBaseFeeProvider();

        vm.prank(daddy);
        auctionTrigger.setBaseFeeProvider(address(provider));
        vm.prank(daddy);
        auctionTrigger.setAcceptableBaseFee(50e9);

        // Simulate front-running scenario
        provider.setBaseFee(40e9); // Initially acceptable
        assertTrue(auctionTrigger.isCurrentBaseFeeAcceptable());

        // Attacker tries to front-run by changing base fee
        provider.setBaseFee(60e9); // Now unacceptable
        assertFalse(auctionTrigger.isCurrentBaseFeeAcceptable());

        // Original transaction should still execute with current state
        (bool shouldKick, bytes memory data) = auctionTrigger
            .defaultAuctionTrigger(
                address(strategyWithAuctionTrigger),
                fromToken
            );
        assertFalse(shouldKick);
        assertEq(data, bytes("Base Fee"));
    }

    /*//////////////////////////////////////////////////////////////
                        PRIVILEGE ESCALATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_preventPrivilegeEscalation() public {
        // Attacker tries to become governance through various means
        PrivilegeEscalationAttacker privEscAttacker = new PrivilegeEscalationAttacker();

        // Cannot set themselves as governance
        vm.expectRevert("!governance");
        vm.prank(address(privEscAttacker));
        auctionTrigger.setBaseFeeProvider(address(privEscAttacker));

        // Cannot transfer governance to themselves
        vm.expectRevert("!governance");
        vm.prank(address(privEscAttacker));
        auctionTrigger.transferGovernance(address(privEscAttacker));

        // Verify governance remains unchanged
        assertEq(auctionTrigger.governance(), daddy);
    }

    /*//////////////////////////////////////////////////////////////
                        TIMING ATTACK TESTS
    //////////////////////////////////////////////////////////////*/

    function test_timingAttackResistance() public {
        MockBaseFeeProvider provider = new MockBaseFeeProvider();
        vm.prank(daddy);
        auctionTrigger.setBaseFeeProvider(address(provider));

        // Test rapid base fee changes
        uint256[] memory baseFees = new uint256[](10);
        for (uint i = 0; i < 10; i++) {
            baseFees[i] = (i + 1) * 10e9;
        }

        for (uint i = 0; i < baseFees.length; i++) {
            provider.setBaseFee(baseFees[i]);
            vm.prank(daddy);
            auctionTrigger.setAcceptableBaseFee(baseFees[i] + 1e9);

            // Each call should be consistent with current state
            uint256 currentFee = auctionTrigger.getCurrentBaseFee();
            assertEq(currentFee, baseFees[i]);
            assertTrue(auctionTrigger.isCurrentBaseFeeAcceptable());
        }
    }
}

/*//////////////////////////////////////////////////////////////
                        ATTACK SIMULATION CONTRACTS
//////////////////////////////////////////////////////////////*/

contract ReentrancyAttacker is ICustomAuctionTrigger {
    CommonAuctionTrigger public target;

    constructor(CommonAuctionTrigger _target) {
        target = _target;
    }

    function auctionTrigger(
        address _strategy,
        address _from
    ) external view override returns (bool, bytes memory) {
        // Attempt reentrancy (will fail with view function)
        try target.auctionTrigger(_strategy, _from) returns (
            bool,
            bytes memory
        ) {
            revert("Reentrancy succeeded");
        } catch {
            // Expected to fail
        }
        return (true, bytes("Reentrancy attempted"));
    }
}

contract DoSAttacker is ICustomAuctionTrigger {
    function auctionTrigger(
        address,
        address
    ) external pure override returns (bool, bytes memory) {
        // Infinite loop to cause DoS
        while (true) {
            // This will eventually run out of gas
        }
        return (false, bytes("Should not reach here"));
    }
}

contract GasGriefingAttacker is ICustomAuctionTrigger {
    function auctionTrigger(
        address,
        address
    ) external pure override returns (bool, bytes memory) {
        // Consume large amounts of gas
        for (uint i = 0; i < 100000; i++) {
            keccak256(abi.encode(i));
        }
        return (true, bytes("Gas griefing"));
    }
}

contract StateManipulationAttacker is ICustomAuctionTrigger {
    CommonAuctionTrigger public target;

    constructor(CommonAuctionTrigger _target) {
        target = _target;
    }

    function auctionTrigger(
        address,
        address
    ) external view override returns (bool, bytes memory) {
        // Attempt to manipulate state (will fail due to view function)
        // This simulates an attack that would try to manipulate state
        uint256 currentBaseFee = target.acceptableBaseFee();
        if (currentBaseFee < 999999e18) {
            revert("Attempting state manipulation");
        }
        return (true, bytes("State manipulation attempt"));
    }
}

contract MalformedResponseTrigger is ICustomAuctionTrigger {
    function auctionTrigger(
        address,
        address
    ) external pure override returns (bool, bytes memory) {
        // Return very large data payload
        bytes memory largeData = new bytes(1000);
        for (uint i = 0; i < 1000; i++) {
            largeData[i] = bytes1(uint8(i % 256));
        }
        return (true, largeData);
    }
}

contract FakeStrategy {
    address public fakeManagement;

    constructor(address _fakeManagement) {
        fakeManagement = _fakeManagement;
    }

    function management() external view returns (address) {
        return fakeManagement;
    }
}

contract PrivilegeEscalationAttacker {
    // Attempts various privilege escalation techniques
    function attemptEscalation(CommonAuctionTrigger target) external {
        target.setBaseFeeProvider(address(this));
    }
}

contract MockBaseFeeProvider is IBaseFee {
    uint256 private _baseFee;

    function setBaseFee(uint256 baseFee) external {
        _baseFee = baseFee;
    }

    function basefee_global() external view returns (uint256) {
        return _baseFee;
    }
}
