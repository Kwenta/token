// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import './ERC20.sol';
import './interfaces/ISupplySchedule.sol';
import './interfaces/IRewardsDistribution.sol';

contract Kwenta is ERC20 {

    address rewardsDistribution;
    address supplySchedule;

    constructor(
        string memory name, 
        string memory symbol, 
        uint _initialSupply, 
        address _treasuryDAO,
        address _rewardsDistribution,
        address _supplySchedule
    ) ERC20(name, symbol) {
        // Treasury DAO 60%
        _mint(_treasuryDAO, _initialSupply * 60 / 100);
        // TODO: Transfer to respective distributions:
        // Synthetix Staker Airdrop 30%
        // SX/Kwenta Airdrop 2.5%
        // Trader Ongoing Distribution 2.5%
        // Aelin 5%
        rewardsDistribution = _rewardsDistribution;
        supplySchedule = _supplySchedule;
    }

    // Mints inflationary supply
    function mint() external override returns (bool) {
        require(rewardsDistribution != address(0), "RewardsDistribution not set");

        ISupplySchedule _supplySchedule = ISupplySchedule(supplySchedule);
        IRewardsDistribution _rewardsDistribution = IRewardsDistribution(rewardsDistribution);

        uint supplyToMint = _supplySchedule.mintableSupply();
        require(supplyToMint > 0, "No supply is mintable");

        // record minting event before mutation to token supply
        _supplySchedule.recordMintEvent(supplyToMint);

        // Set minted SNX balance to RewardEscrow's balance
        // Minus the minterReward and set balance of minter to add reward
        uint minterReward = _supplySchedule.minterReward();
        // Get the remainder
        uint amountToDistribute = supplyToMint - minterReward;

        // Mint to the RewardsDistribution contract
        _mint(rewardsDistribution, amountToDistribute);

        // Kick off the distribution of rewards
        _rewardsDistribution.distributeRewards(amountToDistribute);

        // Assign the minters reward.
        _mint(msg.sender, minterReward);

        return true;
    }

}