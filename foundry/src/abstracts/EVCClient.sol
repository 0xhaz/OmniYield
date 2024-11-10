// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.26;

import {EVCUtil, IEVC} from "evc/src/utils/EVCUtil.sol";

/**
 * @title EVCClient
 * @dev This contract is an abstract base contract for interacting with Ethereum Vault Contract (EVC).
 * It provides utility functions for authenticating callers in the context of EVC operations
 * scheduling and forgiving status checks, and liquidating collateral shares
 */
abstract contract EVCClient is EVCUtil {
    error EVCClient__SharesSeizureFailed();

    constructor(IEVC evc_) EVCUtil(address(evc_)) {}

    /**
     * @notice Retrieves the collateral shares of the owner
     * @dev A collateral is a vault for which an account's balances are under the control of the currently enabled vault.
     * @param owner The owner of the collateral shares
     * @return An array of addresses that are enabled as collaterals for the owner
     */
    function getCollaterals(address owner) internal view returns (address[] memory) {
        return evc.getCollaterals(owner);
    }

    /**
     * @notice Checks whether a vault is enabled as a collateral for an account
     * @dev A controller is a vault that has been chosen for an account to have special control over account's balances in the enabled collaterals vaults.
     * @param owner The owner of the vault
     * @param vault The address of the vault
     * @return A boolean value that indicates whether the vault is an enabled collateral for the account
     */
    function isCollateralEnabled(address owner, address vault) internal view returns (bool) {
        return evc.isCollateralEnabled(owner, vault);
    }

    /**
     * @notice Retrieves the controllers enabled for an account
     * @param account The address of the account
     * @return An array of addresses that are enabled controllers for the account
     */
    function getControllers(address account) internal view returns (address[] memory) {
        return evc.getControllers(account);
    }

    /**
     * @notice Checks whether a vault is enabled as a controller for an account
     * @param account The address of the account
     * @param vault The address of the vault
     * @return A boolean value that indicates whether the vault is an enabled controller for the account
     */
    function isControllerEnabled(address account, address vault) internal view returns (bool) {
        return evc.isControllerEnabled(account, vault);
    }

    /**
     * @notice Disables the controller for an account
     * @dev A controller is a vault that has been chosen for an account to have special control over account's balances in the enabled collaterals vaults.
     * Only the vault itself can call this function.
     * Disabling a controller might change the order of controllers in the array obtained using getControllers function.
     * Account status checks are performed by calling into the selected controller vault and passing the array of currently enabled collaterals.
     * @param owner The owner of the account
     */
    function disableController(address owner) internal {
        evc.disableController(owner);
    }

    /**
     * @notice Checks the status of an account and reverts if it is not valid.
     * @dev If checks deferred, the account is added to the set of accounts to be checked at the end of the outermost checks-deferrable call.
     * There can be at most 10 unique accounts added to the set at a time.
     * Account status check is performed by calling into the selected controller vault and passing the array of currently enabled collaterals.
     * If controller is not selected, the account is always considered valid.
     * @param owner The address of the account to be checked
     */
    function requireAccountStatusCheck(address owner) internal {
        evc.requireAccountStatusCheck(owner);
    }

    /**
     * @notice Checks the status of a vault and reverts if it is not valid
     * @dev If checks deferred, the vault is added to the set of vaults to be checked at the end of the outermost checks-deferrable call.
     * There can be at most 10 unique vaults added to the set at a time.
     * This function can only be called by the vault itself.
     */
    function requireVaultStatusCheck() internal {
        evc.requireVaultStatusCheck();
    }

    /**
     * @notice Checks the status of an account and a vault and reverts if it is not valid.
     * @dev If checks deferred, the account and the vault are added to the respective sets of accounts and vaults to be checked at the end of the outermost checks-deferrable call.
     * Account status check is performed by calling into selected controller vault and passing the array of currently enabled collaterals.
     * If controller is not selected, the account is always considered valid. This function can only be called by the vault itself.
     * @param owner The address of the account to be checked.
     */
    function requireAccountAndVaultStatusCheck(address owner) internal {
        if (owner == address(0)) {
            evc.requireVaultStatusCheck();
        } else {
            evc.requireAccountAndVaultStatusCheck(owner);
        }
    }

    /**
     * @notice Forgives previously deferred account status checks
     * @dev Account address is removed from the set of addresses for which status checks are deferred.
     * This function can only be called by the currently enabled controller of a given account.
     * Depending on the vault implementation, may be needed in the liquidation flow.
     * @param owner The address of the account for which deferred status checks are to be forgiven
     */
    function forgiveAccountStatusCheck(address owner) internal {
        evc.forgiveAccountStatusCheck(owner);
    }

    /**
     * @notice Checks whether the status check is deferred for a given account
     * @dev This function reverts if the checks are in progress.
     * @param owner The address of the account for which it is checked whether the status check is deferred
     * @return A boolean value that indicates whether the status check is deferred for the account
     */
    function isAccountStatusCheckDeferred(address owner) internal view returns (bool) {
        return evc.isAccountStatusCheckDeferred(owner);
    }

    /**
     * @notice Checks whether the status check is deferred for a given vault
     * @dev This function reverts if the checks are in progress.
     * @param vault The address of the vault for which it is checked whether the status check is deferred.
     * @return A boolean value that indicates whether the status check is deferred for the vault
     */
    function isVaultStatusCheckDeferred(address vault) internal view returns (bool) {
        return evc.isVaultStatusCheckDeferred(vault);
    }

    /**
     * @notice Liquidates a certain amount of collateral shares from a violator's vault
     * @dev This function controls the collateral in order to transfers the specified amount of shares from the violator's vault of the liquidator
     * @param vault The address of the vault from which the shares are to be liquidated
     * @param liquidated The address of the account which has the shares being liquidated
     * @param liquidator The address to which the liquidated shares are to be transferred
     * @param shares The amount of shares to be liquidated
     */
    function liquidateCollateralShares(address vault, address liquidated, address liquidator, uint256 shares)
        internal
    {
        // Control the collateral in order to transfer shares from the violator's vault to the liquidator
        bytes memory result = evc.controlCollateral(
            vault, liquidated, 0, abi.encodeWithSignature("transfer(address,uint256)", liquidator, shares)
        );

        if (!(result.length == 0 || abi.decode(result, (bool)))) {
            revert EVCClient__SharesSeizureFailed();
        }
    }
}
