// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.26;

import {SrcPool} from "src/lzApp/SrcPool.sol";

contract PoolSrcFactory {
    address[] private allSrcPools;
    address[] private listedSrcPools;

    mapping(address => address[]) private ownerToSrcPools;

    event DeployedSrcPool(address srcPoolAddress);

    function deploySrcPool(
        address _endpoint,
        address _delegate,
        uint32 _destChainId,
        address _destPoolAddress,
        address _poolToken,
        address _oracleAddress,
        uint256[] memory _oraclePricesIndex,
        address _collateralToken,
        uint256 _ltv,
        uint256 _apr,
        uint256 _expiry
    ) external {
        SrcPool pool = new SrcPool(
            _endpoint,
            _delegate,
            _destChainId,
            _destPoolAddress,
            _poolToken,
            _oracleAddress,
            _oraclePricesIndex,
            _collateralToken,
            _ltv,
            _apr,
            _expiry
        );
        ownerToSrcPools[msg.sender].push(address(pool));
        allSrcPools.push(address(pool));

        emit DeployedSrcPool(address(pool));
    }

    function listSrcPool(address srcPoolAddress) external {
        require(isOwner(msg.sender, srcPoolAddress), "Not owner");

        listedSrcPools.push(srcPoolAddress);
    }

    function buySrcPool(address srcPoolAddress) external {
        address oldOwner = getOwner(srcPoolAddress);

        removeSrcPoolFromOwner(oldOwner, srcPoolAddress);
        ownerToSrcPools[msg.sender].push(srcPoolAddress);

        removeListedPool(srcPoolAddress);
    }

    function getSrcPoolsByOwner(address _owner) external view returns (address[] memory) {
        return ownerToSrcPools[_owner];
    }

    function getAllSrcPools() external view returns (address[] memory) {
        return allSrcPools;
    }

    function getListedSrcPools() external view returns (address[] memory) {
        return listedSrcPools;
    }

    function isOwner(address _owner, address _srcPool) public view returns (bool) {
        address[] memory srcPools = ownerToSrcPools[_owner];

        for (uint256 i = 0; i < srcPools.length; i++) {
            if (srcPools[i] == _srcPool) {
                return true;
            }
        }

        return false;
    }

    function getOwner(address _srcPool) public view returns (address) {
        for (uint256 i = 0; i < allSrcPools.length; i++) {
            if (allSrcPools[i] == _srcPool) {
                return ownerToSrcPools[allSrcPools[i]][0];
            }
        }

        return address(0);
    }

    function removeSrcPoolFromOwner(address _owner, address _srcPool) public {
        address[] storage srcPools = ownerToSrcPools[_owner];

        for (uint256 i = 0; i < srcPools.length; i++) {
            if (srcPools[i] == _srcPool) {
                srcPools[i] = srcPools[srcPools.length - 1];
                srcPools.pop();
                break;
            }
        }
    }

    function removeListedPool(address _srcPool) public {
        for (uint256 i = 0; i < listedSrcPools.length; i++) {
            if (listedSrcPools[i] == _srcPool) {
                listedSrcPools[i] = listedSrcPools[listedSrcPools.length - 1];
                listedSrcPools.pop();
                break;
            }
        }
    }
}
