// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.26;

import {IPtUsdOracle} from "src/interfaces/oracle/IPtUsdOracle.sol";

contract MockPtUsdOracle is IPtUsdOracle {
    function getPtPrice() external pure override returns (uint256) {
        return 0.97 ether;
    }
}
