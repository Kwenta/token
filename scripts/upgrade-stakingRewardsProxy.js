const hardhat = require('hardhat');

async function main() {

  let stakingRewardsProxyAddress = "0x0";

  // We get the contracts to deploy (libraries + staking rewards contract)

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


  StakingRewards_NEW = await hre.ethers.getContractFactory("StakingRewards", {
    libraries: {FixidityLib: fixidityLib.address,
          ExponentLib: exponentLib.address,
    }
  });

  // Upgrade the UUPS Proxy using hardhat upgrades from OpenZeppelin

  upgradedImplementation = await hre.upgrades.upgradeProxy(stakingRewardsProxyAddress, 
          StakingRewards_NEW,
        {
        unsafeAllow: ["external-library-linking"]
        }
          );

  // Get the address from the implementation

  implementation = await hre.upgrades.erc1967.getImplementationAddress(stakingRewardsProxyAddress);

  console.log("Staking Rewards Proxy deployed to:", stakingRewardsProxyAddress);
  console.log("Staking Rewards Logic deployed to:", implementation);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });