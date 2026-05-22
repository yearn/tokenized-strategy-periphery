// SPDX-License-Identifier: MIT
pragma solidity >=0.8.18;

/// @title Currency
/// @notice Currency is a type that represents either a native token or an ERC20 token
type Currency is address;

/// @title IHooks
/// @notice Interface for V4 hooks
interface IHooks {}

/// @title PoolKey
/// @notice Identifies a Uniswap V4 pool
struct PoolKey {
    Currency currency0;
    Currency currency1;
    uint24 fee;
    int24 tickSpacing;
    IHooks hooks;
}

/// @title PathKey
/// @notice Describes a single hop in a multi-hop swap path
struct PathKey {
    Currency intermediateCurrency;
    uint24 fee;
    int24 tickSpacing;
    IHooks hooks;
    bytes hookData;
}

/// @title IV4Router
/// @notice Interface for V4Router swap parameters
interface IV4Router {
    /// @notice Parameters for single-hop exact input swap
    struct ExactInputSingleParams {
        PoolKey poolKey;
        bool zeroForOne;
        uint128 amountIn;
        uint128 amountOutMinimum;
        bytes hookData;
    }

    /// @notice Parameters for multi-hop exact input swap
    struct ExactInputParams {
        Currency currencyIn;
        PathKey[] path;
        uint128 amountIn;
        uint128 amountOutMinimum;
    }
}
