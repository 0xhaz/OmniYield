// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.26;

import {BaseHook} from "v4-periphery/src/base/hooks/BaseHook.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {SqrtPriceMath} from "v4-core/libraries/SqrtPriceMath.sol";
import {TickBitmap} from "v4-core/libraries/TickBitmap.sol";
import {FixedPoint96} from "v4-core/libraries/FixedPoint96.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {SafeCast} from "v4-core/libraries/SafeCast.sol";
import {IERC20Minimal} from "v4-core/interfaces/external/IERC20Minimal.sol";
import {TransferHelper} from "src/libraries/TransferHelper.sol";
import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {CurrencySettler} from "@uniswap/v4-core/test/utils/CurrencySettler.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/types/BeforeSwapDelta.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {LPFeeLibrary} from "v4-core/libraries/LPFeeLibrary.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {PoolGetters} from "src/libraries/PoolGetters.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";

/**
 * @title PerpsHook
 * @author 0xhaz
 * @notice This hook is used to interact with the Perpetuals contract
 */
contract PerpsHook is BaseHook {
    error PerpsHook__InvalidTickSpacing(int24);

    using TransferHelper for IERC20Minimal;
    using CurrencyLibrary for Currency;
    using CurrencySettler for Currency;
    using PoolIdLibrary for PoolKey;
    using SafeCast for uint256;
    using PoolGetters for IPoolManager;
    using TickBitmap for mapping(int16 => uint256);
    using LPFeeLibrary for uint24;
    using FixedPointMathLib for uint256;
    using StateLibrary for IPoolManager;

    bytes internal constant ZERO_BYTES = new bytes(0);

    // constants for sqrtPriceLimitX96 which allow for unlimited impact
    uint160 public constant MIN_PRICE_LIMIT = TickMath.MIN_SQRT_PRICE + 1;
    uint160 public constant MAX_PRICE_LIMIT = TickMath.MAX_SQRT_PRICE - 1;

    mapping(PoolId poolId => int24 tickLower) public tickLowerLasts;
    mapping(PoolId poolId => mapping(int24 tick => mapping(bool zeroForOne => uint256 amount))) public positionId;
    mapping(PoolId poolId => mapping(int24 tick => mapping(bool zeroForOne => uint256[]))) public positionByTicksId;
    mapping(PoolId => mapping(uint24 percent => mapping(bool zeroForOne => uint256[]))) public positionByPercentId;

    uint256 public lastTokenId = 0;
    mapping(uint256 tokenId => PositionInfo) public positionInfoById;

    struct PositionInfo {
        PoolKey poolKey;
        int24 tickLower;
        uint24 percent;
        bool zeroForOne;
        uint256 totalAmount;
        uint256 filledAmount;
        uint256 newId;
    }

    constructor(IPoolManager poolManager) BaseHook(poolManager) {}

    function getHookPermissions() public pure virtual override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: true,
            afterInitialize: true,
            beforeAddLiquidity: false,
            beforeRemoveLiquidity: true,
            afterAddLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: false,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    function beforeInitialize(address, PoolKey calldata key, uint160) external pure override returns (bytes4) {
        // tick spacing of 50 so the price movement is 0.5%
        if (key.tickSpacing != 50) {
            revert PerpsHook__InvalidTickSpacing(key.tickSpacing);
        }

        return this.beforeInitialize.selector;
    }

    function afterInitialize(address, PoolKey calldata key, uint160, int24 tick) external override returns (bytes4) {
        PoolId id = key.toId();

        setTickLowerLast(id, getTickLower(tick, key.tickSpacing));
        return this.afterInitialize.selector;
    }

    function beforeSwap(address sender, PoolKey calldata key, IPoolManager.SwapParams calldata, bytes calldata)
        external
        override
        onlyPoolManager
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        if (sender == address(this)) {
            // prevent from loop call
            return (this.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
        }

        PoolId id = key.toId();
        (, int24 tickAfter,,) = poolManager.getSlot0(id);

        int24 lastTick = tickLowerLasts[id];
        int24 currentTick = getTickLower(tickAfter, key.tickSpacing);
        int24 tick = lastTick;

        if (lastTick != currentTick) {
            // adjust position to the newest tick
            if (lastTick < currentTick) {
                for (; tick < currentTick;) {
                    rebalancePosition(id, tick, currentTick);
                    unchecked {
                        tick += key.tickSpacing;
                    }
                }
            } else {
                for (; currentTick < tick;) {
                    rebalancePosition(id, tick, currentTick);
                    unchecked {
                        tick -= key.tickSpacing;
                    }
                }
            }
            setTickLowerLast(id, currentTick);
        }
    }

    function setTickLowerLast(PoolId id, int24 tickLower) private {
        tickLowerLasts[id] = tickLower;
    }

    function getTickLower(int24 tick, int24 tickSpacing) private pure returns (int24) {
        int24 compressed = tick / tickSpacing;
        if (tick < 0 && tick % tickSpacing != 0) compressed--; // round towards negative infinity
        return compressed * tickSpacing;
    }

    /**
     * @notice Rebalance the position to the new tick
     * If tick goes up, the position will be updated based on currency 0
     * If tick goes down, the position will be updated based on currency 1
     * @param id The pool id
     * @param lastTick The last tick
     * @param newTick The new tick
     */
    function rebalancePosition(PoolId id, int24 lastTick, int24 newTick) private {
        bool zeroForOne = lastTick < newTick;

        for (uint256 i = 1; i < 10; ++i) {
            uint24 percent = uint24(i) * 10_000;
        }
    }
}
