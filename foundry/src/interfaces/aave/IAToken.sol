// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.26;

interface IAToken {
    function UNDERLYING_ASSET_ADDRESS() external view returns (address);
    function getIncentivesController() external view returns (address);
    function POOL() external view returns (address);
    function balanceOf(address user) external view returns (uint256);
}
