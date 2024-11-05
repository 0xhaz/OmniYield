// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.26;

interface IPoolFactory {
    event DeployedSourcePool(address srcPoolAddress);
    event DeployedDestPool(address destPoolAddress);

    function deployScript(
        address endpoint,
        address delegate,
        uint32 destChainId,
        address destPoolAddress,
        address poolToken,
        address collateralToken,
        uint256 ltv,
        uint256 apr,
        uint256 expiry
    ) external;

    function deployDestPool(address endpoint, address delegate, address collateralToken, uint32 destChainId) external;

    function getSrcPoolsByOwner(address owner) external view returns (address[] memory);

    function getDestPoolsByOwner(address owner) external view returns (address[] memory);

    function getAllSrcPools() external view returns (address[] memory);

    function getAllDestPools() external view returns (address[] memory);
}
