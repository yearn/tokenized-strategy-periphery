// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {BaseSwapper} from "./BaseSwapper.sol";
import {
    IPendleRouter,
    IPMarket,
    IPYieldToken,
    ApproxParams,
    TokenInput,
    TokenOutput,
    SwapData,
    SwapType,
    LimitOrderData,
    FillOrderParams
} from "../interfaces/Pendle/IPendle.sol";

/**
 * @title PendleSwapper
 * @author yearn.fi
 * @dev This is a contract that can be inherited by any tokenized
 *   strategy that would like to use Pendle for swapping tokens to/from
 *   Principal Tokens (PT).
 *
 *   The swapper supports:
 *   - Buying PT: swap underlying/SY token -> PT via Pendle AMM
 *   - Selling PT (pre-expiry): swap PT -> underlying via Pendle AMM
 *   - Redeeming PT (post-expiry): redeem PT -> underlying directly
 *
 *   The swapper automatically detects the direction of the swap based on
 *   which token is registered in the markets mapping.
 *
 *   Multiple PT markets can be registered, allowing the same swapper
 *   instance to work with different PT tokens.
 */
contract PendleSwapper is BaseSwapper {
    using SafeERC20 for ERC20;

    // Pendle Router V4 - same address across all supported chains
    address public pendleRouter = 0x888888888889758F76e7103c6CbF23ABbF58F946;

    // Market registry: PT address => market address
    mapping(address => address) public markets;

    /**
     * @dev Register a PT token with its corresponding market.
     * @param _pt The address of the Principal Token.
     * @param _market The address of the Pendle market for this PT.
     */
    function _setMarket(address _pt, address _market) internal virtual {
        markets[_pt] = _market;
    }

    /**
     * @dev Swap tokens using Pendle.
     *
     *   If `_to` is a registered PT, this buys PT with `_from` token.
     *   If `_from` is a registered PT, this sells PT for `_to` token.
     *   For selling, automatically uses AMM if pre-expiry or redemption if post-expiry.
     *
     * @param _from The token to swap from.
     * @param _to The token to swap to.
     * @param _amountIn The amount of `_from` to swap.
     * @param _minAmountOut The minimum amount of `_to` to receive.
     * @return _amountOut The actual amount of `_to` received.
     */
    function _swapFrom(
        address _from,
        address _to,
        uint256 _amountIn,
        uint256 _minAmountOut
    ) internal virtual returns (uint256 _amountOut) {
        if (_amountIn == 0 || _amountIn < minAmountToSell) {
            return 0;
        }

        // Check if we're buying PT (_to is a registered PT)
        address market = markets[_to];
        if (market != address(0)) {
            return _buyPt(_from, _to, market, _amountIn, _minAmountOut);
        }

        // Check if we're selling PT (_from is a registered PT)
        market = markets[_from];
        if (market != address(0)) {
            if (IPMarket(market).isExpired()) {
                return _redeemPt(_from, market, _to, _amountIn, _minAmountOut);
            } else {
                return _sellPt(_from, market, _to, _amountIn, _minAmountOut);
            }
        }

        revert("PendleSwapper: unknown market");
    }

    /**
     * @dev Buy PT tokens using the Pendle AMM.
     * @param _tokenIn The input token (underlying or SY-compatible token).
     * @param _market The Pendle market address.
     * @param _amountIn Amount of input token to spend.
     * @param _minPtOut Minimum PT to receive.
     * @return _amountOut Amount of PT received.
     */
    function _buyPt(
        address _tokenIn,
        address, // _pt - not used, market determines PT
        address _market,
        uint256 _amountIn,
        uint256 _minPtOut
    ) internal virtual returns (uint256 _amountOut) {
        _checkAllowance(pendleRouter, _tokenIn, _amountIn);

        (uint256 netPtOut, , ) = IPendleRouter(pendleRouter).swapExactTokenForPt(
            address(this),
            _market,
            _minPtOut,
            _getDefaultApproxParams(),
            _getSimpleTokenInput(_tokenIn, _amountIn),
            _getEmptyLimitOrderData()
        );

        _amountOut = netPtOut;
    }

    /**
     * @dev Sell PT tokens via the Pendle AMM (pre-expiry).
     * @param _pt The PT token to sell.
     * @param _market The Pendle market address.
     * @param _tokenOut The output token to receive.
     * @param _amountIn Amount of PT to sell.
     * @param _minTokenOut Minimum output token to receive.
     * @return _amountOut Amount of output token received.
     */
    function _sellPt(
        address _pt,
        address _market,
        address _tokenOut,
        uint256 _amountIn,
        uint256 _minTokenOut
    ) internal virtual returns (uint256 _amountOut) {
        _checkAllowance(pendleRouter, _pt, _amountIn);

        (uint256 netTokenOut, , ) = IPendleRouter(pendleRouter).swapExactPtForToken(
            address(this),
            _market,
            _amountIn,
            _getSimpleTokenOutput(_tokenOut, _minTokenOut),
            _getEmptyLimitOrderData()
        );

        _amountOut = netTokenOut;
    }

    /**
     * @dev Redeem PT tokens after expiry.
     * @param _pt The PT token to redeem.
     * @param _market The Pendle market address (used to get YT address).
     * @param _tokenOut The output token to receive.
     * @param _amountIn Amount of PT to redeem.
     * @param _minTokenOut Minimum output token to receive.
     * @return _amountOut Amount of output token received.
     */
    function _redeemPt(
        address _pt,
        address _market,
        address _tokenOut,
        uint256 _amountIn,
        uint256 _minTokenOut
    ) internal virtual returns (uint256 _amountOut) {
        (, , IPYieldToken YT) = IPMarket(_market).readTokens();

        _checkAllowance(pendleRouter, _pt, _amountIn);

        (uint256 netTokenOut, ) = IPendleRouter(pendleRouter).redeemPyToToken(
            address(this),
            address(YT),
            _amountIn,
            _getSimpleTokenOutput(_tokenOut, _minTokenOut)
        );

        _amountOut = netTokenOut;
    }

    /**
     * @dev Returns the default ApproxParams for PT swaps.
     *   These are Pendle's recommended defaults that work without offchain hints.
     *   Uses ~180k gas for the approximation.
     */
    function _getDefaultApproxParams()
        internal
        pure
        virtual
        returns (ApproxParams memory)
    {
        return
            ApproxParams({
                guessMin: 0,
                guessMax: type(uint256).max,
                guessOffchain: 0,
                maxIteration: 256,
                eps: 1e14 // 0.01%
            });
    }

    /**
     * @dev Returns an empty LimitOrderData struct.
     *   Limit order integration is not supported in this base swapper.
     */
    function _getEmptyLimitOrderData()
        internal
        pure
        virtual
        returns (LimitOrderData memory)
    {
        return
            LimitOrderData({
                limitRouter: address(0),
                epsSkipMarket: 0,
                normalFills: new FillOrderParams[](0),
                flashFills: new FillOrderParams[](0),
                optData: ""
            });
    }

    /**
     * @dev Creates a simple TokenInput struct for direct token deposits.
     *   This assumes the input token is directly accepted by the SY contract.
     * @param _tokenIn The input token address.
     * @param _amount The amount of tokens.
     */
    function _getSimpleTokenInput(
        address _tokenIn,
        uint256 _amount
    ) internal pure virtual returns (TokenInput memory) {
        return
            TokenInput({
                tokenIn: _tokenIn,
                netTokenIn: _amount,
                tokenMintSy: _tokenIn, // Same as tokenIn for direct deposits
                pendleSwap: address(0), // No external swap needed
                swapData: SwapData({
                    swapType: SwapType.NONE,
                    extRouter: address(0),
                    extCalldata: "",
                    needScale: false
                })
            });
    }

    /**
     * @dev Creates a simple TokenOutput struct for direct token redemptions.
     *   This assumes the output token is directly redeemable from the SY contract.
     * @param _tokenOut The output token address.
     * @param _minTokenOut Minimum amount of tokens to receive.
     */
    function _getSimpleTokenOutput(
        address _tokenOut,
        uint256 _minTokenOut
    ) internal pure virtual returns (TokenOutput memory) {
        return
            TokenOutput({
                tokenOut: _tokenOut,
                minTokenOut: _minTokenOut,
                tokenRedeemSy: _tokenOut, // Same as tokenOut for direct redemptions
                pendleSwap: address(0), // No external swap needed
                swapData: SwapData({
                    swapType: SwapType.NONE,
                    extRouter: address(0),
                    extCalldata: "",
                    needScale: false
                })
            });
    }

    /**
     * @dev Internal safe function to make sure the contract you want to
     *   interact with has enough allowance to pull the desired tokens.
     * @param _contract The address of the contract that will move the token.
     * @param _token The ERC-20 token that will be getting spent.
     * @param _amount The amount of `_token` to be spent.
     */
    function _checkAllowance(
        address _contract,
        address _token,
        uint256 _amount
    ) internal virtual {
        if (ERC20(_token).allowance(address(this), _contract) < _amount) {
            ERC20(_token).forceApprove(_contract, _amount);
        }
    }
}
