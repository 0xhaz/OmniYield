// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.26;

import {Test, console2} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {MockUSDe} from "test/mocks/MockUSDe.sol";
import {PTVaultBorrowable} from "src/providers/pendle/PTVaultBorrowable.sol";
import {OmniFixedYieldVault} from "src/vaults/OmniFixedYieldVault.sol";
import {IPPrincipalToken} from "@pendle/core/contracts/interfaces/IPPrincipalToken.sol";
import {MockPrincipalToken} from "test/mocks/MockPrincipalToken.sol";
import {PtUsdOracle} from "src/providers/pendle/PtUsdOracle.sol";
import {IPtUsdOracle} from "src/interfaces/oracle/IPtUsdOracle.sol";
import {MockPtUsdOracle} from "test/mocks/MockPtUsdOracle.sol";
import {OmniPlatformOperator} from "src/operator/OmniPlatformOperator.sol";
import "evc/src/EthereumVaultConnector.sol";

contract PTVaultBorrowableTest is Test {
    address public OwnerWallet;
    address public UserWallet;
    address public Liquidator;
    address public lp;
    MockUSDe public usde;
    PTVaultBorrowable public pool;
    MockPrincipalToken public sUSDe;
    MockPtUsdOracle public oracle;
    OmniFixedYieldVault public collateralVault;
    OmniPlatformOperator public operator;

    uint256 NOV242024 = 1606128000;
    uint256 DECIMALS = 10 ** 6;
    uint256 CENTS = 10 ** 4;
    IEVC evc;
    address _SY = 0x50288c30c37FA1Ec6167a31E575EA8632645dE20;
    address _market = 0x8621c587059357d6C669f72dA3Bfe1398fc0D0B5;

    function setUp() public {
        lp = address(69);
        UserWallet = address(420);
        Liquidator = address(4210000000000005);
        usde = new MockUSDe();
        evc = new EthereumVaultConnector();

        vm.warp(NOV242024 - 90 days);
        sUSDe = new MockPrincipalToken(address(0), "PrincipalToken sUSDe", "PTsUSDe", 18, NOV242024);
        sUSDe.mintByYT(UserWallet, 100 * DECIMALS);

        // setup oracle
        oracle = new MockPtUsdOracle();

        collateralVault = new OmniFixedYieldVault(evc, ERC20(sUSDe));

        pool = new PTVaultBorrowable(evc, usde, address(collateralVault), address(sUSDe), address(oracle), _market);

        operator = new OmniPlatformOperator(evc, address(collateralVault), address(pool));

        console2.log(pool.name());
        console2.log(pool.symbol());
        usde.mint(lp, 100 * DECIMALS);
    }

    function test_Approve_Operator() public {
        test_Deposit();

        vm.startPrank(UserWallet);
        evc.setAccountOperator(UserWallet, address(operator), true);
        operator.approveAllVaultsOnBehalfOf(UserWallet);
        sUSDe.approve(address(collateralVault), 10 * DECIMALS);
        collateralVault.deposit(10 * DECIMALS, UserWallet);

        assertEq(collateralVault.balanceOf(UserWallet), 10 * DECIMALS);
        assertEq(sUSDe.balanceOf(UserWallet), 90 * DECIMALS);
    }

    function test_Deposit() public {
        vm.startPrank(lp);
        usde.approve(address(pool), 100 * DECIMALS);
        pool.deposit(100 * DECIMALS, lp);

        assertEq(pool.balanceOf(lp), 100 * DECIMALS);
        assertEq(usde.balanceOf(lp), 0);
        assertEq(usde.balanceOf(address(pool)), 100 * DECIMALS);
        vm.stopPrank();
    }

    function test_Withdraw() public {
        test_Deposit();

        vm.startPrank(lp);
        pool.approve(address(pool), 100 * DECIMALS);
        pool.redeem(100 * DECIMALS, lp, lp);

        assertEq(pool.balanceOf(lp), 0);
        assertEq(usde.balanceOf(lp), 100 * DECIMALS);
        assertEq(usde.balanceOf(address(pool)), 0);
    }

    function test_Borrow() public {
        test_Deposit();

        vm.startPrank(UserWallet);
        evc.enableController(UserWallet, address(pool));
        evc.enableCollateral(UserWallet, address(collateralVault));
        evc.enableCollateral(UserWallet, address(pool));

        sUSDe.approve(address(collateralVault), 10 * DECIMALS);
        collateralVault.deposit(10 * DECIMALS, UserWallet);
        // user moves 10 PT to collateral vault
        assertEq(collateralVault.balanceOf(UserWallet), 10 * DECIMALS);
        assertEq(sUSDe.balanceOf(UserWallet), 90 * DECIMALS);

        pool.borrow(950 * CENTS, 1 days, UserWallet);
        // user holds borrow amount 9.50 pool is less 9.50
        assertEq(usde.balanceOf(UserWallet), 950 * CENTS);
        assertEq(usde.balanceOf(address(pool)), 100 * DECIMALS - (950 * CENTS));
        // pool holds 10 of collateral

        uint256 loanAmount = (950 * CENTS) + pool.getTermFeeForAmount(950 * CENTS, 1 days);
        uint256 collateralValueRequired = (loanAmount) * 1_000_000 / 990_000;
        console2.log("Collateral Value Required: ", collateralValueRequired);

        uint256 collateralAmount = collateralValueRequired * 1 ether / (0.97 ether);
        console2.log("Collateral Amount: ", collateralAmount);

        (uint256 collateralNominal,,) = pool.getUserLoan(address(UserWallet), 1);
        console2.log("Collateral Nominal: ", collateralNominal);

        assertEq(collateralNominal, collateralAmount);

        // user tries to withdraw all PT from collateral Vault
        vm.expectRevert(abi.encodeWithSelector(PTVaultBorrowable.PTVaultBorrowable__MaxLoanExceeded.selector));
        collateralVault.withdraw(10 * DECIMALS, UserWallet, UserWallet);

        vm.stopPrank();
    }

    function test_Repurchase() public {
        uint256 repurchasePrice =
            (950 * CENTS) + ((950 * CENTS) * pool.getRate((950 * CENTS), 10 * DECIMALS, 0) / 1_000_000);
        console2.log("Repurchase Price: ", repurchasePrice);

        test_Borrow();
        console2.log("Rebalance: ", usde.balanceOf(address(UserWallet)));

        usde.mint(UserWallet, repurchasePrice - usde.balanceOf(address(UserWallet)));

        vm.startPrank(UserWallet);
        usde.approve(address(pool), repurchasePrice);

        (uint256 collateralNominal, uint256 loanAmount,) = pool.getUserLoan(address(UserWallet), 1);
        console2.log("Collateral Nominal: ", collateralNominal);
        console2.log("Loan Amount: ", loanAmount);

        pool.repurchase(UserWallet, 1);
        assertEq(usde.balanceOf(UserWallet), 0);

        console2.log("Rebalance: ", usde.balanceOf(address(UserWallet)));
        assertGe(usde.balanceOf(address(pool)), 100 * DECIMALS);

        (collateralNominal, loanAmount,) = pool.getUserLoan(address(UserWallet), 1);
        console2.log("Loan Amount 2: ", loanAmount);

        assertEq(pool.pledgedCollateral(UserWallet), 0);
        assertEq(pool.loans(UserWallet), 0);
    }

    function test_liquidation() public {
        test_Borrow();

        usde.mint(Liquidator, 100 * DECIMALS);
        vm.warp(block.timestamp + 1 days);
        vm.startPrank(Liquidator);
        evc.enableController(Liquidator, address(pool));

        usde.approve(address(pool), 100 * DECIMALS);
        (uint256 collateralNominal, uint256 repurchasePrice,) = pool.getUserLoan(address(UserWallet), 1);

        uint256 preAssets = pool.totalAssets();
        pool.liquidate(UserWallet, 1);

        assertEq(usde.balanceOf(Liquidator), (100 * DECIMALS) - repurchasePrice);
        assertEq(collateralVault.balanceOf(Liquidator), collateralNominal);
        assertEq(usde.balanceOf(address(pool)), preAssets + repurchasePrice);
    }
}
