// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.26;

import {Test, console2} from "forge-std/Test.sol";
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

        // IPoolManager(address(manager)).sync(currency0);
        // IPoolManager(address(manager)).sync(currency1);

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

    function test_Place_Position() public {
        address token0 = Currency.unwrap(currency0);
        deal(token0, bob, 1 ether);

        uint24 onePercent = 10_000;

        (, int24 tickSlot,,) = StateLibrary.getSlot0(manager, key.toId());
        int24 tickPercent = tickSlot - ((100 * int24(onePercent)) / 10_000);
        int24 tickLower = getTickLower(tickPercent, key.tickSpacing);

        assertEq(tickLower, -100);

        uint256 amount = hook.positionIds(poolId, tickLower, true);
        assertEq(0, amount);

        uint256 activeLength = hook.countActivePositionByPercent(poolId, onePercent, true);

        uint256 tickLength = hook.countActivePositionByTicks(poolId, tickLower, true);

        assertEq(0, activeLength);
        assertEq(0, tickLength);

        vm.startPrank(bob);
        IERC20(token0).approve(address(hook), 1 ether);

        (int24 tickPosition, uint256 positionId) = hook.placePosition(key, onePercent, 0.5 ether, true);

        vm.stopPrank();

        assertEq(positionId, 1);
        assertEq(tickPosition, tickLower);

        uint256 amountAfter = hook.positionIds(poolId, tickLower, true);
        assertEq(0.5 ether, amountAfter);

        uint256 balance = hook.balanceOf(bob, positionId);
        assertEq(0.5 ether, balance);

        activeLength = hook.countActivePositionByPercent(poolId, onePercent, true);
        uint256 activeId = hook.positionByPercentId(poolId, onePercent, true, 0);

        assertEq(1, activeLength);
        assertEq(1, activeId);

        tickLength = hook.countActivePositionByTicks(poolId, tickLower, true);
        uint256 idTickList = hook.positionByTicksId(poolId, tickLower, true, 0);

        assertEq(tickLength, 1);
        assertEq(idTickList, 1);
    }

    function test_Remove_Positions() public {
        address token0 = Currency.unwrap(currency0);
        deal(token0, bob, 1 ether);

        uint24 onePercent = 10_000;

        vm.startPrank(bob);
        IERC20(token0).approve(address(hook), 1 ether);
        (, uint256 positionId) = hook.placePosition(key, onePercent, 0.5 ether, true);
        vm.stopPrank();

        uint256 balance0 = IERC20(token0).balanceOf(bob);
        uint256 balance = hook.balanceOf(bob, positionId);
        assertEq(0.5 ether, balance);
        assertEq(0.5 ether, balance0);

        vm.startPrank(bob);
        hook.removePosition(1);
        vm.stopPrank();

        balance0 = IERC20(token0).balanceOf(bob);
        balance = hook.balanceOf(bob, positionId);
        assertEq(0, balance);
        assertEq(1 ether, balance0);
    }

    function test_Execute_Position() public {
        address token0 = Currency.unwrap(currency0);
        address token1 = Currency.unwrap(currency1);
        deal(token0, bob, 1 ether);

        uint24 onePercent = 10_000;

        (, int24 tickSlot,,) = StateLibrary.getSlot0(manager, key.toId());
        int24 tickPercent = tickSlot - ((100 * int24(onePercent)) / 10_000);
        int24 tickLower = getTickLower(tickPercent, key.tickSpacing);

        vm.startPrank(bob);
        IERC20(token0).approve(address(hook), 1 ether);
        (int24 tickPosition, uint256 positionId) = hook.placePosition(key, onePercent, 0.5 ether, true);
        vm.stopPrank();

        bool zeroForOne = true;
        int256 amountSpecified = -2e18; // negative number indicates exact input swap
        BalanceDelta swapDelta = swap(key, zeroForOne, amountSpecified, ZERO_BYTES);

        zeroForOne = false;
        amountSpecified = -2e18; // negative number indicates exact input swap
        swapDelta = swap(key, zeroForOne, amountSpecified, ZERO_BYTES);

        vm.startPrank(bob);
        vm.expectRevert(abi.encodeWithSelector(PerpsHook.PerpsHook__AlreadyFilled.selector, 1));
        hook.removePosition(1);

        // user claim his money
        hook.claim(1);
        vm.stopPrank();

        uint256 balance1 = IERC20(token1).balanceOf(bob);
        uint256 balance = hook.balanceOf(bob, positionId);
        assertEq(0, balance);
        assertGt(balance1, 0.4 ether);
    }

    function getTickLower(int24 tick, int24 tickSpacing) private pure returns (int24) {
        int24 compressed = tick / tickSpacing;
        if (tick < 0 && tick % tickSpacing != 0) compressed--;
        return compressed * tickSpacing;
    }
}
