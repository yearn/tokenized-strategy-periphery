// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import {Setup, ERC20} from "./utils/Setup.sol";

import {IFluidDexT1} from "../interfaces/Fluid/IFluidDexV2Router.sol";
import {MockFluidSwapper, IMockFluidSwapper} from "./mocks/MockFluidSwapper.sol";

contract FluidSwapperTest is Setup {
    IMockFluidSwapper public fluidSwapper;

    ERC20 public base;
    ERC20 public weth;
    ERC20 public swapTo;

    // Mainnet Fluid USDC/USDT dex deployment.
    address internal constant DEX_USDC_USDT =
        0x667701e51B4D1Ca244F17C78F7aB8744B4C99F9B;
    // Mainnet Fluid fxUSD/USDC dex deployment.
    address internal constant DEX_FXUSD_USDC =
        0x0C88C9713520E9546252B09E57fAa46e9854743A;
    // fxUSD token.
    address internal constant FXUSD =
        0x085780639CC2cACd35E474e71f4d000e2405d8f6;

    // USDT (asset) fuzz bounds
    uint256 public minUsdtAmount = 1e6;
    uint256 public maxUsdtAmount = 1e10;

    // USDC (base) fuzz bounds
    uint256 public minUsdcAmount = 1e6;
    uint256 public maxUsdcAmount = 1e10;

    function setUp() public override {
        super.setUp();

        base = ERC20(tokenAddrs["USDC"]);
        weth = ERC20(tokenAddrs["WETH"]);
        swapTo = ERC20(FXUSD);

        fluidSwapper = IMockFluidSwapper(
            address(new MockFluidSwapper(address(asset), address(weth)))
        );

        fluidSwapper.setKeeper(keeper);
        fluidSwapper.setPerformanceFeeRecipient(performanceFeeRecipient);
        fluidSwapper.setPendingManagement(management);

        vm.prank(management);
        fluidSwapper.acceptManagement();

        vm.prank(management);
        fluidSwapper.setBase(address(base));

        vm.prank(management);
        fluidSwapper.setFluidDex(address(base), address(asset), DEX_USDC_USDT);
        vm.prank(management);
        fluidSwapper.setFluidDex(
            address(base),
            address(swapTo),
            DEX_FXUSD_USDC
        );
    }

    function test_setFluidDex_autoDetectsSwapDirection() public {
        IFluidDexT1.ConstantViews memory constants = IFluidDexT1(DEX_USDC_USDT)
            .constantsView();

        (address baseToAssetDex, bool baseToAssetDirection) = fluidSwapper
            .fluidDexes(address(base), address(asset));
        (address assetToBaseDex, bool assetToBaseDirection) = fluidSwapper
            .fluidDexes(address(asset), address(base));

        bool expectedBaseToAssetDirection = constants.token0 == address(base) &&
            constants.token1 == address(asset);

        assertEq(baseToAssetDex, DEX_USDC_USDT);
        assertEq(assetToBaseDex, DEX_USDC_USDT);
        assertEq(baseToAssetDirection, expectedBaseToAssetDirection);
        assertEq(assetToBaseDirection, !expectedBaseToAssetDirection);
    }

    function test_setFluidDex_revertsOnDexMismatch() public {
        vm.prank(management);
        vm.expectRevert("dex mismatch");
        fluidSwapper.setFluidDex(
            address(asset),
            tokenAddrs["WETH"],
            DEX_USDC_USDT
        );
    }

    function test_swapFrom_assetToBase(uint256 amount) public {
        vm.assume(amount >= minUsdtAmount && amount <= maxUsdtAmount);

        airdrop(asset, address(fluidSwapper), amount);

        assertEq(asset.balanceOf(address(fluidSwapper)), amount);
        assertEq(base.balanceOf(address(fluidSwapper)), 0);

        uint256 amountOut = fluidSwapper.swapFrom(
            address(asset),
            address(base),
            amount,
            0
        );

        assertEq(asset.balanceOf(address(fluidSwapper)), 0);
        assertGt(base.balanceOf(address(fluidSwapper)), 0);
        assertEq(base.balanceOf(address(fluidSwapper)), amountOut);
    }

    function test_swapFrom_baseToAsset(uint256 amount) public {
        vm.assume(amount >= minUsdcAmount && amount <= maxUsdcAmount);

        airdrop(base, address(fluidSwapper), amount);

        assertEq(base.balanceOf(address(fluidSwapper)), amount);
        assertEq(asset.balanceOf(address(fluidSwapper)), 0);

        uint256 amountOut = fluidSwapper.swapFrom(
            address(base),
            address(asset),
            amount,
            0
        );

        assertEq(base.balanceOf(address(fluidSwapper)), 0);
        assertGt(asset.balanceOf(address(fluidSwapper)), 0);
        assertEq(asset.balanceOf(address(fluidSwapper)), amountOut);
    }

    function test_swapFrom_minOutReverts(uint256 amount) public {
        vm.assume(amount >= minUsdtAmount && amount <= maxUsdtAmount);

        airdrop(asset, address(fluidSwapper), amount);

        assertEq(asset.balanceOf(address(fluidSwapper)), amount);
        assertEq(base.balanceOf(address(fluidSwapper)), 0);

        vm.expectRevert();
        fluidSwapper.swapFrom(
            address(asset),
            address(base),
            amount,
            type(uint256).max
        );

        assertEq(asset.balanceOf(address(fluidSwapper)), amount);
        assertEq(base.balanceOf(address(fluidSwapper)), 0);
    }

    function test_swapFrom_missingDexReverts(uint256 amount) public {
        vm.assume(amount >= minUsdtAmount && amount <= maxUsdtAmount);

        airdrop(asset, address(fluidSwapper), amount);

        vm.expectRevert("dex not set");
        fluidSwapper.swapFrom(address(asset), tokenAddrs["WETH"], amount, 0);
    }

    function test_swapFrom_respectsMinAmountToSell(uint256 amount) public {
        vm.assume(amount >= minUsdtAmount && amount <= maxUsdtAmount);

        vm.prank(management);
        fluidSwapper.setMinAmountToSell(amount + 1);

        airdrop(asset, address(fluidSwapper), amount);

        uint256 amountOut = fluidSwapper.swapFrom(
            address(asset),
            address(base),
            amount,
            0
        );

        assertEq(amountOut, 0);
        assertEq(asset.balanceOf(address(fluidSwapper)), amount);
        assertEq(base.balanceOf(address(fluidSwapper)), 0);
    }

    function test_swapFrom_multiHop_assetToSwapTo() public {
        uint256 amount = 1e8;

        airdrop(asset, address(fluidSwapper), amount);

        uint256 amountOut = fluidSwapper.swapFrom(
            address(asset),
            address(swapTo),
            amount,
            0
        );

        assertEq(asset.balanceOf(address(fluidSwapper)), 0);
        assertEq(base.balanceOf(address(fluidSwapper)), 0);
        assertGt(swapTo.balanceOf(address(fluidSwapper)), 0);
        assertEq(swapTo.balanceOf(address(fluidSwapper)), amountOut);
    }

    function test_swapFrom_multiHop_swapToToAsset() public {
        uint256 amount = 100e18; // fxUSD has 18 decimals

        airdrop(swapTo, address(fluidSwapper), amount);

        uint256 amountOut = fluidSwapper.swapFrom(
            address(swapTo),
            address(asset),
            amount,
            0
        );

        assertEq(swapTo.balanceOf(address(fluidSwapper)), 0);
        assertEq(base.balanceOf(address(fluidSwapper)), 0);
        assertGt(asset.balanceOf(address(fluidSwapper)), 0);
        assertEq(asset.balanceOf(address(fluidSwapper)), amountOut);
    }

    function test_badBase_reverts(uint256 amount) public {
        vm.assume(amount >= minUsdtAmount && amount <= maxUsdtAmount);

        vm.prank(management);
        fluidSwapper.setBase(management);

        assertEq(fluidSwapper.base(), management);

        airdrop(asset, address(fluidSwapper), amount);

        vm.expectRevert("dex not set");
        fluidSwapper.swapFrom(address(asset), address(swapTo), amount, 0);
    }

    // -----------------------------------------------------------------------
    //  WETH / native-ETH tests
    // -----------------------------------------------------------------------

    // Mainnet Fluid USDC/ETH dex (Dex 12). token0=USDC, token1=native ETH
    address internal constant DEX_USDC_ETH =
        0x836951EB21F3Df98273517B7249dCEFF270d34bf;
    // Mainnet Fluid wstETH/ETH dex (Dex 1). token0=wstETH, token1=native ETH
    address internal constant DEX_WSTETH_ETH =
        0x0B1a513ee24972DAEf112bC777a5610d4325C9e7;

    address internal constant WSTETH =
        0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;

    /// @dev Reset base to WETH and register native-ETH dexes on the existing instance.
    function _setupWethBase() internal {
        vm.prank(management);
        fluidSwapper.setBase(address(weth));

        vm.prank(management);
        fluidSwapper.setFluidDex(address(base), address(weth), DEX_USDC_ETH);
        vm.prank(management);
        fluidSwapper.setFluidDex(address(weth), WSTETH, DEX_WSTETH_ETH);
    }

    function test_swapFrom_weth_assetToBase() public {
        _setupWethBase();
        uint256 amount = 1_000e6; // 1 000 USDC

        airdrop(base, address(fluidSwapper), amount);

        uint256 amountOut = fluidSwapper.swapFrom(
            address(base),
            address(weth),
            amount,
            0
        );

        assertEq(base.balanceOf(address(fluidSwapper)), 0);
        assertGt(weth.balanceOf(address(fluidSwapper)), 0);
        assertEq(weth.balanceOf(address(fluidSwapper)), amountOut);
        assertEq(address(fluidSwapper).balance, 0);
    }

    function test_swapFrom_weth_baseToAsset() public {
        _setupWethBase();
        uint256 amount = 0.5 ether;

        airdrop(weth, address(fluidSwapper), amount);

        uint256 amountOut = fluidSwapper.swapFrom(
            address(weth),
            address(base),
            amount,
            0
        );

        assertEq(weth.balanceOf(address(fluidSwapper)), 0);
        assertGt(base.balanceOf(address(fluidSwapper)), 0);
        assertEq(base.balanceOf(address(fluidSwapper)), amountOut);
        assertEq(address(fluidSwapper).balance, 0);
    }

    function test_swapFrom_weth_multiHop_assetToSwapTo() public {
        _setupWethBase();
        uint256 amount = 1_000e6; // USDC

        airdrop(base, address(fluidSwapper), amount);

        uint256 amountOut = fluidSwapper.swapFrom(
            address(base),
            WSTETH,
            amount,
            0
        );

        assertEq(base.balanceOf(address(fluidSwapper)), 0);
        assertEq(weth.balanceOf(address(fluidSwapper)), 0);
        assertGt(ERC20(WSTETH).balanceOf(address(fluidSwapper)), 0);
        assertEq(ERC20(WSTETH).balanceOf(address(fluidSwapper)), amountOut);
        assertEq(address(fluidSwapper).balance, 0);
    }

    function test_swapFrom_weth_multiHop_swapToToAsset() public {
        _setupWethBase();
        uint256 amount = 1e18; // 1 wstETH

        airdrop(ERC20(WSTETH), address(fluidSwapper), amount);

        uint256 amountOut = fluidSwapper.swapFrom(
            WSTETH,
            address(base),
            amount,
            0
        );

        assertEq(ERC20(WSTETH).balanceOf(address(fluidSwapper)), 0);
        assertEq(weth.balanceOf(address(fluidSwapper)), 0);
        assertGt(base.balanceOf(address(fluidSwapper)), 0);
        assertEq(base.balanceOf(address(fluidSwapper)), amountOut);
        assertEq(address(fluidSwapper).balance, 0);
    }

    function test_setFluidDex_weth_normalizesNativeEth() public {
        _setupWethBase();

        // Verify dex mapping uses WETH (not native ETH) as the key
        (address dex, ) = fluidSwapper.fluidDexes(address(base), address(weth));
        assertEq(dex, DEX_USDC_ETH);
    }
}
