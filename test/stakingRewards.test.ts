/*import { expect } from "chai";
import { ethers } from "hardhat";
import { Signer, ContractFactory, Contract } from "ethers";

describe("Staking Rewards", function () {

	let StakingRewards:ContractFactory;
	let stakingRewards:Contract;
	let accounts:Signer[];
	let owner:string;
	let rewardDistr:string;
	let stakingToken:string;
	let rewardToken:string;
	let staker1:string;
	let staker2:string;

beforeEach(async function () {
    
  	accounts = await ethers.getSigners();

  	owner = await accounts[0].getAddress();
  	rewardDistr = await accounts[1].getAddress();
  	rewardToken = await accounts[2].getAddress();
  	stakingToken = await accounts[3].getAddress();

  	staker1 = await accounts[4].getAddress();
  	staker2 = await accounts[5].getAddress();

  	StakingRewards = await ethers.getContractFactory("StakingRewards");
  	stakingRewards = await StakingRewards.deploy(owner, 
    	rewardDistr,
    	rewardToken, 
    	stakingToken
    	);
  	await stakingRewards.deployed(); 
    
  });	
  
  it("Should deploy with correct addresses", async function () {

  	expect(await stakingRewards.rewardsToken()).to.equal(rewardToken);
    expect(await stakingRewards.stakingToken()).to.equal(stakingToken);
    expect(await stakingRewards.rewardsDistribution()).to.equal(rewardDistr);
    expect(await stakingRewards.owner()).to.equal(owner);

    expect(await stakingRewards.totalSupply()).to.equal(0);
    expect(await stakingRewards.totalRewardScore()).to.equal(0);
  });
  
  it("stakes the correct amount", async() => {
	await stakingRewards.stake(15, {from: staker1});
	let bal = await stakingRewards._balances(staker1);
	expect(bal).to.equal(15);
	let ts = await stakingRewards._totalSupply();
	expect(ts).to.equal(15);

	await stakingRewards.stake(50, {from: staker2});
	bal = await stakingRewards._balances(staker2);
	expect(bal).to.equal(50);
	ts = await stakingRewards._totalSupply();
	expect(ts).to.equal(50);
})

});
*/