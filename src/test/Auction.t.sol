// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import "forge-std/console.sol";
import {Setup, IStrategy, SafeERC20, ERC20} from "./utils/Setup.sol";

import {ITaker} from "../interfaces/ITaker.sol";
import {Auction, AuctionFactory} from "../Auctions/AuctionFactory.sol";
import {GPv2Order} from "../libraries/GPv2Order.sol";

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
        assertEq(auctionFactory.DEFAULT_STARTING_PRICE(), 1e6);
    }

    function test_defaults() public {
        auction = Auction(auctionFactory.createNewAuction(address(asset)));

        vm.expectRevert("initialized");
        auction.initialize(address(asset), address(this), management, 1);

        assertEq(auction.want(), address(asset));
        assertEq(auction.receiver(), address(this));
        assertEq(auction.governance(), address(this));
        assertEq(auction.auctionLength(), 1 days);
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
        assertApproxEqRel(
            auction.getAmountNeeded(from, _amount),
            (startingPrice * fromScaler * _amount) /
                (WAD / wantScaler) /
                wantScaler,
            0.0001e18 // 0.01% tolerance
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

    function test_kickAuction_belowMinimumPrice(uint256 _amount) public {
        vm.assume(_amount >= 1e6 && _amount <= maxFuzzAmount); // Minimum 0.01 WBTC

        address from = tokenAddrs["WBTC"];
        auction = Auction(auctionFactory.createNewAuction(address(asset)));

        auction.setStartingPrice(
            (_amount * 200_000) / (10 ** ERC20(from).decimals())
        );
        auction.setMinimumPrice(100_000 * 1e18);

        fromScaler = WAD / 10 ** ERC20(from).decimals();
        wantScaler = WAD / 10 ** ERC20(asset).decimals();

        auction.enable(from);

        airdrop(ERC20(from), address(auction), _amount);

        auction.kick(from);

        // We need to halve the price, which with 0.5% decay per step takes ~138.6 steps
        uint256 approximateSteps = 138;
        uint256 timeToSkip = approximateSteps * auction.stepDuration();

        // Make sure the total time we skip is less than the auction length
        // so that the re-kick check at the end is valid at all times
        assertGt(auction.auctionLength(), timeToSkip + 1 minutes);

        skip(timeToSkip);

        // Price should be at or just above minimum price
        uint256 currentPrice = auction.price(from) * wantScaler;
        assertApproxEqRel(currentPrice, auction.minimumPrice(), 1e16); // 1% tolerance
        assertGt(currentPrice, auction.minimumPrice());
        assertTrue(auction.isActive(from));

        // Can't kick a new one yet
        vm.expectRevert("too soon");
        auction.kick(from);

        // Skip just a touch more to go below minimum price
        skip(1 minutes);

        assertEq(auction.price(from), 0);
        assertFalse(auction.isActive(from));

        // Now we can kick, even though auction length hasn't fully passed
        auction.kick(from);
    }

    function test_forceKick(uint256 _amount) public {
        vm.assume(_amount >= minFuzzAmount && _amount <= maxFuzzAmount);

        address from = tokenAddrs["WBTC"];
        auction = Auction(
            auctionFactory.createNewAuction(
                address(asset),
                address(this),
                daddy
            )
        );

        fromScaler = WAD / 10 ** ERC20(from).decimals();
        wantScaler = WAD / 10 ** ERC20(asset).decimals();

        vm.prank(daddy);
        auction.enable(from);

        // Test 1: Only governance can call forceKick
        vm.expectRevert("!governance");
        vm.prank(user);
        auction.forceKick(from);

        // Test 2: ForceKick when no auction is active should start a new auction
        airdrop(ERC20(from), address(auction), _amount);

        vm.prank(daddy);
        auction.forceKick(from);

        assertTrue(auction.isActive(from));
        (uint128 _kicked, , uint128 _initialAvailable) = auction.auctions(from);
        assertEq(_kicked, block.timestamp);
        assertEq(_initialAvailable, _amount);
        assertEq(auction.available(from), _amount);

        // Test 3: ForceKick when auction is active should restart with full balance
        // Add more tokens while auction is active
        uint256 additionalAmount = _amount + _amount / 2; // 1.5x the original
        airdrop(ERC20(from), address(auction), additionalAmount);

        // The auction contract now has original _amount (in auction) + additionalAmount
        uint256 totalBalance = ERC20(from).balanceOf(address(auction));
        assertEq(totalBalance, _amount + additionalAmount);

        // Force kick to restart auction with total balance
        vm.prank(daddy);
        auction.forceKick(from);

        // Verify new auction was started with total balance
        assertTrue(auction.isActive(from));
        (uint128 newKicked, , uint128 newInitialAvailable) = auction.auctions(
            from
        );
        assertEq(newKicked, block.timestamp);
        assertEq(newInitialAvailable, totalBalance);
        assertEq(auction.available(from), totalBalance);

        // Test forceKick when no auction is active
        skip(auction.auctionLength() + 1);
        assertFalse(auction.isActive(from));

        // Add tokens again
        airdrop(ERC20(from), address(auction), _amount);

        // ForceKick should start a new auction
        vm.prank(daddy);
        auction.forceKick(from);

        assertTrue(auction.isActive(from));
        (uint128 finalKicked, , uint128 finalAvailable) = auction.auctions(
            from
        );
        assertEq(finalKicked, block.timestamp);
        assertEq(finalAvailable, _amount + additionalAmount + _amount);
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

        ERC20(asset).forceApprove(address(auction), needed);

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

        ERC20(asset).forceApprove(address(auction), needed);

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

        ERC20(asset).forceApprove(address(auction), needed);

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

    function test_setReceiver() public {
        address from = tokenAddrs["WBTC"];
        auction = Auction(auctionFactory.createNewAuction(address(asset)));

        // Check initial receiver is this contract
        assertEq(auction.receiver(), address(this));

        // Test setting valid receiver
        auction.setReceiver(management);
        assertEq(auction.receiver(), management);

        // Test that non-governance cannot set
        vm.prank(management);
        vm.expectRevert("!governance");
        auction.setReceiver(user);

        // Test invalid receiver (zero address)
        vm.expectRevert("ZERO ADDRESS");
        auction.setReceiver(address(0));
    }

    function test_setMinimumPrice() public {
        address from = tokenAddrs["WBTC"];
        auction = Auction(auctionFactory.createNewAuction(address(asset)));

        // Check initial minimum price is 0
        assertEq(auction.minimumPrice(), 0);

        // Test setting valid minimum prices
        auction.setMinimumPrice(1e5);
        assertEq(auction.minimumPrice(), 1e5);

        auction.setMinimumPrice(5e18);
        assertEq(auction.minimumPrice(), 5e18);

        // Test that non-governance cannot set
        vm.prank(management);
        vm.expectRevert("!governance");
        auction.setMinimumPrice(1e6);

        // Test cannot change during active auction
        auction.enable(from);
        airdrop(ERC20(from), address(auction), 1e8);
        auction.kick(from);

        vm.expectRevert("active auction");
        auction.setMinimumPrice(1e7);

        // After auction ends, can change again
        skip(auction.auctionLength() + 1);
        auction.setMinimumPrice(1e7);
        assertEq(auction.minimumPrice(), 1e7);
    }

    function test_setStepDuration() public {
        address from = tokenAddrs["WBTC"];
        auction = Auction(auctionFactory.createNewAuction(address(asset)));

        // Check initial step duration is 60 seconds
        assertEq(auction.stepDuration(), 60);

        // Test setting valid step duration
        auction.setStepDuration(120);
        assertEq(auction.stepDuration(), 120);

        // Test setting another valid step duration
        auction.setStepDuration(30);
        assertEq(auction.stepDuration(), 30);

        // Test that non-governance cannot set
        vm.prank(management);
        vm.expectRevert("!governance");
        auction.setStepDuration(90);

        // Test invalid step durations
        vm.expectRevert("invalid step duration");
        auction.setStepDuration(0);

        vm.expectRevert("invalid step duration");
        auction.setStepDuration(1 days);

        vm.expectRevert("invalid step duration");
        auction.setStepDuration(1 days + 1);

        // Test cannot change during active auction
        auction.enable(from);
        airdrop(ERC20(from), address(auction), 1e8);
        auction.kick(from);

        vm.expectRevert("active auction");
        auction.setStepDuration(45);

        // After auction ends, can change again
        skip(auction.auctionLength() + 1);
        auction.setStepDuration(45);
        assertEq(auction.stepDuration(), 45);
    }

    function test_setStepDecayRate() public {
        address from = tokenAddrs["WBTC"];
        auction = Auction(auctionFactory.createNewAuction(address(asset)));

        // Check initial step decay rate is 50 basis points
        assertEq(auction.stepDecayRate(), 50);

        // Test setting valid decay rates
        auction.setStepDecayRate(100); // 1% decay per step
        assertEq(auction.stepDecayRate(), 100);

        auction.setStepDecayRate(25); // 0.25% decay per step
        assertEq(auction.stepDecayRate(), 25);

        auction.setStepDecayRate(500); // 5% decay per step
        assertEq(auction.stepDecayRate(), 500);

        auction.setStepDecayRate(9999); // 99.99% decay per step (max)
        assertEq(auction.stepDecayRate(), 9999);

        // Test that non-governance cannot set
        vm.prank(management);
        vm.expectRevert("!governance");
        auction.setStepDecayRate(75);

        // Test invalid decay rates
        vm.expectRevert("invalid decay rate");
        auction.setStepDecayRate(0);

        vm.expectRevert("invalid decay rate");
        auction.setStepDecayRate(10000); // Over 100%

        // Test cannot change during active auction
        auction.setStepDecayRate(50); // Reset to default
        auction.enable(from);
        airdrop(ERC20(from), address(auction), 1e8);
        auction.kick(from);

        vm.expectRevert("active auction");
        auction.setStepDecayRate(75);

        // After auction ends, can change again
        skip(auction.auctionLength() + 1);
        auction.setStepDecayRate(75);
        assertEq(auction.stepDecayRate(), 75);
    }

    function test_stepDecayRateAffectsPrice(uint256 _amount) public {
        vm.assume(_amount >= minFuzzAmount && _amount <= maxFuzzAmount);

        address from = tokenAddrs["WBTC"];

        // Create two auctions with different decay rates
        // Use different receiver to get different salts
        Auction auction1 = Auction(
            auctionFactory.createNewAuction(address(asset), address(this))
        );
        Auction auction2 = Auction(
            auctionFactory.createNewAuction(address(asset), address(management))
        );

        // Set different decay rates (in basis points)
        auction1.setStepDecayRate(100); // 1% decay per step
        auction2.setStepDecayRate(25); // 0.25% decay per step

        // Both auctions have same step duration for fair comparison
        auction1.setStepDuration(60);
        auction2.setStepDuration(60);

        // Enable and kick both auctions with same amount
        auction1.enable(from);
        auction2.enable(from);

        airdrop(ERC20(from), address(auction1), _amount);
        airdrop(ERC20(from), address(auction2), _amount);

        auction1.kick(from);
        auction2.kick(from);

        // Initial prices should be the same
        uint256 initialPrice1 = auction1.price(from);
        uint256 initialPrice2 = auction2.price(from);
        assertEq(initialPrice1, initialPrice2);

        // After 60 seconds (1 step), prices should differ
        skip(60);

        uint256 price1After1Step = auction1.price(from);
        uint256 price2After1Step = auction2.price(from);

        // Auction1 (1% decay) should have lower price than auction2 (0.25% decay)
        assertLt(price1After1Step, price2After1Step);

        // Verify the decay amounts are approximately correct
        // Auction1: price should be ~99% of initial (1% decay)
        assertApproxEqRel(
            price1After1Step,
            (initialPrice1 * 9900) / 10000,
            0.01e18
        );

        // Auction2: price should be ~99.75% of initial (0.25% decay)
        assertApproxEqRel(
            price2After1Step,
            (initialPrice2 * 9975) / 10000,
            0.01e18
        );

        // After multiple steps, the difference should be more pronounced
        skip(240); // 4 more steps (5 total)

        // Both should have decayed significantly
        assertLt(auction1.price(from), initialPrice1);
        assertLt(auction2.price(from), initialPrice2);

        // Auction1 should still be much lower due to higher decay rate
        assertLt(auction1.price(from), auction2.price(from));

        // Verify amount needed follows the same pattern
        assertLt(
            auction1.getAmountNeeded(from, _amount),
            auction2.getAmountNeeded(from, _amount)
        );
    }

    function test_stepDurationAffectsPrice(uint256 _amount) public {
        vm.assume(_amount >= minFuzzAmount && _amount <= maxFuzzAmount);

        address from = tokenAddrs["WBTC"];

        // Create two auctions with different step durations
        // Use different receiver to get different salts
        Auction auction1 = Auction(
            auctionFactory.createNewAuction(address(asset), address(this))
        );
        Auction auction2 = Auction(
            auctionFactory.createNewAuction(address(asset), address(management))
        );

        fromScaler = WAD / 10 ** ERC20(from).decimals();
        wantScaler = WAD / 10 ** ERC20(asset).decimals();

        // Set different step durations
        auction1.setStepDuration(30); // Faster decay
        auction2.setStepDuration(120); // Slower decay

        // Enable and kick both auctions with same amount
        auction1.enable(from);
        auction2.enable(from);

        airdrop(ERC20(from), address(auction1), _amount);
        airdrop(ERC20(from), address(auction2), _amount);

        auction1.kick(from);
        auction2.kick(from);

        // Initial prices should be the same
        uint256 initialPrice1 = auction1.price(from);
        uint256 initialPrice2 = auction2.price(from);
        assertEq(initialPrice1, initialPrice2);

        // After 60 seconds, auction1 (30s steps) should have gone through 2 steps
        // while auction2 (120s steps) should have gone through 0 steps
        skip(60);

        uint256 price1After60 = auction1.price(from);
        uint256 price2After60 = auction2.price(from);

        // Auction1 should have lower price (more steps = more decay)
        assertLt(price1After60, price2After60);
        // Auction2 should still be at initial price (no complete steps yet)
        assertEq(price2After60, initialPrice2);

        // After 120 seconds total, auction1 has 4 steps, auction2 has 1 step
        skip(60);

        uint256 price1After120 = auction1.price(from);
        uint256 price2After120 = auction2.price(from);

        // Both should have decayed from initial
        assertLt(price1After120, initialPrice1);
        assertLt(price2After120, initialPrice2);
        // Auction1 should still be lower (more steps)
        assertLt(price1After120, price2After120);

        // Verify amount needed follows the same pattern
        uint256 needed1 = auction1.getAmountNeeded(from, _amount);
        uint256 needed2 = auction2.getAmountNeeded(from, _amount);
        assertLt(needed1, needed2);
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
