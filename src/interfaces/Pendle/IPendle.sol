// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

// ============ Pendle Structs ============

enum SwapType {
    NONE,
    KYBERSWAP,
    ONE_INCH,
    ETH_WETH
}

struct SwapData {
    SwapType swapType;
    address extRouter;
    bytes extCalldata;
    bool needScale;
}

struct TokenInput {
    address tokenIn;
    uint256 netTokenIn;
    address tokenMintSy;
    address pendleSwap;
    SwapData swapData;
}

struct TokenOutput {
    address tokenOut;
    uint256 minTokenOut;
    address tokenRedeemSy;
    address pendleSwap;
    SwapData swapData;
}

struct ApproxParams {
    uint256 guessMin;
    uint256 guessMax;
    uint256 guessOffchain;
    uint256 maxIteration;
    uint256 eps;
}

struct FillOrderParams {
    Order order;
    bytes signature;
    uint256 makingAmount;
}

struct Order {
    uint256 salt;
    uint256 expiry;
    uint256 nonce;
    OrderType orderType;
    address token;
    address YT;
    address maker;
    address receiver;
    uint256 makingAmount;
    uint256 lnImpliedRate;
    uint256 failSafeRate;
    bytes permit;
}

enum OrderType {
    SY_FOR_PT,
    PT_FOR_SY,
    SY_FOR_YT,
    YT_FOR_SY
}

struct LimitOrderData {
    address limitRouter;
    uint256 epsSkipMarket;
    FillOrderParams[] normalFills;
    FillOrderParams[] flashFills;
    bytes optData;
}

// ============ Pendle Interfaces ============

interface IStandardizedYield {
    function deposit(
        address receiver,
        address tokenIn,
        uint256 amountTokenToDeposit,
        uint256 minSharesOut
    ) external payable returns (uint256 amountSharesOut);

    function redeem(
        address receiver,
        uint256 amountSharesToRedeem,
        address tokenOut,
        uint256 minTokenOut,
        bool burnFromInternalBalance
    ) external returns (uint256 amountTokenOut);

    function getTokensIn() external view returns (address[] memory);

    function getTokensOut() external view returns (address[] memory);

    function yieldToken() external view returns (address);
}

interface IPPrincipalToken {
    function SY() external view returns (address);

    function YT() external view returns (address);

    function expiry() external view returns (uint256);

    function isExpired() external view returns (bool);
}

interface IPYieldToken {
    function SY() external view returns (address);

    function PT() external view returns (address);

    function expiry() external view returns (uint256);

    function isExpired() external view returns (bool);

    function redeemPY(address receiver) external returns (uint256 amountSyOut);
}

interface IPMarket {
    function readTokens()
        external
        view
        returns (
            IStandardizedYield _SY,
            IPPrincipalToken _PT,
            IPYieldToken _YT
        );

    function isExpired() external view returns (bool);

    function expiry() external view returns (uint256);
}

interface IPendleRouter {
    function swapExactTokenForPt(
        address receiver,
        address market,
        uint256 minPtOut,
        ApproxParams calldata guessPtOut,
        TokenInput calldata input,
        LimitOrderData calldata limit
    )
        external
        payable
        returns (uint256 netPtOut, uint256 netSyFee, uint256 netSyInterm);

    function swapExactPtForToken(
        address receiver,
        address market,
        uint256 exactPtIn,
        TokenOutput calldata output,
        LimitOrderData calldata limit
    )
        external
        returns (uint256 netTokenOut, uint256 netSyFee, uint256 netSyInterm);

    function redeemPyToToken(
        address receiver,
        address YT,
        uint256 netPyIn,
        TokenOutput calldata output
    ) external returns (uint256 netTokenOut, uint256 netSyInterm);

    function swapExactSyForPt(
        address receiver,
        address market,
        uint256 exactSyIn,
        uint256 minPtOut,
        ApproxParams calldata guessPtOut,
        LimitOrderData calldata limit
    ) external returns (uint256 netPtOut, uint256 netSyFee);

    function swapExactPtForSy(
        address receiver,
        address market,
        uint256 exactPtIn,
        uint256 minSyOut,
        LimitOrderData calldata limit
    ) external returns (uint256 netSyOut, uint256 netSyFee);

    function redeemPyToSy(
        address receiver,
        address YT,
        uint256 netPyIn,
        uint256 minSyOut
    ) external returns (uint256 netSyOut);
}
