// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

abstract contract Governed is Ownable {
    error Governed__NotGovernor();
    error Governed__NotGuardian();

    address public daoGovernor;
    address public daoGuardian;

    modifier onlyDaoGovernor() {
        if (msg.sender != daoGovernor) revert Governed__NotGovernor();
        _;
    }

    modifier onlyDaoGuardian() {
        if (msg.sender != daoGuardian) revert Governed__NotGuardian();
        _;
    }

    constructor() Ownable(msg.sender) {
        daoGovernor = msg.sender;
        daoGuardian = msg.sender;
    }

    function setDaoGovernor(address _daoGovernor) external onlyOwner {
        daoGovernor = _daoGovernor;
    }

    function setDaoGuardian(address _daoGuardian) external onlyOwner {
        daoGuardian = _daoGuardian;
    }
}
