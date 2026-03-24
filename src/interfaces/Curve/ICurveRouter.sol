// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

interface ICurveRouter {

    /// @notice Performs up to 5 swaps in a single transaction
    /// @param _route Array of [token_in, pool, token_out, pool, ...] with unused slots as address(0)
    /// @param _swap_params Array of [i, j, swap_type, pool_type, n_coins] per swap step
    /// @param _amount Amount of input token to swap
    /// @param _expected Minimum acceptable output amount
    /// @param _pools Array of pool addresses (only needed for swap_type 3)
    /// @param _receiver Address to receive output tokens
    /// @return Amount of output tokens received
    function exchange(
        address[11] calldata _route,
        uint256[5][5] calldata _swap_params,
        uint256 _amount,
        uint256 _expected,
        address[5] calldata _pools,
        address _receiver
    ) external returns (uint256);

    /// @notice Get expected output amount for a swap
    function get_dy(
        address[11] calldata _route,
        uint256[5][5] calldata _swap_params,
        uint256 _amount,
        address[5] calldata _pools
    ) external view returns (uint256);
}
