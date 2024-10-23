// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.26;

import {IProvider} from "src/interfaces/IProvider.sol";
import {Governed} from "src/Governed.sol";
import {ISmartYield} from "src/interfaces/ISmartYield.sol";

abstract contract IController is Governed {
    error IController__HarvestCostTooHigh();

    uint256 public constant SCALE = 1e18;

    // compound provider pool
    address public pool;

    address public smartYield;

    address public oracle;

    address public bondModel;

    address public feesOwner;

    /**
     * max accepted cost of harvest when converting COMP to underlying.
     * if havest gets less than (COMP to underlying at spot price) - HARVEST_COST, then skip harvest
     * if it gets more, the difference goes to the harvest caller
     */
    uint256 public HARVEST_COST = 40 * 1e15; // 0.04 COMP

    // fee for buying jTokens
    uint256 public FEE_BUY_JUNIOR_TOKEN = 3 * 1e15; // 0.3%

    // fee for redeeming a sBond
    uint256 public FEE_REDEEM_SENIOR_BOND = 100 * 1e15; // 10%

    // max rate per day for sBonds (30% per year)
    uint256 public BOND_MAX_RATE_PER_DAY = 821917808219178;

    // max duration for a purchased sBond
    uint16 public BOND_LIFE_MAX = 90;

    bool public PAUSED_BUY_JUNIOR_TOKENS = false;

    bool public PAUSED_BUY_SENIOR_BONDS = false;

    function setHarvestCost(uint256 newHarvestCost_) public onlyDaoGovernor {
        if (HARVEST_COST > SCALE) revert IController__HarvestCostTooHigh();
        HARVEST_COST = newHarvestCost_;
    }

    function setBondMaxRatePerDay(uint256 newBondMaxRate_) public onlyDaoGovernor {
        BOND_MAX_RATE_PER_DAY = newBondMaxRate_;
    }

    function setBondLifeMax(uint16 newBondLifeMax_) public onlyDaoGovernor {
        BOND_LIFE_MAX = newBondLifeMax_;
    }

    function setFeeBuyJuniorToken(uint256 newFeeBuyJuniorToken_) public onlyDaoGovernor {
        FEE_BUY_JUNIOR_TOKEN = newFeeBuyJuniorToken_;
    }

    function setFeeRedeemSeniorBond(uint256 newFeeRedeemSeniorBond_) public onlyDaoGovernor {
        FEE_REDEEM_SENIOR_BOND = newFeeRedeemSeniorBond_;
    }

    function setPaused(bool pausedBuyJuniorTokens_, bool pausedBuySeniorBonds_) public onlyDaoGuardian {
        PAUSED_BUY_JUNIOR_TOKENS = pausedBuyJuniorTokens_;
        PAUSED_BUY_SENIOR_BONDS = pausedBuySeniorBonds_;
    }

    function setOracle(address newOracle_) public onlyDaoGovernor {
        oracle = newOracle_;
    }

    function setBondModel(address newBondModel_) public onlyDaoGovernor {
        bondModel = newBondModel_;
    }

    function setFeesOwner(address newFeesOwner_) public onlyDaoGovernor {
        feesOwner = newFeesOwner_;
    }

    function setYieldControllTo(address newController_) public onlyDaoGovernor {
        IProvider(pool).setController(newController_);
        ISmartYield(smartYield).setController(newController_);
    }

    function providerRatePerDay() external virtual returns (uint256);
}
