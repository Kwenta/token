const hardhat = require('hardhat');

async function main() {

  // We get the addresses of the contracts (libraries + staking rewards contract)

  let fixidityLibAddress = "0x0";
  let decayRateLib = "0x0";
  let stakingRewardsProxyAddress = "0x0";

  let newAdminAddress = "0x0";

  StakingRewards = await hre.ethers.getContractFactory("StakingRewards", {
    libraries: {FixidityLib: fixidityLibAddress,
          ExponentLib: decayRateLib,
    }
  });

  // Connect the UUPS Proxy 

  stakingRewardsProxy = await StakingRewards.attach(stakingRewardsProxyAddress);

  await stakingRewardsProxy.setPendingAdmin(newAdminAddress);

  let result = await stakingRewardsProxy.getPendingAdmin();

  console.log("New pending admin has been set to :", result);

}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });