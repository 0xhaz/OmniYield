// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.26;

import {ERC4626, IERC20, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {IERC3156FlashLender} from "@openzeppelin/contracts/interfaces/IERC3156FlashLender.sol";
import {IERC3156FlashBorrower} from "@openzeppelin/contracts/interfaces/IERC3156FlashBorrower.sol";
import {IStandardizedYield} from "@pendle/core/contracts/interfaces/IStandardizedYield.sol";
import {IPYieldToken} from "@pendle/core/contracts/interfaces/IPYieldToken.sol";
import {IPPrincipalToken} from "@pendle/core/contracts/interfaces/IPPrincipalToken.sol";
import {IPMarketV3} from "@pendle/core/contracts/interfaces/IPMarketV3.sol";
import {PtUsdOracle} from "src/providers/pendle/PtUsdOracle.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
// import {PendleLpOracleLib} from "@pendle/core/contracts/oracles/PendleLpOracleLib.sol";
import {PendlePYOracleLib} from "@pendle/core/contracts/oracles/PendlePYOracleLib.sol";
import {PYIndexLib} from "@pendle/core/contracts/core/StandardizedYield/PYIndex.sol";
import {MarketApproxPtOutLib, ApproxParams} from "@pendle/core/contracts/router/base/ActionBase.sol";

/**
 * @title OmniPTVault
 * @notice This implements an ERC4626 vault that allows for repo loans with PT as collateral
 */
