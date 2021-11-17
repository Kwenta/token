const hardhat = require('hardhat');

async function main() {

  owner = "0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266";
  rewardsDistribution = "0x70997970c51812dc3a010c7d01b50e0d17dc79c8";
  rewardsTokenAddress = "0x3c44cdddb6a900fa2b585dd299e03d12fa4293bc";
  stakingTokenAddress = "0x90f79bf6eb2c4f870365e785982e1f101e93b906";
  rewardsEscrowAddress = "0x15d34aaf54267db7d7c367839aaf71a00a2c6a65";

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

  DecayRateLib = await hre.ethers.getContractFactory("DecayRateLib", {
      libraries: {
            ExponentLib: exponentLib.address
      }
    });

  StakingRewards = await hre.ethers.getContractFactory("StakingRewards", {
      libraries: {FixidityLib: fixidityLib.address,
            DecayRateLib: decayRateLib.address
      }
    });

  // Deploy the UUPS Proxy using hardhat upgrades from OpenZeppelin

  stakingRewardsProxy = await hre.upgrades.deployProxy(StakingRewards,
        [
        owner, 
        rewardsDistribution, 
        rewardsTokenAddress, 
        stakingTokenAddress, 
        rewardsEscrowAddress
        ],
        {
          kind: "uups",
          unsafeAllow: ["external-library-linking"]
        });
  await stakingRewardsProxy.deployed();

  // Get the address from the implementation

  implementation = await hre.upgrades.erc1967.getImplementationAddress(stakingRewardsProxy.address);

  console.log("Staking Rewards Proxy deployed to:", stakingRewardsProxy.address);
  console.log("Staking Rewards Logic deployed to:", implementation);

  /*StakingRewards_NEW = await hre.ethers.getContractFactory("StakingRewardsV2", {
    libraries: {FixidityLib: fixidityLib.address,
          ExponentLib: exponentLib.address,
    }
  });

  // Upgrade the UUPS Proxy using hardhat upgrades from OpenZeppelin

  upgradedImplementation = await hre.upgrades.upgradeProxy(stakingRewardsProxy.address, 
          StakingRewards_NEW,
        {
        unsafeAllow: ["external-library-linking"]
        }
          );

  implementation = await hre.upgrades.erc1967.getImplementationAddress(upgradedImplementation.address);

  console.log("Staking Rewards Proxy deployed to:", upgradedImplementation.address);
  console.log("Staking Rewards Logic deployed to:", implementation);*/

}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });