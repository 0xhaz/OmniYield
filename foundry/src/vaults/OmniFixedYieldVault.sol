// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.26;

import {VaultBase, IEVC} from "src/abstracts/VaultBase.sol";
import {EVCClient, EVCUtil} from "src/abstracts/EVCClient.sol";
import {ERC4626, IERC20, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {OmniBaseVault} from "src/vaults/OmniBaseVault.sol";

/**
 * @title OmniFixedYieldVault
 * @notice Implements the Fixed Yield Collateral Vault
 * @notice Holds a fixed yield collateral and puts it under the control of the EVC
 */
contract OmniFixedYieldVault is OmniBaseVault {
    constructor(IEVC _evc, IERC20 _asset)
        OmniBaseVault(
            _evc,
            _asset,
            string.concat("Omni ", ERC20(address(_asset)).name()),
            string.concat("Omni ", ERC20(address(_asset)).name())
        )
    {}

    /**
     * @notice Deposits a certain amount of collateral into the vault
     * @param assets The assets to deposit
     * @param receiver The receiver of the assets
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
        _totalAssets += assets;

        requireVaultStatusCheck();
    }

    /**
     * @notice Mints a certain amount of shares for a receiver
     * @param shares The amount of shares to mint
     * @param receiver The address of the receiver
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
        _totalAssets += assets;

        requireVaultStatusCheck();
    }

    /**
     * 2notice Withdraws a certain amount of assets for a receiver
     * @param assets The amount of assets to withdraw
     * @param receiver The address of the receiver
     * @param owner The address of the owner of the assets
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
        _totalAssets -= assets;

        requireAccountAndVaultStatusCheck(owner);
    }

    /**
     * @notice Redeems a certain amount of assets for a receiver
     * @param shares The amount of shares to redeem
     * @param receiver The receiver of the redeemed assets
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
        _totalAssets -= assets;

        requireAccountAndVaultStatusCheck(owner);
    }
}
