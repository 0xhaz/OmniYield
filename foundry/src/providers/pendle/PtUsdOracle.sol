// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.26;

import {IPPYLpOracle} from "@pendle/core/contracts/interfaces/IPPYLpOracle.sol";
import {IPMarket} from "@pendle/core/contracts/interfaces/IPMarket.sol";
import {PMath} from "@pendle/core/contracts/core/libraries/math/PMath.sol";
import {PendleLpOracleLib} from "@pendle/core/contracts/oracles/PendleLpOracleLib.sol";
import {IPtUsdOracle} from "src/interfaces/oracle/IPtUsdOracle.sol";

import {AggregatorV2V3Interface as IChainlinkAggregator} from
    "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV2V3Interface.sol";

/**
 * @title PtUsdOracle
 * @notice The returned price from this contract is multiplied by the default USD price of the asset, as read from Chainlink Oracles
 * For more details into how the oracle is implemented, refer to PendlePtOracle and PendlePtOracleLib
 */
contract PtUsdOracle is IPPYLpOracle {
    using PendleLpOracleLib for IPMarket;

    uint32 public immutable twapPeriod;
    address public immutable market_;
    address public immutable feed;
    uint8 public immutable feedDecimals;
    address public immutable ptOracle;

    constructor(uint32 _twapPeriod, address _market, address _feed, address _ptOracle) {
        twapPeriod = _twapPeriod;
        market_ = _market;
        feed = _feed;
        feedDecimals = IChainlinkAggregator(_feed).decimals();

        // required only for sample
        ptOracle = _ptOracle;
    }

    /**
     * @notice direct integration with PendleOracleLib, which optimizes gas efficiency
     * @return price The price of the LP token in USD
     */
    function getLpPrice() external view virtual returns (uint256) {
        return IPMarket(market_).getLpToAssetRate(twapPeriod);
    }

    function getLpPriceSample1() external view virtual returns (uint256) {
        uint256 lpRate = IPMarket(market_).getLpToAssetRate(twapPeriod);
        uint256 assetPrice = _getUnderlyingAssetPrice();
        return (assetPrice * lpRate) / PMath.ONE;
    }

    function _getUnderlyingAssetPrice() internal view virtual returns (uint256) {
        uint256 rawPrice = uint256(IChainlinkAggregator(feed).latestAnswer());
        return feedDecimals < 18 ? rawPrice * 10 ** (18 - feedDecimals) : rawPrice / 10 ** (feedDecimals - 18);
    }

    function getPtToAssetRate(address market, uint32 duration) external view override returns (uint256) {}

    function getYtToAssetRate(address market, uint32 duration) external view override returns (uint256) {}

    function getLpToAssetRate(address market, uint32 duration) external view override returns (uint256) {}

    function getPtToSyRate(address market, uint32 duration) external view override returns (uint256) {}

    function getYtToSyRate(address market, uint32 duration) external view override returns (uint256) {}

    function getLpToSyRate(address market, uint32 duration) external view override returns (uint256) {}

    function getOracleState(address market, uint32 duration)
        external
        view
        override
        returns (bool increaseCardinalityRequired, uint16 cardinalityRequired, bool oldestObservationSatisfied)
    {}
}
