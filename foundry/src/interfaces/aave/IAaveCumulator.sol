// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.26;

interface IAaveCumulator {
    function beforeATokenBalanceChange() external;

    function afterATokenBalanceChange() external;
}
