const hardhat = require('hardhat');
// const { deployProxy, upgradeProxy } = require('@openzeppelin/truffle-upgrades');

const Owned = artifacts.require("Owned");

let FixidityLib = artifacts.require("FixidityLib");
let ExponentLib = artifacts.require("ExponentLib");
let LogarithmLib = artifacts.require("LogarithmLib");

let StakingRewards = artifacts.require("StakingRewards");
let StakingRewardsV2 = artifacts.require("StakingRewardsV2");
let TokenContract = artifacts.require("ERC20");
let RewardsEscrow = artifacts.require("RewardEscrow");

const NAME = "Kwenta";
const SYMBOL = "KWENTA";

require("chai")
	.use(require("chai-as-promised"))
	.use(require("chai-bn-equal"))
	.should();

contract('UUPS Proxy for StakingRewards', ([owner, rewardsDistribution]) => {
	console.log("Start tests");
	let stakingRewards;
	let stakingToken;
	let rewardsToken;
	let rewardsEscrow;
	let st_proxy;

	before(async() => {
		stakingToken = await TokenContract.new(NAME, SYMBOL);
		rewardsToken = await TokenContract.new(NAME, SYMBOL);
		rewardsEscrow = await RewardsEscrow.new(
				owner,
				stakingToken.address
			);
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
			st_proxy = await hre.upgrades.deployProxy(StakingRewards,
				[owner, rewardsDistribution, rewardsToken.address, stakingToken.address, rewardsEscrow.address],
				{kind: "uups",
				unsafeAllow: ["external-library-linking"]
				});

			admin_address = await hre.upgrades.erc1967.getAdminAddress(st_proxy.address);
			implementation = await hre.upgrades.erc1967.getImplementationAddress(st_proxy.address);

			owner_address = await st_proxy.owner();

			assert.notEqual(implementation, st_proxy.address);

		});
		it("should stake correctly", async() => {
			const [staker1, staker2] = await hre.ethers.getSigners();

			await stakingToken._mint(staker1.address, 100);
			await stakingToken.approve(st_proxy.address, 100, {from: staker1.address});

			await st_proxy.connect(staker1).stake(50);

			let balance = await st_proxy.connect(staker1).balanceOf(staker1.address);

			assert.equal(balance, 50);
		});

		it("should stake upgrade correctly", async() => {


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


			let stakingRewardsV2 = await hre.ethers.getContractFactory("StakingRewardsV2", {
				libraries: {FixidityLib: fixidityLib.address,
							ExponentLib: exponentLib.address,
				}
			});

  			const upgradedImplementation = await hre.upgrades.upgradeProxy(st_proxy.address, 
  				stakingRewardsV2,
				{
				unsafeAllow: ["external-library-linking"]
				}
  				);

  			let version = await upgradedImplementation.version();

  			assert.equal(version, "V2");

		});
	});
});