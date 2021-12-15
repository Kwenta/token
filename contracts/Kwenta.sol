// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import './utils/ERC20.sol';
import './interfaces/ISupplySchedule.sol';
import './interfaces/IStakingRewards.sol';

contract Kwenta is ERC20 {

    address stakingRewards;
    address supplySchedule;

    constructor(
        string memory name, 
        string memory symbol, 
        uint _initialSupply, 
        address _treasuryDAO,
        address _stakingRewards,
        address _supplySchedule
    ) ERC20(name, symbol) {
        // Treasury DAO 60%
        _mint(_treasuryDAO, _initialSupply * 60 / 100);
        // TODO: Transfer to respective distributions:
        // Synthetix Staker Airdrop 30%
        // SX/Kwenta Airdrop 2.5%
        // Trader Ongoing Distribution 2.5%
        // Aelin 5%
        stakingRewards = _stakingRewards;
        supplySchedule = _supplySchedule;
    }

    // Mints inflationary supply
    function mint() external returns (bool) {
        require(stakingRewards != address(0), "Staking rewards not set");

        ISupplySchedule _supplySchedule = ISupplySchedule(supplySchedule);
        IStakingRewards _stakingRewards = IStakingRewards(stakingRewards);

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
        _mint(stakingRewards, amountToDistribute);

        // Kick off the distribution of rewards
        _stakingRewards.setRewardNEpochs(amountToDistribute, 1);

        // Assign the minters reward.
        _mint(msg.sender, minterReward);

        return true;
    }

}