// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.26;

import {SafeMath} from "@openzeppelin/utils/math/SafeMath.sol";

library MathUtils {
    using SafeMath for uint256;

    uint256 public constant SCALE = 1e18;

    function min(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x < y ? x : y;
    }

    function max(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x > y ? x : y;
    }

    function compound(
        // in wei
        uint256 principal,
        // rate is * SCALE
        uint256 ratePerPeriod,
        uint16 periods
    ) internal pure returns (uint256) {
        if (0 == ratePerPeriod) {
            return principal;
        }

        while (periods > 0) {
            // principal += principal * ratePerPeriod / SCALE;
            principal = principal.add(principal.mul(ratePerPeriod).div(SCALE));
            periods--;
        }

        return principal;
    }

    function compound2(uint256 principal, uint256 ratePerPeriod, uint16 periods) internal pure returns (uint256) {
        if (0 == ratePerPeriod) {
            return principal;
        }

        while (periods > 0) {
            if (periods % 2 == 1) {
                // principal += principal * ratePerPeriod / SCALE;
                principal = principal.add(principal.mul(ratePerPeriod).div(SCALE));
                periods--;
            } else {
                // ratePerPeriod = (( 2 * ratePerPeriod * SCALE ) + (ratePerPeriod * ratePerPeriod)) / SCALE;
                ratePerPeriod =
                    ((uint256(2).mul(ratePerPeriod).mul(SCALE)).add(ratePerPeriod.mul(ratePerPeriod))).div(SCALE);
                periods /= 2;
            }
        }

        return principal;
    }

    function linearGain(uint256 principal, uint256 ratePerPeriod, uint16 periods) internal pure returns (uint256) {
        return principal.add(fractionOf(principal, ratePerPeriod.mul(periods)));
    }

    // computes a * f / SCALE
    function fractionOf(uint256 a, uint256 f) internal pure returns (uint256) {
        return a.mul(f).div(SCALE);
    }
}
