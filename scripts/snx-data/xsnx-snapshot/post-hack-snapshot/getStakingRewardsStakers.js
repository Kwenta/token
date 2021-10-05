const { ethers } = require("hardhat");
const XSNX = require("./xSNX.json");
const { queryFilterHelper, zeroBN } = require("../utils");
const { BPT_POST_HACK_DEPLOYED_BLOCK, AUGUST_SNAP } = require("../blocks");
/**
 * Get snapshot of all addresses staking Balancer Pool Token in Staking Rewards contract pre-hack
 * Used in getStakersSnapshot to retrieve the total xSNX value of LP Stakers at pre-hack time
 */
async function getStakingRewardsStakers(provider) {
  const bpt = new ethers.Contract(
    "0xEA39581977325C0833694D51656316Ef8A926a62",
    XSNX.abi,
    provider
  );
  const stakingRewardsContract = "0x9AA731A7302117A16e008754A8254fEDE2C35f8D";
  const transfers = await queryFilterHelper(
    bpt,
    BPT_POST_HACK_DEPLOYED_BLOCK,
    AUGUST_SNAP,
    bpt.filters.Transfer()
  );
  let transferToStakingRewards = [];
  let transferFromStakingRewards = [];

  // record all transfers to and from pool (all go through balancer pool)
  for (let i = 0; i < transfers.length; ++i) {
    if (transfers[i].from == stakingRewardsContract) {
      transferFromStakingRewards.push(transfers[i]);
    }
    if (transfers[i].to == stakingRewardsContract) {
      transferToStakingRewards.push(transfers[i]);
    }
  }

  // add and subtract balance for account addresses for each deposit/withdraw
  // skip contract addresses and add them in a list
  let totalBalance = {};

  for (let i = 0; i < transferToStakingRewards.length; ++i) {
    let address = transferToStakingRewards[i].from;
    let value = transferToStakingRewards[i].value;
    if (totalBalance[address]) {
      totalBalance[address] = totalBalance[address].add(value);
    } else {
      totalBalance[address] = value;
    }
  }
  for (let i = 0; i < transferFromStakingRewards.length; ++i) {
    let address = transferFromStakingRewards[i].to;
    let value = transferFromStakingRewards[i].value;
    if (totalBalance[address]) {
      totalBalance[address] = totalBalance[address].sub(value);
    }
  }

  let totalAllocated = zeroBN;
  let addressCount = 0;
  for (let address of Object.keys(totalBalance)) {
    // remove 0 balance addresses and address 0x0 which is < 0 balance
    if (totalBalance[address] <= 0) {
      delete totalBalance[address];
      continue;
    }
    totalBalance[address] = totalBalance[address].toString();
    totalAllocated = totalAllocated.add(totalBalance[address]);
    addressCount++;
  }
  console.log("total staking rewards stakers count:", addressCount);
  console.log(
    "total staked in rewards contract:",
    ethers.utils.formatEther(totalAllocated)
  );

  return totalBalance;
}

module.exports = { getStakingRewardsStakers };
