// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import {BaseHealthCheck, ERC20} from "../HealthCheck/BaseHealthCheck.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {AuctionFactory, Auction} from "../../Auctions/AuctionFactory.sol";

import {IMerklDistributor} from "../../interfaces/IMerklDistributor.sol";

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
    event ReportBufferSet(uint16 indexed reportBuffer);
    event MinAmountToSellSet(uint256 indexed minAmountToSell);
    event MaxAmountToSwapSet(
        address indexed from,
        uint256 indexed maxAmountToSwap
    );
    event MaxGasPriceToTendSet(uint256 indexed maxGasPriceToTend);

    uint256 internal constant ORACLE_PRICE_SCALE = 1e36;
    uint256 internal constant DEFAULT_AUCTION_STARTING_PRICE = 1_000_000;
    uint256 internal constant DEFAULT_AUCTION_DECAY_RATE = 50;

    /// @notice The Merkl Distributor contract for claiming rewards
    IMerklDistributor public constant MERKL_DISTRIBUTOR =
        IMerklDistributor(0x3Ef3D8bA38EBe18DB133cEc108f4D14CE00Dd9Ae);

    /// @notice Token converted to/from strategy `asset`.
    ERC20 public immutable WANT;

    /// @notice Auction selling `asset` into `want`.
    Auction public immutable SELL_ASSET_AUCTION;

    /// @notice Auction selling `want` into `asset`.
    Auction public immutable BUY_ASSET_AUCTION;

    /// @notice Morpho-style oracle with answer = asset per want, scaled 1e36.
    address public oracle;

    /// @notice Bps haircut applied to want-denominated value in reports.
    uint16 public reportBuffer;

    /// @notice Maximum tolerated slippage from 1:1 price in bps.
    uint16 public maxSlippageBps;

    /// @notice Starting auction price vs 1:1 price in bps.
    uint16 public startingPriceBps;

    /// @notice Minimum amount required before an auction kick is allowed.
    uint256 public minAmountToSell;

    /// @notice Management configured step decay rate applied to asset/want auctions.
    uint256 public decayRate;

    /// @notice Max base fee accepted for tend trigger. 0 disables the check.
    uint256 public maxGasPriceToTend;

    /// @notice Maximum amount of a token to kick into auction at once.
    /// @dev Zero means unlimited.
    mapping(address => uint256) public maxAmountToSwap;

    constructor(
        address _asset,
        string memory _name,
        address _want,
        address _oracle
    ) BaseHealthCheck(_asset, _name) {
        WANT = ERC20(_want);

        AuctionFactory factory = AuctionFactory(
            0xbA7FCb508c7195eE5AE823F37eE2c11D7ED52F8e
        );

        Auction _sellAssetAuction = Auction(
            factory.createNewAuction(_want, address(this), address(this))
        );
        _sellAssetAuction.enable(_asset);
        _sellAssetAuction.setStepDecayRate(1);
        _sellAssetAuction.setGovernanceOnlyKick(true);
        SELL_ASSET_AUCTION = _sellAssetAuction;

        Auction _buyAssetAuction = Auction(
            factory.createNewAuction(_asset, address(this), address(this))
        );
        _buyAssetAuction.enable(_want);
        _buyAssetAuction.setStepDecayRate(1);
        _buyAssetAuction.setGovernanceOnlyKick(true);
        BUY_ASSET_AUCTION = _buyAssetAuction;

        // We store the default decay rate in case a custom one
        // is ever used for a specific auction we can reset it to the default.
        decayRate = 1;

        _setStartingPriceBps(uint16(MAX_BPS + 5));
        _setMaxSlippageBps(5);
        _setOracle(_oracle);
        // Default to no triggers until minAmountToSell is set.
        _setMinAmountToSell(type(uint256).max);
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

    function setMaxAmountToSwap(
        address _from,
        uint256 _maxAmountToSwap
    ) external onlyManagement {
        _setMaxAmountToSwap(_from, _maxAmountToSwap);
    }

    function setMaxSlippageBps(uint16 _maxSlippageBps) external onlyManagement {
        _setMaxSlippageBps(_maxSlippageBps);
    }

    function setStartingPriceBps(
        uint16 _startingPriceBps
    ) external onlyManagement {
        _setStartingPriceBps(_startingPriceBps);
    }

    /// @notice Set the default decay rate used for want/asset auctions.
    ///  Reward token auctions always use DEFAULT_AUCTION_DECAY_RATE.
    function setDecayRate(uint256 _decayRate) external onlyManagement {
        _setDecayRate(_decayRate);
    }

    function setReportBuffer(uint16 _reportBuffer) external onlyManagement {
        _setReportBuffer(_reportBuffer);
    }

    function setMaxGasPriceToTend(
        uint256 _maxGasPriceToTend
    ) external onlyManagement {
        _setMaxGasPriceToTend(_maxGasPriceToTend);
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

    /// @notice Management passthrough to sweep the auction token back to strategy.
    function sweepAuctionToken(address _from) external onlyManagement {
        _auctionForToken(_from).sweep(_from);
    }

    /*//////////////////////////////////////////////////////////////
                            KEEPER API
    //////////////////////////////////////////////////////////////*/

    function kickAuction(address _from) external onlyKeepers returns (uint256) {
        return _kickAuction(_from);
    }

    function freeWant(uint256 _wantAmount) external virtual onlyKeepers {
        _freeWant(_wantAmount);
    }

    function _kickAuction(address _from) internal virtual returns (uint256) {
        if (_from == address(WANT)) {
            return
                _kickConfiguredAuction(
                    BUY_ASSET_AUCTION,
                    _from,
                    type(uint256).max
                );
        }
        return
            _kickConfiguredAuction(
                SELL_ASSET_AUCTION,
                _from,
                type(uint256).max
            );
    }

    function kickable(address _from) public view virtual returns (uint256) {
        if (_from == address(WANT)) {
            return _kickableFromAuction(BUY_ASSET_AUCTION, _from);
        }
        return _kickableFromAuction(SELL_ASSET_AUCTION, _from);
    }

    /// @notice We use trigger to go from asset -> want.
    /// We cannot assume loose want should be converted, so it does not go back.
    function auctionTrigger(
        address _from
    ) external view returns (bool shouldKick, bytes memory data) {
        if (_from == address(WANT)) return (false, bytes("want"));

        if (!(_isBaseFeeAcceptable())) return (false, bytes("base fee"));

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

    function _freeWant(uint256 _wantAmount) internal virtual {
        _kickConfiguredAuction(BUY_ASSET_AUCTION, address(WANT), _wantAmount);
    }

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
        uint256 wantValueInAsset = (_quoteAssetFromWant(totalWant()) *
            (MAX_BPS - reportBuffer)) / MAX_BPS;

        return balanceOfAsset() + balanceOfAssetInAuction() + wantValueInAsset;
    }

    function _claimAndSellRewards() internal virtual {}

    function totalWant() public view virtual returns (uint256) {
        return balanceOfWant() + balanceOfWantInAuction();
    }

    function balanceOfAsset() public view virtual returns (uint256) {
        return asset.balanceOf(address(this));
    }

    function balanceOfWant() public view virtual returns (uint256) {
        return WANT.balanceOf(address(this));
    }

    function balanceOfAssetInAuction() public view virtual returns (uint256) {
        return asset.balanceOf(address(SELL_ASSET_AUCTION));
    }

    function balanceOfWantInAuction() public view virtual returns (uint256) {
        return WANT.balanceOf(address(BUY_ASSET_AUCTION));
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

        // Call _oraclePrice() to ensure the oracle is valid.
        _oraclePrice();

        emit OracleSet(_oracle);
    }

    function _setMinAmountToSell(uint256 _minAmountToSell) internal virtual {
        minAmountToSell = _minAmountToSell;
        emit MinAmountToSellSet(_minAmountToSell);
    }

    function _setMaxAmountToSwap(
        address _from,
        uint256 _maxAmountToSwap
    ) internal virtual {
        maxAmountToSwap[_from] = _maxAmountToSwap;
        emit MaxAmountToSwapSet(_from, _maxAmountToSwap);
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

    function _setReportBuffer(uint16 _reportBuffer) internal virtual {
        require(_reportBuffer <= MAX_BPS, "report buffer");
        reportBuffer = _reportBuffer;
        emit ReportBufferSet(_reportBuffer);
    }

    function _setMaxGasPriceToTend(
        uint256 _maxGasPriceToTend
    ) internal virtual {
        maxGasPriceToTend = _maxGasPriceToTend;
        emit MaxGasPriceToTendSet(_maxGasPriceToTend);
    }

    function _isBaseFeeAcceptable() internal view virtual returns (bool) {
        uint256 _maxGasPriceToTend = maxGasPriceToTend;
        if (_maxGasPriceToTend == 0) return true;
        return block.basefee <= _maxGasPriceToTend;
    }

    function _kickConfiguredAuction(
        Auction _auction,
        address _from,
        uint256 _maxKickAmount
    ) internal virtual returns (uint256 _available) {
        if (_auction.isActive(_from)) {
            // Will revert if the auction still has available funds.
            _auction.settle(_from);
        }

        _available = _kickableFromAuction(_auction, _from);
        _available = Math.min(_available, _maxKickAmount);
        if (_available == 0) return 0;

        _setAuctionPricing(_auction, _from, _available);

        uint256 balanceInAuction = ERC20(_from).balanceOf(address(_auction));
        if (balanceInAuction < _available) {
            ERC20(_from).safeTransfer(
                address(_auction),
                _available - balanceInAuction
            );
        } else {
            _auction.sweep(_from);
            ERC20(_from).safeTransfer(address(_auction), _available);
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

        uint256 _kickable = ERC20(_from).balanceOf(address(this)) +
            ERC20(_from).balanceOf(address(_auction));
        uint256 _maxAmountToSwap = maxAmountToSwap[_from];

        if (_maxAmountToSwap != 0 && _kickable > _maxAmountToSwap) {
            return _maxAmountToSwap;
        }

        return _kickable;
    }

    function _auctionForToken(
        address _from
    ) internal view returns (Auction _auction) {
        if (_from == address(WANT)) return BUY_ASSET_AUCTION;
        return SELL_ASSET_AUCTION;
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
        // If non want/asset tokens, use the default auction pricing.
        if (_from != address(asset) && _from != address(WANT)) {
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

        // Auction starting price is a lot size, so we need to adjust for amount.
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
            return Math.mulDiv(quoteWant, 1e18, 10 ** WANT.decimals());
        }

        uint256 oneWant = 10 ** WANT.decimals();
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

    /**
     * @notice Claims rewards from Merkl distributor
     * @param users Recipients of tokens
     * @param tokens ERC20 tokens being claimed
     * @param amounts Amounts of tokens that will be sent to the corresponding users
     * @param proofs Array of Merkle proofs verifying the claims
     */
    function claim(
        address[] calldata users,
        address[] calldata tokens,
        uint256[] calldata amounts,
        bytes32[][] calldata proofs
    ) external {
        MERKL_DISTRIBUTOR.claim(users, tokens, amounts, proofs);
    }
}
