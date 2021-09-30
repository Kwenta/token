const { ethers } = require("hardhat");
const fs = require("fs");

const { getStakingRewardsStakers } = require("./getStakingRewardsStakers");
const XSNX = require("../xSNX.json");
const { POST_HACK_START, AUGUST_SNAP } = require("../blocks");
const { queryFilterHelper } = require("../../utils");

/**
 * Get snapshot of all addresses staking xSNX in xSNXa-WETH Balancer Pool
 * Need to run with mainnet forking enabled
 */
async function getStakersSnapshot(blockNumber, provider) {
  console.log("---Get Stakers Snapshot---");
  const xsnx = new ethers.Contract(
    "0x1cf0f3aabe4d12106b27ab44df5473974279c524",
    XSNX.abi,
    provider
  );
  const bpt = new ethers.Contract(
    "0xEA39581977325C0833694D51656316Ef8A926a62",
    XSNX.abi,
    provider
  );
  const balancerVault = "0xBA12222222228d8Ba445958a75a0704d566BF2C8"; // balancer vault which holds xsnx tokens
  const stakingRewardsContract = "0x9AA731A7302117A16e008754A8254fEDE2C35f8D"; // staking rewards address
  const transfers = await queryFilterHelper(
    bpt,
    POST_HACK_START + 1,
    AUGUST_SNAP - 1,
    bpt.filters.Transfer()
  );
  console.log("total bpt transfers:", transfers.length);

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
  console.log(
    "balance of staking rewards contract:",
    ethers.utils.formatEther(totalBalance[stakingRewardsContract])
  );

  delete totalBalance[balancerVault]; // remove balancer vault from snapshot
  delete totalBalance[stakingRewardsContract]; // remove staking rewards contract from snapshot

  let stakingRewardsStakers = await getStakingRewardsStakers(
    blockNumber,
    provider
  );

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
  let xsnxInPool = await xsnx.balanceOf(balancerVault);
  let xsnxPer1BPT = xsnxInPool.mul(100000000).div(bptTotalSupply).toNumber(); // mul by 100M for precision

  console.log("total address balances count:", addressCount);

  console.log(
    "sum of all bpt token holders:",
    ethers.utils.formatEther(balanceSum)
  );
  console.log("total bpt supply:", ethers.utils.formatEther(bptTotalSupply));
  console.log("total xsnx in pool:", ethers.utils.formatEther(xsnxInPool));
  console.log("xsnx per 1 bpt:", xsnxPer1BPT / 100000000);

  let totalxSNXBalance = new ethers.BigNumber.from(0);
  // Convert BPT to xSNX balance
  for (let address of Object.keys(totalBalance)) {
    const balance = new ethers.BigNumber.from(totalBalance[address]);
    totalBalance[address] = balance.mul(xsnxPer1BPT).div(100000000).toString();
    totalxSNXBalance = totalxSNXBalance.add(totalBalance[address]);
  }

  console.log(
    "total xSNX balance of snapshot:",
    ethers.utils.formatEther(totalxSNXBalance)
  );
  console.log("total xsnx in pool:", ethers.utils.formatEther(xsnxInPool));

  fs.writeFileSync(
    "scripts/snx-data/xsnx-snapshot/post-hack-snapshot/snapshotPoolStakers.json",
    JSON.stringify(totalBalance)
  );
  return totalBalance;
}

module.exports = { getStakersSnapshot };
