// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

import "forge-std/console.sol";
import {Setup, ERC20, IStrategy} from "./utils/Setup.sol";

import {MockSolidlySwapper, IMockSolidlySwapper} from "./mocks/MockSolidlySwapper.sol";

// NOTE: These tests wont run on mainnet and will need to be run on polygon fork
contract SolidlySwapperTest is Setup {
    IMockSolidlySwapper public solidlySwapper;

    ERC20 public base;

    uint256 public minBaseAmount = 1e9;
    uint256 public maxBaseAmount = 100_000e9;

    address public whale = 0x00e8c0E92eB3Ad88189E7125Ec8825eDc03Ab265;

    function setUp() public override {
        if (block.chainid != 137) return;

        base = ERC20(0x40379a439D4F6795B6fc9aa5687dB461677A2dBa);
        asset = ERC20(0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619);

        decimals = asset.decimals();

        minFuzzAmount = 1e14;
        maxFuzzAmount = 2e21;

        solidlySwapper = IMockSolidlySwapper(
            address(new MockSolidlySwapper(address(asset)))
        );

        solidlySwapper.setKeeper(keeper);
        solidlySwapper.setPerformanceFeeRecipient(performanceFeeRecipient);
        solidlySwapper.setPendingManagement(management);

        solidlySwapper.setBase(0x40379a439D4F6795B6fc9aa5687dB461677A2dBa);
        solidlySwapper.setRouter(0x06374F57991CDc836E5A318569A910FE6456D230);
        // Accept management.
        vm.prank(management);
        solidlySwapper.acceptManagement();
    }

    function test_swapFrom_assetToBase(uint256 amount) public {
        if (block.chainid != 137) return;
        vm.assume(amount >= minFuzzAmount && amount <= maxFuzzAmount);

        // Send some asset to the contract
        airdrop(asset, address(solidlySwapper), amount);

        // Assert asset balance in the contract is equal to the transferred amount
        assertEq(asset.balanceOf(address(solidlySwapper)), amount);
        // Assert Base balance in the contract is 0
        assertEq(base.balanceOf(address(solidlySwapper)), 0);

        // Perform swap from asset to Base
        solidlySwapper.swapFrom(address(asset), address(base), amount, 0);

        // Assert asset balance in the contract is 0
        assertEq(asset.balanceOf(address(solidlySwapper)), 0);
        // Assert Base balance in the contract is greater than 0
        assertGt(base.balanceOf(address(solidlySwapper)), 0);
    }

    function test_swapFrom_baseToAsset(uint256 amount) public {
        if (block.chainid != 137) return;
        vm.assume(amount >= minBaseAmount && amount <= maxBaseAmount);

        // Send some Base to the contract
        //airdrop(base, address(solidlySwapper), amount);
        vm.prank(whale);
        base.transfer(address(solidlySwapper), amount);

        // Assert Base balance in the contract is equal to base_amount
        assertEq(base.balanceOf(address(solidlySwapper)), amount);
        // Assert asset balance in the contract is 0
        assertEq(asset.balanceOf(address(solidlySwapper)), 0);

        // Perform swap from Base to asset
        solidlySwapper.swapFrom(address(base), address(asset), amount, 0);

        // Assert Base balance in the contract is 0
        assertEq(base.balanceOf(address(solidlySwapper)), 0);
        // Assert asset balance in the contract is greater than 0
        assertGt(asset.balanceOf(address(solidlySwapper)), 0);
    }

    function test_swapFrom_multiHop(uint256 amount) public {
        if (block.chainid != 137) return;
        // Need to make sure we are getting enough DAI to be non 0 USDC.
        vm.assume(amount >= 1e15 && amount <= maxFuzzAmount);
        ERC20 swapTo = ERC20(0x1BFD67037B42Cf73acF2047067bd4F2C47D9BfD6);

        // Send some asset to the contract
        airdrop(asset, address(solidlySwapper), amount);

        // Assert asset balance in the contract is equal to amount
        assertEq(asset.balanceOf(address(solidlySwapper)), amount);
        // Assert base balance in the contract is 0
        assertEq(base.balanceOf(address(solidlySwapper)), 0);
        // Assert swap_to balance in the contract is 0
        assertEq(swapTo.balanceOf(address(solidlySwapper)), 0);

        // Perform swap from asset to swap_to
        solidlySwapper.swapFrom(address(asset), address(swapTo), amount, 0);

        // Assert asset balance in the contract is 0
        assertEq(asset.balanceOf(address(solidlySwapper)), 0);
        // Assert base balance in the contract is 0
        assertEq(base.balanceOf(address(solidlySwapper)), 0);
        // Assert swap_to balance in the contract is greater than 0
        assertGt(swapTo.balanceOf(address(solidlySwapper)), 0);
    }

    function test_swapFrom_minOutReverts(uint256 amount) public {
        if (block.chainid != 137) return;
        vm.assume(amount >= minFuzzAmount && amount <= maxFuzzAmount);

        // Send some asset to the contract
        airdrop(asset, address(solidlySwapper), amount);

        // Assert asset balance in the contract is equal to amount
        assertEq(asset.balanceOf(address(solidlySwapper)), amount);
        // Assert base balance in the contract is 0
        assertEq(base.balanceOf(address(solidlySwapper)), 0);

        // Define the minimum amount of Base to receive
        uint256 minOut = amount;

        // Perform swap from asset to Base with minimum output requirement
        vm.expectRevert();
        solidlySwapper.swapFrom(address(asset), address(base), amount, minOut);

        assertEq(asset.balanceOf(address(solidlySwapper)), amount);
        // Assert base balance in the contract is 0
        assertEq(base.balanceOf(address(solidlySwapper)), 0);
    }

    function test_badRouter_reverts(uint256 amount) public {
        if (block.chainid != 137) return;
        vm.assume(amount >= minFuzzAmount && amount <= maxFuzzAmount);

        // Set the router address
        solidlySwapper.setRouter(management);

        // Assert the router address is set correctly
        assertEq(solidlySwapper.router(), management);

        // Send some asset to the contract
        airdrop(asset, address(solidlySwapper), amount);

        // Assert asset balance in the contract is equal to amount
        assertEq(asset.balanceOf(address(solidlySwapper)), amount);
        // Assert base balance in the contract is 0
        assertEq(base.balanceOf(address(solidlySwapper)), 0);

        // Attempt to perform swap from asset to Base
        vm.expectRevert();
        solidlySwapper.swapFrom(address(asset), address(base), amount, 0);

        assertEq(asset.balanceOf(address(solidlySwapper)), amount);
        // Assert base balance in the contract is 0
        assertEq(base.balanceOf(address(solidlySwapper)), 0);
    }

    function test_badBase_reverts(uint256 amount) public {
        if (block.chainid != 137) return;
        vm.assume(amount >= minFuzzAmount && amount <= maxFuzzAmount);

        // Set the base address
        solidlySwapper.setBase(management);

        // Assert the base address is set correctly
        assertEq(solidlySwapper.base(), management);

        // Send some asset to the contract
        airdrop(asset, address(solidlySwapper), amount);

        // Assert asset balance in the contract is equal to amount
        assertEq(asset.balanceOf(address(solidlySwapper)), amount);
        // Assert base balance in the contract is 0
        assertEq(base.balanceOf(address(solidlySwapper)), 0);

        // Attempt to perform swap from asset to Base
        vm.expectRevert();
        solidlySwapper.swapFrom(address(asset), address(base), amount, 0);

        assertEq(asset.balanceOf(address(solidlySwapper)), amount);
        // Assert base balance in the contract is 0
        assertEq(base.balanceOf(address(solidlySwapper)), 0);
    }

    function test_setStable(address _token0, address _token1) public {
        if (block.chainid != 137) return;
        vm.assume(_token0 != _token1);

        // Should start off as false.
        assertTrue(!solidlySwapper.stable(_token0, _token1));
        assertTrue(!solidlySwapper.stable(_token1, _token0));

        vm.prank(management);
        solidlySwapper.setStable(_token0, _token1, true);

        // Should now be true.
        assertTrue(solidlySwapper.stable(_token0, _token1));
        assertTrue(solidlySwapper.stable(_token1, _token0));

        vm.prank(management);
        solidlySwapper.setStable(_token0, _token1, false);

        // Should now be back to false
        assertTrue(!solidlySwapper.stable(_token0, _token1));
        assertTrue(!solidlySwapper.stable(_token1, _token0));
    }
}
