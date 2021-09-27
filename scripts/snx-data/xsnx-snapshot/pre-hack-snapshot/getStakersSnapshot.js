const { ethers } = require("hardhat");
const fs = require("fs");

const { getStakingRewardsStakers } = require("./getStakingRewardsStakers");
const XSNX = require("./xSNX.json");
const { PRE_HACK_END } = require("./blocks");

/**
 * Get snapshot of all addresses staking xSNX in xSNX Pool at a block before the xToken hack occurred
 * Need to run with mainnet forking enabled pinned at block 12419912
 */
async function getStakersSnapshot(provider) {
  console.log("---Get Stakers Snapshot---");
  const xsnx = new ethers.Contract(
    "0x2367012ab9c3da91290f71590d5ce217721eefe4",
    XSNX.abi,
    provider
  );
  const bpt = new ethers.Contract(
    "0xe3f9cf7d44488715361581dd8b3a15379953eb4c",
    XSNX.abi,
    provider
  );
  const balancerXsnxPool = "0xE3f9cF7D44488715361581DD8B3a15379953eB4C"; // balancer pool address
  const stakingRewardsContract = "0x1c65b1763eEE90fca83E65F14bB1d63c5280c651"; // staking rewards address
  const transferEvents = await bpt.queryFilter(
    bpt.filters.Transfer(),
    0,
    PRE_HACK_END
  );
  console.log("total bpt transfers:", transferEvents.length);
  const transfers = [];

  for (let i = 0; i < transferEvents.length; ++i) {
    const data = {
      value: transferEvents[i].args.value,
      from: transferEvents[i].args.from,
      to: transferEvents[i].args.to,
    };
    transfers.push(data);
  }

  // add and subtract balance for addresses for each transfer
  const totalBalance = {};

  for (let i = 0; i < transfers.length; ++i) {
    const address = transfers[i].to;
    const value = transfers[i].value;
    if (totalBalance[address]) {
      totalBalance[address] = totalBalance[address].add(value);
    } else {
      totalBalance[address] = value;
    }
  }
  for (let i = 0; i < transfers.length; ++i) {
    const address = transfers[i].from;
    const value = transfers[i].value;
    if (totalBalance[address]) {
      totalBalance[address] = totalBalance[address].sub(value);
    } else {
      //totalBalance[address] = value;
    }
  }
  delete totalBalance[balancerXsnxPool]; // remove balancer pool from snapshot
  console.log(
    "balance of staking rewards contract:",
    totalBalance[stakingRewardsContract].toString()
  );

  delete totalBalance[stakingRewardsContract]; // remove staking rewards contract from snapshot

  let stakingRewardsStakers = await getStakingRewardsStakers(provider);

  // merge two snapshots
  totalBalance = { ...totalBalance, ...stakingRewardsStakers };

  let balanceSum = new ethers.BigNumber.from(0);
  let addressCount = 0;
  for (let address of Object.keys(totalBalance)) {
    // remove 0 balance addresses and address 0x0 which is < 0 balance
    if (totalBalance[address] <= 0) {
      delete totalBalance[address];
      continue;
    }
    totalBalance[address] = totalBalance[address].toString();
    balanceSum = balanceSum.add(totalBalance[address]);
    addressCount++;
  }
  let bptTotalSupply = await bpt.totalSupply();
  let xsnxInPool = await xsnx.balanceOf(balancerXsnxPool);
  let xsnxPer1BPT = xsnxInPool.mul(100000000).div(bptTotalSupply).toNumber();

  console.log("total address balances count:", addressCount);

  console.log(
    "sum of all bpt token holders:",
    ethers.utils.formatEther(balanceSum)
  );
  console.log("total bpt supply:", ethers.utils.formatEther(bptTotalSupply));
  console.log("total xsnx in pool:", ethers.utils.formatEther(xsnxInPool));
  console.log("xsnx per 1 bpt:", xsnxPer1BPT / 100000000);

  let totalxSNXBalance = bn(0);
  // Convert BPT to xSNX balance
  for (let address of Object.keys(totalBalance)) {
    let balance = totalBalance[address];
    totalBalance[address] = balance.mul(xsnxPer1BPT).div(100000000).toString();
    totalxSNXBalance = totalxSNXBalance.add(totalBalance[address]);
  }

  console.log(
    "total xSNX balance of snapshot:",
    ethers.utils.formatEther(totalxSNXBalance)
  );
  console.log(
    "total xsnx in primary pool:",
    ethers.utils.formatEther(xsnxInPool)
  );

  fs.writeFileSync(
    "scripts/snx-data/xsnx-snapshot/pre-hack-snapshot/snapshotPoolStakers.json",
    JSON.stringify(totalBalance)
  );
  return totalBalance;
}

module.exports = { getStakersSnapshot };
