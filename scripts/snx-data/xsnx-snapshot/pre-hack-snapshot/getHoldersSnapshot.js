const fs = require("fs");
const { ethers } = require("hardhat");
const XSNX = require("./xSNX.json");
const { PRE_HACK_END } = require("./blocks");

/**
 * Get snapshot of all addresses holding xSNX at a block before the xToken hack occurred
 * Need to run with mainnet forking enabled pinned at block 12419912
 */
async function getHoldersSnapshot(provider) {
  console.log("---Get Holders Snapshot---");
  const xsnx = new ethers.contract(
    "0x2367012ab9c3da91290f71590d5ce217721eefe4",
    XSNX.abi,
    provider
  );
  let balancerXsnxPool = "0xE3f9cF7D44488715361581DD8B3a15379953eB4C"; // balancer pool address
  let balancerXsnxPoolSecondary = "0x4939e1557613B6e84b92bf4C5D2db4061bD1A7c7"; // balancer AAVE-LINK-xSNX pool address
  let transferEvents = await xsnx.queryFilter(
    xsnx.filters.Transfer(),
    0,
    PRE_HACK_END
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
  let poolBalance = totalBalance[balancerXsnxPool];
  delete totalBalance[balancerXsnxPool]; // remove balancer pool from snapshot
  delete totalBalance[balancerXsnxPoolSecondary]; // remove balancer pool 2 from snapshot

  let balanceSum = bn(0);
  let addressCount = 0;
  for (let address of Object.keys(totalBalance)) {
    // remove 0 balance addresses and address 0x0 which is < 0 balance
    if (totalBalance[address] <= 0) {
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
  let xsnxBalanceInPool = await xsnx.balanceOf(balancerXsnxPool);

  console.log("xsnx total supply:", ethers.utils.formatEther(xsnxTotalSupply));
  console.log(
    "xsnx balance in pool:",
    ethers.utils.formatEther(xsnxBalanceInPool)
  );

  fs.writeFileSync(
    "scripts/snx-data/xsnx-snapshot/pre-hack-snapshot/snapshotHolders.json",
    JSON.stringify(totalBalance)
  );
  return totalBalance;
}

module.exports = { getHoldersSnapshot };
