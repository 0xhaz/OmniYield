// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.26;

import {Owned} from "solmate/auth/Owned.sol";
import {ERC4626, ERC20} from "solmate/mixins/ERC4626.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {VaultBase, IEVC, EVCClient} from "src/abstracts/VaultBase.sol";
import {EVCUtil} from "evc/src/utils/EVCUtil.sol";

/**
 * @title VaultSimple
 * @dev This contract is a simple implementation of a Vault
 * @notice This contract is authenticated by the EVC before any action that may affect the state of the vault of an account
 * This is done to ensure that if it's EVC calling, the account is correctly authorized. This contract does
 * take the supply cap into account when calculating max deposit and max mint values
 */
contract VaultSimple is VaultBase, Owned, ERC4626 {
    using FixedPointMathLib for uint256;
    using SafeTransferLib for ERC20;
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error VaultSimple__SnapshotNotTaken();
    error VaultSimple__SupplyCapExceeded();
    error VaultSimple__ZeroShares();

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
    constructor(IEVC evc_, ERC20 asset_, string memory name_, string memory symbol_)
        VaultBase(evc_)
        Owned(msg.sender)
        ERC4626(asset_, name_, symbol_)
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
    function transfer(address to, uint256 amount) public virtual override callThroughEVC nonReentrant returns (bool) {
        address msgSender = _msgSender();

        createVaultSnapshot();

        balanceOf[msgSender] -= amount;

        // cannot overflow becuase the sum of all user
        // balances can't exceed the max uint value
        unchecked {
            balanceOf[to] += amount;
        }

        emit Transfer(msgSender, to, amount);

        // despite the fact that the vault status check might not be needed for shares transfer with current logic, it's
        // added here so that if anyone changes the snapshot/vault status check mechanisms in the inheriting contracts,
        // they will not forget to add the vault status check here
        requireAccountAndVaultStatusCheck(_msgSender());
        return true;
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
        override
        callThroughEVC
        nonReentrant
        returns (bool)
    {
        address msgSender = _msgSender();

        createVaultSnapshot();

        uint256 allowed = allowance[from][msgSender]; // Saves gas for limited approvals

        if (allowed != type(uint256).max) {
            allowance[from][msgSender] = allowed - amount;
        }

        balanceOf[from] -= amount;

        // cannot overflow becuase the sum of all user
        // balances can't exceed the max uint value
        unchecked {
            balanceOf[to] += amount;
        }

        // despite the fact that the vault status check might not be needed for shares transfer with current logic, it's
        // added here so that if anyone changes the snapshot/vault status check mechanisms in the inheriting contracts,
        // they will not forget to add the vault status check here
        requireAccountAndVaultStatusCheck(from);
        return true;
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
        address msgSender = _msgSender();

        createVaultSnapshot();

        // Check for rounding error since we round down in previewDeposit
        if ((shares = _convertToShares(assets, false)) == 0) revert VaultSimple__ZeroShares();

        totalAssets_ += assets;

        _mint(receiver, shares);

        emit Deposit(msgSender, receiver, assets, shares);

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
        address msgSender = _msgSender();

        createVaultSnapshot();

        assets = _convertToAssets(shares, true); // No need to check for rounding error, previewMint rounds up

        // Need to transfer before minting or ERC777s could reenter
        asset.safeTransferFrom(msgSender, address(this), assets);

        totalAssets_ += assets;

        _mint(receiver, shares);

        emit Deposit(msgSender, receiver, assets, shares);

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
        address msgSender = _msgSender();

        createVaultSnapshot();

        shares = _convertToShares(assets, true); // No need to check for rounding error, previewWithdraw rounds down

        if (msgSender != owner) {
            uint256 allowed = allowance[owner][msgSender]; // Saves gas for limited approvals

            if (allowed != type(uint256).max) {
                allowance[owner][msgSender] = allowed - shares;
            }
        }

        _burn(owner, shares);

        emit Withdraw(msgSender, receiver, owner, assets, shares);

        asset.safeTransfer(receiver, assets);

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
        address msgSender = _msgSender();

        createVaultSnapshot();

        if (msgSender != owner) {
            uint256 allowed = allowance[owner][msgSender]; // Saves gas for limited approvals

            if (allowed != type(uint256).max) {
                allowance[owner][msgSender] = allowed - shares;
            }
        }

        // check for rounding error since we round down in previewRedeem
        if ((assets = _convertToAssets(shares, false)) == 0) revert VaultSimple__ZeroShares();

        _burn(owner, shares);

        emit Withdraw(msgSender, receiver, owner, assets, shares);

        asset.safeTransfer(receiver, assets);

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

    /**
     * @notice Simulates the effects of depositing a certain amount of assets at the current block
     * @param assets The amount of assets to deposit
     * @return The amount of shares that would be minted
     */
    function previewDeposit(uint256 assets) public view virtual override returns (uint256) {
        return _convertToShares(assets, false);
    }

    /**
     * @notice Simulates the effects of minting a certain amount of shares at the current block
     * @param shares The amount of shares to mint
     * @return The amount of assets that would be deposited
     */
    function previewMint(uint256 shares) public view virtual override returns (uint256) {
        return _convertToAssets(shares, true);
    }

    /**
     * @notice Simulates the effects of withdrawing a certain amount of assets at the current block.
     * @param assets The amount of assets to simulate withdrawing.
     * @return The amount of shares that would be burned.
     */
    function previewWithdraw(uint256 assets) public view virtual override returns (uint256) {
        return _convertToShares(assets, true);
    }

    /**
     * @notice Simulates the effects of redeeming a certain amount of shares at the current block.
     * @param shares The amount of shares to simulate redeeming.
     * @return The amount of assets that would be redeemed.
     */
    function previewRedeem(uint256 shares) public view virtual override returns (uint256) {
        return _convertToAssets(shares, false);
    }

    /**
     * @notice Approves a spender to spend a certain amount
     * @param spender The address of the spender
     * @param amount The amount to approve
     * @return A boolean indicating whether the approval was successful
     */
    function approve(address spender, uint256 amount) public virtual override returns (bool) {
        address msgSender = _msgSender();

        allowance[msgSender][spender] = amount;

        emit Approval(msgSender, spender, amount);

        return true;
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
        uint256 finalSupply = _convertToAssets(totalSupply, false);

        if (supplyCap != 0 && finalSupply > supplyCap && finalSupply > initialSupply) {
            revert VaultSimple__SupplyCapExceeded();
        }
    }

    /**
     * @notice Checks the account status
     * @dev This function is called after any action that may affect the account's state
     */
    function doCheckAccountStatus(address owner, address[] calldata) internal view virtual override {
        // no need to do anything here because the vault does not allow borrowing
    }

    function _convertToShares(uint256 assets, bool roundUp) internal view virtual returns (uint256) {
        return roundUp
            ? assets.mulDivUp(totalSupply + 1, totalAssets_ + 1)
            : assets.mulDivDown(totalSupply + 1, totalAssets_ + 1);
    }

    function _convertToAssets(uint256 shares, bool roundUp) internal view virtual returns (uint256) {
        return roundUp
            ? shares.mulDivUp(totalAssets_ + 1, totalSupply + 1)
            : shares.mulDivDown(totalAssets_ + 1, totalSupply + 1);
    }
}
