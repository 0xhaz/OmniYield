// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.26;

interface IYieldOracle {
    function update() external;

    function consult(uint256 forInterval) external view returns (uint256 amountOut);

    // accumulates/updates internal state and returns cumulatives
    // oracle should call this when updating
    function cumulatives() external returns (uint256 cumulativeYield);
}
