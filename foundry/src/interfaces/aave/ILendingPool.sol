// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.26;

interface ILendingPool {
    struct ReserveConfigurationMap {
        // bit 0-15: LTV
        // bit 16-31: Liq. threshold
        // bit 32-47: Liq. bonus
        // bit 48-55: Decimals
        // bit 56: Reserve is active
        // bit 57: Reserve is frozen
        // bit 58: Borrowing is enabled
        // bit 59: Stable rate borrowing enabled
        // bit 60-63: Reserve factor
        // bit 64-79: Usage as collateral enabled
        uint256 data;
    }

    struct ReserveData {
        // stores the reserve configuration
        ReserveConfigurationMap configuration;
        // the liquidity index. Expressed in ray
        uint128 liquidityIndex;
        // variable borrow index. Expressed in ray
        uint128 variableBorrowIndex;
        // the current supply rate. Expressed in ray
        uint128 currentLiquidityRate;
        // the current variable borrow rate. Expressed in ray
        uint128 currentVariableBorrowRate;
        // the current stable borrow rate. Expressed in ray
        uint128 currentStableBorrowRate;
        uint40 lastUpdateTimestamp;
        // tokens addresses
        address aTokenAddress;
        address stableDebtTokenAddress;
        address variableDebtTokenAddress;
        // address of the interest rate strategy
        address interestRateStrategyAddress;
        // the id of the reserve. Represents the position in the list of the active reserves
        uint8 id;
    }

    function getReserveData(address asset) external view returns (ReserveData memory);
    function getReserveNormalizedIncome(address asset) external view returns (uint256);
    function deposit(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external;
    function withdraw(address asset, uint256 amount, address to) external returns (uint256);
}
