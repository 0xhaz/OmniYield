// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ILayerZeroReceiver} from "src/interfaces/lzApp/ILayerZeroReceiver.sol";
import {ILayerZeroUserApplicationConfig} from "src/interfaces/lzApp/ILayerZeroUserApplicationConfig.sol";
import {ILayerZeroEndpoint} from "src/interfaces/lzApp/ILayerZeroEndpoint.sol";
import {BytesLib} from "src/utils/BytesLib.sol";

/**
 * @title LzApp
 * @notice A generic LzReceiver Implementation
 */
abstract contract LzApp is Ownable, ILayerZeroReceiver, ILayerZeroUserApplicationConfig {
    using BytesLib for bytes;

    /*//////////////////////////////////////////////////////////////
                              ERROR CODES
    //////////////////////////////////////////////////////////////*/
    error LzApp__INVALID_ENDPOINT_CALLER();
    error LzApp__UNTRUSTED_REMOTE();
    error LzApp__MIN_GAS_NOT_SET();
    error LzApp__INSUFFICIENT_GAS();
    error LzApp__PAYLOAD_TOO_LARGE();
    error LzApp__INVALID_ADAPTER_PARAMS();

    /*//////////////////////////////////////////////////////////////
                              GLOBAL STATE
    //////////////////////////////////////////////////////////////*/
    // ua cannot send payload larger than this by default, but it can be changed by the ua owner
    uint256 public constant DEFAULT_PAYLOAD_SIZE_LIMIT = 10_000;

    ILayerZeroEndpoint public immutable lzEndpoint;
    mapping(uint16 => bytes) public trustedRemoteLookup;
    mapping(uint16 => mapping(uint16 => uint256)) public minDstGasLookup;
    mapping(uint16 => uint256) public payloadSizeLimitLookup;
    address public precrime;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    event SetPrecrime(address precrime);
    event SetTrustedRemote(uint16 _remoteChainId, bytes _path);
    event SetTrustedRemoteAddress(uint16 _remoteChainId, bytes _remoteAddress);
    event SetMinDstGas(uint16 _dstChainId, uint16 _type, uint256 _minDstGas);

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    constructor(address _endPoint) {
        lzEndpoint = ILayerZeroEndpoint(_endPoint);
    }

    /*//////////////////////////////////////////////////////////////
                            PUBLIC FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function lzReceive(uint16 _srcChainId, bytes calldata _srcAddress, uint64 _nonce, bytes calldata _payload)
        public
        virtual
        override
    {
        // lzReceive must be called by the endpoint for security
        if (_msgSender() != address(lzEndpoint)) revert LzApp__INVALID_ENDPOINT_CALLER();

        bytes memory trustedRemote = trustedRemoteLookup[_srcChainId];
        // if will still block the message pathway from (srcChainId, srcAddress). should not receive message from untrusted remote
        if (_srcAddress.length != trustedRemote.length && trustedRemote.length != 0) revert LzApp__UNTRUSTED_REMOTE();

        _blockingLzReceive(_srcChainId, _srcAddress, _nonce, _payload);
    }

    /*//////////////////////////////////////////////////////////////
                            INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function _lzSend(
        uint16 _dstChainId,
        bytes memory _payload,
        address payable _refundAddress,
        address _zroPaymentAddress,
        bytes memory _adapterParams,
        uint256 _nativeFee
    ) internal virtual {
        bytes memory trustedRemote = trustedRemoteLookup[_dstChainId];

        if (trustedRemote.length == 0) revert LzApp__UNTRUSTED_REMOTE();

        _checkPayloadSize(_dstChainId, _payload.length);

        lzEndpoint.send{value: _nativeFee}(
            _dstChainId, trustedRemote, _payload, _refundAddress, _zroPaymentAddress, _adapterParams
        );
    }

    function _checkGasLimit(uint16 _dstChainId, uint16 _type, bytes memory _adapterParams, uint256 _extraGas)
        internal
        view
        virtual
    {
        uint256 providedGasLimit = _getGasLimit(_adapterParams);
        uint256 minGasLimit = minDstGasLookup[_dstChainId][_type] + _extraGas;

        if (minGasLimit == 0) revert LzApp__MIN_GAS_NOT_SET();
        if (providedGasLimit <= minGasLimit) revert LzApp__INSUFFICIENT_GAS();
    }

    /// @notice the default behavior of LayerZero is blocking. See: NonblockingLzApp if you dont need to enforce ordered messaging
    function _blockingLzReceive(uint16 _srcChainId, bytes memory _srcAddress, uint64 _nonce, bytes memory _payload)
        internal
        virtual;

    function _checkPayloadSize(uint16 _dstChainId, uint256 _payloadSize) internal view virtual {
        uint256 payloadSizeLimit = payloadSizeLimitLookup[_dstChainId];
        if (payloadSizeLimit == 0) {
            payloadSizeLimit = DEFAULT_PAYLOAD_SIZE_LIMIT;
        }
        if (_payloadSize >= payloadSizeLimit) revert LzApp__PAYLOAD_TOO_LARGE();
    }

    function _getGasLimit(bytes memory _adapterParams) internal pure virtual returns (uint256 gasLimit) {
        if (_adapterParams.length <= 34) revert LzApp__INVALID_ADAPTER_PARAMS();

        assembly {
            gasLimit := mload(add(_adapterParams, 34))
        }
    }

    /*//////////////////////////////////////////////////////////////
                         USER APPLICATION CONFIG
    //////////////////////////////////////////////////////////////*/
    function getConfig(uint16 _version, uint16 _chainId, address, uint256 _configType)
        external
        view
        returns (bytes memory)
    {
        return lzEndpoint.getConfig(_version, _chainId, address(this), _configType);
    }

    // generic config for LayerZero User Application
    function setConfig(uint16 _version, uint16 _chainId, uint256 _configType, bytes calldata _config)
        external
        override
        onlyOwner
    {
        lzEndpoint.setConfig(_version, _chainId, _configType, _config);
    }

    function setSendVersion(uint16 _version) external override onlyOwner {
        lzEndpoint.setSendVersion(_version);
    }

    function setReceiveVersion(uint16 _version) external override onlyOwner {
        lzEndpoint.setReceiveVersion(_version);
    }

    function forceResumeReceive(uint16 _srcChainId, bytes calldata _srcAddress) external override onlyOwner {
        lzEndpoint.forceResumeReceive(_srcChainId, _srcAddress);
    }

    // _path = abi.encodePacked(remoteAddress, localAddress)
    // this function set the trusted path for the cross-chain communication
    function setTrustedRemote(uint16 _remoteChainId, bytes calldata _path) external onlyOwner {
        trustedRemoteLookup[_remoteChainId] = _path;
        emit SetTrustedRemote(_remoteChainId, _path);
    }

    function getTrustedRemoteAddress(uint16 _remoteChainId) external view returns (bytes memory) {
        bytes memory path = trustedRemoteLookup[_remoteChainId];
        require(path.length != 0, "LzApp: no trusted path record");
        return path.slice(0, path.length - 20); // the last 20 bytes should be address(this)
    }

    function setPrecrime(address _precrime) external onlyOwner {
        precrime = _precrime;
        emit SetPrecrime(_precrime);
    }

    function setMinDstGas(uint16 _dstChainId, uint16 _packetType, uint256 _minGas) external onlyOwner {
        require(_minGas > 0, "LzApp: invalid minGas");
        minDstGasLookup[_dstChainId][_packetType] = _minGas;
        emit SetMinDstGas(_dstChainId, _packetType, _minGas);
    }

    // if the size is 0, it means default size limit
    function setPayloadSizeLimit(uint16 _dstChainId, uint256 _size) external onlyOwner {
        payloadSizeLimitLookup[_dstChainId] = _size;
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function isTrustedRemote(uint16 _srcChainId, bytes calldata _srcAddress) external view returns (bool) {
        bytes memory trustedSource = trustedRemoteLookup[_srcChainId];
        return keccak256(trustedSource) == keccak256(_srcAddress);
    }
}
