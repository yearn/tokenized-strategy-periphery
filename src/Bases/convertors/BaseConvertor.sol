// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import {BaseHealthCheck, ERC20} from "../HealthCheck/BaseHealthCheck.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {AuctionFactory, Auction} from "../../Auctions/AuctionFactory.sol";

interface IMorphoOracle {
    function price() external view returns (uint256);
}

/**
 * @title BaseConvertor
 * @dev Generic auction based convertor between `asset` and `want`.
 *
 * This base assumes converted `want` tokens are held directly by the strategy.
 */
contract BaseConvertor is BaseHealthCheck {
    using SafeERC20 for ERC20;

    event OracleSet(address indexed oracle);
    event MaxSlippageBpsSet(uint16 indexed maxSlippageBps);
    event StartingPriceBpsSet(uint16 indexed startingPriceBps);
    event DecayRateSet(uint256 indexed decayRate);

    /// @notice Token converted to/from strategy `asset`.
    ERC20 public immutable want;

    /// @notice Auction selling `asset` into `want`.
    Auction public immutable sellAssetAuction;

    /// @notice Auction selling `want` into `asset`.
    Auction public immutable buyAssetAuction;

    /// @notice Morpho-style oracle with answer = asset per want, scaled 1e36.
    address public oracle;

    /// @notice Maximum tolerated slippage from 1:1 price in bps.
    uint16 public maxSlippageBps;

    /// @notice Starting auction price vs 1:1 price in bps.
    uint16 public startingPriceBps;

    /// @notice Minimum amount required before an auction kick is allowed.
    uint256 public minAmountToSell;

    uint256 internal constant ORACLE_PRICE_SCALE = 1e36;
    uint256 internal constant DEFAULT_AUCTION_STARTING_PRICE = 1_000_000;
    uint256 internal constant DEFAULT_AUCTION_DECAY_RATE = 50;

    /// @notice Management configured step decay rate applied to asset/want auctions.
    uint256 public decayRate;

    constructor(
        address _asset,
        string memory _name,
        address _want,
        address _oracle
    ) BaseHealthCheck(_asset, _name) {
        want = ERC20(_want);

        AuctionFactory factory = AuctionFactory(
            0xbA7FCb508c7195eE5AE823F37eE2c11D7ED52F8e
        );

        Auction _sellAssetAuction = Auction(
            factory.createNewAuction(_want, address(this), address(this))
        );
        _sellAssetAuction.enable(_asset);
        _sellAssetAuction.setStepDecayRate(1);
        _sellAssetAuction.setGovernanceOnlyKick(true);
        sellAssetAuction = _sellAssetAuction;

        Auction _buyAssetAuction = Auction(
            factory.createNewAuction(_asset, address(this), address(this))
        );
        _buyAssetAuction.enable(_want);
        _buyAssetAuction.setStepDecayRate(1);
        _buyAssetAuction.setGovernanceOnlyKick(true);
        buyAssetAuction = _buyAssetAuction;

        decayRate = 1;

        _setStartingPriceBps(uint16(MAX_BPS + 10));
        _setMaxSlippageBps(5);
        _setOracle(_oracle);
    }

    /*//////////////////////////////////////////////////////////////
                        MANAGEMENT CONFIG
    //////////////////////////////////////////////////////////////*/

    function setMinAmountToSell(
        uint256 _minAmountToSell
    ) external onlyManagement {
        _setMinAmountToSell(_minAmountToSell);
    }

    function setOracle(address _oracle) external onlyManagement {
        _setOracle(_oracle);
    }

    function setMaxSlippageBps(uint16 _maxSlippageBps) external onlyManagement {
        _setMaxSlippageBps(_maxSlippageBps);
    }

    function setStartingPriceBps(
        uint16 _startingPriceBps
    ) external onlyManagement {
        _setStartingPriceBps(_startingPriceBps);
    }

    function setDecayRate(uint256 _decayRate) external onlyManagement {
        _setDecayRate(_decayRate);
    }

    /// @notice Management passthrough to set auction step decay rate.
    function setAuctionStepDecayRate(
        address _from,
        uint256 _stepDecayRate
    ) external onlyManagement {
        _auctionForToken(_from).setStepDecayRate(_stepDecayRate);
    }

    /// @notice Management passthrough to set auction step duration.
    function setAuctionStepDuration(
        address _from,
        uint256 _stepDuration
    ) external onlyManagement {
        _auctionForToken(_from).setStepDuration(_stepDuration);
    }

    /// @notice Management passthrough to enable an auction token.
    function enableAuctionToken(address _from) external onlyManagement {
        _auctionForToken(_from).enable(_from);
    }

    /// @notice Management passthrough to sweep tokens from an auction back to strategy.
    function sweepAuctionToken(
        address _from,
        address _token
    ) external onlyManagement {
        _auctionForToken(_from).sweep(_token);
    }

    /*//////////////////////////////////////////////////////////////
                            KEEPER API
    //////////////////////////////////////////////////////////////*/

    function kickAuction(address _from) external onlyKeepers returns (uint256) {
        return _kickAuction(_from);
    }

    function _kickAuction(address _from) internal virtual returns (uint256) {
        if (_from == address(asset)) {
            return _kickConfiguredAuction(sellAssetAuction, _from);
        }
        return _kickConfiguredAuction(buyAssetAuction, _from);
    }

    function kickable(address _from) public view virtual returns (uint256) {
        if (_from == address(asset)) {
            return _kickableFromAuction(sellAssetAuction, _from);
        }
        return _kickableFromAuction(buyAssetAuction, _from);
    }

    function auctionTrigger(
        address _from
    ) external view returns (bool shouldKick, bytes memory data) {
        uint256 kickableAmount = kickable(_from);
        if (kickableAmount >= minAmountToSell) {
            return (true, abi.encodeCall(this.kickAuction, (_from)));
        }

        return (false, bytes("not enough kickable"));
    }

    /*//////////////////////////////////////////////////////////////
                            STRATEGY HOOKS
    //////////////////////////////////////////////////////////////*/

    function _deployFunds(uint256) internal virtual override {}

    function _freeFunds(uint256) internal virtual override {}

    function _harvestAndReport()
        internal
        virtual
        override
        returns (uint256 _totalAssets)
    {
        _claimAndSellRewards();

        _totalAssets = estimatedTotalAssets();
    }

    function estimatedTotalAssets() public view virtual returns (uint256) {
        return
            balanceOfAsset() +
            balanceOfAssetInAuction() +
            _quoteAssetFromWant(totalWant());
    }

    function _claimAndSellRewards() internal virtual {}

    function totalWant() internal view virtual returns (uint256) {
        return balanceOfWant() + balanceOfWantInAuction();
    }

    function balanceOfAsset() public view virtual returns (uint256) {
        return asset.balanceOf(address(this));
    }

    function balanceOfWant() public view virtual returns (uint256) {
        return want.balanceOf(address(this));
    }

    function balanceOfAssetInAuction() public view virtual returns (uint256) {
        return asset.balanceOf(address(sellAssetAuction));
    }

    function balanceOfWantInAuction() public view virtual returns (uint256) {
        return want.balanceOf(address(buyAssetAuction));
    }

    function availableWithdrawLimit(
        address
    ) public view virtual override returns (uint256) {
        return balanceOfAsset();
    }

    /*//////////////////////////////////////////////////////////////
                            INTERNAL HELPERS
    //////////////////////////////////////////////////////////////*/

    function _setOracle(address _oracle) internal virtual {
        require(_oracle != address(0), "ZERO ADDRESS");

        oracle = _oracle;
        emit OracleSet(_oracle);
    }

    function _setMinAmountToSell(uint256 _minAmountToSell) internal virtual {
        minAmountToSell = _minAmountToSell;
    }

    function _setMaxSlippageBps(uint16 _maxSlippageBps) internal virtual {
        require(_maxSlippageBps <= MAX_BPS, "slippage");
        require(
            startingPriceBps >= uint16(MAX_BPS - _maxSlippageBps),
            "starting bps"
        );

        maxSlippageBps = _maxSlippageBps;
        emit MaxSlippageBpsSet(_maxSlippageBps);
    }

    function _setStartingPriceBps(uint16 _startingPriceBps) internal virtual {
        require(_startingPriceBps != 0, "starting bps");
        require(
            _startingPriceBps >= uint16(MAX_BPS - maxSlippageBps),
            "starting bps"
        );

        startingPriceBps = _startingPriceBps;
        emit StartingPriceBpsSet(_startingPriceBps);
    }

    function _setDecayRate(uint256 _decayRate) internal virtual {
        require(_decayRate > 0 && _decayRate < MAX_BPS, "decay rate");
        decayRate = _decayRate;
        emit DecayRateSet(_decayRate);
    }

    function _kickConfiguredAuction(
        Auction _auction,
        address _from
    ) internal virtual returns (uint256 _available) {
        if (_auction.isActive(_from)) {
            // Will revert if the auction still has available funds.
            _auction.settle(_from);
        }

        _available = _kickableFromAuction(_auction, _from);
        if (_available < minAmountToSell) return 0;

        _setAuctionPricing(_auction, _from, _available);

        uint256 balanceHere = ERC20(_from).balanceOf(address(this));
        if (balanceHere != 0) {
            ERC20(_from).safeTransfer(address(_auction), balanceHere);
        }

        _available = _auction.kick(_from);
    }

    function _setAuctionPricing(
        Auction _auction,
        address _from,
        uint256 _amount
    ) internal virtual {
        (
            uint256 _startingPrice,
            uint256 _minimumPrice,
            uint256 _stepDecayRate
        ) = _auctionPricingFor(_from, _amount);

        if (_auction.startingPrice() != _startingPrice) {
            _auction.setStartingPrice(_startingPrice);
        }
        if (_auction.minimumPrice() != _minimumPrice) {
            _auction.setMinimumPrice(_minimumPrice);
        }
        if (_auction.stepDecayRate() != _stepDecayRate) {
            _auction.setStepDecayRate(_stepDecayRate);
        }
    }

    function _kickableFromAuction(
        Auction _auction,
        address _from
    ) internal view virtual returns (uint256) {
        if (_auction.isActive(_from) && _auction.available(_from) > 0) return 0;

        return
            ERC20(_from).balanceOf(address(this)) +
            ERC20(_from).balanceOf(address(_auction));
    }

    function _auctionForToken(
        address _from
    ) internal view returns (Auction _auction) {
        if (_from == address(asset)) return sellAssetAuction;
        return buyAssetAuction;
    }

    function _oraclePrice() internal view virtual returns (uint256 _price) {
        _price = IMorphoOracle(oracle).price();
        require(_price > 0, "oracle");
    }

    function _auctionPricingFor(
        address _from,
        uint256 _amount
    )
        internal
        view
        virtual
        returns (
            uint256 _startingPrice,
            uint256 _minimumPrice,
            uint256 _stepDecayRate
        )
    {
        if (_from != address(asset) && _from != address(want)) {
            return (
                DEFAULT_AUCTION_STARTING_PRICE,
                0,
                DEFAULT_AUCTION_DECAY_RATE
            );
        }

        uint256 fromScaler = 10 ** ERC20(_from).decimals();
        uint256 targetPrice = _targetAuctionPrice(_from);
        uint256 startUnitPrice = Math.mulDiv(
            targetPrice,
            uint256(startingPriceBps),
            MAX_BPS,
            Math.Rounding.Up
        );

        _startingPrice = Math.mulDiv(
            _amount,
            startUnitPrice,
            fromScaler * 1e18,
            Math.Rounding.Up
        );
        if (_startingPrice == 0) _startingPrice = 1;

        _minimumPrice = Math.mulDiv(
            targetPrice,
            uint256(MAX_BPS) - uint256(maxSlippageBps),
            MAX_BPS
        );
        _stepDecayRate = decayRate;
    }

    function _targetAuctionPrice(
        address _from
    ) internal view virtual returns (uint256 _price) {
        if (_from == address(asset)) {
            uint256 oneAsset = 10 ** asset.decimals();
            uint256 quoteWant = _quoteWantFromAsset(oneAsset);
            return Math.mulDiv(quoteWant, 1e18, 10 ** want.decimals());
        }

        uint256 oneWant = 10 ** want.decimals();
        uint256 quoteAsset = _quoteAssetFromWant(oneWant);
        return Math.mulDiv(quoteAsset, 1e18, 10 ** asset.decimals());
    }

    /// @dev Convert `asset` amount to `want` using oracle price.
    /// Oracle semantics: `asset = want * price / 1e36`.
    function _quoteWantFromAsset(
        uint256 _amount
    ) internal view virtual returns (uint256) {
        if (_amount == 0) return 0;
        return Math.mulDiv(_amount, ORACLE_PRICE_SCALE, _oraclePrice());
    }

    /// @dev Convert `want` amount to `asset` using oracle price.
    /// Oracle semantics: `asset = want * price / 1e36`.
    function _quoteAssetFromWant(
        uint256 _amount
    ) internal view virtual returns (uint256) {
        if (_amount == 0) return 0;
        return Math.mulDiv(_amount, _oraclePrice(), ORACLE_PRICE_SCALE);
    }

    function _emergencyWithdraw(uint256) internal virtual override {}
}
