// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.26;

interface IStakedTokenIncentivesController {
    function REWARD_TOKEN() external view returns (address);

    function claimRewards(address[] calldata assets, uint256 amount, address to) external returns (uint256);
}
