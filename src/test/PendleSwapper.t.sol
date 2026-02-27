// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import {Setup, ERC20, IStrategy} from "./utils/Setup.sol";

import {MockPendleSwapper, IMockPendleSwapper} from "./mocks/MockPendleSwapper.sol";
import {IPMarket, IPPrincipalToken} from "../interfaces/Pendle/IPendle.sol";

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

    function test_defaultGuessMaxMultiplier() public {
        // Verify default guessMaxMultiplier is 0 (uses type(uint256).max)
        assertEq(pendleSwapper.guessMaxMultiplier(), 0);
    }

    function test_setGuessMaxMultiplier() public {
        // Set multiplier
        vm.prank(management);
        pendleSwapper.setGuessMaxMultiplier(1e14);

        assertEq(pendleSwapper.guessMaxMultiplier(), 1e14);
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
    IMockPendleSwapper public pendleSwapper;

    // USDC token on mainnet
    ERC20 public usdc;
    address public constant USDC_ADDRESS =
        0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    // Pendle market for USDC PT
    address public constant PENDLE_MARKET =
        0xaC24A6f0068d9701EAEa76AB0B418021017F8D59;

    // Pendle Router V4
    address public constant PENDLE_ROUTER =
        0x888888888889758F76e7103c6CbF23ABbF58F946;

    // PT token address - will be fetched from market
    address public pt;

    // Fuzz amounts for USDC (6 decimals)
    uint256 public minUsdcAmount = 100e6; // 100 USDC
    uint256 public maxUsdcAmount = 100_000e6; // 100,000 USDC

    function setUp() public override {
        usdc = ERC20(USDC_ADDRESS);

        // Get PT address from market
        (, IPPrincipalToken _PT, ) = IPMarket(PENDLE_MARKET).readTokens();
        pt = address(_PT);

        // Deploy mock pendle swapper with USDC as asset
        pendleSwapper = IMockPendleSwapper(
            address(new MockPendleSwapper(USDC_ADDRESS))
        );

        pendleSwapper.setKeeper(keeper);
        pendleSwapper.setPerformanceFeeRecipient(performanceFeeRecipient);
        pendleSwapper.setPendingManagement(management);
        vm.prank(management);
        pendleSwapper.acceptManagement();

        // Register the PT market
        vm.prank(management);
        pendleSwapper.setMarket(pt, PENDLE_MARKET);

        // Label addresses for better trace output
        vm.label(USDC_ADDRESS, "USDC");
        vm.label(PENDLE_MARKET, "PendleMarket");
        vm.label(PENDLE_ROUTER, "PendleRouter");
        vm.label(pt, "PT");
    }

    function test_fork_buyPt(uint256 amount) public {
        vm.assume(amount >= minUsdcAmount && amount <= maxUsdcAmount);

        // Airdrop USDC to the swapper
        airdrop(usdc, address(pendleSwapper), amount);

        // Record balances before swap
        uint256 usdcBefore = usdc.balanceOf(address(pendleSwapper));
        uint256 ptBefore = ERC20(pt).balanceOf(address(pendleSwapper));

        assertEq(
            usdcBefore,
            amount,
            "USDC balance should equal airdropped amount"
        );
        assertEq(ptBefore, 0, "PT balance should be 0 before swap");

        // Swap USDC to PT (buying PT)
        uint256 amountOut = pendleSwapper.pendleSwapFrom(
            USDC_ADDRESS,
            pt,
            amount,
            0 // No minimum for test
        );

        // Verify swap results
        uint256 usdcAfter = usdc.balanceOf(address(pendleSwapper));
        uint256 ptAfter = ERC20(pt).balanceOf(address(pendleSwapper));

        assertEq(usdcAfter, 0, "USDC should be fully spent");
        assertGt(ptAfter, 0, "Should have received PT");
        assertEq(ptAfter, amountOut, "PT balance should match return value");
    }

    function test_fork_sellPt(uint256 amount) public {
        vm.assume(amount >= minUsdcAmount && amount <= maxUsdcAmount);

        // Skip if market is expired (can't sell via AMM after expiry)
        if (IPMarket(PENDLE_MARKET).isExpired()) {
            return;
        }

        // First buy some PT
        airdrop(usdc, address(pendleSwapper), amount);
        uint256 ptAmount = pendleSwapper.pendleSwapFrom(
            USDC_ADDRESS,
            pt,
            amount,
            0
        );

        // Record balances before selling
        uint256 usdcBefore = usdc.balanceOf(address(pendleSwapper));
        uint256 ptBefore = ERC20(pt).balanceOf(address(pendleSwapper));

        assertEq(usdcBefore, 0, "USDC balance should be 0 before sell");
        assertEq(ptBefore, ptAmount, "PT balance should equal bought amount");

        // Sell PT back to USDC
        uint256 amountOut = pendleSwapper.pendleSwapFrom(
            pt,
            USDC_ADDRESS,
            ptAmount,
            0 // No minimum for test
        );

        // Verify sell results
        uint256 usdcAfter = usdc.balanceOf(address(pendleSwapper));
        uint256 ptAfter = ERC20(pt).balanceOf(address(pendleSwapper));

        assertEq(ptAfter, 0, "PT should be fully sold");
        assertGt(usdcAfter, 0, "Should have received USDC");
        assertEq(
            usdcAfter,
            amountOut,
            "USDC balance should match return value"
        );
    }

    function test_fork_buyPt_withMinAmountOut() public {
        uint256 amount = 10_000e6; // 10,000 USDC

        // Airdrop USDC to the swapper
        airdrop(usdc, address(pendleSwapper), amount);

        // Set an unreasonably high minAmountOut that should cause revert
        uint256 unreasonableMin = amount * 1e18; // Way more PT than possible

        vm.expectRevert();
        pendleSwapper.pendleSwapFrom(USDC_ADDRESS, pt, amount, unreasonableMin);

        // Verify no swap occurred
        assertEq(
            usdc.balanceOf(address(pendleSwapper)),
            amount,
            "USDC should not be spent"
        );
        assertEq(
            ERC20(pt).balanceOf(address(pendleSwapper)),
            0,
            "Should not have PT"
        );
    }

    function test_fork_sellPt_withMinAmountOut() public {
        // Skip if market is expired
        if (IPMarket(PENDLE_MARKET).isExpired()) {
            return;
        }

        uint256 amount = 10_000e6; // 10,000 USDC

        // First buy some PT
        airdrop(usdc, address(pendleSwapper), amount);
        uint256 ptAmount = pendleSwapper.pendleSwapFrom(
            USDC_ADDRESS,
            pt,
            amount,
            0
        );

        // Set an unreasonably high minAmountOut
        uint256 unreasonableMin = amount * 1e18;

        vm.expectRevert();
        pendleSwapper.pendleSwapFrom(
            pt,
            USDC_ADDRESS,
            ptAmount,
            unreasonableMin
        );

        // Verify no swap occurred
        assertEq(
            ERC20(pt).balanceOf(address(pendleSwapper)),
            ptAmount,
            "PT should not be spent"
        );
    }

    function test_fork_marketConfiguration() public {
        // Verify market is correctly registered
        assertEq(
            pendleSwapper.markets(pt),
            PENDLE_MARKET,
            "Market should be registered"
        );

        // Verify PT is not expired for active trading tests
        (, IPPrincipalToken _PT, ) = IPMarket(PENDLE_MARKET).readTokens();

        // Log expiry for debugging
        uint256 expiry = _PT.expiry();
        emit log_named_uint("PT expiry timestamp", expiry);
        emit log_named_uint("Current timestamp", block.timestamp);
    }

    function test_fork_guessMaxMultiplier(uint256 amount) public {
        vm.assume(amount >= minUsdcAmount && amount <= maxUsdcAmount);

        // Set a custom guessMaxMultiplier
        vm.prank(management);
        pendleSwapper.setGuessMaxMultiplier(2e18); // 2x multiplier

        assertEq(
            pendleSwapper.guessMaxMultiplier(),
            2e18,
            "Multiplier should be set"
        );

        // Airdrop USDC to the swapper
        airdrop(usdc, address(pendleSwapper), amount);

        // Swap should still work with custom multiplier
        uint256 amountOut = pendleSwapper.pendleSwapFrom(
            USDC_ADDRESS,
            pt,
            amount,
            0
        );

        assertGt(amountOut, 0, "Swap should succeed with custom multiplier");
        assertEq(
            ERC20(pt).balanceOf(address(pendleSwapper)),
            amountOut,
            "Should have PT"
        );
    }

    function test_fork_minAmountToSell() public {
        uint256 amount = 1000e6; // 1000 USDC

        // Set minAmountToSell higher than our swap amount
        vm.prank(management);
        pendleSwapper.setMinAmountToSell(2000e6); // 2000 USDC minimum

        // Airdrop USDC to the swapper
        airdrop(usdc, address(pendleSwapper), amount);

        // Swap should return 0 and not execute because amount < minAmountToSell
        uint256 amountOut = pendleSwapper.pendleSwapFrom(
            USDC_ADDRESS,
            pt,
            amount,
            0
        );

        assertEq(amountOut, 0, "Should return 0 when below minAmountToSell");
        assertEq(
            usdc.balanceOf(address(pendleSwapper)),
            amount,
            "USDC should not be spent"
        );
        assertEq(
            ERC20(pt).balanceOf(address(pendleSwapper)),
            0,
            "Should not have PT"
        );
    }

    function test_fork_roundTrip(uint256 amount) public {
        vm.assume(amount >= minUsdcAmount && amount <= maxUsdcAmount);

        // Skip if market is expired
        if (IPMarket(PENDLE_MARKET).isExpired()) {
            return;
        }

        // Airdrop USDC to the swapper
        airdrop(usdc, address(pendleSwapper), amount);

        // Buy PT
        uint256 ptReceived = pendleSwapper.pendleSwapFrom(
            USDC_ADDRESS,
            pt,
            amount,
            0
        );

        assertGt(ptReceived, 0, "Should receive PT");

        // Sell PT back to USDC
        uint256 usdcReceived = pendleSwapper.pendleSwapFrom(
            pt,
            USDC_ADDRESS,
            ptReceived,
            0
        );

        assertGt(usdcReceived, 0, "Should receive USDC back");

        // Due to AMM fees and slippage, we expect some loss
        // The received amount should be less than original but reasonably close
        assertLt(usdcReceived, amount, "Should have some slippage loss");
        assertGt(
            usdcReceived,
            (amount * 90) / 100,
            "Should not lose more than 10%"
        );
    }

    function test_fork_multipleSwaps() public {
        // Skip if market is expired
        if (IPMarket(PENDLE_MARKET).isExpired()) {
            return;
        }

        uint256 amount1 = 5_000e6;
        uint256 amount2 = 10_000e6;
        uint256 amount3 = 15_000e6;

        // First swap
        airdrop(usdc, address(pendleSwapper), amount1);
        uint256 pt1 = pendleSwapper.pendleSwapFrom(
            USDC_ADDRESS,
            pt,
            amount1,
            0
        );
        assertGt(pt1, 0, "First swap should succeed");

        // Second swap
        airdrop(usdc, address(pendleSwapper), amount2);
        uint256 pt2 = pendleSwapper.pendleSwapFrom(
            USDC_ADDRESS,
            pt,
            amount2,
            0
        );
        assertGt(pt2, 0, "Second swap should succeed");

        // Third swap
        airdrop(usdc, address(pendleSwapper), amount3);
        uint256 pt3 = pendleSwapper.pendleSwapFrom(
            USDC_ADDRESS,
            pt,
            amount3,
            0
        );
        assertGt(pt3, 0, "Third swap should succeed");

        // Total PT should be sum of all swaps
        uint256 totalPt = ERC20(pt).balanceOf(address(pendleSwapper));
        assertEq(totalPt, pt1 + pt2 + pt3, "Total PT should be sum of swaps");

        // Sell all PT at once
        uint256 usdcBack = pendleSwapper.pendleSwapFrom(
            pt,
            USDC_ADDRESS,
            totalPt,
            0
        );
        assertGt(usdcBack, 0, "Should receive USDC back");
    }

    function test_fork_pendleRouterAddress() public {
        assertEq(
            pendleSwapper.pendleRouter(),
            PENDLE_ROUTER,
            "Pendle router should be correctly set"
        );
    }

    // Chainlink USDC/USD price feed on mainnet
    address public constant CHAINLINK_USDC_USD =
        0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;

    /**
     * @dev Helper to mock Chainlink price feeds after time warp.
     *   The underlying CapToken uses Oracle price feeds with staleness checks.
     *   After warping to expiry, we need to mock the feeds to return valid timestamps.
     */
    function _mockChainlinkAfterWarp() internal {
        // Mock the USDC/USD Chainlink feed to return valid data at current block.timestamp
        // latestRoundData returns (roundId, answer, startedAt, updatedAt, answeredInRound)
        vm.mockCall(
            CHAINLINK_USDC_USD,
            abi.encodeWithSignature("latestRoundData()"),
            abi.encode(
                uint80(1000), // roundId
                int256(100000000), // answer: $1.00 with 8 decimals
                block.timestamp - 1, // startedAt
                block.timestamp - 1, // updatedAt (recent)
                uint80(1000) // answeredInRound
            )
        );
    }

    function test_fork_redeemPtAfterExpiry(uint256 amount) public {
        vm.assume(amount >= minUsdcAmount && amount <= maxUsdcAmount);

        // Buy PT before expiry
        airdrop(usdc, address(pendleSwapper), amount);
        uint256 ptReceived = pendleSwapper.pendleSwapFrom(
            USDC_ADDRESS,
            pt,
            amount,
            0
        );

        assertGt(ptReceived, 0, "Should receive PT");

        // Get PT expiry and warp past it
        (, IPPrincipalToken _PT, ) = IPMarket(PENDLE_MARKET).readTokens();
        uint256 expiry = _PT.expiry();

        // Warp to after expiry
        vm.warp(expiry + 1);

        // Mock Chainlink feed after warp to avoid staleness errors in underlying CapToken
        _mockChainlinkAfterWarp();

        // Verify market is now expired
        assertTrue(
            IPMarket(PENDLE_MARKET).isExpired(),
            "Market should be expired"
        );

        // Record PT balance before redemption
        uint256 ptBefore = ERC20(pt).balanceOf(address(pendleSwapper));
        assertEq(ptBefore, ptReceived, "PT balance should match");

        // Redeem PT after expiry - should call redeemPyToToken
        uint256 usdcReceived = pendleSwapper.pendleSwapFrom(
            pt,
            USDC_ADDRESS,
            ptReceived,
            0
        );

        // Verify redemption results
        uint256 ptAfter = ERC20(pt).balanceOf(address(pendleSwapper));
        uint256 usdcAfter = usdc.balanceOf(address(pendleSwapper));

        assertEq(ptAfter, 0, "All PT should be redeemed");
        assertGt(usdcReceived, 0, "Should receive USDC from redemption");
        assertEq(
            usdcAfter,
            usdcReceived,
            "USDC balance should match return value"
        );

        // After expiry, PT redeems 1:1 with underlying value
        // We should get back approximately the original amount (within 1% for rounding)
        // PT at expiry = 1 unit of underlying value
        assertGe(
            usdcReceived,
            (amount * 99) / 100,
            "Should receive at least 99% of original amount after expiry redemption"
        );
    }

    function test_fork_redeemPtAfterExpiry_exactValue() public {
        uint256 amount = 10_000e6; // 10,000 USDC

        // Buy PT before expiry
        airdrop(usdc, address(pendleSwapper), amount);
        uint256 ptReceived = pendleSwapper.pendleSwapFrom(
            USDC_ADDRESS,
            pt,
            amount,
            0
        );

        // Get PT expiry and warp past it
        (, IPPrincipalToken _PT, ) = IPMarket(PENDLE_MARKET).readTokens();
        uint256 expiry = _PT.expiry();
        vm.warp(expiry + 1);

        // Mock Chainlink feed after warp to avoid staleness errors in underlying CapToken
        _mockChainlinkAfterWarp();

        // Redeem PT after expiry
        uint256 usdcReceived = pendleSwapper.pendleSwapFrom(
            pt,
            USDC_ADDRESS,
            ptReceived,
            0
        );

        // Log values for debugging
        emit log_named_uint("Original USDC amount", amount);
        emit log_named_uint("PT received from swap", ptReceived);
        emit log_named_uint("USDC received from redemption", usdcReceived);
        emit log_named_uint(
            "Difference",
            usdcReceived > amount
                ? usdcReceived - amount
                : amount - usdcReceived
        );

        // PT should redeem for full underlying value at expiry
        // The slight gain is due to buying PT at a discount (implied yield)
        assertGe(
            usdcReceived,
            amount,
            "Should receive at least original amount at expiry"
        );
    }
}
