const hardhat = require('hardhat');

async function main() {

  // We get the addresses of the contracts (libraries + staking rewards contract)

  let fixidityLibAddress = "0x0";
  let exponentLibAddress = "0x0";
  let stakingRewardsProxyAddress = "0x0";

  StakingRewards = await hre.ethers.getContractFactory("StakingRewards", {
    libraries: {FixidityLib: fixidityLibAddress,
          ExponentLib: exponentLibAddress
    }
  });

  // Connect the UUPS Proxy 

  stakingRewardsProxy = await StakingRewards.attach(stakingRewardsProxyAddress);

  await stakingRewardsProxy.pendingAdminAccept();

  let result = await stakingRewardsProxy.getAdmin();

  console.log("New admin has been set to :", result);

}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });