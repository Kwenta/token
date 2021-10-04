const { ethers } = require("hardhat");
const XSNX = require("./xSNX.json");

const provider = new ethers.providers.JsonRpcProvider({
  url: process.env.ARCHIVE_NODE_URL,
  user: process.env.ARCHIVE_NODE_USER,
  password: process.env.ARCHIVE_NODE_PASS,
});

const xsnx = new ethers.Contract(
  "0x1cf0f3aabe4d12106b27ab44df5473974279c524",
  XSNX.abi,
  provider
);
let balancerVault = "0xBA12222222228d8Ba445958a75a0704d566BF2C8"; // balancer pool address

let holders = require("./snapshotHolders.json");
let stakers = require("./snapshotPoolStakers.json");

/**
 * Verify the numbers in both holders and stakers snapshot match
 */
async function verify() {
  let holdersTotal = new ethers.BigNumber.from(0);
  for (let amount of Object.values(holders)) {
    holdersTotal = holdersTotal.add(amount);
  }

  let stakersTotal = new ethers.BigNumber.from(0);
  for (let amount of Object.values(stakers)) {
    stakersTotal = stakersTotal.add(amount);
  }

  let totalSupply = await xsnx.totalSupply();
  let poolValue = await xsnx.balanceOf(balancerVault);

  console.log(
    "holders snapshot total value:",
    ethers.utils.formatEther(holdersTotal)
  );
  console.log(
    "stakers snapshot total value:",
    ethers.utils.formatEther(stakersTotal)
  );
  console.log("total value of pool:", ethers.utils.formatEther(poolValue));
  console.log("total supply of xsnx:", ethers.utils.formatEther(totalSupply));
}

verify();
