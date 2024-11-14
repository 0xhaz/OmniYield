// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {OApp, MessagingFee, Origin} from "LayerZero-v2/packages/layerzero-v2/evm/oapp/contracts/oapp/OApp.sol";
import {MessagingReceipt} from "LayerZero-v2/packages/layerzero-v2/evm/oapp/contracts/oapp/OAppSender.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {OAppOptionsType3} from "LayerZero-v2/packages/layerzero-v2/evm/oapp/contracts/oapp/libs/OAppOptionsType3.sol";
import {IOracle} from "src/interfaces/oracle/IOracle.sol";

contract SrcPool is OApp, OAppOptionsType3 {
    error SrcPool__NoLoanToRepay();
    error SrcPool__PoolExpired();
    error SrcPool__InsufficientPoolTokenBalance();
    error SrcPool__TransferFailed();
    error SrcPool__AmountIsZero();

    uint16 public constant SEND = 1;

    struct PoolMetadata {
        uint32 destChainId;
        address destPoolAddress;
        address poolOwner;
        uint256 poolBalance;
        address poolToken;
        address oracleAddress;
        uint256[] oraclePricesIndex;
        address collateralToken;
        uint256 ltv;
        uint256 apr;
        uint256 expiry;
    }

    PoolMetadata public poolMetadata;

    struct Loan {
        uint256 amount;
        uint256 collateral;
        uint256 startTime;
        address borrower;
    }

    mapping(address => Loan) public loans;

    constructor(
        address endpoint_,
        address delegate_,
        uint32 destChainId_,
        address destPoolAddress_,
        address poolToken_,
        address oracleAddress_,
        uint256[] memory oraclePricesIndex_,
        address collateralToken_,
        uint256 ltv_,
        uint256 apr_,
        uint256 expiry_
    ) OApp(endpoint_, delegate_) Ownable(delegate_) {
        poolMetadata = PoolMetadata({
            destChainId: destChainId_,
            destPoolAddress: destPoolAddress_,
            poolOwner: delegate_,
            poolBalance: 0,
            poolToken: poolToken_,
            oracleAddress: oracleAddress_,
            oraclePricesIndex: oraclePricesIndex_,
            collateralToken: collateralToken_,
            ltv: ltv_,
            apr: apr_,
            expiry: expiry_
        });
    }

    function quote(bytes memory _message, bytes calldata _extraSendOptions, bool _payInLzToken)
        public
        view
        returns (MessagingFee memory totalFee)
    {
        bytes memory options = combineOptions(poolMetadata.destChainId, SEND, _extraSendOptions);

        MessagingFee memory fee = _quote(poolMetadata.destChainId, _message, options, _payInLzToken);

        totalFee.nativeFee += fee.nativeFee;
        totalFee.lzTokenFee += fee.lzTokenFee;
    }

    function repayLoan(bytes calldata _extraSendOptions) external payable returns (MessagingReceipt memory receipt) {
        if (loans[msg.sender].amount == 0) revert SrcPool__NoLoanToRepay();
        if (block.timestamp >= poolMetadata.expiry) revert SrcPool__PoolExpired();
        if (IERC20(poolMetadata.poolToken).balanceOf(msg.sender) <= getRepaymentAmount(msg.sender)) {
            revert SrcPool__InsufficientPoolTokenBalance();
        }

        uint256 totalRepayment = getRepaymentAmount(msg.sender);
        poolMetadata.poolBalance += totalRepayment;

        bytes memory options = combineOptions(poolMetadata.destChainId, SEND, _extraSendOptions);

        if (!IERC20(poolMetadata.poolToken).transferFrom(msg.sender, address(this), totalRepayment)) {
            revert SrcPool__TransferFailed();
        }

        // Clear the user's loan record and update the pool balance
        poolMetadata.poolBalance += totalRepayment;
        delete loans[msg.sender];

        bytes memory payload = abi.encode(msg.sender);

        MessagingFee memory fee = _quote(poolMetadata.destChainId, payload, options, false);

        receipt = _lzSend(poolMetadata.destChainId, payload, options, fee, payable(msg.sender));
    }

    /// @dev requires approval from user
    function deposit(uint256 _amount) external {
        if (_amount < 0) revert SrcPool__AmountIsZero();
        IERC20(poolMetadata.poolToken).transferFrom(msg.sender, address(this), _amount);

        poolMetadata.poolBalance += _amount;
    }

    function getRepaymentAmount(address _sender) public view returns (uint256) {
        Loan storage loan = loans[_sender];
        if (loan.amount == 0) return 0;

        uint256 interest = (loan.amount * poolMetadata.apr * (block.timestamp - loan.startTime)) / (10_000 * 365 days);

        return loan.amount + interest;
    }

    function getLoanAmount(uint256 collateral) public view returns (uint256 loanAmount) {
        uint256 poolPrice = IOracle(poolMetadata.oracleAddress).getPrice(poolMetadata.oraclePricesIndex[0]);
        uint256 debtPrice = IOracle(poolMetadata.oracleAddress).getPrice(poolMetadata.oraclePricesIndex[1]);

        loanAmount = (collateral * debtPrice * poolMetadata.ltv) / (poolPrice * 10_000);
    }

    function _lzReceive(
        Origin calldata, /*_origin */
        bytes32, /*_guid */
        bytes calldata payload,
        address, /*_executor */
        bytes calldata /*_extraData */
    ) internal override {
        // Decode payload from DestPool to get borrower and collateral info
        (address borrower, uint256 collateral) = abi.decode(payload, (address, uint256));

        // Calculate the loan amount using the given collateral
        uint256 loanAmount = getLoanAmount(collateral);

        // Verfify if the pool has enough balance to lend the loan amount
        if (poolMetadata.poolBalance <= loanAmount) {
            revert SrcPool__InsufficientPoolTokenBalance();
        }

        // Record the loan details
        loans[borrower] =
            Loan({amount: loanAmount, collateral: collateral, startTime: block.timestamp, borrower: borrower});

        // Update the pool balance and send loan amount to borrower
        poolMetadata.poolBalance -= loanAmount;

        IERC20(poolMetadata.poolToken).transfer(borrower, loanAmount);
    }

    function getPoolMetadata() external view returns (PoolMetadata memory) {
        return poolMetadata;
    }
}
