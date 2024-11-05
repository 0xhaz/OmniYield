// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.26;

import {MessagingReceipt} from "LayerZero-v2/packages/layerzero-v2/evm/oapp/contracts/oapp/OAppSender.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ISrcPool {
    struct PoolMetadata {
        uint32 destChainId;
        address destPoolAddress;
        address poolOwner;
        uint256 poolBalance;
        address poolToken;
        address collateralToken;
        uint256 ltv;
        uint256 apr;
        uint256 expiry;
    }

    struct Loan {
        uint256 amount;
        uint256 collateral;
        uint256 startTime;
        address borrower;
    }

    function poolMetadata() external view returns (PoolMetadata memory);

    function loans(address borrower) external view returns (Loan memory);

    function repayLoan() external returns (MessagingReceipt memory receipt);

    function deposit(uint256 amount) external;

    function getRepaymentAmount(address sender) external view returns (uint256);

    function getPoolMetadata() external view returns (PoolMetadata memory);
}
