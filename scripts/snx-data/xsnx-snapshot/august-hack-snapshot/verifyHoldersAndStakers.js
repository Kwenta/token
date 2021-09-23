const { ethers } = require("hardhat");
const { bn, getNumberNoDecimals } = require("../helpers");
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
  let holdersTotal = bn(0);
  for (let amount of Object.values(holders)) {
    holdersTotal = holdersTotal.add(amount);
  }

  let stakersTotal = bn(0);
  for (let amount of Object.values(stakers)) {
    stakersTotal = stakersTotal.add(amount);
  }

  let totalSupply = await xsnx.methods.totalSupply().call();
  let poolValue = await xsnx.methods.balanceOf(balancerVault).call();

  console.log(
    "holders snapshot total value:",
    getNumberNoDecimals(holdersTotal)
  );
  console.log(
    "stakers snapshot total value:",
    getNumberNoDecimals(stakersTotal)
  );
  console.log("total value of pool:", getNumberNoDecimals(bn(poolValue)));
  console.log("total supply of xsnx:", getNumberNoDecimals(bn(totalSupply)));
}

verify();
