// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import {Setup, ERC20, IStrategy} from "./utils/Setup.sol";

import {MockUniswapUniversalSwapper, IMockUniswapUniversalSwapper} from "./mocks/MockUniswapUniversalSwapper.sol";

contract UniswapUniversalSwapperTest is Setup {
    IMockUniswapUniversalSwapper public swapper;

    // Mainnet addresses
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant UNIVERSAL_ROUTER =
        0x66a9893cC07D91D95644AEDD05D03f95e1dBA8Af;

    address public constant TOKEN_A = address(0x1111);
    address public constant TOKEN_B = address(0x2222);

    function setUp() public override {
        super.setUp();

        swapper = IMockUniswapUniversalSwapper(
            address(new MockUniswapUniversalSwapper(address(asset)))
        );

        swapper.setKeeper(keeper);
        swapper.setPerformanceFeeRecipient(performanceFeeRecipient);
        swapper.setPendingManagement(management);
        vm.prank(management);
        swapper.acceptManagement();
    }

    function test_defaultBase() public {
        assertEq(swapper.base(), WETH);
    }

    function test_defaultRouter() public {
        assertEq(swapper.router(), UNIVERSAL_ROUTER);
    }

    function test_defaultMinAmountToSell() public {
        assertEq(swapper.minAmountToSell(), 0);
    }

    function test_setUniFees() public {
        assertEq(swapper.uniFees(TOKEN_A, TOKEN_B), 0);

        vm.prank(management);
        swapper.setUniFees(TOKEN_A, TOKEN_B, 3000);

        assertEq(swapper.uniFees(TOKEN_A, TOKEN_B), 3000);
        assertEq(swapper.uniFees(TOKEN_B, TOKEN_A), 3000);
    }

    function test_setV4Pool() public {
        (uint24 fee, int24 tickSpacing, address hooks) = swapper.v4Pools(
            TOKEN_A,
            TOKEN_B
        );
        assertEq(fee, 0);
        assertEq(tickSpacing, 0);
        assertEq(hooks, address(0));

        vm.prank(management);
        swapper.setV4Pool(TOKEN_A, TOKEN_B, 500, 10, address(0));

        (fee, tickSpacing, hooks) = swapper.v4Pools(TOKEN_A, TOKEN_B);
        assertEq(fee, 500);
        assertEq(tickSpacing, 10);
        assertEq(hooks, address(0));

        // Check both directions
        (fee, tickSpacing, hooks) = swapper.v4Pools(TOKEN_B, TOKEN_A);
        assertEq(fee, 500);
        assertEq(tickSpacing, 10);
    }

    function test_setV4PoolWithHooks() public {
        address hookAddr = address(0xDEAD);

        vm.prank(management);
        swapper.setV4Pool(TOKEN_A, TOKEN_B, 500, 10, hookAddr);

        (uint24 fee, int24 tickSpacing, address hooks) = swapper.v4Pools(
            TOKEN_A,
            TOKEN_B
        );
        assertEq(fee, 500);
        assertEq(tickSpacing, 10);
        assertEq(hooks, hookAddr);
    }

    function test_swapFrom_zeroAmount_returnsZero() public {
        vm.prank(management);
        swapper.setUniFees(address(asset), WETH, 3000);

        uint256 amountOut = swapper.swapFrom(address(asset), WETH, 0, 0);
        assertEq(amountOut, 0);
    }

    function test_swapFrom_belowMinAmount_returnsZero() public {
        vm.prank(management);
        swapper.setUniFees(address(asset), WETH, 3000);

        vm.prank(management);
        swapper.setMinAmountToSell(1e18);

        uint256 amount = 1e15;
        airdrop(asset, address(swapper), amount);

        uint256 amountOut = swapper.swapFrom(address(asset), WETH, amount, 0);
        assertEq(amountOut, 0);
    }
}

/**
 * @title UniswapUniversalSwapperForkTest
 * @notice Fork tests for UniswapUniversalSwapper covering all swap flow combinations.
 * @dev These tests require a mainnet fork (--fork-url).
 *
 * Test Scenarios:
 * 1. Single V3 hop - from/to is WETH (base), use V3 pool
 * 2. Single V4 hop - from/to is WETH (base), use V4 pool
 * 3. Two V3 hops - from -> WETH -> to, both hops V3
 * 4. Two V4 hops - from -> WETH -> to, both hops V4
 * 5. Mixed V3 then V4 - from -> WETH via V3, WETH -> to via V4
 * 6. Mixed V4 then V3 - from -> WETH via V4, WETH -> to via V3
 */
