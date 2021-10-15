const hardhat = require('hardhat');
// const { deployProxy, upgradeProxy } = require('@openzeppelin/truffle-upgrades');

const Owned = artifacts.require("Owned");

let FixidityLib = artifacts.require("FixidityLib");
let ExponentLib = artifacts.require("ExponentLib");
let LogarithmLib = artifacts.require("LogarithmLib");

let StakingRewards = artifacts.require("StakingRewards");
let TokenContract = artifacts.require("ERC20");
let RewardsEscrow = artifacts.require("RewardEscrow");

const NAME = "Kwenta";
const SYMBOL = "KWENTA";

require("chai")
	.use(require("chai-as-promised"))
	.use(require("chai-bn-equal"))
	.should();

contract('UUPS Proxy for StakingRewards', ([owner, admin, rewardsDistribution, staker1, staker2]) => {
	console.log("Start tests");
	let stakingRewards;
	let stakingToken;
	let rewardsToken;
	let rewardsEscrow;

	before(async() => {
		stakingToken = await TokenContract.new(NAME, SYMBOL);
		rewardsToken = await TokenContract.new(NAME, SYMBOL);

		fixidityLib = await FixidityLib.new();
		await LogarithmLib.link(fixidityLib);
		logarithmLib = await LogarithmLib.new();
		await ExponentLib.link(fixidityLib);
		await ExponentLib.link(logarithmLib);
		exponentLib = await ExponentLib.new();

		await StakingRewards.link(fixidityLib);
		await StakingRewards.link(exponentLib);
		rewardsEscrow = await RewardsEscrow.new(
				owner,
				stakingToken.address
			);

		/*stakingRewards = await StakingRewards.new(owner,
			rewardsDistribution,
			rewardsToken.address,
			stakingToken.address,
			rewardsEscrow.address
			);*/


		//rewardsEscrow.setStakingRewards(stakingRewards.address, {from: owner});

	});

	describe("UUPS Deployment", async() => {
		it("should deploy the proxy", async() => {

			FixidityLib = await hre.ethers.getContractFactory("FixidityLib");
			fixidityLib = await FixidityLib.deploy();
			
			LogarithmLib = await hre.ethers.getContractFactory("LogarithmLib", {
				libraries: {FixidityLib: fixidityLib.address}
			});
			logarithmLib = await LogarithmLib.deploy();

			ExponentLib = await hre.ethers.getContractFactory("ExponentLib", {
				libraries: {FixidityLib: fixidityLib.address,
							LogarithmLib: logarithmLib.address,
				}
			});
			exponentLib = await ExponentLib.deploy();


			StakingRewards = await hre.ethers.getContractFactory("StakingRewards", {
				libraries: {FixidityLib: fixidityLib.address,
							ExponentLib: exponentLib.address,
				}
			});
			const st_proxy = await hre.upgrades.deployProxy(StakingRewards,
				[owner, rewardsDistribution, rewardsToken.address, stakingToken.address, rewardsEscrow.address],
				{kind: "uups",
				unsafeAllow: ["external-library-linking"]
				});
		});
	});
});