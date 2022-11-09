import { task } from "hardhat/config";
import "@nomiclabs/hardhat-waffle";
import "hardhat-typechain";
import "@nomiclabs/hardhat-truffle5";
import "hardhat-gas-reporter";
import "hardhat-contract-sizer";
import "@openzeppelin/hardhat-upgrades";
import "solidity-coverage";
import dotenv from "dotenv";
import "hardhat-exposed";
import "hardhat-interact";
import "hardhat-deploy";
import "hardhat-interface-generator";
import "@nomiclabs/hardhat-etherscan";

dotenv.config();

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

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
export default {
  solidity: {
    compilers: [
      {
        version: "0.8.2",
        settings: {
          optimizer: {
            enabled: true,
            runs: 1000,
          },
        },
      },
      {
        version: '0.5.16',
        settings: {
          optimizer: {
            enabled: true,
            runs: 1000,
          },
        },
      },
      {
        version: "0.8.7",
        settings: {
          optimizer: {
            enabled: true,
            runs: 1000,
          },
        },
      },
    ],
    settings: {
      outputSelection: { // Smock settings
        "*": {
            "*": ["storageLayout"],
        },
      },
    },
  },
  networks: {
    hardhat: {
      allowUnlimitedContractSize: true
    },
    "optimistic-kovan": {
      url: `https://opt-kovan.g.alchemy.com/v2/${process.env.ALCHEMY_API_KEY}`,
      accounts: process.env.DEPLOYER_PRIVATE_KEY ? [process.env.DEPLOYER_PRIVATE_KEY] : undefined,
    },
    "optimistic-goerli": {
      url: `https://opt-goerli.g.alchemy.com/v2/${process.env.ALCHEMY_API_KEY}`,
      accounts: process.env.DEPLOYER_PRIVATE_KEY ? [process.env.DEPLOYER_PRIVATE_KEY] : undefined,
    },
    "optimistic-mainnet": {
      url: `https://opt-mainnet.g.alchemy.com/v2/${process.env.ALCHEMY_API_KEY}`,
      accounts: process.env.DEPLOYER_PRIVATE_KEY ? [process.env.DEPLOYER_PRIVATE_KEY] : undefined,
    },
  },
  etherscan: {
    apiKey: process.env.ETHERSCAN_API_KEY,
    customChains: [
      {
        network: "optimistic-goerli",
        chainId: 420,
        urls: {
          apiURL: "https://api-goerli-optimism.etherscan.io/api",
          browserURL: "https://goerli-optimism.etherscan.io/"
        }
      }
    ]
  },
  exposed: {
    exclude: ["**/libraries/SafeDecimalMath.sol"]
  },
};