contract UniswapUniversalSwapperForkTest is Setup {
    IMockUniswapUniversalSwapper public swapper;

    // Token addresses
    ERC20 public weth;
    ERC20 public usdc;
    ERC20 public morpho;

    // Mainnet token addresses
    address public constant WETH_ADDR =
        0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant USDC_ADDR =
        0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant MORPHO_ADDR =
        0x58D97B57BB95320F9a05dC918Aef65434969c2B2;
    // USDT is the asset from Setup: 0xdAC17F958D2ee523a2206206994597C13D831ec7

    // V3 pool fees
    uint24 public constant V3_FEE_LOW = 500; // 0.05% - USDT/WETH
    uint24 public constant V3_FEE_MID = 3000; // 0.3% - USDC/WETH

    // V4 pool IDs
    bytes32 public constant MORPHO_WETH_POOL_ID =
        0xd9f5cbaeb88b7f0d9b0549257ddd4c46f984e2fc4bccf056cc254b9fe3417fff;
    bytes32 public constant USDC_WETH_V4_POOL_ID =
        0xdce6394339af00981949f5f3baf27e3610c76326a700af57e4b3e3ae4977f78d;
    // USDC/USDT V4 pool - fee: 10, tickSpacing: 1, no hooks
    bytes32 public constant USDC_USDT_POOL_ID =
        0x8aa4e11cbdf30eedc92100f4c8a31ff748e201d44712cc8c90d189edaa8e4e47;

    // V4 pool parameters (for manual setting if needed)
    uint24 public constant MORPHO_FEE = 2999;
    uint24 public constant USDC_V4_FEE = 3000;
    int24 public constant V4_TICK_SPACING = 60;

    // Fuzz amounts for WETH (different scale than USDT)
    uint256 public minWethAmount = 1e15; // 0.001 WETH
    uint256 public maxWethAmount = 1e19; // 10 WETH

    // Fuzz amounts for MORPHO (use smaller amounts due to potential liquidity constraints)
    uint256 public minMorphoAmount = 1e17; // 0.1 MORPHO
    uint256 public maxMorphoAmount = 1e20; // 100 MORPHO

    // Fuzz amounts for USDC (6 decimals)
    uint256 public minUsdcAmount = 1e6; // 1 USDC
    uint256 public maxUsdcAmount = 1e10; // 10,000 USDC

    function setUp() public override {
        super.setUp();

        // Initialize token references
        weth = ERC20(WETH_ADDR);
        usdc = ERC20(USDC_ADDR);
        morpho = ERC20(MORPHO_ADDR);

        // Deploy swapper with USDT as the strategy asset
        swapper = IMockUniswapUniversalSwapper(
            address(new MockUniswapUniversalSwapper(address(asset)))
        );

        // Setup swapper management
        swapper.setKeeper(keeper);
        swapper.setPerformanceFeeRecipient(performanceFeeRecipient);
        swapper.setPendingManagement(management);
        vm.prank(management);
        swapper.acceptManagement();

        // Label addresses for better trace output
        vm.label(address(weth), "WETH");
        vm.label(address(usdc), "USDC");
        vm.label(address(morpho), "MORPHO");
        vm.label(address(swapper), "UniversalSwapper");
    }

    // ==================== SINGLE V3 HOP TESTS ====================

    /**
     * @notice Test single V3 hop: USDT -> WETH (asset to base)
     */
    function test_singleV3Hop_assetToWeth(uint256 amount) public {
        vm.assume(amount >= minFuzzAmount && amount <= maxFuzzAmount);

        // Set V3 fee for USDT <-> WETH
        vm.prank(management);
        swapper.setUniFees(address(asset), WETH_ADDR, V3_FEE_LOW);

        // Airdrop USDT to swapper
        airdrop(asset, address(swapper), amount);

        // Verify initial balances
        assertEq(asset.balanceOf(address(swapper)), amount);
        assertEq(weth.balanceOf(address(swapper)), 0);

        // Execute swap
        uint256 amountOut = swapper.swapFrom(
            address(asset),
            WETH_ADDR,
            amount,
            0
        );

        // Verify swap results
        assertEq(asset.balanceOf(address(swapper)), 0);
        assertGt(weth.balanceOf(address(swapper)), 0);
        assertEq(weth.balanceOf(address(swapper)), amountOut);
    }

    /**
     * @notice Test single V3 hop: WETH -> USDT (base to asset)
     */
    function test_singleV3Hop_wethToAsset(uint256 amount) public {
        vm.assume(amount >= minWethAmount && amount <= maxWethAmount);

        // Set V3 fee for WETH <-> USDT
        vm.prank(management);
        swapper.setUniFees(WETH_ADDR, address(asset), V3_FEE_LOW);

        // Airdrop WETH to swapper
        airdrop(weth, address(swapper), amount);

        // Verify initial balances
        assertEq(weth.balanceOf(address(swapper)), amount);
        assertEq(asset.balanceOf(address(swapper)), 0);

        // Execute swap
        uint256 amountOut = swapper.swapFrom(
            WETH_ADDR,
            address(asset),
            amount,
            0
        );

        // Verify swap results
        assertEq(weth.balanceOf(address(swapper)), 0);
        assertGt(asset.balanceOf(address(swapper)), 0);
        assertEq(asset.balanceOf(address(swapper)), amountOut);
    }

    /**
     * @notice Test single V3 hop: USDC -> WETH
     */
    function test_singleV3Hop_usdcToWeth(uint256 amount) public {
        vm.assume(amount >= minUsdcAmount && amount <= maxUsdcAmount);

        // Set V3 fee for USDC <-> WETH
        vm.prank(management);
        swapper.setUniFees(USDC_ADDR, WETH_ADDR, V3_FEE_MID);

        // Airdrop USDC to swapper
        airdrop(usdc, address(swapper), amount);

        // Verify initial balances
        assertEq(usdc.balanceOf(address(swapper)), amount);
        assertEq(weth.balanceOf(address(swapper)), 0);

        // Execute swap
        uint256 amountOut = swapper.swapFrom(USDC_ADDR, WETH_ADDR, amount, 0);

        // Verify swap results
        assertEq(usdc.balanceOf(address(swapper)), 0);
        assertGt(weth.balanceOf(address(swapper)), 0);
        assertEq(weth.balanceOf(address(swapper)), amountOut);
    }

    /**
     * @notice Test single V3 hop: WETH -> USDC
     */
    function test_singleV3Hop_wethToUsdc(uint256 amount) public {
        vm.assume(amount >= minWethAmount && amount <= maxWethAmount);

        // Set V3 fee for WETH <-> USDC
        vm.prank(management);
        swapper.setUniFees(WETH_ADDR, USDC_ADDR, V3_FEE_MID);

        // Airdrop WETH to swapper
        airdrop(weth, address(swapper), amount);

        // Verify initial balances
        assertEq(weth.balanceOf(address(swapper)), amount);
        assertEq(usdc.balanceOf(address(swapper)), 0);

        // Execute swap
        uint256 amountOut = swapper.swapFrom(WETH_ADDR, USDC_ADDR, amount, 0);

        // Verify swap results
        assertEq(weth.balanceOf(address(swapper)), 0);
        assertGt(usdc.balanceOf(address(swapper)), 0);
        assertEq(usdc.balanceOf(address(swapper)), amountOut);
    }

    // ==================== SINGLE V4 HOP TESTS ====================

    /**
     * @notice Test single V4 hop: USDC -> USDT (asset)
     */
    function test_singleV4Hop_usdcToUsdt(uint256 amount) public {
        vm.assume(amount >= minUsdcAmount && amount <= maxUsdcAmount);

        // Set V4 pool for USDC <-> USDT
        vm.prank(management);
        swapper.setV4Pool(USDC_ADDR, address(asset), USDC_USDT_POOL_ID);

        vm.prank(management);
        swapper.setBase(address(asset));

        // Airdrop USDC to swapper
        airdrop(usdc, address(swapper), amount);

        // Verify initial balances
        assertEq(usdc.balanceOf(address(swapper)), amount);
        assertEq(asset.balanceOf(address(swapper)), 0);

        // Execute swap
        uint256 amountOut = swapper.swapFrom(
            USDC_ADDR,
            address(asset),
            amount,
            0
        );

        // Verify swap results
        assertEq(usdc.balanceOf(address(swapper)), 0);
        assertGt(asset.balanceOf(address(swapper)), 0);
        assertEq(asset.balanceOf(address(swapper)), amountOut);
    }

    /**
     * @notice Test single V4 hop: MORPHO -> WETH
     */
    function test_singleV4Hop_morphoToWeth(uint256 amount) public {
        vm.assume(amount >= minMorphoAmount && amount <= maxMorphoAmount);

        // Set V4 pool for MORPHO <-> WETH using pool ID
        vm.prank(management);
        swapper.setV4Pool(MORPHO_ADDR, WETH_ADDR, MORPHO_WETH_POOL_ID);

        // Airdrop MORPHO to swapper
        airdrop(morpho, address(swapper), amount);

        // Verify initial balances
        assertEq(morpho.balanceOf(address(swapper)), amount);
        assertEq(weth.balanceOf(address(swapper)), 0);

        // Execute swap
        uint256 amountOut = swapper.swapFrom(MORPHO_ADDR, WETH_ADDR, amount, 0);

        // Verify swap results
        assertEq(morpho.balanceOf(address(swapper)), 0);
        assertGt(weth.balanceOf(address(swapper)), 0);
        assertEq(weth.balanceOf(address(swapper)), amountOut);
    }

    /**
     * @notice Test single V4 hop: WETH -> MORPHO
     */
    function test_singleV4Hop_wethToMorpho(uint256 amount) public {
        vm.assume(amount >= minWethAmount && amount <= maxWethAmount);

        // Set V4 pool for WETH <-> MORPHO using pool ID
        vm.prank(management);
        swapper.setV4Pool(WETH_ADDR, MORPHO_ADDR, MORPHO_WETH_POOL_ID);

        // Airdrop WETH to swapper
        airdrop(weth, address(swapper), amount);

        // Verify initial balances
        assertEq(weth.balanceOf(address(swapper)), amount);
        assertEq(morpho.balanceOf(address(swapper)), 0);

        // Execute swap
        uint256 amountOut = swapper.swapFrom(WETH_ADDR, MORPHO_ADDR, amount, 0);

        // Verify swap results
        assertEq(weth.balanceOf(address(swapper)), 0);
        assertGt(morpho.balanceOf(address(swapper)), 0);
        assertEq(morpho.balanceOf(address(swapper)), amountOut);
    }

    /**
     * @notice Test single V4 hop: USDC -> WETH (using V4 pool)
     */
    function test_singleV4Hop_usdcToWeth(uint256 amount) public {
        vm.assume(amount >= minUsdcAmount && amount <= maxUsdcAmount);

        // Set V4 pool for USDC <-> WETH using pool ID
        vm.prank(management);
        swapper.setV4Pool(USDC_ADDR, WETH_ADDR, USDC_WETH_V4_POOL_ID);

        // Airdrop USDC to swapper
        airdrop(usdc, address(swapper), amount);

        // Verify initial balances
        assertEq(usdc.balanceOf(address(swapper)), amount);
        assertEq(weth.balanceOf(address(swapper)), 0);

        // Execute swap
        uint256 amountOut = swapper.swapFrom(USDC_ADDR, WETH_ADDR, amount, 0);

        // Verify swap results
        assertEq(usdc.balanceOf(address(swapper)), 0);
        assertGt(weth.balanceOf(address(swapper)), 0);
        assertEq(weth.balanceOf(address(swapper)), amountOut);
    }

    /**
     * @notice Test single V4 hop: WETH -> USDC (using V4 pool)
     */
    function test_singleV4Hop_wethToUsdc(uint256 amount) public {
        vm.assume(amount >= minWethAmount && amount <= maxWethAmount);

        // Set V4 pool for WETH <-> USDC using pool ID
        vm.prank(management);
        swapper.setV4Pool(WETH_ADDR, USDC_ADDR, USDC_WETH_V4_POOL_ID);

        // Airdrop WETH to swapper
        airdrop(weth, address(swapper), amount);

        // Verify initial balances
        assertEq(weth.balanceOf(address(swapper)), amount);
        assertEq(usdc.balanceOf(address(swapper)), 0);

        // Execute swap
        uint256 amountOut = swapper.swapFrom(WETH_ADDR, USDC_ADDR, amount, 0);

        // Verify swap results
        assertEq(weth.balanceOf(address(swapper)), 0);
        assertGt(usdc.balanceOf(address(swapper)), 0);
        assertEq(usdc.balanceOf(address(swapper)), amountOut);
    }

    // ==================== TWO V3 HOPS TESTS ====================

    /**
     * @notice Test two V3 hops: USDT -> WETH -> USDC
     */
    function test_twoV3Hops_assetToUsdc(uint256 amount) public {
        vm.assume(amount >= minFuzzAmount && amount <= maxFuzzAmount);

        // Set V3 fees for both hops
        vm.prank(management);
        swapper.setUniFees(address(asset), WETH_ADDR, V3_FEE_LOW);
        vm.prank(management);
        swapper.setUniFees(WETH_ADDR, USDC_ADDR, V3_FEE_MID);

        // Airdrop USDT to swapper
        airdrop(asset, address(swapper), amount);

        // Verify initial balances
        assertEq(asset.balanceOf(address(swapper)), amount);
        assertEq(weth.balanceOf(address(swapper)), 0);
        assertEq(usdc.balanceOf(address(swapper)), 0);

        // Execute swap
        uint256 amountOut = swapper.swapFrom(
            address(asset),
            USDC_ADDR,
            amount,
            0
        );

        // Verify swap results
        assertEq(asset.balanceOf(address(swapper)), 0);
        assertEq(weth.balanceOf(address(swapper)), 0); // No WETH left in swapper
        assertGt(usdc.balanceOf(address(swapper)), 0);
        assertEq(usdc.balanceOf(address(swapper)), amountOut);
    }

    /**
     * @notice Test two V3 hops: USDC -> WETH -> USDT
     */
    function test_twoV3Hops_usdcToAsset(uint256 amount) public {
        vm.assume(amount >= minUsdcAmount && amount <= maxUsdcAmount);

        // Set V3 fees for both hops
        vm.prank(management);
        swapper.setUniFees(USDC_ADDR, WETH_ADDR, V3_FEE_MID);
        vm.prank(management);
        swapper.setUniFees(WETH_ADDR, address(asset), V3_FEE_LOW);

        // Airdrop USDC to swapper
        airdrop(usdc, address(swapper), amount);

        // Verify initial balances
        assertEq(usdc.balanceOf(address(swapper)), amount);
        assertEq(weth.balanceOf(address(swapper)), 0);
        assertEq(asset.balanceOf(address(swapper)), 0);

        // Execute swap
        uint256 amountOut = swapper.swapFrom(
            USDC_ADDR,
            address(asset),
            amount,
            0
        );

        // Verify swap results
        assertEq(usdc.balanceOf(address(swapper)), 0);
        assertEq(weth.balanceOf(address(swapper)), 0); // No WETH left in swapper
        assertGt(asset.balanceOf(address(swapper)), 0);
        assertEq(asset.balanceOf(address(swapper)), amountOut);
    }

    // ==================== TWO V4 HOPS TESTS ====================

    /**
     * @notice Test two V4 hops: MORPHO -> WETH -> USDC (both V4)
     */
    function test_twoV4Hops_morphoToUsdc(uint256 amount) public {
        vm.assume(amount >= minMorphoAmount && amount <= maxMorphoAmount);

        // Set V4 pools for both hops
        vm.prank(management);
        swapper.setV4Pool(MORPHO_ADDR, WETH_ADDR, MORPHO_WETH_POOL_ID);
        vm.prank(management);
        swapper.setV4Pool(WETH_ADDR, USDC_ADDR, USDC_WETH_V4_POOL_ID);

        // Airdrop MORPHO to swapper
        airdrop(morpho, address(swapper), amount);

        // Verify initial balances
        assertEq(morpho.balanceOf(address(swapper)), amount);
        assertEq(weth.balanceOf(address(swapper)), 0);
        assertEq(usdc.balanceOf(address(swapper)), 0);

        // Execute swap
        uint256 amountOut = swapper.swapFrom(MORPHO_ADDR, USDC_ADDR, amount, 0);

        // Verify swap results
        assertEq(morpho.balanceOf(address(swapper)), 0);
        assertEq(weth.balanceOf(address(swapper)), 0); // No WETH left in swapper
        assertGt(usdc.balanceOf(address(swapper)), 0);
        assertEq(usdc.balanceOf(address(swapper)), amountOut);
    }

    /**
     * @notice Test two V4 hops: USDC -> WETH -> MORPHO (both V4)
     */
    function test_twoV4Hops_usdcToMorpho(uint256 amount) public {
        vm.assume(amount >= minUsdcAmount && amount <= maxUsdcAmount);

        // Set V4 pools for both hops
        vm.prank(management);
        swapper.setV4Pool(USDC_ADDR, WETH_ADDR, USDC_WETH_V4_POOL_ID);
        vm.prank(management);
        swapper.setV4Pool(WETH_ADDR, MORPHO_ADDR, MORPHO_WETH_POOL_ID);

        // Airdrop USDC to swapper
        airdrop(usdc, address(swapper), amount);

        // Verify initial balances
        assertEq(usdc.balanceOf(address(swapper)), amount);
        assertEq(weth.balanceOf(address(swapper)), 0);
        assertEq(morpho.balanceOf(address(swapper)), 0);

        // Execute swap
        uint256 amountOut = swapper.swapFrom(USDC_ADDR, MORPHO_ADDR, amount, 0);

        // Verify swap results
        assertEq(usdc.balanceOf(address(swapper)), 0);
        assertEq(weth.balanceOf(address(swapper)), 0); // No WETH left in swapper
        assertGt(morpho.balanceOf(address(swapper)), 0);
        assertEq(morpho.balanceOf(address(swapper)), amountOut);
    }

    // ==================== MIXED V3 THEN V4 TESTS ====================

    /**
     * @notice Test mixed hops: USDT -> WETH (V3) -> MORPHO (V4)
     */
    function test_mixedV3ThenV4_assetToMorpho(uint256 amount) public {
        vm.assume(amount >= minFuzzAmount && amount <= maxFuzzAmount);

        // Set V3 fee for first hop (USDT -> WETH)
        vm.prank(management);
        swapper.setUniFees(address(asset), WETH_ADDR, V3_FEE_LOW);

        // Set V4 pool for second hop (WETH -> MORPHO)
        vm.prank(management);
        swapper.setV4Pool(WETH_ADDR, MORPHO_ADDR, MORPHO_WETH_POOL_ID);

        // Airdrop USDT to swapper
        airdrop(asset, address(swapper), amount);

        // Verify initial balances
        assertEq(asset.balanceOf(address(swapper)), amount);
        assertEq(weth.balanceOf(address(swapper)), 0);
        assertEq(morpho.balanceOf(address(swapper)), 0);

        // Execute swap
        uint256 amountOut = swapper.swapFrom(
            address(asset),
            MORPHO_ADDR,
            amount,
            0
        );

        // Verify swap results
        assertEq(asset.balanceOf(address(swapper)), 0);
        assertEq(weth.balanceOf(address(swapper)), 0); // No WETH left in swapper
        assertGt(morpho.balanceOf(address(swapper)), 0);
        assertEq(morpho.balanceOf(address(swapper)), amountOut);
    }

    /**
     * @notice Test mixed hops: USDC -> WETH (V3) -> MORPHO (V4)
     */
    function test_mixedV3ThenV4_usdcToMorpho(uint256 amount) public {
        vm.assume(amount >= minUsdcAmount && amount <= maxUsdcAmount);

        // Set V3 fee for first hop (USDC -> WETH)
        vm.prank(management);
        swapper.setUniFees(USDC_ADDR, WETH_ADDR, V3_FEE_MID);

        // Set V4 pool for second hop (WETH -> MORPHO)
        vm.prank(management);
        swapper.setV4Pool(WETH_ADDR, MORPHO_ADDR, MORPHO_WETH_POOL_ID);

        // Airdrop USDC to swapper
        airdrop(usdc, address(swapper), amount);

        // Verify initial balances
        assertEq(usdc.balanceOf(address(swapper)), amount);
        assertEq(weth.balanceOf(address(swapper)), 0);
        assertEq(morpho.balanceOf(address(swapper)), 0);

        // Execute swap
        uint256 amountOut = swapper.swapFrom(USDC_ADDR, MORPHO_ADDR, amount, 0);

        // Verify swap results
        assertEq(usdc.balanceOf(address(swapper)), 0);
        assertEq(weth.balanceOf(address(swapper)), 0); // No WETH left in swapper
        assertGt(morpho.balanceOf(address(swapper)), 0);
        assertEq(morpho.balanceOf(address(swapper)), amountOut);
    }

    // ==================== MIXED V4 THEN V3 TESTS ====================

    /**
     * @notice Test mixed hops: MORPHO -> WETH (V4) -> USDT (V3)
     */
    function test_mixedV4ThenV3_morphoToAsset(uint256 amount) public {
        vm.assume(amount >= minMorphoAmount && amount <= maxMorphoAmount);

        // Set V4 pool for first hop (MORPHO -> WETH)
        vm.prank(management);
        swapper.setV4Pool(MORPHO_ADDR, WETH_ADDR, MORPHO_WETH_POOL_ID);

        // Set V3 fee for second hop (WETH -> USDT)
        vm.prank(management);
        swapper.setUniFees(WETH_ADDR, address(asset), V3_FEE_LOW);

        // Airdrop MORPHO to swapper
        airdrop(morpho, address(swapper), amount);

        // Verify initial balances
        assertEq(morpho.balanceOf(address(swapper)), amount);
        assertEq(weth.balanceOf(address(swapper)), 0);
        assertEq(asset.balanceOf(address(swapper)), 0);

        // Execute swap
        uint256 amountOut = swapper.swapFrom(
            MORPHO_ADDR,
            address(asset),
            amount,
            0
        );

        // Verify swap results
        assertEq(morpho.balanceOf(address(swapper)), 0);
        assertEq(weth.balanceOf(address(swapper)), 0); // No WETH left in swapper
        assertGt(asset.balanceOf(address(swapper)), 0);
        assertEq(asset.balanceOf(address(swapper)), amountOut);
    }

    /**
     * @notice Test mixed hops: MORPHO -> WETH (V4) -> USDC (V3)
     */
    function test_mixedV4ThenV3_morphoToUsdc(uint256 amount) public {
        vm.assume(amount >= minMorphoAmount && amount <= maxMorphoAmount);

        // Set V4 pool for first hop (MORPHO -> WETH)
        vm.prank(management);
        swapper.setV4Pool(MORPHO_ADDR, WETH_ADDR, MORPHO_WETH_POOL_ID);

        // Set V3 fee for second hop (WETH -> USDC)
        vm.prank(management);
        swapper.setUniFees(WETH_ADDR, USDC_ADDR, V3_FEE_MID);

        // Airdrop MORPHO to swapper
        airdrop(morpho, address(swapper), amount);

        // Verify initial balances
        assertEq(morpho.balanceOf(address(swapper)), amount);
        assertEq(weth.balanceOf(address(swapper)), 0);
        assertEq(usdc.balanceOf(address(swapper)), 0);

        // Execute swap
        uint256 amountOut = swapper.swapFrom(MORPHO_ADDR, USDC_ADDR, amount, 0);

        // Verify swap results
        assertEq(morpho.balanceOf(address(swapper)), 0);
        assertEq(weth.balanceOf(address(swapper)), 0); // No WETH left in swapper
        assertGt(usdc.balanceOf(address(swapper)), 0);
        assertEq(usdc.balanceOf(address(swapper)), amountOut);
    }

    // ==================== EDGE CASE TESTS ====================

    /**
     * @notice Test V3 swap with minAmountOut enforcement
     */
    function test_singleV3Hop_minOutReverts(uint256 amount) public {
        vm.assume(amount >= minFuzzAmount && amount <= maxFuzzAmount);

        // Set V3 fee
        vm.prank(management);
        swapper.setUniFees(address(asset), WETH_ADDR, V3_FEE_LOW);

        // Airdrop USDT to swapper
        airdrop(asset, address(swapper), amount);

        // Set unrealistic minAmountOut (expect way more WETH than possible)
        uint256 unrealisticMinOut = amount * 1e12;

        // Should revert due to slippage
        vm.expectRevert();
        swapper.swapFrom(address(asset), WETH_ADDR, amount, unrealisticMinOut);

        // Verify funds are still in swapper
        assertEq(asset.balanceOf(address(swapper)), amount);
        assertEq(weth.balanceOf(address(swapper)), 0);
    }

    /**
     * @notice Test V4 swap with minAmountOut enforcement
     */
    function test_singleV4Hop_minOutReverts(uint256 amount) public {
        vm.assume(amount >= minMorphoAmount && amount <= maxMorphoAmount);

        // Set V4 pool
        vm.prank(management);
        swapper.setV4Pool(MORPHO_ADDR, WETH_ADDR, MORPHO_WETH_POOL_ID);

        // Airdrop MORPHO to swapper
        airdrop(morpho, address(swapper), amount);

        // Set unrealistic minAmountOut
        uint256 unrealisticMinOut = amount * 1e12;

        // Should revert due to slippage
        vm.expectRevert();
        swapper.swapFrom(MORPHO_ADDR, WETH_ADDR, amount, unrealisticMinOut);

        // Verify funds are still in swapper
        assertEq(morpho.balanceOf(address(swapper)), amount);
        assertEq(weth.balanceOf(address(swapper)), 0);
    }

    /**
     * @notice Test two hop swap with minAmountOut enforcement (V3 + V3)
     */
    function test_twoV3Hops_minOutReverts(uint256 amount) public {
        vm.assume(amount >= minFuzzAmount && amount <= maxFuzzAmount);

        // Set V3 fees for both hops
        vm.prank(management);
        swapper.setUniFees(address(asset), WETH_ADDR, V3_FEE_LOW);
        vm.prank(management);
        swapper.setUniFees(WETH_ADDR, USDC_ADDR, V3_FEE_MID);

        // Airdrop USDT to swapper
        airdrop(asset, address(swapper), amount);

        // Set unrealistic minAmountOut
        uint256 unrealisticMinOut = amount * 1e12;

        // Should revert due to slippage
        vm.expectRevert();
        swapper.swapFrom(address(asset), USDC_ADDR, amount, unrealisticMinOut);

        // Verify funds are still in swapper
        assertEq(asset.balanceOf(address(swapper)), amount);
        assertEq(usdc.balanceOf(address(swapper)), 0);
    }

    /**
     * @notice Test mixed hop swap with minAmountOut enforcement (V3 + V4)
     */
    function test_mixedHops_minOutReverts(uint256 amount) public {
        vm.assume(amount >= minFuzzAmount && amount <= maxFuzzAmount);

        // Set V3 fee for first hop
        vm.prank(management);
        swapper.setUniFees(address(asset), WETH_ADDR, V3_FEE_LOW);

        // Set V4 pool for second hop
        vm.prank(management);
        swapper.setV4Pool(WETH_ADDR, MORPHO_ADDR, MORPHO_WETH_POOL_ID);

        // Airdrop USDT to swapper
        airdrop(asset, address(swapper), amount);

        // Set unrealistic minAmountOut
        uint256 unrealisticMinOut = amount * 1e30;

        // Should revert due to slippage
        vm.expectRevert();
        swapper.swapFrom(
            address(asset),
            MORPHO_ADDR,
            amount,
            unrealisticMinOut
        );

        // Verify input funds are still in swapper
        assertEq(asset.balanceOf(address(swapper)), amount);
    }

    /**
     * @notice Test setting V4 pool via manual parameters
     */
    function test_singleV4Hop_manualPoolParams(uint256 amount) public {
        vm.assume(amount >= minMorphoAmount && amount <= maxMorphoAmount);

        // Set V4 pool manually (not from pool ID)
        vm.prank(management);
        swapper.setV4Pool(
            MORPHO_ADDR,
            WETH_ADDR,
            MORPHO_FEE,
            V4_TICK_SPACING,
            address(0) // no hooks
        );

        // Verify pool config was set correctly
        (uint24 fee, int24 tickSpacing, address hooks) = swapper.v4Pools(
            MORPHO_ADDR,
            WETH_ADDR
        );
        assertEq(fee, MORPHO_FEE);
        assertEq(tickSpacing, V4_TICK_SPACING);
        assertEq(hooks, address(0));

        // Airdrop MORPHO to swapper
        airdrop(morpho, address(swapper), amount);

        // Execute swap
        uint256 amountOut = swapper.swapFrom(MORPHO_ADDR, WETH_ADDR, amount, 0);

        // Verify swap results
        assertEq(morpho.balanceOf(address(swapper)), 0);
        assertGt(weth.balanceOf(address(swapper)), 0);
        assertEq(weth.balanceOf(address(swapper)), amountOut);
    }

    /**
     * @notice Test V4 pool config is set correctly from pool ID
     */
    function test_setV4Pool_fromPoolId_configCorrect() public {
        // Set V4 pool from pool ID
        vm.prank(management);
        swapper.setV4Pool(MORPHO_ADDR, WETH_ADDR, MORPHO_WETH_POOL_ID);

        // Verify pool config matches expected values
        (uint24 fee, int24 tickSpacing, address hooks) = swapper.v4Pools(
            MORPHO_ADDR,
            WETH_ADDR
        );
        assertEq(fee, MORPHO_FEE);
        assertEq(tickSpacing, V4_TICK_SPACING);
        assertEq(hooks, address(0));

        // Verify both directions are set
        (fee, tickSpacing, hooks) = swapper.v4Pools(WETH_ADDR, MORPHO_ADDR);
        assertEq(fee, MORPHO_FEE);
        assertEq(tickSpacing, V4_TICK_SPACING);
        assertEq(hooks, address(0));
    }

    /**
     * @notice Test USDC V4 pool config from pool ID
     */
    function test_setV4Pool_usdc_fromPoolId_configCorrect() public {
        // Set V4 pool from pool ID
        vm.prank(management);
        swapper.setV4Pool(USDC_ADDR, WETH_ADDR, USDC_WETH_V4_POOL_ID);

        // Verify pool config matches expected values
        (uint24 fee, int24 tickSpacing, address hooks) = swapper.v4Pools(
            USDC_ADDR,
            WETH_ADDR
        );
        assertEq(fee, USDC_V4_FEE);
        assertEq(tickSpacing, V4_TICK_SPACING);
        assertEq(hooks, address(0));
    }

    /**
     * @notice Test that V3 fee takes precedence over V4 pool when both are set
     */
    function test_v3FeePreferredOverV4(uint256 amount) public {
        vm.assume(amount >= minUsdcAmount && amount <= maxUsdcAmount);

        // Set BOTH V3 fee and V4 pool for USDC <-> WETH
        vm.prank(management);
        swapper.setV4Pool(USDC_ADDR, WETH_ADDR, USDC_WETH_V4_POOL_ID);
        vm.prank(management);
        swapper.setUniFees(USDC_ADDR, WETH_ADDR, V3_FEE_MID);

        // Airdrop USDC to swapper
        airdrop(usdc, address(swapper), amount);

        // Verify initial balances
        assertEq(usdc.balanceOf(address(swapper)), amount);
        assertEq(weth.balanceOf(address(swapper)), 0);

        // Execute swap - should use V3 since fee is set
        uint256 amountOut = swapper.swapFrom(USDC_ADDR, WETH_ADDR, amount, 0);

        // Verify swap completed successfully (using V3 path)
        assertEq(usdc.balanceOf(address(swapper)), 0);
        assertGt(weth.balanceOf(address(swapper)), 0);
        assertEq(weth.balanceOf(address(swapper)), amountOut);
    }

    // ==================== TWO HOP WITH WETH AS INPUT/OUTPUT (NON-WETH BASE) ====================

    /**
     * @notice Test two V3 hops with WETH as input: WETH -> USDC (base) -> USDT
     *         Base is USDC, not WETH
     */
    function test_twoV3Hops_wethAsInput_toAsset(uint256 amount) public {
        vm.assume(amount >= minWethAmount && amount <= maxWethAmount);

        // Set base to USDC (not WETH)
        vm.prank(management);
        swapper.setBase(USDC_ADDR);

        // Set V3 fees for both hops
        vm.prank(management);
        swapper.setUniFees(WETH_ADDR, USDC_ADDR, V3_FEE_MID); // WETH -> USDC
        vm.prank(management);
        swapper.setUniFees(USDC_ADDR, address(asset), V3_FEE_LOW); // USDC -> USDT

        // Airdrop WETH to swapper
        airdrop(weth, address(swapper), amount);

        // Verify initial balances
        assertEq(weth.balanceOf(address(swapper)), amount);
        assertEq(usdc.balanceOf(address(swapper)), 0);
        assertEq(asset.balanceOf(address(swapper)), 0);

        // Execute swap: WETH -> USDC -> USDT
        uint256 amountOut = swapper.swapFrom(
            WETH_ADDR,
            address(asset),
            amount,
            0
        );

        // Verify swap results
        assertEq(weth.balanceOf(address(swapper)), 0);
        assertEq(usdc.balanceOf(address(swapper)), 0); // No USDC left in swapper
        assertGt(asset.balanceOf(address(swapper)), 0);
        assertEq(asset.balanceOf(address(swapper)), amountOut);
    }

    /**two
     * @notice Test two V3 hops with WETH as output: USDT -> USDC (base) -> WETH
     *         Base is USDC, not WETH
     */
    function test_twoV3Hops_wethAsOutput_fromAsset(uint256 amount) public {
        vm.assume(amount >= minFuzzAmount && amount <= maxFuzzAmount);

        // Set base to USDC (not WETH)
        vm.prank(management);
        swapper.setBase(USDC_ADDR);

        // Set V3 fees for both hops
        vm.prank(management);
        swapper.setUniFees(address(asset), USDC_ADDR, V3_FEE_LOW); // USDT -> USDC
        vm.prank(management);
        swapper.setUniFees(USDC_ADDR, WETH_ADDR, V3_FEE_MID); // USDC -> WETH

        // Airdrop USDT to swapper
        airdrop(asset, address(swapper), amount);

        // Verify initial balances
        assertEq(asset.balanceOf(address(swapper)), amount);
        assertEq(usdc.balanceOf(address(swapper)), 0);
        assertEq(weth.balanceOf(address(swapper)), 0);

        // Execute swap: USDT -> USDC -> WETH
        uint256 amountOut = swapper.swapFrom(
            address(asset),
            WETH_ADDR,
            amount,
            0
        );

        // Verify swap results
        assertEq(asset.balanceOf(address(swapper)), 0);
        assertEq(usdc.balanceOf(address(swapper)), 0); // No USDC left in swapper
        assertGt(weth.balanceOf(address(swapper)), 0);
        assertEq(weth.balanceOf(address(swapper)), amountOut);
    }

    /**
     * @notice Test two V4 hops with WETH as input: WETH -> USDC (base) -> MORPHO
     *         Base is USDC, not WETH. Tests V4 with native ETH as input.
     */
    function test_twoV4Hops_wethAsInput_toAsset(uint256 amount) public {
        vm.assume(amount >= minWethAmount && amount <= maxWethAmount);

        // Set base to USDC (not WETH)
        vm.prank(management);
        swapper.setBase(USDC_ADDR);

        // Set V4 pools for both hops
        vm.prank(management);
        swapper.setV4Pool(WETH_ADDR, USDC_ADDR, USDC_WETH_V4_POOL_ID); // ETH -> USDC
        vm.prank(management);
        swapper.setV4Pool(USDC_ADDR, address(asset), USDC_USDT_POOL_ID); // USDC -> MORPHO (manual params)

        // Airdrop WETH to swapper
        airdrop(weth, address(swapper), amount);

        // Verify initial balances
        assertEq(weth.balanceOf(address(swapper)), amount);
        assertEq(usdc.balanceOf(address(swapper)), 0);
        assertEq(asset.balanceOf(address(swapper)), 0);

        // Execute swap: WETH -> USDC -> USDT
        uint256 amountOut = swapper.swapFrom(
            WETH_ADDR,
            address(asset),
            amount,
            0
        );

        // Verify swap results
        assertEq(weth.balanceOf(address(swapper)), 0);
        assertEq(usdc.balanceOf(address(swapper)), 0); // No USDC left in swapper
        assertGt(asset.balanceOf(address(swapper)), 0);
        assertEq(asset.balanceOf(address(swapper)), amountOut);
    }

    /**
     * @notice Test two V4 hops with WETH as output: USDT -> USDC (base) -> WETH
     *         Base is USDC, not WETH. Tests V4 with native ETH as output.
     */
    function test_twoV4Hops_wethAsOutput_fromAsset(uint256 amount) public {
        vm.assume(amount >= minFuzzAmount && amount <= maxFuzzAmount);

        // Set base to USDC (not WETH)
        vm.prank(management);
        swapper.setBase(USDC_ADDR);

        // Set V4 pools for both hops
        vm.prank(management);
        swapper.setV4Pool(address(asset), USDC_ADDR, USDC_USDT_POOL_ID); // USDT -> USDC (manual params)
        vm.prank(management);
        swapper.setV4Pool(USDC_ADDR, WETH_ADDR, USDC_WETH_V4_POOL_ID); // USDC -> ETH

        // Airdrop MORPHO to swapper
        airdrop(asset, address(swapper), amount);

        // Verify initial balances
        assertEq(asset.balanceOf(address(swapper)), amount);
        assertEq(usdc.balanceOf(address(swapper)), 0);
        assertEq(weth.balanceOf(address(swapper)), 0);

        // Execute swap: MORPHO -> USDC -> WETH
        uint256 amountOut = swapper.swapFrom(
            address(asset),
            WETH_ADDR,
            amount,
            0
        );

        // Verify swap results
        assertEq(asset.balanceOf(address(swapper)), 0);
        assertEq(usdc.balanceOf(address(swapper)), 0); // No USDC left in swapper
        assertGt(weth.balanceOf(address(swapper)), 0);
        assertEq(weth.balanceOf(address(swapper)), amountOut);
    }

    /**
     * @notice Test mixed V3 then V4 with WETH as input: WETH -> USDC (V3) -> MORPHO (V4)
     *         Base is USDC. First hop uses WETH as input via V3.
     */
    function test_mixedV3ThenV4_wethAsInput(uint256 amount) public {
        vm.assume(amount >= minWethAmount && amount <= maxWethAmount);

        // Set base to USDC (not WETH)
        vm.prank(management);
        swapper.setBase(USDC_ADDR);

        // Set V3 fee for first hop (WETH -> USDC)
        vm.prank(management);
        swapper.setUniFees(WETH_ADDR, USDC_ADDR, V3_FEE_MID);

        // Set V4 pool for second hop (USDC -> MORPHO)
        vm.prank(management);
        swapper.setV4Pool(USDC_ADDR, address(asset), USDC_USDT_POOL_ID);

        // Airdrop WETH to swapper
        airdrop(weth, address(swapper), amount);

        // Verify initial balances
        assertEq(weth.balanceOf(address(swapper)), amount);
        assertEq(usdc.balanceOf(address(swapper)), 0);
        assertEq(asset.balanceOf(address(swapper)), 0);

        // Execute swap: WETH -> USDC -> USDT
        uint256 amountOut = swapper.swapFrom(
            WETH_ADDR,
            address(asset),
            amount,
            0
        );

        // Verify swap results
        assertEq(weth.balanceOf(address(swapper)), 0);
        assertEq(usdc.balanceOf(address(swapper)), 0);
        assertGt(asset.balanceOf(address(swapper)), 0);
        assertEq(asset.balanceOf(address(swapper)), amountOut);
    }

    /**
     * @notice Test mixed V4 then V3 with WETH as output: MORPHO -> USDC (V4) -> WETH (V3)
     *         Base is USDC. Second hop outputs WETH via V3.
     */
    function test_mixedV4ThenV3_wethAsOutput(uint256 amount) public {
        vm.assume(amount >= minMorphoAmount && amount <= maxMorphoAmount);

        // Set base to USDC (not WETH)
        vm.prank(management);
        swapper.setBase(USDC_ADDR);

        // Set V4 pool for first hop (MORPHO -> USDC)
        vm.prank(management);
        swapper.setV4Pool(address(asset), USDC_ADDR, USDC_USDT_POOL_ID);

        // Set V3 fee for second hop (USDC -> WETH)
        vm.prank(management);
        swapper.setUniFees(USDC_ADDR, WETH_ADDR, V3_FEE_MID);

        // Airdrop USDT to swapper
        airdrop(asset, address(swapper), amount);

        // Verify initial balances
        assertEq(asset.balanceOf(address(swapper)), amount);
        assertEq(usdc.balanceOf(address(swapper)), 0);
        assertEq(weth.balanceOf(address(swapper)), 0);

        // Execute swap: USDT -> USDC -> WETH
        uint256 amountOut = swapper.swapFrom(
            address(asset),
            WETH_ADDR,
            amount,
            0
        );

        // Verify swap results
        assertEq(asset.balanceOf(address(swapper)), 0);
        assertEq(usdc.balanceOf(address(swapper)), 0);
        assertGt(weth.balanceOf(address(swapper)), 0);
        assertEq(weth.balanceOf(address(swapper)), amountOut);
    }

    /**
     * @notice Test mixed V3 then V4 with WETH as output: USDT -> USDC (V3) -> WETH (V4)
     *         Base is USDC. Second hop outputs ETH via V4, needs wrapping.
     */
    function test_mixedV3ThenV4_wethAsOutput(uint256 amount) public {
        vm.assume(amount >= minFuzzAmount && amount <= maxFuzzAmount);

        // Set base to USDC (not WETH)
        vm.prank(management);
        swapper.setBase(USDC_ADDR);

        // Set V3 fee for first hop (USDT -> USDC)
        vm.prank(management);
        swapper.setUniFees(address(asset), USDC_ADDR, V3_FEE_LOW);

        // Set V4 pool for second hop (USDC -> WETH/ETH)
        vm.prank(management);
        swapper.setV4Pool(USDC_ADDR, WETH_ADDR, USDC_WETH_V4_POOL_ID);

        // Airdrop USDT to swapper
        airdrop(asset, address(swapper), amount);

        // Verify initial balances
        assertEq(asset.balanceOf(address(swapper)), amount);
        assertEq(usdc.balanceOf(address(swapper)), 0);
        assertEq(weth.balanceOf(address(swapper)), 0);

        // Execute swap: USDT -> USDC -> WETH
        uint256 amountOut = swapper.swapFrom(
            address(asset),
            WETH_ADDR,
            amount,
            0
        );

        // Verify swap results
        assertEq(asset.balanceOf(address(swapper)), 0);
        assertEq(usdc.balanceOf(address(swapper)), 0);
        assertGt(weth.balanceOf(address(swapper)), 0);
        assertEq(weth.balanceOf(address(swapper)), amountOut);
    }

    /**
     * @notice Test mixed V4 then V3 with WETH as input: WETH -> USDC (V4) -> USDT (V3)
     *         Base is USDC. First hop takes ETH via V4 (unwrap WETH first).
     */
    function test_mixedV4ThenV3_wethAsInput(uint256 amount) public {
        vm.assume(amount >= minWethAmount && amount <= maxWethAmount);

        // Set base to USDC (not WETH)
        vm.prank(management);
        swapper.setBase(USDC_ADDR);

        // Set V4 pool for first hop (WETH/ETH -> USDC)
        vm.prank(management);
        swapper.setV4Pool(WETH_ADDR, USDC_ADDR, USDC_WETH_V4_POOL_ID);

        // Set V3 fee for second hop (USDC -> USDT)
        vm.prank(management);
        swapper.setUniFees(USDC_ADDR, address(asset), V3_FEE_LOW);

        // Airdrop WETH to swapper
        airdrop(weth, address(swapper), amount);

        // Verify initial balances
        assertEq(weth.balanceOf(address(swapper)), amount);
        assertEq(usdc.balanceOf(address(swapper)), 0);
        assertEq(asset.balanceOf(address(swapper)), 0);

        // Execute swap: WETH -> USDC -> USDT
        uint256 amountOut = swapper.swapFrom(
            WETH_ADDR,
            address(asset),
            amount,
            0
        );

        // Verify swap results
        assertEq(weth.balanceOf(address(swapper)), 0);
        assertEq(usdc.balanceOf(address(swapper)), 0);
        assertGt(asset.balanceOf(address(swapper)), 0);
        assertEq(asset.balanceOf(address(swapper)), amountOut);
    }
}
