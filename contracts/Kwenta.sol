// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import './utils/ERC20.sol';
import './Owned.sol';
import './interfaces/ISupplySchedule.sol';
import './interfaces/IStakingRewards.sol';
import './interfaces/IKwenta.sol';

contract Kwenta is ERC20, Owned, IKwenta {

    address treasuryDAO;
    address supplySchedule;
    address public stakingRewards;

    uint public treasuryDiversion;

    constructor(
        string memory name, 
        string memory symbol, 
        uint _initialSupply, 
        address _owner,
        address _treasuryDAO,
        address _supplySchedule,
        uint _treasuryDiversion
    ) ERC20(name, symbol) Owned(_owner) {
        treasuryDAO = _treasuryDAO;
        supplySchedule = _supplySchedule;
        // Provide treasury with 100% of the initial supply
        _mint(treasuryDAO, _initialSupply);
        // Divert percentage of weekly inflation to treasury
        setTreasuryDiversion(_treasuryDiversion);
    }

    // Mints inflationary supply
    function mint() override external returns (bool) {
        require(stakingRewards != address(0), "Staking rewards not set");

        ISupplySchedule _supplySchedule = ISupplySchedule(supplySchedule);
        IStakingRewards _stakingRewards = IStakingRewards(stakingRewards);

        uint supplyToMint = _supplySchedule.mintableSupply();
        require(supplyToMint > 0, "No supply is mintable");

        // record minting event before mutation to token supply
        _supplySchedule.recordMintEvent(supplyToMint);

        uint minterReward = _supplySchedule.minterReward();
        uint amountToDistribute = supplyToMint - minterReward;
        uint amountToTreasury = amountToDistribute * treasuryDiversion / 10000;
        uint amountToStakingRewards = amountToDistribute - amountToTreasury;

        _mint(treasuryDAO, amountToTreasury);
        _mint(stakingRewards, amountToStakingRewards);
        _stakingRewards.setRewardNEpochs(amountToDistribute, 1);
        _mint(msg.sender, minterReward);

        return true;
    }

    function setTreasuryDiversion(uint _treasuryDiversion) public {
        require(_treasuryDiversion < 10000, "Represented in basis points");
        treasuryDiversion = _treasuryDiversion;
    }

    function setStakingRewards(address _stakingRewards) override external onlyOwner {
        stakingRewards = _stakingRewards;
    }

}