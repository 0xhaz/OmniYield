// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.26;

interface IAutomation {
    function checkUpkeep(bytes calldata /* checkData */ ) external view returns (bool, bytes memory);

    function performUpkeep(bytes calldata /* performData */ ) external;
}
