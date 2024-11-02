// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.26;

interface ISmartYield {
    function deposit(uint256 _amount) external;
    function withdraw(uint256 _amount) external;
    function getTotalBalance() external view returns (uint256);
}
