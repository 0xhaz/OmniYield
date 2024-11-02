// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.26;

import {VaultBase, IEVC} from "src/abstracts/VaultBase.sol";
import {Ownable, Context} from "@openzeppelin/contracts/access/Ownable.sol";
import {ISmartYield} from "src/interfaces/ISmartYield.sol";
import {EVCClient, EVCUtil} from "src/abstracts/EVCClient.sol";

contract VaultManager is VaultBase, Ownable {
    ISmartYield[] public strategies;

    constructor(IEVC evc_) VaultBase(evc_) Ownable(msg.sender) {
        _transferOwnership(msg.sender);
    }

    /// @notice Add a new strategy to the vault
    function addStrategy(ISmartYield strategy) external onlyOwner {
        strategies.push(strategy);
    }

    function deposit(uint256 amount) external callThroughEVC nonReentrant {
        uint256 amountPerStrategy = amount / strategies.length;
        for (uint256 i = 0; i < strategies.length; i++) {
            strategies[i].deposit(amountPerStrategy);
        }
    }

    function _msgSender() internal view override(Context, EVCUtil) returns (address sender) {
        return EVCUtil._msgSender();
    }

    function disableController() external override {}

    function doCreateVaultSnapshot() internal virtual override returns (bytes memory snapshot) {}

    function doCheckVaultStatus(bytes memory snapshot) internal virtual override {}

    function doCheckAccountStatus(address owner, address[] calldata) internal view virtual override {}
}
