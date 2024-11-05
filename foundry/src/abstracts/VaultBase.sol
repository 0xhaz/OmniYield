// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.26;

import {IVault} from "evc/src/interfaces/IVault.sol";
import {EVCClient, IEVC} from "./EVCClient.sol";

/**
 * @title VaultBase
 * @dev This contract is an abstract contract for Vaults
 * It declares function that must be defined in the child contract in order to
 * correctly implement the controller release, vault status snapshot and vault status check
 */
abstract contract VaultBase is IVault, EVCClient {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error VaultBase__ReentrancyGuard();
    error VaultBase__AlreadyInitialized();

    /*//////////////////////////////////////////////////////////////
                              GLOBAL STATE
    //////////////////////////////////////////////////////////////*/

    IEVC internal _evc;

    uint256 private constant REENTRANCY_UNLOCKED = 1;
    uint256 private constant REENTRANCY_LOCKED = 2;

    uint256 private reentrancyLock;
    bytes private snapshot;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    constructor(IEVC evc_) EVCClient(evc_) {
        reentrancyLock = REENTRANCY_UNLOCKED;
        _evc = evc_;
    }

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/
    /// @notice Prevents reentrancy attacks
    modifier nonReentrant() virtual {
        if (reentrancyLock == REENTRANCY_LOCKED) revert VaultBase__ReentrancyGuard();

        reentrancyLock = REENTRANCY_LOCKED;

        _;

        reentrancyLock = REENTRANCY_UNLOCKED;
    }

    /// @notice Prevents read-only reentrancy (view functions)
    modifier nonReentrantRO() virtual {
        if (reentrancyLock != REENTRANCY_UNLOCKED) revert VaultBase__ReentrancyGuard();

        _;
    }

    /*//////////////////////////////////////////////////////////////
                           EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Initializes the vault
    /// @dev Must be called by the proxy contract
    function initialize(IEVC evc_) external {
        _evc = evc_;
    }

    /// @notice Checks the vault status
    /// @dev Executed as a result of requiring vault status check on the EVC
    function checkVaultStatus() external onlyEVCWithChecksInProgress returns (bytes4 magicValue) {
        doCheckVaultStatus(snapshot);
        delete snapshot;

        return IVault.checkVaultStatus.selector;
    }

    /// @notice Checks the account status
    /// @dev Executed on a controller as a result of requiring account status check on the EVC
    function checkAccountStatus(address owner, address[] calldata collaterals)
        external
        view
        onlyEVCWithChecksInProgress
        returns (bytes4 magicValue)
    {
        doCheckAccountStatus(owner, collaterals);

        return IVault.checkAccountStatus.selector;
    }

    /*//////////////////////////////////////////////////////////////
                           INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Creates a snapshot of the vault state
    function createVaultSnapshot() internal {
        // We delete snapshots on `checkVaultStatus`, which can only happen at the end of the EVC batch. Snapshots
        // are taken before any action is taken on the vault that affects the vault asset records and deleted at the end,
        // so that asset calculations are always based on the state before the current batch of actions
        if (snapshot.length == 0) {
            snapshot = doCreateVaultSnapshot();
        }
    }

    /*//////////////////////////////////////////////////////////////
                           UTILITY FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Creates a snapshot of the vault state
    /// @dev Must be overridden by the child contract
    function doCreateVaultSnapshot() internal virtual returns (bytes memory snapshot);

    /// @notice Checks the vault status
    /// @dev Must be overridden by the child contract
    function doCheckVaultStatus(bytes memory snapshot) internal virtual;

    /// @notice Checks the account status
    /// @dev Must be overridden by the child contract
    function doCheckAccountStatus(address owner, address[] calldata) internal view virtual;

    /// @notice Disables a controller for an account
    /// @dev Must be overridden by the child contract. Must call the EVC.disableController() only if it's safe to do so
    /// (i.e the account has repaid their debt)
    function disableController() external virtual;
}
