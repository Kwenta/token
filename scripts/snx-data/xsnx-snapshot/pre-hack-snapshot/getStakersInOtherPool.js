const { ethers } = require("hardhat");
const fs = require("fs");
const XSNX = require("./xSNX.json");
const { PRE_HACK_END } = require("../blocks");

/**
 * Get snapshot of all addresses staking xSNX in AAVE-LINK-xSNX-UNI-YFI Balancer Pool
 * at a block before the xToken hack occurred
 * Need to run with mainnet forking enabled pinned at block 12419912
 */
async function getStakersInOtherPool(provider) {
  console.log("---Get Stakers in other pool Snapshot---");
  const xsnx = new ethers.Contract(
    "0x2367012ab9c3da91290f71590d5ce217721eefe4",
    XSNX.abi,
    provider
  );
  const bpt = new ethers.Contract(
    "0x4939e1557613b6e84b92bf4c5d2db4061bd1a7c7",
    XSNX.abi,
    provider
  );
  let balancerXsnxPool = "0x4939e1557613b6e84b92bf4c5d2db4061bd1a7c7"; // balancer pool address
  let transferEvents = await bpt.queryFilter(
    bpt.filters.Transfer(),
    0,
    PRE_HACK_END
  );
  console.log("total bpt transfers:", transferEvents.length);
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
  delete totalBalance[balancerXsnxPool]; // remove balancer pool from snapshot

  let balanceSum = new ethers.BigNumber.from(0);
  let addressCount = 0;
  for (let address of Object.keys(totalBalance)) {
    // remove 0 balance addresses and address 0x0 which is < 0 balance
    if (totalBalance[address].lte(0)) {
      delete totalBalance[address];
      continue;
    }
    totalBalance[address] = totalBalance[address].toString();
    balanceSum = balanceSum.add(totalBalance[address]);
    addressCount++;
  }
  let bptTotalSupply = await bpt.totalSupply();
  let xsnxInPool = await xsnx.balanceOf(balancerXsnxPool);
  let xsnxPer1BPT = xsnxInPool.mul(100000000).div(bptTotalSupply).toNumber(); // mul by 100M for precision

  console.log("total address balances count:", addressCount);

  console.log("sum of all bpt token holders:", ethers.utils.formatEther(balanceSum));
  console.log("total bpt supply:", ethers.utils.formatEther(bptTotalSupply));
  console.log("total xsnx in pool:", ethers.utils.formatEther(xsnxInPool));
  console.log("xsnx per 1 bpt:", xsnxPer1BPT / 100000000);

  let totalxSNXBalance = new ethers.BigNumber.from(0);
  // Convert BPT to xSNX balance
  for (let address of Object.keys(totalBalance)) {
    let balance = totalBalance[address];
    totalBalance[address] = balance.mul(xsnxPer1BPT).div(100000000).toString();
    totalxSNXBalance = totalxSNXBalance.add(totalBalance[address]);
    console.log(`${address}:`, ethers.utils.formatEther(totalBalance[address]));
    // add to existing snapshot
    totalBalance[address] = totalBalance[address].toString();
  }

  console.log("total xSNX balance of snapshot:", ethers.utils.formatEther(totalxSNXBalance));
  console.log("total xsnx in secondary pool:", ethers.utils.formatEther(xsnxInPool)));
  fs.writeFileSync(
    "scripts/snx-data/xsnx-snapshot/pre-hack-snapshot/snapshotAAVELINKPool.json",
    JSON.stringify(totalBalance)
  );
  return totalBalance;
}

module.exports = { getStakersInOtherPool };
