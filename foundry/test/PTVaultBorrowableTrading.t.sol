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

// forge script --rpc-url https://rpc.buildbear.io/persistent-siryn-0132e20a scripts/01_deployment.s.sol --legacy
// forge test --fork-url https://rpc.buildbear.io/persistent-siryn-0132e20a -vv

interface IUSDE {
    function balanceOf(address account) external view returns (uint256);
    function mint(address to, uint256 amount) external;
    function configureMinter(address minter, uint256 minterAllowedAmount) external;
    function masterMinter() external view returns (address);
}

contract PTVaultBorrowableTradingTest is Test {
    address public OwnerWallet;
    address public UserWallet;
    address public lp;
    ERC20 public usde;
    IUSDE public usde_spoof;
    PTVaultBorrowable public pool;
    IPPrincipalToken public sUSDe;
    PtUsdOracle public oracle;
    uint256 NOV242024 = 1606128000;
    uint256 DECIMALS = 10 ** 6;
    OmniFixedYieldVault public collateralVault;
    IEVC evc;
    address _SY = 0x50288c30c37FA1Ec6167a31E575EA8632645dE20;
    address _PT = 0xb72b988CAF33f3d8A6d816974fE8cAA199E5E86c;
    address _market = 0x8621c587059357d6C669f72dA3Bfe1398fc0D0B5;
    address _USDE = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;

    function setUp() public {
        lp = address(69);
        UserWallet = address(420);
        usde = ERC20(_USDE);
        usde_spoof = IUSDE(address(usde));
        evc = new EthereumVaultConnector();
        vm.prank(usde_spoof.masterMinter());
        // allow this test contract to mint USDe
        usde_spoof.configureMinter(address(this), type(uint256).max);

        sUSDe = IPPrincipalToken(_PT);
        // setup oracle
        oracle = new PtUsdOracle(
            0.1 hours,
            _market,
            address(0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3),
            address(0x7e16e4253CE4a1C96422a9567B23b4b5Ebc207F1)
        );

        collateralVault = new OmniFixedYieldVault(evc, ERC20(address(sUSDe)));
        pool = new PTVaultBorrowable(evc, usde, address(collateralVault), address(sUSDe), address(oracle), _market);

        usde_spoof.mint(lp, 1000 * DECIMALS);
        usde_spoof.mint(UserWallet, 100 * DECIMALS);
    }

    function test_Deposit() public {
        vm.startPrank(lp);
        usde.approve(address(pool), 100 * DECIMALS);
        pool.deposit(100 * DECIMALS, lp);

        assertEq(pool.balanceOf(lp), 100 * DECIMALS);
        assertEq(usde.balanceOf(lp), 100 * DECIMALS);
        assertEq(usde.balanceOf(address(pool)), 100 * DECIMALS);
        vm.stopPrank();
    }
}
