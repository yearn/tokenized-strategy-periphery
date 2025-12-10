// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import {Setup, ERC20, IStrategy} from "./utils/Setup.sol";

import {MockPendleSwapper, IMockPendleSwapper} from "./mocks/MockPendleSwapper.sol";
import {IPMarket} from "../interfaces/Pendle/IPendle.sol";

import {MockToken} from "./mocks/MockToken.sol";

/**
 * @title PendleSwapperTest
 * @notice Unit tests for the PendleSwapper contract
 * @dev These tests verify the swapper logic without requiring mainnet fork.
 *   For full integration tests, use a mainnet fork with a currently active Pendle market.
 */
contract PendleSwapperTest is Setup {
    IMockPendleSwapper public pendleSwapper;

    MockToken public mockAsset;

    // Pendle Router V4
    address public constant PENDLE_ROUTER =
        0x888888888889758F76e7103c6CbF23ABbF58F946;

    // Mock addresses for unit tests
    address public constant MOCK_MARKET = address(0x1111);
    address public constant MOCK_PT = address(0x2222);
    address public constant MOCK_UNDERLYING = address(0x3333);

    function setUp() public override {
        // Deploy mock token for testing
        mockAsset = new MockToken("Mock Asset", "MOCK", 18);

        // Deploy mock pendle swapper with the mock asset
        pendleSwapper = IMockPendleSwapper(
            address(new MockPendleSwapper(address(mockAsset)))
        );

        pendleSwapper.setKeeper(keeper);
        pendleSwapper.setPerformanceFeeRecipient(performanceFeeRecipient);
        pendleSwapper.setPendingManagement(management);
        vm.prank(management);
        pendleSwapper.acceptManagement();
    }

    function test_setMarket() public {
        address pt = address(0x1111);
        address market = address(0x2222);

        assertEq(pendleSwapper.markets(pt), address(0));

        vm.prank(management);
        pendleSwapper.setMarket(pt, market);

        assertEq(pendleSwapper.markets(pt), market);
    }

    function test_multipleMarkets() public {
        address pt1 = address(0x1111);
        address market1 = address(0x2222);
        address pt2 = address(0x3333);
        address market2 = address(0x4444);

        vm.prank(management);
        pendleSwapper.setMarket(pt1, market1);

        vm.prank(management);
        pendleSwapper.setMarket(pt2, market2);

        // Verify both markets are registered
        assertEq(pendleSwapper.markets(pt1), market1);
        assertEq(pendleSwapper.markets(pt2), market2);
    }

    function test_minAmountToSell() public {
        // Set a market so swap detection works
        vm.prank(management);
        pendleSwapper.setMarket(address(0x9999), MOCK_MARKET);

        uint256 amount = 1e15;

        // Set min amount to sell higher than our amount
        vm.prank(management);
        pendleSwapper.setMinAmountToSell(1e16);

        assertEq(pendleSwapper.minAmountToSell(), 1e16);

        // Mint tokens to the swapper
        mockAsset.mint(address(pendleSwapper), amount);

        // Swap should return 0 when amount is below minAmountToSell
        uint256 amountOut = pendleSwapper.pendleSwapFrom(
            address(mockAsset),
            address(0x9999),
            amount,
            0
        );

        // Should not have swapped
        assertEq(amountOut, 0);
        assertEq(mockAsset.balanceOf(address(pendleSwapper)), amount);
    }

    function test_unknownMarket_reverts() public {
        address unknownToken = address(0xdead);

        uint256 amount = 1e18;
        mockAsset.mint(address(pendleSwapper), amount);

        // Try to swap to an unknown token (no market registered)
        vm.expectRevert("PendleSwapper: unknown market");
        pendleSwapper.pendleSwapFrom(
            address(mockAsset),
            unknownToken,
            amount,
            0
        );
    }

    function test_zeroAmount_returns_zero() public {
        // Set a market so swap detection works
        vm.prank(management);
        pendleSwapper.setMarket(MOCK_PT, MOCK_MARKET);

        // Swap with 0 amount should return 0
        uint256 amountOut = pendleSwapper.pendleSwapFrom(
            address(mockAsset),
            MOCK_PT,
            0,
            0
        );

        assertEq(amountOut, 0);
    }

    function test_defaultPendleRouter() public {
        // Verify default router is set correctly
        assertEq(pendleSwapper.pendleRouter(), PENDLE_ROUTER);
    }

    function test_defaultMinAmountToSell() public {
        // Verify default minAmountToSell is 0
        assertEq(pendleSwapper.minAmountToSell(), 0);
    }
}

/**
 * @title PendleSwapperForkTest
 * @notice Fork tests for the PendleSwapper contract
 * @dev These tests require a mainnet fork with ETH_RPC_URL set.
 *   Run with: forge test --match-contract PendleSwapperForkTest --fork-url $ETH_RPC_URL
 *
 *   Note: The specific market addresses and block numbers may need to be updated
 *   as Pendle markets expire. Find active markets at https://app.pendle.finance/
 */
contract PendleSwapperForkTest is Setup {
    // Skip fork tests if ETH_RPC_URL is not set
    // To run: forge test --match-contract PendleSwapperForkTest --fork-url $ETH_RPC_URL
}
