// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.26;

import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {IEVC} from "src/abstracts/VaultBase.sol";

contract OmniPlatformOperator {
    IEVC public immutable evc;
    address public collateralVault;
    address public omniVault;

    constructor(IEVC _evc, address _collateralVault, address _omniVault) {
        evc = _evc;
        collateralVault = _collateralVault;
        omniVault = _omniVault;
    }

    function approveAllVaultsOnBehalfOf(address onBehalfOfAccount) external {
        evc.enableController(onBehalfOfAccount, omniVault);
        evc.enableCollateral(onBehalfOfAccount, omniVault);
        evc.enableCollateral(onBehalfOfAccount, collateralVault);
    }
}
