// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.26;

import "./VaultSimple.sol";

/**
 * @title VaultSimpleBorrowable
 * @notice This contract extends VaultSimple to add borrowing functionality
 * @notice In this contract, the EVC is authenticated before any action that may affect the state of the vault or an account
 * This is done to ensure that if it's EVC calling, the account is correctly authorized and the vault is enabled as a controller if needed.
 * This contract does not take the account health into account when calculating max withdraw and max redeem values. This contract does not implement
 * the interest accrual hence it returns raw values of total borrows and 0 for the interest accumulator in the interest accrual-related functions.
 */
contract VaultSimpleBorrowable is VaultSimple {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    event BorrowCapSet(uint256 newBorrowCap);
    event Borrow(address indexed caller, address indexed owner, uint256 assets);
    event Repay(address indexed caller, address indexed receiver, uint256 assets);

    error BorrowCapExceeded();
    error AccountUnhealthy();
    error OutstandingDebt();

    uint256 public borrowCap;
    uint256 internal _totalBorrowed;
    mapping(address account => uint256 assets) internal owed;

    constructor(address _evc, ERC20 _asset, string memory _name, string memory _symbol)
        VaultSimple(IEVC(_evc), _asset, _name, _symbol)
    {}
}
