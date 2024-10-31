// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.26;

import {Ownable, Context} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC4626, IERC20, ERC20, Math} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {VaultBase, IEVC, EVCClient} from "src/abstracts/VaultBase.sol";
import {EVCUtil} from "evc/utils/EVCUtil.sol";

/**
 * @title VaultSimple
 * @dev This contract is a simple implementation of a Vault
 * @notice This contract is authenticated by the EVC before any action that may affect the state of the vault of an account
 * This is done to ensure that if it's EVC calling, the account is correctly authorized. This contract does
 * take the supply cap into account when calculating max deposit and max mint values
 */
contract VaultSimple is VaultBase, Ownable, ERC4626 {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error VaultSimple__SnapshotNotTaken();
    error VaultSimple__SupplyCapExceeded(uint256 maxDeposit, uint256 maxMint);

    /*//////////////////////////////////////////////////////////////
                              GLOBAL STATE
    //////////////////////////////////////////////////////////////*/
    uint256 internal totalAssets_;
    uint256 public supplyCap;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    event SupplyCapSet(uint256 supplyCap);

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    constructor(IEVC evc_, IERC20 asset_, string memory name_, string memory symbol_)
        VaultBase(evc_)
        Ownable(msg.sender)
        ERC4626(asset_)
        ERC20(name_, symbol_)
    {}

    /*//////////////////////////////////////////////////////////////
                            PUBLIC FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Transfers a certain amount of shares to a recipient
     * @param to The address of the recipient
     * @param amount The amount of shares to transfer
     * @return A boolean value indicating whether the transfer was successful
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
     * @notice Transfers a certain amount of shares from a sender to a recipient
     * @param from the sender of the transfer
     * @param to the recipient of the transfer
     * @param amount The amount shares to transfer
     * @return A boolean indicating whether the transfer was successful
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

    /**
     * @notice Deposits a certain amount of assets into the vault
     * @param assets The amount of assets to deposit
     * @param receiver The address of the account to receive the shares
     * @return shares The shares equivalent to the deposited assets
     */
    function deposit(uint256 assets, address receiver)
        public
        virtual
        override
        callThroughEVC
        nonReentrant
        returns (uint256 shares)
    {
        createVaultSnapshot();
        shares = super.deposit(assets, receiver);
        totalAssets_ += assets;
        requireVaultStatusCheck();
    }

    /**
     * @notice Mints a certain amount of shares to a recipient
     * @param shares The amount of shares to mint
     * @param receiver The address of the recipient
     * @return assets The assets equivalent to the minted shares
     */
    function mint(uint256 shares, address receiver)
        public
        virtual
        override
        callThroughEVC
        nonReentrant
        returns (uint256 assets)
    {
        createVaultSnapshot();
        assets = super.mint(shares, receiver);
        totalAssets_ += assets;
        requireVaultStatusCheck();
    }

    /**
     * @notice Withdraws a certain amount of assets for a recipient
     * @param assets The amount of assets to withdraw
     * @param receiver The address of the recipient
     * @param owner The owner of the assets
     * @return shares The shares equivalent to the withdrawn assets
     */
    function withdraw(uint256 assets, address receiver, address owner)
        public
        virtual
        override
        callThroughEVC
        nonReentrant
        returns (uint256 shares)
    {
        createVaultSnapshot();
        shares = super.withdraw(assets, receiver, owner);
        totalAssets_ -= assets;
        requireAccountAndVaultStatusCheck(owner);
    }

    /**
     * @notice Redeems a certain amount of shares for a recipient
     * @param shares The amount of shares to redeem
     * @param receiver The address of the recipient
     * @param owner The owner of the shares
     * @return assets The assets equivalent to the redeemed shares
     */
    function redeem(uint256 shares, address receiver, address owner)
        public
        virtual
        override
        callThroughEVC
        nonReentrant
        returns (uint256 assets)
    {
        createVaultSnapshot();
        assets = super.redeem(shares, receiver, owner);
        totalAssets_ -= assets;
        requireAccountAndVaultStatusCheck(owner);
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the total assets of the vault
     * @return The total assets of the vault
     */
    function totalAssets() public view virtual override returns (uint256) {
        return totalAssets_;
    }

    /**
     * @notice Converts assets to shares
     * @dev This function is manipulate in its current form as it uses exact values. Considering that other vaults may rely on it
     * for a production vault, a manipulation resistant mechanism should be used
     * @dev Considering that this function may be relied by controller vaults, it's read-only reentrancy protected
     * @param assets The amount of assets to convert
     * @return The converted shares
     */
    function convertToShares(uint256 assets) public view override nonReentrantRO returns (uint256) {
        return super.convertToShares(assets);
    }

    /**
     * @notice Converts shares to assets
     * @dev This function is to manipulate in its current form as it uses exact values. Considering that other vaults may rely on it
     * for a production vault, a manipulation resistant mechanism should be used
     * @dev Considering that this function may be relied by controller vaults, it's read-only reentrancy protected
     * @param shares The amount of shares to convert
     * @return The converted assets
     */
    function convertToAssets(uint256 shares) public view override nonReentrantRO returns (uint256) {
        return super.convertToAssets(shares);
    }

    /*//////////////////////////////////////////////////////////////
                           EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Sets the supply cap for the vault
     * @param newSupplyCap The new supply cap
     */
    function setSupplyCap(uint256 newSupplyCap) external onlyOwner {
        supplyCap = newSupplyCap;
        emit SupplyCapSet(newSupplyCap);
    }

    /**
     * @notice Disables the controller for an account
     * @dev The controller is only disable if the account has no debt
     */
    function disableController() external override {
        // this vault doesn't allow borrowing, so we can't check that the account has no debt
        // this vault should never be a controller, but user errors can happen
        EVCClient.disableController(_msgSender());
    }

    /*//////////////////////////////////////////////////////////////
                           INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Retrieves the message sender in the context of the EVC
     * @dev This function returns the account on behalf of which the current operation is being performed
     * which is either msg.sender or the account that has been authorized by the EVC
     * @return The address of the message sender
     */
    function _msgSender() internal view override(EVCUtil, Context) returns (address) {
        return EVCUtil._msgSender();
    }

    /**
     * @notice Creates a snapshot of the vault state
     * @dev This function is called before any action that may affect the vault's state
     * @return snapshot A snapshot of the vault state
     */
    function doCreateVaultSnapshot() internal virtual override returns (bytes memory snapshot) {
        // make total assets snapshot here and return it
        return abi.encode(totalAssets_);
    }

    /**
     * @notice Checks the vault status
     * @dev This function is called after any action that may affect the vault's state
     * @param snapshot The snapshot of the vault state before the action
     */
    function doCheckVaultStatus(bytes memory snapshot) internal virtual override {
        // sanity check that snapshot was taken
        if (snapshot.length == 0) revert VaultSimple__SnapshotNotTaken();

        uint256 initialSupply = abi.decode(snapshot, (uint256));
        uint256 finalSupply = _convertToAssets(totalSupply(), Math.Rounding.Floor);

        if (supplyCap != 0 && finalSupply > supplyCap && finalSupply > initialSupply) {
            revert VaultSimple__SupplyCapExceeded(finalSupply - initialSupply, finalSupply);
        }
    }

    /**
     * @notice Checks the account status
     * @dev This function is called after any action that may affect the account's state
     */
    function doCheckAccountStatus(address owner, address[] calldata) internal view virtual override {
        // no-op
    }
}
