// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.26;

abstract contract IPtUsdOracle {
    function getPtPrice() external view virtual returns (uint256);
}
