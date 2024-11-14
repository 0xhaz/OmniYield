// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {CurrencyLibrary, Currency} from "v4-core/types/Currency.sol";
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";
import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {PerpsHook} from "src/dex/PerpsHook.sol";
import {HookMiner} from "test/utils/HookMiner.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";
import {MockUSDe} from "test/mocks/MockUSDe.sol";

contract PerpsHookTest is Test, Deployers {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;

    address bob = makeAddr("bob");
    address alice = makeAddr("alice");
    address carol = makeAddr("carol");

    // IERC20 USDe = IERC20(0xf805ce4F96e0EdD6f0b6cd4be22B34b92373d696);
    MockUSDe USDe = new MockUSDe();
    uint256 public sUSDeRewardRate = 1000; // 10%

    PerpsHook hook;
    PoolId poolId;

    function setUp() public {
        Deployers.deployFreshManagerAndRouters();
        Deployers.deployMintAndApprove2Currencies();

        uint160 flags = uint160(
            Hooks.BEFORE_INITIALIZE_FLAG | Hooks.AFTER_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG
        );

        (address hookAddress, bytes32 salt) = HookMiner.find(
            address(this), flags, type(PerpsHook).creationCode, abi.encode(address(manager), USDe, sUSDeRewardRate)
        );

        hook = new PerpsHook{salt: salt}(IPoolManager(address(manager)), USDe, sUSDeRewardRate);

        require(address(hook) == hookAddress, "hook address mismatch");

        key = PoolKey(currency0, currency1, 3000, 50, IHooks(address(hook)));
        poolId = key.toId();
        manager.initialize(key, SQRT_PRICE_1_1);

        USDe.mint(bob, 1000e18);
        USDe.mint(alice, 1000e18);
        USDe.mint(carol, 1000e18);

        modifyLiquidityRouter.modifyLiquidity(
            key,
            IPoolManager.ModifyLiquidityParams({tickLower: -50, tickUpper: 50, liquidityDelta: 10e18, salt: 0}),
            ZERO_BYTES
        );

        modifyLiquidityRouter.modifyLiquidity(
            key,
            IPoolManager.ModifyLiquidityParams({tickLower: -100, tickUpper: 100, liquidityDelta: 10e18, salt: 0}),
            ZERO_BYTES
        );

        modifyLiquidityRouter.modifyLiquidity(
            key,
            IPoolManager.ModifyLiquidityParams({
                tickLower: TickMath.minUsableTick(50),
                tickUpper: TickMath.maxUsableTick(50),
                liquidityDelta: 10e18,
                salt: 0
            }),
            ZERO_BYTES
        );
    }

    function test_Modify_Liquidity_Hooks() public {
        int256 liquidityDelta = -1e18;
        modifyLiquidityRouter.modifyLiquidity(
            key,
            IPoolManager.ModifyLiquidityParams({tickLower: -50, tickUpper: 50, liquidityDelta: liquidityDelta, salt: 0}),
            ZERO_BYTES
        );
    }

    function test_Incorrect_Tick_Spacing() public {
        int256 liquidityDelta = -1e18;
        vm.expectRevert();
        modifyLiquidityRouter.modifyLiquidity(
            key,
            IPoolManager.ModifyLiquidityParams({tickLower: -60, tickUpper: 60, liquidityDelta: liquidityDelta, salt: 0}),
            ZERO_BYTES
        );
    }
}
