// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.26;

import {IEVC} from "src/abstracts/VaultBase.sol";
import {OmniBaseVault} from "src/vaults/OmniBaseVault.sol";
import {IStandardizedYield} from "@pendle/core/contracts/interfaces/IStandardizedYield.sol";
import {IPYieldToken} from "@pendle/core/contracts/interfaces/IPYieldToken.sol";
import {IPPrincipalToken} from "@pendle/core/contracts/interfaces/IPPrincipalToken.sol";
import {IPMarketV3} from "@pendle/core/contracts/interfaces/IPMarketV3.sol";
import {PYIndexLib} from "@pendle/core/contracts/core/StandardizedYield/PYIndex.sol";
import {PtUsdOracle} from "src/providers/pendle/PtUsdOracle.sol";
import {PendlePYOracleLib} from "@pendle/core/contracts/oracles/PendlePYOracleLib.sol";
import {IOmniYieldCollateralVault} from "src/interfaces/IOmniYieldCollateralVault.sol";
import {IERC20, ERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {MarketApproxPtOutLib, ApproxParams} from "@pendle/core/contracts/router/base/ActionBase.sol";

/**
 * @title YTVaultBorrowable
 * @notice The contract for the Yield Token Vault that allows borrowing
 */
// contract YTVaultBorrowable is OmniBaseVault {
// /*//////////////////////////////////////////////////////////////
//                                  ERRORS
//     //////////////////////////////////////////////////////////////*/
// }
