// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.26;

import {DestPool} from "src/lzApp/DestPool.sol";

contract PoolDestFactory {
    mapping(address => address[]) public ownerToDestPools;

    address[] public allDestPools;

    event DeployedDestPool(address destPoolAddress);

    function deployDestPool(address _endpoint, address _delegate, address _collateralToken, uint32 _destChainId)
        external
    {
        DestPool pool = new DestPool(_endpoint, _delegate, _collateralToken, _destChainId);

        ownerToDestPools[msg.sender].push(address(pool));
        allDestPools.push(address(pool));

        emit DeployedDestPool(address(pool));
    }

    function getDestPoolsByOwner(address _owner) external view returns (address[] memory) {
        return ownerToDestPools[_owner];
    }

    function getAllDestPools() external view returns (address[] memory) {
        return allDestPools;
    }
}
