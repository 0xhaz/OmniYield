// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.26;

interface IOracle {
    function getPrice(uint256 index) external view returns (uint256);
}
