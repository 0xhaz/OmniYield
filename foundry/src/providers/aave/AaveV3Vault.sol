// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.26;

import {AaveV3ERC4626, ERC4626, ERC20, IPool, IRewardsController} from "yield-daddy/src/aave-v3/AaveV3ERC4626.sol";
import {VaultBase, EVCClient, IEVC, IVault} from "src/abstracts/VaultBase.sol";
import {IIRM} from "src/interfaces/IIRM.sol";
import {EVCClient, EVCUtil} from "src/abstracts/EVCClient.sol";
import {IPriceOracle} from "src/interfaces/IPriceOracle.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Ownable, Context} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title AaveV3Vault
 * @dev This contract is the Aave V3 Vault using EVC as the controller
 */
contract AaveV3Vault is AaveV3ERC4626, Ownable {
    using Math for uint256;
    /*//////////////////////////////////////////////////////////////
                              ERRORS
    //////////////////////////////////////////////////////////////*/

    error AaveV3Vault__ZeroShares();

    /*//////////////////////////////////////////////////////////////
                           GLOBAL STATE
    //////////////////////////////////////////////////////////////*/

    /*//////////////////////////////////////////////////////////////
                           CONSTRUCTORS
    //////////////////////////////////////////////////////////////*/

    constructor(
        IEVC evc_,
        ERC20 asset_,
        ERC20 aToken_,
        IPool lendingPool_,
        address rewardsRecipient_,
        IRewardsController rewardsController_
    ) AaveV3ERC4626(asset_, aToken_, lendingPool_, rewardsRecipient_, rewardsController_) Ownable(msg.sender) {}

    /*//////////////////////////////////////////////////////////////
                           PUBLIC FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function deposit(uint256 assets, address receiver) public override returns (uint256 shares) {
        address msgSender = _msgSender();

        super.deposit(assets, receiver);
    }

    /*//////////////////////////////////////////////////////////////
                           INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /*//////////////////////////////////////////////////////////////
                           OVERRIDE FUNCTIONS
    //////////////////////////////////////////////////////////////*/
}
