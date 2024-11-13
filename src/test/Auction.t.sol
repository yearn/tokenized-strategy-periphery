// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import "forge-std/console.sol";
import {Setup, IStrategy, SafeERC20, ERC20} from "./utils/Setup.sol";

import {ITaker} from "../interfaces/ITaker.sol";
import {Auction, AuctionFactory} from "../Auctions/AuctionFactory.sol";

contract AuctionTest is Setup, ITaker {
    using SafeERC20 for ERC20;

    event AuctionEnabled(address indexed from, address indexed to);

    event AuctionDisabled(address indexed from, address indexed to);

    event AuctionKicked(address indexed from, uint256 available);

    event Callback(
        address indexed from,
        address _sender,
        uint256 _amountTaken,
        uint256 _amountNeeded,
        bytes _data
    );

    Auction public auction;
    AuctionFactory public auctionFactory;

    uint256 public wantScaler;
    uint256 public fromScaler;

    bool public callbackHit;

    function setUp() public override {
        super.setUp();

        auctionFactory = new AuctionFactory();
    }

    function test_setup() public {
        assertEq(auctionFactory.DEFAULT_AUCTION_LENGTH(), 1 days);
        assertEq(auctionFactory.DEFAULT_STARTING_PRICE(), 1e6);
    }

    function test_defaults() public {
        auction = Auction(auctionFactory.createNewAuction(address(asset)));

        vm.expectRevert("initialized");
        auction.initialize(address(asset), address(this), management, 1, 10);

        assertEq(auction.want(), address(asset));
        assertEq(auction.receiver(), address(this));
        assertEq(auction.governance(), address(this));
        assertEq(
            auction.auctionLength(),
            auctionFactory.DEFAULT_AUCTION_LENGTH()
        );
        assertEq(
            auction.startingPrice(),
            auctionFactory.DEFAULT_STARTING_PRICE()
        );
    }

    function test_enableAuction() public {
        address from = tokenAddrs["USDC"];
        auction = Auction(auctionFactory.createNewAuction(address(asset)));

        vm.expectRevert("!governance");
        vm.prank(management);
        auction.enable(from);

        vm.expectEmit(true, true, true, true, address(auction));
        emit AuctionEnabled(from, address(asset));

        auction.enable(from);

        assertEq(auction.getAllEnabledAuctions().length, 1);
        assertEq(auction.enabledAuctions(0), from);
        assertEq(auction.kickable(from), 0);
        assertEq(auction.getAmountNeeded(from, 1e18), 0);
        assertEq(auction.price(from), 0);
        assertEq(auction.receiver(), address(this));

        (uint128 _kicked, uint128 _scaler, uint128 _initialAvailable) = auction
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
        auction.enable(from);
    }

    function test_disableAuction() public {
        address from = tokenAddrs["USDC"];
        auction = Auction(auctionFactory.createNewAuction(address(asset)));

        vm.expectRevert("not enabled");
        auction.disable(from);

        auction.enable(from);

        assertEq(auction.getAllEnabledAuctions().length, 1);

        (uint128 _kicked, uint128 _scaler, uint128 _initialAvailable) = auction
            .auctions(from);

        assertEq(_kicked, 0);
        assertEq(_scaler, 1e12);
        assertEq(_initialAvailable, 0);
        assertEq(auction.available(from), 0);

        vm.expectRevert("!governance");
        vm.prank(management);
        auction.disable(from);

        vm.expectEmit(true, true, true, true, address(auction));
        emit AuctionDisabled(from, address(asset));
        auction.disable(from);

        assertEq(auction.getAllEnabledAuctions().length, 0);

        (_kicked, _scaler, _initialAvailable) = auction.auctions(from);

        assertEq(_kicked, 0);
        assertEq(_scaler, 0);
        assertEq(_initialAvailable, 0);
        assertEq(auction.available(from), 0);
    }

    function test_kickAuction(uint256 _amount) public {
        vm.assume(_amount >= minFuzzAmount && _amount <= maxFuzzAmount);

        address from = tokenAddrs["WBTC"];
        auction = Auction(auctionFactory.createNewAuction(address(asset)));

        fromScaler = WAD / 10 ** ERC20(from).decimals();
        wantScaler = WAD / 10 ** ERC20(asset).decimals();

        auction.enable(from);

        assertEq(auction.kickable(from), 0);
        (uint128 _kicked, uint128 _scaler, uint128 _initialAvailable) = auction
            .auctions(from);

        assertEq(_kicked, 0);
        assertEq(_scaler, 1e10);
        assertEq(_initialAvailable, 0);
        assertEq(auction.available(from), 0);

        airdrop(ERC20(from), address(auction), _amount);

        assertEq(auction.kickable(from), _amount);
        (_kicked, , _initialAvailable) = auction.auctions(from);
        assertEq(_kicked, 0);
        assertEq(_initialAvailable, 0);
        assertEq(auction.available(from), 0);

        uint256 available = auction.kick(from);

        assertEq(auction.kickable(from), 0);
        (_kicked, , _initialAvailable) = auction.auctions(from);
        assertEq(_kicked, block.timestamp);
        assertEq(_initialAvailable, _amount);
        assertEq(auction.available(from), _amount);
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

        // Can't kick a new one yet
        vm.expectRevert("too soon");
        auction.kick(from);

        // Skip full auction
        skip(auction.auctionLength());

        assertEq(auction.price(from), 0);
        assertEq(auction.getAmountNeeded(from, _amount), 0);
        assertEq(auction.available(from), 0);

        assertEq(auction.kickable(from), _amount);
    }

    function test_takeAuction_all(uint256 _amount) public {
        vm.assume(_amount >= minFuzzAmount && _amount <= maxFuzzAmount);

        address from = tokenAddrs["WBTC"];
        auction = Auction(
            auctionFactory.createNewAuction(
                address(asset),
                address(mockStrategy)
            )
        );

        fromScaler = WAD / 10 ** ERC20(from).decimals();
        wantScaler = WAD / 10 ** ERC20(asset).decimals();

        auction.enable(from);

        airdrop(ERC20(from), address(auction), _amount);

        uint256 available = auction.kick(from);

        assertEq(auction.kickable(from), 0);
        (uint128 _kicked, uint128 _scaler, uint128 _initialAvailable) = auction
            .auctions(from);
        assertEq(_kicked, block.timestamp);
        assertEq(_scaler, 1e10);
        assertEq(_initialAvailable, _amount);
        assertEq(auction.available(from), _amount);

        skip(auction.auctionLength() / 2);

        uint256 needed = auction.getAmountNeeded(from, _amount);
        uint256 beforeAsset = ERC20(asset).balanceOf(address(this));

        airdrop(ERC20(asset), address(this), needed);

        ERC20(asset).safeApprove(address(auction), needed);

        uint256 before = ERC20(from).balanceOf(address(this));

        uint256 amountTaken = auction.take(from);

        assertEq(amountTaken, _amount);

        (, , _initialAvailable) = auction.auctions(from);
        assertEq(_initialAvailable, _amount);
        assertEq(auction.available(from), 0);

        assertEq(ERC20(asset).balanceOf(address(this)), beforeAsset);
        assertEq(ERC20(from).balanceOf(address(this)), before + _amount);
        assertEq(ERC20(from).balanceOf(address(auction)), 0);
        assertEq(ERC20(asset).balanceOf(address(mockStrategy)), needed);
        assertEq(ERC20(asset).balanceOf(address(auction)), 0);
    }

    function test_takeAuction_part(uint256 _amount, uint16 _percent) public {
        vm.assume(_amount >= minFuzzAmount && _amount <= maxFuzzAmount);
        _percent = uint16(bound(uint256(_percent), 1_000, MAX_BPS));

        address from = tokenAddrs["WBTC"];
        auction = Auction(
            auctionFactory.createNewAuction(
                address(asset),
                address(mockStrategy)
            )
        );

        fromScaler = WAD / 10 ** ERC20(from).decimals();
        wantScaler = WAD / 10 ** ERC20(asset).decimals();

        auction.enable(from);

        airdrop(ERC20(from), address(auction), _amount);

        auction.kick(from);

        assertEq(auction.kickable(from), 0);
        (uint256 _kicked, uint256 _scaler, uint256 _initialAvailable) = auction
            .auctions(from);
        assertEq(_kicked, block.timestamp);
        assertEq(_scaler, 1e10);
        assertEq(_initialAvailable, _amount);
        assertEq(auction.available(from), _amount);

        skip(auction.auctionLength() / 2);

        uint256 toTake = (_amount * _percent) / MAX_BPS;
        uint256 left = _amount - toTake;
        uint256 needed = auction.getAmountNeeded(from, toTake);
        uint256 beforeAsset = ERC20(asset).balanceOf(address(this));

        airdrop(ERC20(asset), address(this), needed);

        ERC20(asset).safeApprove(address(auction), needed);

        uint256 before = ERC20(from).balanceOf(address(this));

        uint256 amountTaken = auction.take(from, toTake);

        assertEq(amountTaken, toTake);

        (, , _initialAvailable) = auction.auctions(from);
        assertEq(_initialAvailable, _amount);
        assertEq(auction.available(from), left);
        assertEq(ERC20(asset).balanceOf(address(this)), beforeAsset);
        assertEq(ERC20(from).balanceOf(address(this)), before + toTake);
        assertEq(ERC20(from).balanceOf(address(auction)), left);
        assertEq(ERC20(asset).balanceOf(address(mockStrategy)), needed);
        assertEq(ERC20(asset).balanceOf(address(auction)), 0);
    }

    function test_takeAuction_callback(uint256 _amount) public {
        vm.assume(_amount >= minFuzzAmount && _amount <= maxFuzzAmount);

        address from = tokenAddrs["WBTC"];
        auction = Auction(
            auctionFactory.createNewAuction(
                address(asset),
                address(mockStrategy)
            )
        );

        fromScaler = WAD / 10 ** ERC20(from).decimals();
        wantScaler = WAD / 10 ** ERC20(asset).decimals();

        auction.enable(from);

        airdrop(ERC20(from), address(auction), _amount);

        auction.kick(from);

        assertEq(auction.kickable(from), 0);
        (uint256 _kicked, uint256 _scaler, uint256 _initialAvailable) = auction
            .auctions(from);
        assertEq(_kicked, block.timestamp);
        assertEq(_scaler, 1e10);
        assertEq(_initialAvailable, _amount);
        assertEq(auction.available(from), _amount);
        skip(auction.auctionLength() / 2);

        uint256 toTake = _amount / 2;
        uint256 left = _amount - toTake;
        uint256 needed = auction.getAmountNeeded(from, toTake);
        uint256 beforeAsset = ERC20(asset).balanceOf(address(this));

        airdrop(ERC20(asset), address(this), needed);

        ERC20(asset).safeApprove(address(auction), needed);

        uint256 before = ERC20(from).balanceOf(address(this));

        callbackHit = false;
        bytes memory _data = new bytes(69);

        vm.expectEmit(true, true, true, true, address(this));
        emit Callback(from, address(this), toTake, needed, _data);
        uint256 amountTaken = auction.take(from, toTake, address(this), _data);

        assertTrue(callbackHit);
        assertEq(amountTaken, toTake);

        (, , _initialAvailable) = auction.auctions(from);
        assertEq(_initialAvailable, _amount);
        assertEq(auction.available(from), left);
        assertEq(ERC20(asset).balanceOf(address(this)), beforeAsset);
        assertEq(ERC20(from).balanceOf(address(this)), before + toTake);
        assertEq(ERC20(from).balanceOf(address(auction)), left);
        assertEq(ERC20(asset).balanceOf(address(mockStrategy)), needed);
        assertEq(ERC20(asset).balanceOf(address(auction)), 0);
    }

    // Taker call back function
    function auctionTakeCallback(
        address _from,
        address _sender,
        uint256 _amountTaken,
        uint256 _amountNeeded,
        bytes memory _data
    ) external {
        callbackHit = true;
        emit Callback(_from, _sender, _amountTaken, _amountNeeded, _data);
    }
}
