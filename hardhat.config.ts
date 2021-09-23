import { task } from "hardhat/config";
import { NetworksUserConfig } from "hardhat/types";

import "@nomiclabs/hardhat-waffle";
import "@nomiclabs/hardhat-ethers";

// This is a sample Hardhat task. To learn how to create your own go to
// https://hardhat.org/guides/create-task.html
task("accounts", "Prints the list of accounts", async (args, hre) => {
  const accounts = await hre.ethers.getSigners();

  for (const account of accounts) {
    console.log(account.address);
  }
});

// You need to export an object to set up your config
// Go to https://hardhat.org/config/ to learn more

const networks: NetworksUserConfig = {};

if (
  process.env.ALCHEMY_API_KEY != null &&
  process.env.KOVAN_PRIVATE_KEY != null
) {
  networks.kovan = {
    url: `https://eth-kovan.alchemyapi.io/v2/${process.env.ALCHEMY_API_KEY}`,
    accounts: [`0x${process.env.KOVAN_PRIVATE_KEY}`],
  };
}

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
export default {
  solidity: {
    compilers: [
      {
        version: "0.5.0",
      },
      {
        version: "0.5.16",
      },
      {
        version: "0.8.7",
      },
    ],
  },
  networks,
};
