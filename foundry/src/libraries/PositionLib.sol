// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.26;

import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {IERC20Minimal} from "v4-core/interfaces/external/IERC20Minimal.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";
import {PerpsHook} from "src/dex/PerpsHook.sol";

/**
 * @title PositionLib
 * @dev Library for handling positions within the Perps contract
 *
 */
library PositionLib {
    using PoolIdLibrary for PoolId;

    /**
     * @notice Places a position based on user-defined parameters
     * @param self The instance of the PerpsHook contract for storage access
     * @param key The key of the pool to place the position in
     * @param percent The trailing stop percentage for the position
     * @param amountIn The amount of the token to place in the position
     * @param zeroForOne the direction of the position
     * @return tickLower The lower tick of the position
     * @return tokenId The ID of the position
     */
    function placePosition(PerpsHook self, PoolKey calldata key, uint24 percent, uint256 amountIn, bool zeroForOne)
        internal
        returns (int24 tickLower, uint256 tokenId)
    {
        if (percent < 10_000 || percent > 100_000 || percent % 10_000 != 0) {
            revert PerpsHook.PerpsHook__InvalidPercentage(percent);
        }
    }
}
