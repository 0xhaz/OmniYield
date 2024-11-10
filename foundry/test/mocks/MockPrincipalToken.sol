// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IPPrincipalToken} from "@pendle/core/contracts/interfaces/IPPrincipalToken.sol";

contract MockPrincipalToken is IPPrincipalToken, ERC20 {
    address public immutable SY;
    address public immutable factory;
    uint256 public immutable expiry;
    address public YT;

    constructor(address _SY, string memory _name, string memory _symbol, uint8 __decimals, uint256 _expiry)
        ERC20(_name, _symbol)
    {
        SY = _SY;
        factory = msg.sender;
        expiry = _expiry;
    }

    function isExpired() external view override returns (bool) {
        return block.timestamp >= expiry;
    }

    function burnByYT(address _to, uint256 _amount) external override {
        _burn(_to, _amount);
    }

    function initialize(address _YT) external override {
        YT = _YT;
    }

    function mintByYT(address _to, uint256 _amount) external override {
        _mint(_to, _amount);
    }
}
