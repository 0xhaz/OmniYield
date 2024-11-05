// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.26;

import {MessagingReceipt} from "LayerZero-v2/packages/layerzero-v2/evm/oapp/contracts/oapp/OAppSender.sol";
import {Origin} from "LayerZero-v2/packages/layerzero-v2/evm/oapp/contracts/oapp/OApp.sol";

interface IDestPool {
    function depositedCollateral(address user) external view returns (uint256);

    function collateralToken() external view returns (address);

    function destChainId() external view returns (uint32);

    function takeLoan(uint256 _collateralAmount) external returns (MessagingReceipt memory receipt);

    function _lzReceive(
        Origin calldata _origin,
        bytes32 _guid,
        bytes calldata _payload,
        address _executor,
        bytes calldata _extraData
    ) external;
}
