// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.26;

import {BaseHook} from "v4-periphery/src/base/hooks/BaseHook.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
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
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/types/BeforeSwapDelta.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {LPFeeLibrary} from "v4-core/libraries/LPFeeLibrary.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {PoolGetters} from "src/libraries/PoolGetters.sol";
import {FixedPointMathLib} from "solmate/src/utils/FixedPointMathLib.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC6909} from "v4-core/ERC6909.sol";
import {console} from "forge-std/Console.sol";

/**
 * @title PerpsHook
 * @author 0xhaz
 * @notice This hook is used to interact with the Perpetuals contract
 */
contract PerpsHook is BaseHook, ERC6909 {
    error PerpsHook__InvalidTickSpacing(int24);
    error PerpsHook__InvalidPercentage(uint24);
    error PerpsHook__ZeroBalance();
    error PerpsHook__AlreadyFilled(uint256);
    error PerpsHook__ZeroClaim(uint256);
    error PerpsHook__NotExecuted(uint256);
    error PerpsHook__ExceedMaxLeverage();
    error PerpsHook__PositionNotFound(uint256);
    error PerpsHook__NoClaimAvailable();
    error PerpsHook__InsufficientBalance();

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
    using Math for uint256;

    bytes internal constant ZERO_BYTES = new bytes(0);
    uint256 internal constant SCALE_FACTOR = 1e18;

    // sUSDe reward rate per unit position size per second, e.g 1e18 means 1 sUSDe per second per unit position size
    uint256 public sUSDeRewardRate;
    IERC20 public sUSDeToken;

    // Liquidation Threshold
    uint256 public maintenanceMarginRatio = 10 * SCALE_FACTOR / 100; // 10% maintenance margin ratio
    uint256 public liquidationPenalty = 5 * SCALE_FACTOR / 100; // 5% liquidation penalty upon liquidation

    // constants for sqrtPriceLimitX96 which allow for unlimited impact
    uint160 public constant MIN_PRICE_LIMIT = TickMath.MIN_SQRT_PRICE + 1;
    uint160 public constant MAX_PRICE_LIMIT = TickMath.MAX_SQRT_PRICE - 1;

    mapping(PoolId poolId => int24 tickLower) public tickLowerLasts;
    mapping(PoolId poolId => mapping(int24 tick => mapping(bool zeroForOne => uint256 amount))) public positionIds;
    mapping(PoolId poolId => mapping(int24 tick => mapping(bool zeroForOne => uint256[]))) public positionByTicksId;
    mapping(PoolId => mapping(uint24 percent => mapping(bool zeroForOne => uint256[]))) public positionByPercentId;
    mapping(uint256 timestamp => uint256 reward) public lastRewardCalculation;

    event PositionPlaced(address indexed sender, uint256 indexed tokenId, uint256 amount, PositionInfo position);
    event PositionCanceled(address indexed sender, uint256 indexed tokenId, uint256 amount);
    event PositionClaimed(address indexed sender, uint256 indexed tokenId, uint256 amount, uint256 amountOut);
    event RewardClaimed(address indexed sender, uint256 indexed tokenId, uint256 amount);
    event PositionUpdated(uint256 indexed positionId, uint256 newSize, uint256 leverage, bool isLong);
    event RewardAccrued(uint256 indexed positionId, uint256 accruedReward);
    event PositionLiquidated(uint256 indexed positionId, uint256 collateralSeized, address liquidator);
    event PositionIncreased(uint256 indexed positionId, uint256 additionalCollateral, uint256 newLeverage);
    event PositionDecreased(uint256 indexed positionId, uint256 collateralWithdrawn, uint256 newLeverage);

    uint256 public lastTokenId = 0;
    mapping(uint256 tokenId => PositionInfo) public positionInfoById;
    mapping(uint256 tokenId => LeveragePosition) public leveragePositionById;

    // open interest for long and short position
    uint256 public openInterestLong;
    uint256 public openInterestShort;

    // Funding Rate and Leverage Support
    uint256 public fundingRate;
    uint256 public maxLeverage = 10e18; // maximum leverage allowed is 10x

    struct LeveragePosition {
        uint256 positionSize; // size of the position in terms of the asset
        uint256 collateral; // margin or collateral provided for this position
        uint256 entryPrice; // price at which the position was entered
        uint256 leverage; // leverage used for this position
        bool isLong; // true if the position is long, false if short
        IERC20 collateralToken; // token used as collateral
    }

    struct PositionInfo {
        PoolKey poolKey;
        int24 tickLower;
        uint24 percent;
        bool zeroForOne;
        uint256 totalAmount;
        uint256 filledAmount;
        uint256 newId;
    }

    constructor(IPoolManager poolManager, IERC20 _sUSDeToken, uint256 _sUSDeRewardRate) BaseHook(poolManager) {
        sUSDeToken = _sUSDeToken;
        sUSDeRewardRate = _sUSDeRewardRate;
    }

    function getHookPermissions() public pure virtual override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: true,
            afterInitialize: true,
            beforeAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterAddLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: true,
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

    function beforeSwap(address sender, PoolKey calldata key, IPoolManager.SwapParams calldata params, bytes calldata)
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
        uint256[] memory positions = positionByTicksId[id][getTickLower(tickAfter, key.tickSpacing)][params.zeroForOne];

        // accrue rewards for positions impacted by this swap
        accrueAndEmitRewards(positions);

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

        uint256 feeAdjustment = fundingRate / SCALE_FACTOR;
        uint24 adjustedFee = uint24(feeAdjustment);

        return (this.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, adjustedFee);
    }

    function afterSwap(
        address sender,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        BalanceDelta,
        bytes calldata
    ) external override returns (bytes4, int128) {
        PoolId id = key.toId();

        if (sender == address(this)) {
            // prevent from loop call
            return (this.afterSwap.selector, 0);
        }

        int24 prevTick = tickLowerLasts[id];
        (, int24 tick,,) = poolManager.getSlot0(id);
        int24 currentTick = getTickLower(tick, key.tickSpacing);
        tick = prevTick;

        // fill trailing in the opposite direction of the swap
        // avoids attack vectors
        bool stopLossZeroForOne = !params.zeroForOne;
        uint256 swapAmount;

        if (prevTick < currentTick) {
            for (; tick < currentTick;) {
                swapAmount = positionIds[id][tick][stopLossZeroForOne];

                if (swapAmount > 0) {
                    fillStopLoss(key, tick, stopLossZeroForOne, swapAmount);
                    // adjust open interest after fulfilling position
                    adjustOpenInterestAfterFill(id, tick, stopLossZeroForOne);
                }
                unchecked {
                    tick += key.tickSpacing;
                }
            }
        } else {
            for (; currentTick < tick;) {
                swapAmount = positionIds[id][tick][stopLossZeroForOne];

                if (swapAmount > 0) {
                    fillStopLoss(key, tick, stopLossZeroForOne, swapAmount);
                    // adjust open interest after fulfilling position
                    adjustOpenInterestAfterFill(id, tick, stopLossZeroForOne);
                }
                unchecked {
                    tick -= key.tickSpacing;
                }
            }
        }

        // Re-adjust open interest after swap
        adjustFundingRate();

        // log rewards for any affected positions due to this swap
        uint256[] memory positions = positionByTicksId[id][currentTick][params.zeroForOne];
        accrueAndEmitRewards(positions);

        return (this.afterSwap.selector, 0);
    }

    function placeLeveragePosition(PoolKey calldata key, uint256 margin, uint256 leverage, bool isLong, bool zeroForOne)
        external
        returns (uint256 positionId)
    {
        if (leverage >= maxLeverage) revert PerpsHook__ExceedMaxLeverage();

        uint256 positionSize = margin * leverage;

        if (isLong) {
            openInterestLong += positionSize;
        } else {
            openInterestShort += positionSize;
        }

        adjustFundingRate();

        address token = zeroForOne ? Currency.unwrap(key.currency0) : Currency.unwrap(key.currency1);
        // Transfer margin to this contract
        IERC20(token).transferFrom(msg.sender, address(this), margin);

        LeveragePosition memory position = LeveragePosition({
            positionSize: positionSize,
            collateral: margin,
            entryPrice: getPrice(key),
            leverage: leverage,
            isLong: isLong,
            collateralToken: IERC20(token)
        });

        leveragePositionById[positionId] = position;
        lastRewardCalculation[lastTokenId] = block.timestamp;
        lastTokenId++;

        emit PositionUpdated(positionId, positionSize, leverage, isLong);

        return lastTokenId - 1;
    }

    function placePosition(PoolKey calldata key, uint24 percent, uint256 amountIn, bool zeroForOne)
        external
        returns (int24 tickLower, uint256 tokenId)
    {
        // between 1 and 10%, with a step of 1%
        if (percent < 10_000 || percent > 100_000 || percent % 10_000 != 0) {
            revert PerpsHook__InvalidPercentage(percent);
        }

        PoolId id = key.toId();
        (, int24 tick,,) = poolManager.getSlot0(id);
        // calculate tickLower based on percent trailing stop, 1% price movement equal 100 ticks change
        int24 tickChange = ((100 * int24(percent)) / 10_000);
        // change direction depend if it's zeroForOne
        int24 tickPercent = zeroForOne ? tick - tickChange : tick + tickChange;
        // round down according to tickSpacing
        tickLower = getTickLower(tickPercent, key.tickSpacing);

        // transfer token to this contract
        address token = zeroForOne ? Currency.unwrap(key.currency0) : Currency.unwrap(key.currency1);
        IERC20(token).transferFrom(msg.sender, address(this), amountIn);

        positionIds[id][tickLower][zeroForOne] += amountIn;

        // found corresponding position in existing position
        tokenId = mergePosition(id, percent, zeroForOne, amountIn, tickLower, 0);

        if (tokenId == 0) {
            // if no position is found, create a new one
            PositionInfo memory data = PositionInfo(key, tickLower, percent, zeroForOne, amountIn, 0, 0);
            lastTokenId++;
            tokenId = lastTokenId;
            positionInfoById[tokenId] = data;
            positionByTicksId[id][tickLower][zeroForOne].push(tokenId);
            positionByPercentId[id][percent][zeroForOne].push(tokenId);
        }

        // mint the token to the sender
        _mint(msg.sender, tokenId, amountIn);

        emit PositionPlaced(msg.sender, tokenId, amountIn, positionInfoById[tokenId]);
    }

    function removePosition(uint256 id) external {
        uint256 userBalance = balanceOf[msg.sender][id];
        if (userBalance == 0) {
            revert PerpsHook__ZeroBalance();
        }

        // the trailing can be merge with other trailing to check if it's possible to merge
        uint256 activeId = getActivePosition(id);

        PositionInfo storage position = positionInfoById[activeId];
        LeveragePosition storage leveragePos = leveragePositionById[id];

        if (position.filledAmount > 0) {
            // if trailing was filled then it wont get cancelled
            revert PerpsHook__AlreadyFilled(id);
        }

        if (leveragePositionById[id].isLong) {
            openInterestLong -= leveragePos.positionSize;
        } else {
            openInterestShort -= leveragePos.positionSize;
        }

        adjustFundingRate();

        // burn the share of the user and remove the active position
        _burn(msg.sender, id, userBalance);
        position.totalAmount -= userBalance;

        PoolKey memory key = position.poolKey;
        bool zeroForOne = position.zeroForOne;
        PoolId poolId = key.toId();
        int24 tick = position.tickLower;

        // remove amount from trailing position
        positionIds[poolId][tick][zeroForOne] -= userBalance;

        // if the trailing got no amount anymore, we delete it from everywhere
        if (position.totalAmount == 0) {
            deleteFromActive(activeId, poolId, position.percent, zeroForOne);
            deleteFromTicks(activeId, poolId, tick, zeroForOne);
        }

        address token = zeroForOne ? Currency.unwrap(key.currency0) : Currency.unwrap(key.currency1);

        // reimburse the user
        IERC20(token).transfer(msg.sender, userBalance);

        lastRewardCalculation[id] = 0;

        emit PositionCanceled(msg.sender, id, userBalance);
    }

    function claim(uint256 tokenId) external {
        // check an amount to redeem
        uint256 receiptBalance = balanceOf[msg.sender][tokenId];
        if (receiptBalance == 0) revert PerpsHook__ZeroClaim(tokenId);

        uint256 activeId = getActivePosition(tokenId);
        PositionInfo storage position = positionInfoById[activeId];

        if (position.filledAmount == 0) revert PerpsHook__NotExecuted(tokenId);

        address token = position.zeroForOne
            ? Currency.unwrap(position.poolKey.currency0)
            : Currency.unwrap(position.poolKey.currency1);

        // burn the token
        uint256 amountOut = receiptBalance.mulDivDown(position.filledAmount, position.totalAmount);

        _burn(msg.sender, tokenId, receiptBalance);

        // transfer the amount to the user
        IERC20(token).transfer(msg.sender, amountOut);

        emit PositionClaimed(msg.sender, tokenId, receiptBalance, amountOut);
    }

    /**
     * @notice Claims the accumulated sUSDe rewawrd for the caller's position
     * @param positionId The ID of the position for which to claim the reward
     */
    function claimReward(uint256 positionId) external {
        if (balanceOf[msg.sender][positionId] == 0) revert PerpsHook__ZeroClaim(positionId);

        // calculate the reward
        uint256 reward = calculateReward(positionId);
        if (reward == 0) revert PerpsHook__NoClaimAvailable();

        // ensure contract has enough sUSDe to cover the reward
        uint256 contractBalance = sUSDeToken.balanceOf(address(this));
        if (contractBalance <= reward) revert PerpsHook__InsufficientBalance();

        // update the last reward calculation timestamp
        lastRewardCalculation[positionId] = block.timestamp;

        // transfer the reward to the caller
        sUSDeToken.transfer(msg.sender, reward);

        emit RewardClaimed(msg.sender, positionId, reward);
    }

    /**
     * @notice Liquidates an undercollateralized position
     * @param positionId The ID of the position to liquidate
     * @dev Can be called by any user if the position's collateral is below maintenance margin
     */
    function liquidatePosition(PoolKey calldata key, uint256 positionId) external {
        LeveragePosition storage position = leveragePositionById[positionId];

        if (position.positionSize == 0) revert PerpsHook__PositionNotFound(positionId);

        uint256 currentPrice = getPrice(key);
        uint256 positionValue = position.positionSize.mulDiv(currentPrice, SCALE_FACTOR);
        uint256 maintenanceMargin = positionValue.mulDiv(maintenanceMarginRatio, SCALE_FACTOR);

        // Ensure position is eligible for liquidation
        if (position.collateral >= maintenanceMargin) revert PerpsHook__PositionNotFound(positionId);

        uint256 collateralSeized = position.collateral.mulDiv(SCALE_FACTOR - liquidationPenalty, SCALE_FACTOR);

        // Transfer the seized collateral to the liquidator
        position.collateralToken.transfer(msg.sender, collateralSeized);

        // Emit liquidation event
        emit PositionLiquidated(positionId, collateralSeized, msg.sender);

        // Remove the position from the open interest
        delete leveragePositionById[positionId];
        delete positionInfoById[positionId];
    }

    /**
     * @notice Increases the collateral and leverage of an existing position
     * @param positionId The ID of the position to increase
     * @param additionalCollateral The amount of additional collateral to add to the position
     * @param newLeverage The new leverage to apply to the position
     * @dev Collateral is transferred from the caller to the position
     */
    function increasePosition(uint256 positionId, uint256 additionalCollateral, uint256 newLeverage) external {
        if (newLeverage >= maxLeverage) revert PerpsHook__ExceedMaxLeverage();

        LeveragePosition storage position = leveragePositionById[positionId];
        if (position.positionSize == 0) revert PerpsHook__PositionNotFound(positionId);

        // Transfer the additional collateral to the position
        position.collateralToken.transferFrom(msg.sender, address(this), additionalCollateral);
        position.collateral += additionalCollateral;
        position.leverage = newLeverage;
        position.positionSize = position.collateral * position.leverage;

        emit PositionIncreased(positionId, additionalCollateral, newLeverage);
    }

    /**
     * @notice Decreases the collateral and leverage of an existing position
     * @param positionId The ID of the position to decrease
     * @param collateralWithdrawn The amount of collateral to withdraw from the position
     * @param newLeverage The new leverage to apply to the position
     * @dev Collateral is transferred from the position to the caller
     */
    function decreasePosition(uint256 positionId, uint256 collateralWithdrawn, uint256 newLeverage) external {
        if (newLeverage >= maxLeverage) revert PerpsHook__ExceedMaxLeverage();

        LeveragePosition storage position = leveragePositionById[positionId];
        if (position.positionSize == 0) revert PerpsHook__PositionNotFound(positionId);
        if (position.collateral < collateralWithdrawn) revert PerpsHook__InsufficientBalance();

        // Adjust collateral and transfer the withdrawn amount to the caller
        position.collateral -= collateralWithdrawn;
        position.collateralToken.transfer(msg.sender, collateralWithdrawn);

        // Update leverage and position size
        position.leverage = newLeverage;
        position.positionSize = position.collateral * position.leverage;

        emit PositionDecreased(positionId, collateralWithdrawn, newLeverage);
    }

    function setTickLowerLast(PoolId id, int24 tickLower) private {
        tickLowerLasts[id] = tickLower;
    }

    function getActivePosition(uint256 tokenId) public view returns (uint256) {
        PositionInfo memory position = positionInfoById[tokenId];
        if (position.newId != 0 && position.newId != tokenId) {
            return getActivePosition(position.newId);
        }

        return tokenId;
    }

    function getTickLower(int24 tick, int24 tickSpacing) private pure returns (int24) {
        int24 compressed = tick / tickSpacing;
        if (tick < 0 && tick % tickSpacing != 0) compressed--; // round towards negative infinity
        return compressed * tickSpacing;
    }

    function countActivePositionByPercent(PoolId id, uint24 percent, bool zeroForOne) public view returns (uint256) {
        return positionByPercentId[id][percent][zeroForOne].length;
    }

    function countActivePositionByTicks(PoolId id, int24 tick, bool zeroForOne) public view returns (uint256) {
        return positionByTicksId[id][tick][zeroForOne].length;
    }

    function getPrice(PoolKey calldata key) public view returns (uint256) {
        PoolId id = key.toId();
        (, int24 tick,,) = poolManager.getSlot0(id);

        return TickMath.getSqrtPriceAtTick(tick);
    }

    /**
     * @notice Calculates the accumulated sUSDe reward for a position based on time held and size
     * @param positionId The id of the position
     * @return reward The accumulated sUSDe reward
     */
    function calculateReward(uint256 positionId) public returns (uint256 reward) {
        // Fetch the position and verify it exists
        LeveragePosition memory position = leveragePositionById[positionId];
        if (position.positionSize == 0) revert PerpsHook__PositionNotFound(positionId);

        // Time since last reward calculation
        uint256 timeHeld = block.timestamp - lastRewardCalculation[positionId];

        // calculate reward: position size * reward rate * time held
        reward = position.positionSize * sUSDeRewardRate * timeHeld / SCALE_FACTOR;

        emit RewardAccrued(positionId, reward);
    }

    function accrueAndEmitRewards(uint256[] memory positions) internal {
        for (uint256 i = 0; i < positions.length; i++) {
            uint256 positionId = positions[i];

            // calculate reward for each position
            uint256 accruedReward = calculateReward(positionId);

            if (accruedReward > 0) {
                emit RewardAccrued(positionId, accruedReward);
                lastRewardCalculation[positionId] = block.timestamp;
            }
        }
    }

    function fillStopLoss(PoolKey calldata poolKey, int24 triggerTick, bool zeroForOne, uint256 swapAmount) internal {
        PoolId id = poolKey.toId();

        IPoolManager.SwapParams memory stopLossSwapParams = IPoolManager.SwapParams({
            zeroForOne: zeroForOne,
            // negative for exact input
            amountSpecified: -int256(swapAmount),
            sqrtPriceLimitX96: zeroForOne ? MIN_PRICE_LIMIT : MAX_PRICE_LIMIT
        });

        BalanceDelta delta = handleSwap(poolKey, stopLossSwapParams, address(this));

        // this amount was positive or they would have been reverted
        uint256 amount = zeroForOne ? uint256(int256(delta.amount1())) : uint256(int256(delta.amount0()));

        uint256[] memory positionByIds = positionByTicksId[id][triggerTick][zeroForOne];

        for (uint256 i = 0; i < positionByIds.length; i++) {
            uint256 positionById = positionByIds[i];
            PositionInfo storage position = positionInfoById[positionById];
            uint256 filledAmount = amount.mulDivDown(position.totalAmount, swapAmount);
            position.filledAmount += filledAmount;

            // delete the trailing position from active positions
            uint256[] storage activePositions = positionByPercentId[id][position.percent][position.zeroForOne];

            for (uint256 j = 0; j < activePositions.length; j++) {
                if (activePositions[j] == positionById) {
                    activePositions[j] = activePositions[activePositions.length - 1];
                    break;
                }
            }
            activePositions.pop();
        }

        // delete the position from the tick
        delete positionByTicksId[id][triggerTick][zeroForOne];
        delete positionIds[id][triggerTick][zeroForOne];
    }

    /**
     * @notice Adjusts funding reate based on the open interest imbalance
     * @dev Called periodically to keep funding rate in sync with market conditions
     */
    function adjustFundingRate() internal {
        if (openInterestLong > openInterestShort) {
            uint256 imbalance = openInterestLong - openInterestShort;
            fundingRate = (imbalance * SCALE_FACTOR) / openInterestLong;
        } else if (openInterestShort > openInterestLong) {
            uint256 imbalance = openInterestShort - openInterestLong;
            fundingRate = (imbalance * SCALE_FACTOR) / openInterestShort;
        } else {
            fundingRate = 0; // if balanced, set funding rate to 0
        }
    }

    /**
     * @notice Adjusts open interest after a position is filled
     * @param id The pool id
     * @param tick The tick of the position
     * @param zeroForOne The direction of the position
     */
    function adjustOpenInterestAfterFill(PoolId id, int24 tick, bool zeroForOne) internal {
        uint256[] memory filledPositions = positionByTicksId[id][tick][zeroForOne];

        for (uint256 i = 0; i < filledPositions.length; i++) {
            uint256 positionId = filledPositions[i];
            LeveragePosition storage leveragePos = leveragePositionById[positionId];

            // Adjust open interest based on direction of filled position
            if (leveragePos.isLong) {
                openInterestLong -= leveragePos.positionSize;
            } else {
                openInterestShort -= leveragePos.positionSize;
            }

            // remove filled position from mappings to prevent further fills
            deleteFromActive(positionId, id, positionInfoById[positionId].percent, zeroForOne);
            delete positionInfoById[positionId];
        }
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
            uint256[] memory activePositions = positionByPercentId[id][percent][zeroForOne];

            for (uint256 j = 0; j < activePositions.length; j++) {
                // calculate tick lower by percent
                // calculate tickLower based on percent trailing stop, 1% price movement equal 100 ticks change
                int24 tickChange = ((100 * int24(percent)) / 10_000);
                // change direction depend if it's zeroForOne
                int24 tickLower = zeroForOne ? newTick - tickChange : newTick + tickChange;
                uint256 positionId_ = activePositions[j];
                PositionInfo storage position = positionInfoById[positionId_];
                int24 oldTick = position.tickLower;
                // move amount from position
                positionIds[id][oldTick][zeroForOne] -= position.totalAmount;
                positionIds[id][tickLower][zeroForOne] += position.totalAmount;

                // update trailing by tick id
                deleteFromTicks(positionId_, id, oldTick, zeroForOne);

                // try and merge it
                uint256 mergeId = mergePosition(id, percent, zeroForOne, position.totalAmount, tickLower, positionId_);

                if (mergeId == 0) {
                    // if it's not merged, add it to the new tick
                    positionByTicksId[id][tickLower][zeroForOne].push(positionId_);
                    position.tickLower = tickLower;
                } else {
                    position.newId = mergeId;
                    // delete from active if the position is merged
                    deleteFromActive(positionId_, id, percent, zeroForOne);
                }
            }
        }
    }

    /**
     * @notice Find a position that match the trailing pass in params
     * the goal is to reunite trailing of same percentage on the same ticks
     * so we will manage less trailing in each operations
     * return 0 if no position is found
     */
    function mergePosition(
        PoolId poolId,
        uint24 percent,
        bool zeroForOne,
        uint256 amount,
        int24 newTick,
        uint256 positionId
    ) private returns (uint256) {
        uint256[] storage activePositions = positionByPercentId[poolId][percent][zeroForOne];

        for (uint256 i = 0; i < activePositions.length; i++) {
            uint256 id = activePositions[i];
            if (positionId != id) {
                PositionInfo storage position = positionInfoById[id];
                if (position.tickLower == newTick) {
                    // merge the position
                    position.totalAmount += amount;
                    return id;
                }
            }
        }
        return 0;
    }

    function handleSwap(PoolKey memory key, IPoolManager.SwapParams memory params, address)
        private
        returns (BalanceDelta delta)
    {
        delta = poolManager.swap(key, params, ZERO_BYTES);

        console.log("//////// Swap ////////");

        // return delta
        if (params.zeroForOne) {
            console.log("//////// ZeroForOne for amount0() ////////");
            if (delta.amount0() < 0) {
                if (key.currency0.isAddressZero()) {
                    console.log("//////// ZeroForOne for amount0() isAddressZero() ////////");
                    _settle(key.currency0, uint128(-delta.amount0()));
                } else {
                    console.log("//////// ZeroForOne for amount0() !isAddressZero() ////////");
                    IERC20Minimal(Currency.unwrap(key.currency0)).transfer(
                        address(poolManager), uint128(-delta.amount0())
                    );
                    poolManager.settle();
                }
            }
            if (delta.amount1() > 0) {
                console.log("//////// ZeroForOne for amount1() ////////");
                _take(key.currency1, uint128(delta.amount1()));
            }
        } else {
            if (delta.amount1() < 0) {
                console.log("//////// OneForZero for amount1() ////////");
                if (key.currency1.isAddressZero()) {
                    console.log("//////// OneForZero for amount1() isAddressZero() ////////");
                    _settle(key.currency1, uint128(-delta.amount1()));
                } else {
                    console.log("//////// OneForZero for amount1() !isAddressZero() ////////");
                    IERC20Minimal(Currency.unwrap(key.currency1)).transfer(
                        address(poolManager), uint128(-delta.amount1())
                    );
                    poolManager.settle();
                }
            }
            if (delta.amount0() > 0) {
                console.log("//////// OneForZero for amount0() ////////");
                _take(key.currency0, uint128(delta.amount0()));
            }
        }
    }

    function deleteFromActive(uint256 idToDelete, PoolId id, uint24 percent, bool zeroForOne) private {
        uint256[] storage arr = positionByPercentId[id][percent][zeroForOne];

        // Move the last element into the place to delete
        for (uint256 j = 0; j < arr.length; j++) {
            if (arr[j] == idToDelete) {
                arr[j] = arr[arr.length - 1];
                break;
            }
        }

        // remove the last element
        arr.pop();
    }

    function deleteFromTicks(uint256 idToDelete, PoolId id, int24 tick, bool zeroForOne) private {
        uint256[] storage arr = positionByTicksId[id][tick][zeroForOne];

        // move the last element into the place to delete
        for (uint256 j = 0; j < arr.length; j++) {
            if (arr[j] == idToDelete) {
                arr[j] = arr[arr.length - 1];
                break;
            }
        }

        // remove the last element
        arr.pop();
    }

    function _settle(Currency currency, uint128 amount) private {
        poolManager.sync(currency);
        currency.transfer(address(poolManager), amount);
        poolManager.settle();
    }

    function _take(Currency currency, uint128 amount) private {
        poolManager.take(currency, address(this), amount);
    }
}
