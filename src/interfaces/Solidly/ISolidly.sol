// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.18;

interface ISolidly {
    struct route {
        address from;
        address to;
        bool stable;
    }

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        route[] calldata routes,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function getAmountsOut(
        uint256 amountIn,
        route[] memory routes
    ) external view returns (uint256[] memory amounts);
}
