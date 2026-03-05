// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import {Setup, ERC20} from "./utils/Setup.sol";

import {IFluidDexT1} from "../interfaces/Fluid/IFluidDexV2Router.sol";
import {MockFluidSwapper, IMockFluidSwapper} from "./mocks/MockFluidSwapper.sol";

contract FluidSwapperTest is Setup {
    IMockFluidSwapper public fluidSwapper;

    ERC20 public base;
    ERC20 public swapTo;

    // Mainnet Fluid USDC/USDT dex deployment.
    address internal constant DEX_USDC_USDT =
        0x667701e51B4D1Ca244F17C78F7aB8744B4C99F9B;
    // Mainnet Fluid USDC/GHO dex deployment.
    address internal constant DEX_USDC_GHO =
        0xdE632C3a214D5f14C1d8ddF0b92F8BCd188fee45;
    // GHO token.
    address internal constant GHO = 0x40D16FC0246aD3160Ccc09B8D0D3A2cD28aE6C2f;

    // USDT (asset) fuzz bounds
    uint256 public minUsdtAmount = 1e6;
    uint256 public maxUsdtAmount = 1e10;

    // USDC (base) fuzz bounds
    uint256 public minUsdcAmount = 1e6;
    uint256 public maxUsdcAmount = 1e10;

    function setUp() public override {
        super.setUp();

        base = ERC20(tokenAddrs["USDC"]);
        swapTo = ERC20(GHO);

        fluidSwapper = IMockFluidSwapper(
            address(new MockFluidSwapper(address(asset)))
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
            DEX_USDC_GHO,
            false
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

    function test_badBase_reverts(uint256 amount) public {
        vm.assume(amount >= minUsdtAmount && amount <= maxUsdtAmount);

        vm.prank(management);
        fluidSwapper.setBase(management);

        assertEq(fluidSwapper.base(), management);

        airdrop(asset, address(fluidSwapper), amount);

        vm.expectRevert("dex not set");
        fluidSwapper.swapFrom(address(asset), address(swapTo), amount, 0);
    }
}
