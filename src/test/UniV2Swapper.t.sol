// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

import "forge-std/console.sol";
import {Setup, ERC20, IStrategy} from "./utils/Setup.sol";

import {MockUniswapV2Swapper, IMockUniswapV2Swapper} from "./mocks/MockUniswapV2Swapper.sol";

contract UniswapV2SwapperTest is Setup {
    IMockUniswapV2Swapper public uniV2Swapper;

    ERC20 public base;

    uint256 public minBaseAmount = 1e8;
    uint256 public maxBaseAmount = 1e20;

    function setUp() public override {
        super.setUp();

        base = ERC20(tokenAddrs["WETH"]);

        uniV2Swapper = IMockUniswapV2Swapper(
            address(new MockUniswapV2Swapper(address(asset)))
        );

        uniV2Swapper.setKeeper(keeper);
        uniV2Swapper.setPerformanceFeeRecipient(performanceFeeRecipient);
        uniV2Swapper.setPendingManagement(management);

        // Accept management.
        vm.prank(management);
        uniV2Swapper.acceptManagement();
    }

    function test_swapFrom_assetToBase(uint256 amount) public {
        vm.assume(amount >= minFuzzAmount && amount <= maxFuzzAmount);

        // Send some asset to the contract
        airdrop(asset, address(uniV2Swapper), amount);

        // Assert asset balance in the contract is equal to the transferred amount
        assertEq(asset.balanceOf(address(uniV2Swapper)), amount);
        // Assert Base balance in the contract is 0
        assertEq(base.balanceOf(address(uniV2Swapper)), 0);

        // Perform swap from asset to Base
        uniV2Swapper.swapFrom(address(asset), address(base), amount, 0);

        // Assert asset balance in the contract is 0
        assertEq(asset.balanceOf(address(uniV2Swapper)), 0);
        // Assert Base balance in the contract is greater than 0
        assertGt(base.balanceOf(address(uniV2Swapper)), 0);
    }

    function test_swapFrom_baseToAsset(uint256 amount) public {
        vm.assume(amount >= minBaseAmount && amount <= maxBaseAmount);

        // Send some Base to the contract
        airdrop(base, address(uniV2Swapper), amount);

        // Assert Base balance in the contract is equal to base_amount
        assertEq(base.balanceOf(address(uniV2Swapper)), amount);
        // Assert asset balance in the contract is 0
        assertEq(asset.balanceOf(address(uniV2Swapper)), 0);

        // Perform swap from Base to asset
        uniV2Swapper.swapFrom(address(base), address(asset), amount, 0);

        // Assert Base balance in the contract is 0
        assertEq(base.balanceOf(address(uniV2Swapper)), 0);
        // Assert asset balance in the contract is greater than 0
        assertGt(asset.balanceOf(address(uniV2Swapper)), 0);
    }

    function test_swapFrom_multiHop(uint256 amount) public {
        // Need to make sure we are getting enough DAI to be non 0 USDC.
        vm.assume(amount >= 1e15 && amount <= maxFuzzAmount);
        ERC20 swapTo = ERC20(tokenAddrs["USDC"]);

        // Send some asset to the contract
        airdrop(asset, address(uniV2Swapper), amount);

        // Assert asset balance in the contract is equal to amount
        assertEq(asset.balanceOf(address(uniV2Swapper)), amount);
        // Assert base balance in the contract is 0
        assertEq(base.balanceOf(address(uniV2Swapper)), 0);
        // Assert swap_to balance in the contract is 0
        assertEq(swapTo.balanceOf(address(uniV2Swapper)), 0);

        // Perform swap from asset to swap_to
        uniV2Swapper.swapFrom(address(asset), address(swapTo), amount, 0);

        // Assert asset balance in the contract is 0
        assertEq(asset.balanceOf(address(uniV2Swapper)), 0);
        // Assert base balance in the contract is 0
        assertEq(base.balanceOf(address(uniV2Swapper)), 0);
        // Assert swap_to balance in the contract is greater than 0
        assertGt(swapTo.balanceOf(address(uniV2Swapper)), 0);
    }

    function test_swapFrom_minOutReverts(uint256 amount) public {
        vm.assume(amount >= minFuzzAmount && amount <= maxFuzzAmount);

        // Send some asset to the contract
        airdrop(asset, address(uniV2Swapper), amount);

        // Assert asset balance in the contract is equal to amount
        assertEq(asset.balanceOf(address(uniV2Swapper)), amount);
        // Assert base balance in the contract is 0
        assertEq(base.balanceOf(address(uniV2Swapper)), 0);

        // Define the minimum amount of Base to receive
        uint256 minOut = amount;

        // Perform swap from asset to Base with minimum output requirement
        vm.expectRevert();
        uniV2Swapper.swapFrom(address(asset), address(base), amount, minOut);

        assertEq(asset.balanceOf(address(uniV2Swapper)), amount);
        // Assert base balance in the contract is 0
        assertEq(base.balanceOf(address(uniV2Swapper)), 0);
    }

    function test_badRouter_reverts(uint256 amount) public {
        vm.assume(amount >= minFuzzAmount && amount <= maxFuzzAmount);

        // Set the router address
        uniV2Swapper.setRouter(management);

        // Assert the router address is set correctly
        assertEq(uniV2Swapper.router(), management);

        // Send some asset to the contract
        airdrop(asset, address(uniV2Swapper), amount);

        // Assert asset balance in the contract is equal to amount
        assertEq(asset.balanceOf(address(uniV2Swapper)), amount);
        // Assert base balance in the contract is 0
        assertEq(base.balanceOf(address(uniV2Swapper)), 0);

        // Attempt to perform swap from asset to Base
        vm.expectRevert();
        uniV2Swapper.swapFrom(address(asset), address(base), amount, 0);

        assertEq(asset.balanceOf(address(uniV2Swapper)), amount);
        // Assert base balance in the contract is 0
        assertEq(base.balanceOf(address(uniV2Swapper)), 0);
    }

    function test_badBase_reverts(uint256 amount) public {
        vm.assume(amount >= minFuzzAmount && amount <= maxFuzzAmount);

        // Set the base address
        uniV2Swapper.setBase(management);

        // Assert the base address is set correctly
        assertEq(uniV2Swapper.base(), management);

        // Send some asset to the contract
        airdrop(asset, address(uniV2Swapper), amount);

        // Assert asset balance in the contract is equal to amount
        assertEq(asset.balanceOf(address(uniV2Swapper)), amount);
        // Assert base balance in the contract is 0
        assertEq(base.balanceOf(address(uniV2Swapper)), 0);

        // Attempt to perform swap from asset to Base
        vm.expectRevert();
        uniV2Swapper.swapFrom(address(asset), address(base), amount, 0);

        assertEq(asset.balanceOf(address(uniV2Swapper)), amount);
        // Assert base balance in the contract is 0
        assertEq(base.balanceOf(address(uniV2Swapper)), 0);
    }
}
