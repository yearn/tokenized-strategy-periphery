// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import "forge-std/console.sol";
import {Setup, IStrategy, SafeERC20, ERC20} from "./utils/Setup.sol";

import {IMockAuctionSwapper, MockAuctionSwapper} from "./mocks/MockAuctionSwapper.sol";
import {Auction, AuctionFactory} from "../Auctions/AuctionFactory.sol";

contract AuctionSwapperTest is Setup {
    using SafeERC20 for ERC20;

    event PreTake(address token, uint256 amountToTake, uint256 amountToPay);
    event PostTake(address token, uint256 amountTaken, uint256 amountPayed);

    event DeployedNewAuction(address indexed auction, address indexed want);

    event AuctionEnabled(address indexed from, address indexed to);

    event AuctionDisabled(address indexed from, address indexed to);

    event AuctionKicked(address indexed token, uint256 available);

    event AuctionTaken(
        address indexed token,
        uint256 amountTaken,
        uint256 amountLeft
    );

    IMockAuctionSwapper public swapper;

    Auction public auction;
    AuctionFactory public auctionFactory =
        AuctionFactory(0x4A14145C4977E18c719BB70E6FcBF8fBFF6F62d2);

    uint256 public wantScaler;
    uint256 public fromScaler;

    function setUp() public override {
        super.setUp();

        swapper = IMockAuctionSwapper(
            address(new MockAuctionSwapper(address(asset)))
        );

        vm.label(address(auctionFactory), "Auction Factory ");
        vm.label(address(swapper), "Auction Swapper");
    }

    function test_enableAuction() public {
        address from = tokenAddrs["USDC"];
        assertEq(swapper.auction(), address(0));

        swapper.enableAuction(from, address(asset));

        auction = Auction(swapper.auction());
        assertNeq(address(auction), address(0));
        assertEq(auction.kickable(from), 0);
        assertEq(auction.getAmountNeeded(from, 1e18), 0);
        assertEq(auction.price(from), 0);

        (uint64 _kicked, uint64 _scaler, uint128 _initialAvailable) = auction
            .auctions(from);

        assertEq(_kicked, 0);
        assertEq(_scaler, 1e12);
        assertEq(_initialAvailable, 0);
        assertEq(auction.available(from), 0);

        // Kicking it reverts
        vm.expectRevert("nothing to kick");
        auction.kick(from);

        // Can't re-enable
        vm.expectRevert("already enabled");
        swapper.enableAuction(from, address(asset));
    }

    function test_enableSecondAuction() public {
        address from = tokenAddrs["USDC"];
        assertEq(swapper.auction(), address(0));

        swapper.enableAuction(from, address(asset));

        auction = Auction(swapper.auction());

        assertNeq(address(auction), address(0));
        assertEq(auction.kickable(from), 0);
        assertEq(auction.getAmountNeeded(from, 1e18), 0);
        assertEq(auction.price(from), 0);

        (uint64 _kicked, uint64 _scaler, uint128 _initialAvailable) = auction
            .auctions(from);

        assertEq(_kicked, 0);
        assertEq(_scaler, 1e12);
        assertEq(_initialAvailable, 0);
        assertEq(auction.available(from), 0);

        address secondFrom = tokenAddrs["WETH"];

        vm.expectRevert("wrong want");
        swapper.enableAuction(secondFrom, from);

        vm.expectEmit(true, true, true, true, address(auction));
        emit AuctionEnabled(secondFrom, address(asset));
        swapper.enableAuction(secondFrom, address(asset));

        assertEq(swapper.auction(), address(auction));
        assertEq(auction.kickable(secondFrom), 0);
        assertEq(auction.getAmountNeeded(secondFrom, 1e18), 0);
        assertEq(auction.price(secondFrom), 0);
        (_kicked, _scaler, _initialAvailable) = auction.auctions(secondFrom);

        assertEq(_kicked, 0);
        assertEq(_scaler, 1e12);
        assertEq(_initialAvailable, 0);
        assertEq(auction.available(secondFrom), 0);
    }

    function test_disableAuction() public {
        address from = tokenAddrs["USDC"];
        assertEq(swapper.auction(), address(0));
        swapper.enableAuction(from, address(asset));

        auction = Auction(swapper.auction());

        assertNeq(address(auction), address(0));
        assertEq(auction.kickable(from), 0);
        assertEq(auction.getAmountNeeded(from, 1e18), 0);
        assertEq(auction.price(from), 0);
        (uint64 _kicked, uint64 _scaler, uint128 _initialAvailable) = auction
            .auctions(from);

        assertEq(_kicked, 0);
        assertEq(_scaler, 1e12);
        assertEq(_initialAvailable, 0);
        assertEq(auction.available(from), 0);

        vm.expectEmit(true, true, true, true, address(auction));
        emit AuctionDisabled(from, address(asset));
        swapper.disableAuction(from);

        (_kicked, _scaler, _initialAvailable) = auction.auctions(from);

        assertEq(_kicked, 0);
        assertEq(_scaler, 0);
        assertEq(_initialAvailable, 0);
        assertEq(auction.available(from), 0);
    }

    function test_kickAuction_default(uint256 _amount) public {
        vm.assume(_amount >= minFuzzAmount && _amount <= maxFuzzAmount);

        address from = tokenAddrs["WBTC"];

        fromScaler = WAD / 10 ** ERC20(from).decimals();
        wantScaler = WAD / 10 ** ERC20(asset).decimals();

        swapper.enableAuction(from, address(asset));

        auction = Auction(swapper.auction());

        assertEq(auction.kickable(from), 0);
        (uint64 _kicked, uint64 _scaler, uint128 _initialAvailable) = auction
            .auctions(from);

        assertEq(_kicked, 0);
        assertEq(_scaler, fromScaler);
        assertEq(_initialAvailable, 0);

        airdrop(ERC20(from), address(swapper), _amount);

        assertEq(auction.kickable(from), _amount);
        (, _kicked, _initialAvailable) = auction.auctions(from);
        assertEq(_kicked, 0);
        assertEq(_initialAvailable, 0);

        vm.expectEmit(true, true, true, true, address(auction));
        emit AuctionKicked(from, _amount);
        uint256 available = auction.kick(from);

        assertEq(ERC20(from).balanceOf(address(swapper)), 0);
        assertEq(ERC20(from).balanceOf(address(auction)), _amount);

        assertEq(auction.kickable(from), 0);
        (, _kicked, _initialAvailable) = auction.auctions(from);
        assertEq(_kicked, block.timestamp);
        assertEq(_initialAvailable, _amount);
        uint256 startingPrice = ((auction.startingPrice() *
            (WAD / wantScaler)) * 1e18) /
            _amount /
            fromScaler;
        assertEq(auction.price(from), startingPrice);
        assertRelApproxEq(
            auction.getAmountNeeded(from, _amount),
            (startingPrice * fromScaler * _amount) /
                (WAD / wantScaler) /
                wantScaler,
            MAX_BPS
        );

        uint256 expectedPrice = auction.price(from, block.timestamp + 100);
        assertLt(expectedPrice, startingPrice);
        uint256 expectedAmount = auction.getAmountNeeded(
            from,
            _amount,
            block.timestamp + 100
        );
        assertLt(
            expectedAmount,
            (startingPrice * fromScaler * _amount) /
                (WAD / wantScaler) /
                wantScaler
        );

        skip(100);

        assertEq(auction.price(from), expectedPrice);
        assertEq(auction.getAmountNeeded(from, _amount), expectedAmount);

        // Skip full auction
        skip(auction.auctionLength());

        assertEq(auction.price(from), 0);
        assertEq(auction.getAmountNeeded(from, _amount), 0);

        // Can't kick a new one yet
        vm.expectRevert("too soon");
        auction.kick(from);

        assertEq(auction.kickable(from), 0);
    }

    function test_takeAuction_default(uint256 _amount, uint16 _percent) public {
        vm.assume(_amount >= minFuzzAmount && _amount <= maxFuzzAmount);
        _percent = uint16(bound(uint256(_percent), 1_000, MAX_BPS));

        address from = tokenAddrs["WBTC"];

        fromScaler = WAD / 10 ** ERC20(from).decimals();
        wantScaler = WAD / 10 ** ERC20(asset).decimals();

        swapper.enableAuction(from, address(asset));

        auction = Auction(swapper.auction());

        airdrop(ERC20(from), address(swapper), _amount);

        auction.kick(from);

        assertEq(auction.kickable(from), 0);
        (uint64 _kicked, uint64 _scaler, uint128 _initialAvailable) = auction
            .auctions(from);
        assertEq(_kicked, block.timestamp);
        assertEq(_scaler, fromScaler);
        assertEq(_initialAvailable, _amount);
        assertEq(ERC20(from).balanceOf(address(swapper)), 0);
        assertEq(ERC20(from).balanceOf(address(auction)), _amount);

        skip(auction.auctionLength() / 2);

        uint256 toTake = (_amount * _percent) / MAX_BPS;
        uint256 left = _amount - toTake;
        uint256 needed = auction.getAmountNeeded(from, toTake);
        uint256 beforeAsset = ERC20(asset).balanceOf(address(this));

        airdrop(ERC20(asset), address(this), needed);

        ERC20(asset).safeApprove(address(auction), needed);

        uint256 before = ERC20(from).balanceOf(address(this));

        vm.expectEmit(true, true, true, true, address(auction));
        emit AuctionTaken(from, toTake, left);
        uint256 amountTaken = auction.take(from, toTake);

        assertEq(amountTaken, toTake);

        (, _kicked, _initialAvailable) = auction.auctions(from);
        assertEq(_initialAvailable, _amount);
        assertEq(auction.available(from), left);
        assertEq(ERC20(asset).balanceOf(address(this)), beforeAsset);
        assertEq(ERC20(from).balanceOf(address(this)), before + toTake);
        assertEq(ERC20(from).balanceOf(address(auction)), left);
        assertEq(ERC20(asset).balanceOf(address(swapper)), needed);
        assertEq(ERC20(asset).balanceOf(address(auction)), 0);
        assertEq(ERC20(from).balanceOf(address(swapper)), 0);
    }

    function test_kickAuction_custom(uint256 _amount) public {
        vm.assume(_amount >= minFuzzAmount && _amount <= maxFuzzAmount);

        address from = tokenAddrs["WBTC"];

        fromScaler = WAD / 10 ** ERC20(from).decimals();
        wantScaler = WAD / 10 ** ERC20(asset).decimals();

        swapper.enableAuction(from, address(asset));

        auction = Auction(swapper.auction());

        assertEq(auction.kickable(from), 0);
        (uint64 _kicked, uint64 _scaler, uint128 _initialAvailable) = auction
            .auctions(from);

        assertEq(_kicked, 0);
        assertEq(_scaler, fromScaler);
        assertEq(_initialAvailable, 0);

        airdrop(ERC20(from), address(swapper), _amount);

        swapper.setUseDefault(false);

        assertEq(auction.kickable(from), 0);

        uint256 kickable = _amount / 10;
        swapper.setLetKick(kickable);

        assertEq(auction.kickable(from), kickable);
        (, _kicked, _initialAvailable) = auction.auctions(from);
        assertEq(_kicked, 0);
        assertEq(_initialAvailable, 0);

        vm.expectEmit(true, true, true, true, address(auction));
        emit AuctionKicked(from, kickable);
        uint256 available = auction.kick(from);

        assertEq(ERC20(from).balanceOf(address(swapper)), _amount - kickable);
        assertEq(ERC20(from).balanceOf(address(auction)), kickable);

        assertEq(auction.kickable(from), 0);
        (, _kicked, _initialAvailable) = auction.auctions(from);
        assertEq(_kicked, block.timestamp);
        assertEq(_initialAvailable, kickable);
        uint256 startingPrice = ((auction.startingPrice() *
            (WAD / wantScaler)) * 1e18) /
            kickable /
            fromScaler;
        assertEq(auction.price(from), startingPrice);
        assertRelApproxEq(
            auction.getAmountNeeded(from, kickable),
            (startingPrice * fromScaler * kickable) /
                (WAD / wantScaler) /
                wantScaler,
            MAX_BPS
        );

        uint256 expectedPrice = auction.price(from, block.timestamp + 100);
        assertLt(expectedPrice, startingPrice);
        uint256 expectedAmount = auction.getAmountNeeded(
            from,
            kickable,
            block.timestamp + 100
        );
        assertLt(
            expectedAmount,
            (startingPrice * fromScaler * kickable) /
                (WAD / wantScaler) /
                wantScaler
        );

        skip(100);

        assertEq(auction.price(from), expectedPrice);
        assertEq(auction.getAmountNeeded(from, kickable), expectedAmount);

        // Skip full auction
        skip(auction.auctionLength());

        assertEq(auction.price(from), 0);
        assertEq(auction.getAmountNeeded(from, kickable), 0);

        // Can't kick a new one yet
        vm.expectRevert("too soon");
        auction.kick(from);

        assertEq(auction.kickable(from), 0);
    }

    function test_takeAuction_custom(uint256 _amount, uint16 _percent) public {
        vm.assume(_amount >= minFuzzAmount && _amount <= maxFuzzAmount);
        _percent = uint16(bound(uint256(_percent), 1_000, MAX_BPS));

        address from = tokenAddrs["WBTC"];

        fromScaler = WAD / 10 ** ERC20(from).decimals();
        wantScaler = WAD / 10 ** ERC20(asset).decimals();

        swapper.enableAuction(from, address(asset));

        auction = Auction(swapper.auction());

        airdrop(ERC20(from), address(swapper), _amount);

        swapper.setUseDefault(false);

        assertEq(auction.kickable(from), 0);

        uint256 kickable = _amount / 10;
        swapper.setLetKick(kickable);

        auction.kick(from);

        assertEq(auction.kickable(from), 0);
        (uint64 _kicked, uint64 _scaler, uint128 _initialAvailable) = auction
            .auctions(from);

        assertEq(_kicked, block.timestamp);
        assertEq(_scaler, fromScaler);
        assertEq(_initialAvailable, kickable);
        assertEq(ERC20(from).balanceOf(address(swapper)), _amount - kickable);
        assertEq(ERC20(from).balanceOf(address(auction)), kickable);

        skip(auction.auctionLength() / 2);

        uint256 toTake = (kickable * _percent) / MAX_BPS;
        uint256 left = kickable - toTake;
        uint256 needed = auction.getAmountNeeded(from, toTake);
        uint256 beforeAsset = ERC20(asset).balanceOf(address(this));

        airdrop(ERC20(asset), address(this), needed);

        ERC20(asset).safeApprove(address(auction), needed);

        uint256 before = ERC20(from).balanceOf(address(this));

        vm.expectEmit(true, true, true, true, address(swapper));
        emit PreTake(from, toTake, needed);
        vm.expectEmit(true, true, true, true, address(swapper));
        emit PostTake(address(asset), toTake, needed);
        uint256 amountTaken = auction.take(from, toTake);

        assertEq(amountTaken, toTake);

        (, _kicked, _initialAvailable) = auction.auctions(from);
        assertEq(_initialAvailable, _amount);
        assertEq(auction.available(from), left);
        assertEq(ERC20(asset).balanceOf(address(this)), beforeAsset);
        assertEq(ERC20(from).balanceOf(address(this)), before + toTake);
        assertEq(ERC20(from).balanceOf(address(auction)), left);
        assertEq(ERC20(asset).balanceOf(address(swapper)), needed);
        assertEq(ERC20(asset).balanceOf(address(auction)), 0);
    }
}
