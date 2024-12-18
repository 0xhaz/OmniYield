// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.26;

import {VaultBase, IEVC} from "src/abstracts/VaultBase.sol";
import {Ownable, Context} from "@openzeppelin/contracts/access/Ownable.sol";
import {EVCClient, EVCUtil} from "src/abstracts/EVCClient.sol";
import {ERC4626, IERC20, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @title OmniBaseVault
 * @notice Implements the base Vault functionality combining EVC and ERC4626 for use in the Omni Yield system
 *
 */
contract OmniBaseVault is VaultBase, ERC4626, Ownable {
    using Math for uint256;

    event SupplyCapSet(uint256 newSupplyCap);

    /*//////////////////////////////////////////////////////////////
                               ERRORS
    //////////////////////////////////////////////////////////////*/
    error OmniBaseVault__SnapshotNotTaken();
    error OmniBaseVault__SupplyCapExceeded();

    /*//////////////////////////////////////////////////////////////
                            GLOBAL STATE
    //////////////////////////////////////////////////////////////*/
    uint256 internal _totalAssets;
    uint256 public supplyCap;

    /*//////////////////////////////////////////////////////////////åç
                            CONSTRUCTORS
    //////////////////////////////////////////////////////////////*/
    constructor(IEVC _evc, IERC20 _asset, string memory _name, string memory _symbol)
        VaultBase(_evc)
        ERC4626(_asset)
        ERC20(_name, _symbol)
        Ownable(msg.sender)
    {}

    /**
     * @notice Retrieves the message sender in the context of the EVC
     * @dev This function returns the account on behalf of which the current operation is being performed, which is
     * either msg.sender or the account authenticated by the EVC
     * @return The address of the message sender.
     */
    function _msgSender() internal view override(EVCUtil, Context) returns (address) {
        return EVCUtil._msgSender();
    }

    /**
     * @notice Creates a snapshot of the vault
     * @dev This function is called before any action that may affect the vault's state
     * @return The snapshot of the vault's state
     */
    function doCreateVaultSnapshot() internal virtual override returns (bytes memory) {
        // make total assets snapshot here and return it:
        return abi.encode(_totalAssets);
    }

    /**
     * @notice Checks the vault's status
     * @dev This function is called after any action that may affect the vault's state
     * @param snapshot The snapshot of the vault's state before the action
     */
    function doCheckVaultStatus(bytes memory snapshot) internal virtual override {
        // sanity check in case the snapshot hasn't been taken
        if (snapshot.length == 0) revert OmniBaseVault__SnapshotNotTaken();

        // validate the vault's state
        uint256 initialSupply = abi.decode(snapshot, (uint256));
        uint256 finalSupply = _convertToAssets(totalSupply(), Math.Rounding.Floor);

        // the supply cap is checked only if it's set
        if (supplyCap != 0 && finalSupply > supplyCap && finalSupply > initialSupply) {
            revert OmniBaseVault__SupplyCapExceeded();
        }
    }

    /**
     * @notice Checks the account's status
     * @dev This function is called after any action that may affect the account's state
     */
    function doCheckAccountStatus(address owner, address[] calldata) internal view virtual override {
        // no need to do anything here because the vault does not allow borrowing
    }

    /**
     * @notice Disables the controller for the account
     * @dev The controller is only disabled if the account has no debt
     */
    function disableController() external virtual override nonReentrant {
        // this vault doesn't allow borrowing, so we can't check that the account has no debt.
        // this vault should never be a controller, but user errors can happen
        EVCClient.disableController(_msgSender());
    }

    /**
     * @notice Returns the total assets in the vault
     * @return The total assets in the vault
     */
    function totalAssets() public view virtual override returns (uint256) {
        return _totalAssets;
    }

    /**
     * @notice Converts assets to shares
     * @dev That function is manipulable in its current form as it uses exact values. Considering that other vaults may
     * rely on it, for a production vault, a manipulation resistant mechanism should be implemented.
     * @dev Considering that this function may be relied on by controller vaults, it's read-only re-entrancy protected.
     * @param assets The amount of assets to convert
     * @return The converted amount of shares
     */
    function convertToShares(uint256 assets) public view virtual override nonReentrantRO returns (uint256) {
        return super.convertToShares(assets);
    }

    /**
     * @notice Converts shares to assets
     * @dev That function is manipulable in its current form as it uses exact values. Considering that other vaults may
     * rely on it, for a production vault, a manipulation resistant mechanism should be implemented.
     * @dev Considering that this function may be relied on by controller vaults, it's read-only re-entrancy protected.
     * @param shares The amount of shares to convert
     * @return The converted amount of assets
     */
    function convertToAssets(uint256 shares) public view virtual override nonReentrantRO returns (uint256) {
        return super.convertToAssets(shares);
    }

    /**
     * @notice Transfers a certain amount of shares to a recipient.
     * @param to The recipient of the transfer.
     * @param amount The amount shares to transfer.
     * @return A boolean indicating whether the transfer was successful.
     */
    function transfer(address to, uint256 amount)
        public
        virtual
        override(IERC20, ERC20)
        callThroughEVC
        nonReentrant
        returns (bool)
    {
        createVaultSnapshot();
        bool result = super.transfer(to, amount);

        // despite the fact that the vault status check might not be needed for shares transfer with current logic, it's
        // added here so that if anyone changes the snapshot/vault status check mechanisms in the inheriting contracts,
        // they will not forget to add the vault status check here
        requireAccountAndVaultStatusCheck(_msgSender());
        return result;
    }

    /**
     * @notice Transfers a certain amount of shares from a sender to a recipient.
     * @param from The sender of the transfer.
     * @param to The recipient of the transfer.
     * @param amount The amount of shares to transfer.
     * @return A boolean indicating whether the transfer was successful.
     */
    function transferFrom(address from, address to, uint256 amount)
        public
        virtual
        override(IERC20, ERC20)
        callThroughEVC
        nonReentrant
        returns (bool)
    {
        createVaultSnapshot();
        bool result = super.transferFrom(from, to, amount);

        // despite the fact that the vault status check might not be needed for shares transfer with current logic, it's
        // added here so that if anyone changes the snapshot/vault status check mechanisms in the inheriting contracts,
        // they will not forget to add the vault status check here
        requireAccountAndVaultStatusCheck(from);
        return result;
    }
}
