// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.26;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IVault} from "evc/src/interfaces/IVault.sol";

/**
 * @title IOmniYieldCollateralVault
 * @dev Interface for the Omni Yield Collateral Vault
 */
interface IOmniYieldCollateralVault is IVault, IERC4626 {}
