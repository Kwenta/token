const { wei } = require('@synthetixio/wei');
const hardhat = require('hardhat');

const NAME = "Kwenta";
const SYMBOL = "KWENTA";
const INITIAL_SUPPLY = hre.ethers.utils.parseUnits("313373");
const INFLATION_DIVERSION_BPS = 2000;

require("chai")
	.use(require("chai-as-promised"))
	.use(require("chai-bn-equal"))
	.should();

contract('UUPS Proxy for StakingRewards', ([owner, rewardsDistribution, supplySchedule]) => {
	console.log("Start tests");
	let stakingRewards;
	let kwentaToken;
	let rewardsEscrow;
	let st_proxy;
	let staker1;
	let staker2;
	let treasuryDAO;

	before(async() => {
		[staker1, staker2, treasuryDAO] = await hre.ethers.getSigners();
		KwentaToken = await hre.ethers.getContractFactory("Kwenta");
		kwentaToken = await KwentaToken.deploy(
			NAME, 
			SYMBOL,
			INITIAL_SUPPLY,
			owner,
			treasuryDAO.address
		);
		RewardsEscrow = await hre.ethers.getContractFactory("RewardEscrow");
		rewardsEscrow = await RewardsEscrow.deploy(owner, kwentaToken.address);
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
							ExponentLib: exponentLib.address
				}
			});
			st_proxy = await hre.upgrades.deployProxy(
                StakingRewards,
                [
                    owner,
                    kwentaToken.address,
                    rewardsEscrow.address,
                    supplySchedule,
                    3,
                ],
                {kind: 'uups', unsafeAllow: ['external-library-linking']}
            );

			admin_address = await hre.upgrades.erc1967.getAdminAddress(st_proxy.address);
			implementation = await hre.upgrades.erc1967.getImplementationAddress(st_proxy.address);

			owner_address = await st_proxy.owner();

			assert.notEqual(implementation, st_proxy.address);

		});
		it("should stake correctly", async() => {
			
			await kwentaToken.connect(treasuryDAO).transfer(staker1.address, wei(100).toBN());
			await kwentaToken.connect(staker1).approve(st_proxy.address, wei(100).toBN());

			await st_proxy.connect(staker1).stake(wei(50).toBN());

			let balance = await st_proxy.connect(staker1).stakedBalanceOf(staker1.address);

			assert.equal(balance.toString(), wei(50).toBN());
		});

		it("should upgrade correctly", async() => {

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
							ExponentLib: exponentLib.address
				}
			});

  			const upgradedImplementation = await hre.upgrades.upgradeProxy(st_proxy.address, 
  				stakingRewardsV2,
				{
				unsafeAllow: ["external-library-linking"]
				}
  				);

  			await upgradedImplementation.setVersion("V2");

  			let version = await upgradedImplementation.getVersion();

  			assert.equal(version, "V2");

  			let stakingRewardsV3 = await hre.ethers.getContractFactory("StakingRewardsV3", {
				libraries: {FixidityLib: fixidityLib.address,
							ExponentLib: exponentLib.address
				}
			});

			const upgradedImplementationV3 = await hre.upgrades.upgradeProxy(upgradedImplementation.address, 
  				stakingRewardsV3,
				{
				unsafeAllow: ["external-library-linking"]
				}
  				);

			await upgradedImplementationV3.setVersion("V3");

  			version = await upgradedImplementationV3.getVersion();

  			assert.equal(version, "V3");

  			await upgradedImplementationV3.setTotalRewardScoreAdded(); 
  			let rewardScoreAdded = await upgradedImplementationV3.getTotalRewardScoreAdded();
  			assert.equal(rewardScoreAdded.toString(), "2");


			let balance = await upgradedImplementationV3.stakedBalanceOf(staker1.address);
			assert.equal(balance.toString(), wei(50).toBN());



		});
	});
});