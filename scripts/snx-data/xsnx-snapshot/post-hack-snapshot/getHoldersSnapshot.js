const { ethers } = require("hardhat");
const fs = require("fs");
const XSNX = require("../xSNX.json");
const { POST_HACK_START, AUGUST_SNAP } = require("../blocks");

/**
 * Get snapshot of all addresses holding xSNXa
 * Need to run with mainnet forking enabled
 */
async function getHoldersSnapshot(provider) {
  console.log("---Get Holders Snapshot---");
  const xsnx = new ethers.Contract(
    "0x1cf0f3aabe4d12106b27ab44df5473974279c524",
    XSNX.abi,
    provider
  );
  let balancerVault = "0xBA12222222228d8Ba445958a75a0704d566BF2C8"; // balancer vault which holds xsnx tokens
  let transferEvents = await xsnx.queryFilter(
    xsnx.filters.Transfer(),
    POST_HACK_START,
    AUGUST_SNAP - 1
  );
  let transfers = [];

  for (let i = 0; i < transferEvents.length; ++i) {
    const data = {
      value: transferEvents[i].args.value,
      from: transferEvents[i].args.from,
      to: transferEvents[i].args.to,
    };
    transfers.push(data);
  }

  // add and subtract balance for addresses for each transfer
  let totalBalance = {};

  for (let i = 0; i < transfers.length; ++i) {
    let address = transfers[i].to;
    let value = transfers[i].value;
    if (totalBalance[address]) {
      totalBalance[address] = totalBalance[address].add(value);
    } else {
      totalBalance[address] = value;
    }
  }
  for (let i = 0; i < transfers.length; ++i) {
    let address = transfers[i].from;
    let value = transfers[i].value;
    if (totalBalance[address]) {
      totalBalance[address] = totalBalance[address].sub(value);
    } else {
      //totalBalance[address] = value;
    }
  }
  let poolBalance = totalBalance[balancerVault];
  delete totalBalance[balancerVault]; // remove balancer pool from snapshot

  let balanceSum = new ethers.BigNumber.from(0);
  let addressCount = 0;
  for (let address of Object.keys(totalBalance)) {
    // remove 0 balance addresses and address 0x0 which is < 0 balance
    if (totalBalance[address].lte(0)) {
      delete totalBalance[address];
      continue;
    }
    balanceSum = balanceSum.add(totalBalance[address]);
    totalBalance[address] = totalBalance[address].toString();
    addressCount++;
  }
  console.log("total addresses in snapshot count:", addressCount);
  console.log(
    "calculated pool balance:",
    ethers.utils.formatEther(poolBalance)
  );
  console.log(
    "calculated holders balance:",
    ethers.utils.formatEther(balanceSum)
  );
  console.log(
    "pool balance + holders balance:",
    ethers.utils.formatEther(poolBalance) + ethers.utils.formatEther(balanceSum)
  );
  let xsnxTotalSupply = await xsnx.totalSupply();
  let xsnxBalanceInPool = await xsnx.balanceOf(balancerVault);

  console.log("xsnx total supply:", ethers.utils.formatEther(xsnxTotalSupply));
  console.log(
    "xsnx balance in pool:",
    ethers.utils.formatEther(xsnxBalanceInPool)
  );

  fs.writeFileSync(
    "scripts/snx-data/xsnx-snapshot/post-hack-snapshot/snapshotHolders.json",
    JSON.stringify(totalBalance)
  );
  return totalBalance;
}

module.exports = { getHoldersSnapshot };
