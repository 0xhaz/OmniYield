// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.26;

import {VaultManager} from "src/VaultManager.sol";
import {EVCClient, EVCUtil} from "src/abstracts/EVCClient.sol";

contract MockVault is VaultManager {
    function incrementStoredValue() public {
        storedValue += 1;
    }

    function disableController() external override {}

    function doCreateVaultSnapshot() internal virtual override returns (bytes memory snapshot) {}

    function doCheckVaultStatus(bytes memory snapshot) internal virtual override {}

    function doCheckAccountStatus(address owner, address[] calldata) internal view virtual override {}

    function _msgSender() internal view override returns (address sender) {
        return EVCUtil.msgSender();
    }
}
