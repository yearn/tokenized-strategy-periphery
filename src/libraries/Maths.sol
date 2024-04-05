// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.18;

// Math library from https://github.com/ajna-finance/ajna-core/blob/master/src/libraries/internal/Maths.sol

/**
    @title  Maths library
    @notice Internal library containing common maths.
 */
library Maths {
    uint256 internal constant WAD = 1e18;
    uint256 internal constant RAY = 1e27;

    function wmul(uint256 x, uint256 y) internal pure returns (uint256) {
        return (x * y + WAD / 2) / WAD;
    }

    function floorWmul(uint256 x, uint256 y) internal pure returns (uint256) {
        return (x * y) / WAD;
    }

    function ceilWmul(uint256 x, uint256 y) internal pure returns (uint256) {
        return (x * y + WAD - 1) / WAD;
    }

    function wdiv(uint256 x, uint256 y) internal pure returns (uint256) {
        return (x * WAD + y / 2) / y;
    }

    function floorWdiv(uint256 x, uint256 y) internal pure returns (uint256) {
        return (x * WAD) / y;
    }

    function ceilWdiv(uint256 x, uint256 y) internal pure returns (uint256) {
        return (x * WAD + y - 1) / y;
    }

    function ceilDiv(uint256 x, uint256 y) internal pure returns (uint256) {
        return (x + y - 1) / y;
    }

    function max(uint256 x, uint256 y) internal pure returns (uint256) {
        return x >= y ? x : y;
    }

    function min(uint256 x, uint256 y) internal pure returns (uint256) {
        return x <= y ? x : y;
    }

    function wad(uint256 x) internal pure returns (uint256) {
        return x * WAD;
    }

    function rmul(uint256 x, uint256 y) internal pure returns (uint256) {
        return (x * y + RAY / 2) / RAY;
    }

    function rpow(uint256 x, uint256 n) internal pure returns (uint256 z) {
        z = n % 2 != 0 ? x : RAY;

        for (n /= 2; n != 0; n /= 2) {
            x = rmul(x, x);

            if (n % 2 != 0) {
                z = rmul(z, x);
            }
        }
    }

    /*************************/
    /*** Integer Functions ***/
    /*************************/

    function maxInt(int256 x, int256 y) internal pure returns (int256) {
        return x >= y ? x : y;
    }

    function minInt(int256 x, int256 y) internal pure returns (int256) {
        return x <= y ? x : y;
    }
}
