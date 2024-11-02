// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {VaultManager} from "src/VaultManager.sol";
import {MockVault} from "test/mocks/vaults/MockVault.sol";

contract ProxyTest is Test {
    VaultManager public vaultManager;
    MockVault public vaultManagerV2;
    ProxyAdmin public proxyAdmin;
    TransparentUpgradeableProxy public proxy;
    VaultManager public vaultManagerProxy;

    function setUp() public {
        // Deploy the VaultManager contract
        vaultManager = new VaultManager();

        // Deploy the ProxyAdmin contract
        proxyAdmin = new ProxyAdmin();

        // Deploy the TransparentUpgradeableProxy contract, pointing to the initial implementation
        proxy = new TransparentUpgradeableProxy(
            address(vaultManager),
            address(proxyAdmin),
            abi.encodeWithSignature("initialize(uint256)", 42) // Call the initialize function with 42
        );

        // Cast the proxy address to the VaultManager interface for testing
        vaultManagerProxy = VaultManager(address(proxy));
    }

    function test_ProxyInitialization() public {
        // Check that the storedValue was initialized to 42
        uint256 initialValue = vaultManagerProxy.storedValue();
        assertEq(initialValue, 42);
    }
}
