import { expect } from "chai";
import { ethers } from "hardhat";

const StakingRewards = await ethers.getContractFactory("StakingRewards");

contract('StakingRewards_KWENTA', ([owner, staker1, staker2, staker3]) => {
	console.log("Start tests");
	let stakingRewards;

	before(async() => {
		stakingRewards = await StakingRewards.deploy(owner, staker1, staker2, staker3);
		await stakingRewards.deployed();
	});

	describe("StakingRewards_KWENTA deployment", async() => {
		it("has a name", async() => {
			const name = await stakingRewards.name();
			assert.equal(name, "KWENTA Staking rewards contract");
		})
	});
});