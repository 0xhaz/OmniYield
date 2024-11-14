// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.26;

import {OApp, MessagingFee, Origin} from "LayerZero-v2/packages/layerzero-v2/evm/oapp/contracts/oapp/OApp.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MessagingReceipt} from "LayerZero-v2/packages/layerzero-v2/evm/oapp/contracts/oapp/OAppSender.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {OAppOptionsType3} from "LayerZero-v2/packages/layerzero-v2/evm/oapp/contracts/oapp/libs/OAppOptionsType3.sol";

contract DestPool is OApp, OAppOptionsType3 {
    mapping(address => uint256) public depositedCollateral;

    address public collateralToken;
    uint32 public destChainId;
    uint16 public constant SEND = 1;

    constructor(address endpoint_, address delegate_, address collateralToken_, uint32 destChainId_)
        OApp(endpoint_, delegate_)
        Ownable(delegate_)
    {
        collateralToken = collateralToken_;
        destChainId = destChainId_;
    }

    function quote(bytes memory _message, bytes calldata _extraSendOptions, bool _payInLzToken)
        public
        view
        returns (MessagingFee memory totalFee)
    {
        bytes memory options = combineOptions(destChainId, SEND, _extraSendOptions);

        MessagingFee memory fee = _quote(destChainId, _message, options, _payInLzToken);

        totalFee.nativeFee += fee.nativeFee;
        totalFee.lzTokenFee += fee.lzTokenFee;
    }

    /**
     * @notice Allows a user to deposit collateral on the destination chain
     * This collateral will be used for loans on the source chain
     */
    function depositCollateral(uint256 _collateralAmount, bytes calldata _extraSendOptions)
        external
        payable
        returns (MessagingReceipt memory receipt)
    {
        IERC20(collateralToken).transferFrom(msg.sender, address(this), _collateralAmount);
        depositedCollateral[msg.sender] += _collateralAmount;

        // Prepare payload with collateral information
        bytes memory payload = abi.encode(msg.sender, _collateralAmount);
        bytes memory options = combineOptions(destChainId, SEND, _extraSendOptions);
        MessagingFee memory fee = _quote(destChainId, payload, options, false);

        receipt = _lzSend(destChainId, payload, options, fee, payable(msg.sender));
    }

    /// @dev requires approval from user
    function takeLoan(uint256 _collateralAmount, bytes calldata _extraSendOptions)
        external
        payable
        returns (MessagingReceipt memory receipt)
    {
        IERC20(collateralToken).transferFrom(msg.sender, address(this), _collateralAmount);

        // Store collateral for borrower
        depositedCollateral[msg.sender] += _collateralAmount;

        // Prepare payload with collateral information
        bytes memory payload = abi.encode(msg.sender, _collateralAmount);

        // Define LZ options
        bytes memory options = combineOptions(destChainId, SEND, _extraSendOptions);

        // Estimate and charge the LZ messaging fee
        MessagingFee memory fee = _quote(destChainId, payload, options, false);

        receipt = _lzSend(destChainId, payload, options, fee, payable(msg.sender));
    }

    function _lzReceive(
        Origin calldata, /*_origin*/
        bytes32, /*_guid*/
        bytes calldata payload,
        address, /*_executor*/
        bytes calldata /* _extraData */
    ) internal override {
        address borrower = abi.decode(payload, (address));

        uint256 amountToReturn = depositedCollateral[borrower];
        require(amountToReturn > 0, "No collateral to return");
        // Retrieve and reset the collateral amount

        IERC20(collateralToken).transfer(borrower, amountToReturn);

        delete depositedCollateral[borrower];
    }
}
