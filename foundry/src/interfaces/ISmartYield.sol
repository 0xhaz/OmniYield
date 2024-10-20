// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.26;

interface ISmartYield {
    // a senior BOND token
    struct SeniorBond {
        // amount seniors put in
        uint256 principal;
        // amount yielded at the end. total = principal + gain
        uint256 gain;
        // bond was issued at timestamp
        uint256 issuedAt;
        // bond matures at timestamp
        uint256 maturesAt;
        // bool whether the bond was liquidated
        bool liquidated;
    }

    // a junior BOND token
    struct JuniorBond {
        // amount of tokens (jTokens) juniors put in
        uint256 tokens;
        // bond matures at timestamp
        uint256 maturesAt;
    }

    // a checkpoint for all JuniorBonds with same maturity date JuniorBond.maturesAt
    struct JuniorBondsAt {
        // sum of JuniorBond.tokens for JuniorBonds with the same JuniorBond.maturesAt
        uint256 tokens;
        // price at which JuniorBonds will be paid. Initially 0 -> unliquidated (price is in the future or not yet liquidated)
        uint256 price;
    }

    function controller() external view returns (address);

    function buyBond(uint256 principalAmount_, uint256 minGain_, uint256 deadline_, uint16 forDays_)
        external
        returns (uint256);

    function redeemBond(uint256 bondId_) external;

    function unAccountBonds(uint256[] calldata bondIds_) external;

    function buyTokens(uint256 underlyingAmount_, uint256 minTokens_, uint256 deadline_) external;

    function sellTokens(uint256 tokens_, uint256 minUnderlying_, uint256 deadline_) external;

    function buyJuniorBond(uint256 tokenAmount_, uint256 maxMaturesAt_, uint256 deadline_) external;

    function redeemJuniorBond(uint256 jBondId_) external;

    function liquidateJuniorBond(uint256 upUntilTimestamp_) external;

    function price() external returns (uint256);

    function aBondPaid() external view returns (uint256);

    function aBondDebt() external view returns (uint256);

    function aBondGain() external view returns (uint256);

    // current total underlying balance, without accruing interest
    function underlyingTotal() external returns (uint256);

    // current underlying loable, without accruing interest
    function underlyingLoanable() external returns (uint256);

    function underlyingJuniors() external returns (uint256);

    function bondGain(uint256 principalAmount_, uint16 forDays_) external returns (uint256);

    function maxBondDailyRate() external returns (uint256);

    function setController(address newController_) external;
}
