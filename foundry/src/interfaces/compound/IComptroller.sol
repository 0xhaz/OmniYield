// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.26;

interface IComptroller {
    struct CompMarketState {
        uint224 index;
        uint32 block;
    }

    function enterMarkets(address[] calldata cTokens) external returns (uint256[] memory);
    function claimComp(address[] memory holders, address[] memory cTokens, bool borrowers, bool suppliers) external;
    function mintAllowed(address cToken, address minter, uint256 mintAmount) external returns (uint256);
    function getCompAddress() external view returns (address);
    function compSupplyState(address cToken) external view returns (uint224, uint32);
    function compSpeeds(address cToken) external view returns (uint256);
    function oracle() external view returns (address);
}
