// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.26;

abstract contract ILpUsdOracle {
    function getPtPrice() external view virtual returns (uint256);
}
