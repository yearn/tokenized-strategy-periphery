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

    event AuctionEnabled(
        bytes32 auctionId,
        address indexed from,
        address indexed to,
        address indexed strategy
    );

    event AuctionDisabled(
        bytes32 auctionId,
        address indexed from,
        address indexed to,
        address indexed strategy
    );

    event AuctionKicked(bytes32 auctionId, uint256 available);

    event AuctionTaken(
        bytes32 auctionId,
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

        bytes32 id = swapper.enableAuction(from, address(asset));

        auction = Auction(swapper.auction());
        assertNeq(address(auction), address(0));
        assertEq(auction.kickable(id), 0);
        assertEq(auction.getAmountNeeded(id, 1e18), 0);
        assertEq(auction.price(id), 0);
        (
            address _from,
            address _to,
            uint256 _kicked,
            uint256 _available
        ) = auction.auctionInfo(id);

        assertEq(_from, from);
        assertEq(_to, address(asset));
        assertEq(_kicked, 0);
        assertEq(_available, 0);
        assertEq(auction.hook(), address(swapper));
        (bool hook1, bool hook2, bool hook3, bool hook4) = auction
            .getHookFlags();
        assertTrue(hook1);
        assertTrue(hook2);
        assertTrue(hook3);
        assertTrue(hook4);

        // Kicking it reverts
        vm.expectRevert("nothing to kick");
        auction.kick(id);

        // Can't re-enable
        vm.expectRevert("already enabled");
        swapper.enableAuction(from, address(asset));
    }

    function test_enableSecondAuction() public {
        address from = tokenAddrs["USDC"];
        assertEq(swapper.auction(), address(0));

        bytes32 id = swapper.enableAuction(from, address(asset));

        auction = Auction(swapper.auction());

        assertNeq(address(auction), address(0));
        assertEq(auction.kickable(id), 0);
        assertEq(auction.getAmountNeeded(id, 1e18), 0);
        assertEq(auction.price(id), 0);
        (
            address _from,
            address _to,
            uint256 _kicked,
            uint256 _available
        ) = auction.auctionInfo(id);

        assertEq(_from, from);
        assertEq(_to, address(asset));
        assertEq(_kicked, 0);
        assertEq(_available, 0);

        address secondFrom = tokenAddrs["WETH"];

        vm.expectRevert("wrong want");
        swapper.enableAuction(secondFrom, from);

        bytes32 expectedId = auction.getAuctionId(secondFrom);

        vm.expectEmit(true, true, true, true, address(auction));
        emit AuctionEnabled(
            expectedId,
            secondFrom,
            address(asset),
            address(auction)
        );
        bytes32 secondId = swapper.enableAuction(secondFrom, address(asset));

        assertEq(expectedId, secondId);
        assertEq(swapper.auction(), address(auction));
        assertEq(auction.kickable(secondId), 0);
        assertEq(auction.getAmountNeeded(secondId, 1e18), 0);
        assertEq(auction.price(secondId), 0);
        (_from, _to, _kicked, _available) = auction.auctionInfo(secondId);

        assertEq(_from, secondFrom);
        assertEq(_to, address(asset));
        assertEq(_kicked, 0);
        assertEq(_available, 0);
    }

    function test_disableAuction() public {
        address from = tokenAddrs["USDC"];
        assertEq(swapper.auction(), address(0));

        bytes32 id = swapper.enableAuction(from, address(asset));

        auction = Auction(swapper.auction());

        assertNeq(address(auction), address(0));
        assertEq(auction.kickable(id), 0);
        assertEq(auction.getAmountNeeded(id, 1e18), 0);
        assertEq(auction.price(id), 0);
        (
            address _from,
            address _to,
            uint256 _kicked,
            uint256 _available
        ) = auction.auctionInfo(id);

        assertEq(_from, from);
        assertEq(_to, address(asset));
        assertEq(_kicked, 0);
        assertEq(_available, 0);

        vm.expectEmit(true, true, true, true, address(auction));
        emit AuctionDisabled(id, from, address(asset), address(auction));
        swapper.disableAuction(from);

        (_from, _to, _kicked, _available) = auction.auctionInfo(id);

        assertEq(_from, address(0));
        assertEq(_to, address(asset));
        assertEq(_kicked, 0);
        assertEq(_available, 0);
    }

    function test_kickAuction_default(uint256 _amount) public {
        vm.assume(_amount >= minFuzzAmount && _amount <= maxFuzzAmount);

        address from = tokenAddrs["WBTC"];

        fromScaler = WAD / 10 ** ERC20(from).decimals();
        wantScaler = WAD / 10 ** ERC20(asset).decimals();

        bytes32 id = swapper.enableAuction(from, address(asset));

        auction = Auction(swapper.auction());

        assertEq(auction.kickable(id), 0);
        (
            address _from,
            address _to,
            uint256 _kicked,
            uint256 _available
        ) = auction.auctionInfo(id);

        assertEq(_from, from);
        assertEq(_to, address(asset));
        assertEq(_kicked, 0);
        assertEq(_available, 0);

        airdrop(ERC20(from), address(swapper), _amount);

        assertEq(auction.kickable(id), _amount);
        (, , _kicked, _available) = auction.auctionInfo(id);
        assertEq(_kicked, 0);
        assertEq(_available, 0);

        vm.expectEmit(true, true, true, true, address(auction));
        emit AuctionKicked(id, _amount);
        uint256 available = auction.kick(id);

        assertEq(ERC20(from).balanceOf(address(swapper)), 0);
        assertEq(ERC20(from).balanceOf(address(auction)), _amount);

        assertEq(auction.kickable(id), 0);
        (, , _kicked, _available) = auction.auctionInfo(id);
        assertEq(_kicked, block.timestamp);
        assertEq(_available, _amount);
        uint256 startingPrice = ((auction.startingPrice() *
            (WAD / wantScaler)) * 1e18) /
            _amount /
            fromScaler;
        assertEq(auction.price(id), startingPrice);
        assertRelApproxEq(
            auction.getAmountNeeded(id, _amount),
            (startingPrice * fromScaler * _amount) /
                (WAD / wantScaler) /
                wantScaler,
            MAX_BPS
        );

        uint256 expectedPrice = auction.price(id, block.timestamp + 100);
        assertLt(expectedPrice, startingPrice);
        uint256 expectedAmount = auction.getAmountNeeded(
            id,
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

        assertEq(auction.price(id), expectedPrice);
        assertEq(auction.getAmountNeeded(id, _amount), expectedAmount);

        // Skip full auction
        skip(auction.auctionLength());

        assertEq(auction.price(id), 0);
        assertEq(auction.getAmountNeeded(id, _amount), 0);

        // Can't kick a new one yet
        vm.expectRevert("too soon");
        auction.kick(id);

        assertEq(auction.kickable(id), 0);
    }

    function test_takeAuction_default(uint256 _amount, uint16 _percent) public {
        vm.assume(_amount >= minFuzzAmount && _amount <= maxFuzzAmount);
        _percent = uint16(bound(uint256(_percent), 1_000, MAX_BPS));

        address from = tokenAddrs["WBTC"];

        fromScaler = WAD / 10 ** ERC20(from).decimals();
        wantScaler = WAD / 10 ** ERC20(asset).decimals();

        bytes32 id = swapper.enableAuction(from, address(asset));

        auction = Auction(swapper.auction());

        airdrop(ERC20(from), address(swapper), _amount);

        auction.kick(id);

        assertEq(auction.kickable(id), 0);
        (
            address _from,
            address _to,
            uint256 _kicked,
            uint256 _available
        ) = auction.auctionInfo(id);
        assertEq(_from, from);
        assertEq(_to, address(asset));
        assertEq(_kicked, block.timestamp);
        assertEq(_available, _amount);
        assertEq(ERC20(from).balanceOf(address(swapper)), 0);
        assertEq(ERC20(from).balanceOf(address(auction)), _amount);

        skip(auction.auctionLength() / 2);

        uint256 toTake = (_amount * _percent) / MAX_BPS;
        uint256 left = _amount - toTake;
        uint256 needed = auction.getAmountNeeded(id, toTake);

        airdrop(ERC20(asset), address(this), needed);

        ERC20(asset).safeApprove(address(auction), needed);

        uint256 before = ERC20(from).balanceOf(address(this));

        vm.expectEmit(true, true, true, true, address(auction));
        emit AuctionTaken(id, toTake, left);
        uint256 amountTaken = auction.take(id, toTake);

        assertEq(amountTaken, toTake);

        (, , , _available) = auction.auctionInfo(id);
        assertEq(_available, left);
        assertEq(ERC20(asset).balanceOf(address(this)), 0);
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

        bytes32 id = swapper.enableAuction(from, address(asset));

        auction = Auction(swapper.auction());

        assertEq(auction.kickable(id), 0);
        (
            address _from,
            address _to,
            uint256 _kicked,
            uint256 _available
        ) = auction.auctionInfo(id);

        assertEq(_from, from);
        assertEq(_to, address(asset));
        assertEq(_kicked, 0);
        assertEq(_available, 0);

        airdrop(ERC20(from), address(swapper), _amount);

        swapper.setUseDefault(false);

        assertEq(auction.kickable(id), 0);

        uint256 kickable = _amount / 10;
        swapper.setLetKick(kickable);

        assertEq(auction.kickable(id), kickable);
        (, , _kicked, _available) = auction.auctionInfo(id);
        assertEq(_kicked, 0);
        assertEq(_available, 0);

        vm.expectEmit(true, true, true, true, address(auction));
        emit AuctionKicked(id, kickable);
        uint256 available = auction.kick(id);

        assertEq(ERC20(from).balanceOf(address(swapper)), _amount - kickable);
        assertEq(ERC20(from).balanceOf(address(auction)), kickable);

        assertEq(auction.kickable(id), 0);
        (, , _kicked, _available) = auction.auctionInfo(id);
        assertEq(_kicked, block.timestamp);
        assertEq(_available, kickable);
        uint256 startingPrice = ((auction.startingPrice() *
            (WAD / wantScaler)) * 1e18) /
            kickable /
            fromScaler;
        assertEq(auction.price(id), startingPrice);
        assertRelApproxEq(
            auction.getAmountNeeded(id, kickable),
            (startingPrice * fromScaler * kickable) /
                (WAD / wantScaler) /
                wantScaler,
            MAX_BPS
        );

        uint256 expectedPrice = auction.price(id, block.timestamp + 100);
        assertLt(expectedPrice, startingPrice);
        uint256 expectedAmount = auction.getAmountNeeded(
            id,
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

        assertEq(auction.price(id), expectedPrice);
        assertEq(auction.getAmountNeeded(id, kickable), expectedAmount);

        // Skip full auction
        skip(auction.auctionLength());

        assertEq(auction.price(id), 0);
        assertEq(auction.getAmountNeeded(id, kickable), 0);

        // Can't kick a new one yet
        vm.expectRevert("too soon");
        auction.kick(id);

        assertEq(auction.kickable(id), 0);
    }

    function test_takeAuction_custom(uint256 _amount, uint16 _percent) public {
        vm.assume(_amount >= minFuzzAmount && _amount <= maxFuzzAmount);
        _percent = uint16(bound(uint256(_percent), 1_000, MAX_BPS));

        address from = tokenAddrs["WBTC"];

        fromScaler = WAD / 10 ** ERC20(from).decimals();
        wantScaler = WAD / 10 ** ERC20(asset).decimals();

        bytes32 id = swapper.enableAuction(from, address(asset));

        auction = Auction(swapper.auction());

        airdrop(ERC20(from), address(swapper), _amount);

        swapper.setUseDefault(false);

        assertEq(auction.kickable(id), 0);

        uint256 kickable = _amount / 10;
        swapper.setLetKick(kickable);

        auction.kick(id);

        assertEq(auction.kickable(id), 0);
        (
            address _from,
            address _to,
            uint256 _kicked,
            uint256 _available
        ) = auction.auctionInfo(id);
        assertEq(_from, from);
        assertEq(_to, address(asset));
        assertEq(_kicked, block.timestamp);
        assertEq(_available, kickable);
        assertEq(ERC20(from).balanceOf(address(swapper)), _amount - kickable);
        assertEq(ERC20(from).balanceOf(address(auction)), kickable);

        skip(auction.auctionLength() / 2);

        uint256 toTake = (kickable * _percent) / MAX_BPS;
        uint256 left = kickable - toTake;
        uint256 needed = auction.getAmountNeeded(id, toTake);

        airdrop(ERC20(asset), address(this), needed);

        ERC20(asset).safeApprove(address(auction), needed);

        uint256 before = ERC20(from).balanceOf(address(this));

        vm.expectEmit(true, true, true, true, address(swapper));
        emit PreTake(from, toTake, needed);
        vm.expectEmit(true, true, true, true, address(swapper));
        emit PostTake(address(asset), toTake, needed);
        uint256 amountTaken = auction.take(id, toTake);

        assertEq(amountTaken, toTake);

        (, , , _available) = auction.auctionInfo(id);
        assertEq(_available, left);
        assertEq(ERC20(asset).balanceOf(address(this)), 0);
        assertEq(ERC20(from).balanceOf(address(this)), before + toTake);
        assertEq(ERC20(from).balanceOf(address(auction)), left);
        assertEq(ERC20(asset).balanceOf(address(swapper)), needed);
        assertEq(ERC20(asset).balanceOf(address(auction)), 0);
    }

    function test_setFlags(uint256 _amount, uint16 _percent) public {
        vm.assume(_amount >= minFuzzAmount && _amount <= maxFuzzAmount);
        _percent = uint16(bound(uint256(_percent), 1_000, MAX_BPS));

        address from = tokenAddrs["WBTC"];

        fromScaler = WAD / 10 ** ERC20(from).decimals();
        wantScaler = WAD / 10 ** ERC20(asset).decimals();

        bytes32 id = swapper.enableAuction(from, address(asset));

        auction = Auction(swapper.auction());

        airdrop(ERC20(from), address(swapper), _amount);

        assertEq(auction.kickable(id), _amount);

        vm.prank(address(swapper));
        auction.setHookFlags(false, false, true, true);

        assertEq(auction.kickable(id), 0);

        vm.expectRevert("nothing to kick");
        auction.kick(id);

        vm.prank(address(swapper));
        auction.setHookFlags(false, true, true, true);

        auction.kick(id);

        assertEq(ERC20(from).balanceOf(address(auction)), _amount);

        swapper.setShouldRevert(true);

        skip(auction.auctionLength() / 2);

        uint256 toTake = (_amount * _percent) / MAX_BPS;
        uint256 left = _amount - toTake;
        uint256 needed = auction.getAmountNeeded(id, toTake);

        airdrop(ERC20(asset), address(this), needed);

        ERC20(asset).safeApprove(address(auction), needed);

        vm.expectRevert("pre take revert");
        auction.take(id, toTake);

        vm.prank(address(swapper));
        auction.setHookFlags(false, true, false, true);

        vm.expectRevert("post take revert");
        auction.take(id, toTake);

        vm.prank(address(swapper));
        auction.setHookFlags(false, true, false, false);

        auction.take(id, toTake);
    }
}
