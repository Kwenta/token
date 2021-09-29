const { ethers } = require("hardhat");
const XSNX = require("./xSNX.json");
const { PRE_HACK_END } = require("../blocks");

/**
 * Get snapshot of all addresses staking Balancer Pool Token in Staking Rewards contract pre-hack
 * Used in getStakersSnapshot to retrieve the total xSNX value of LP Stakers at pre-hack time
 */
async function getStakingRewardsStakers(provider) {
  console.log("---Get Staking Rewards LP Stakers Snapshot---");
  const bpt = new ethers.Contract(
    "0xe3f9cf7d44488715361581dd8b3a15379953eb4c",
    XSNX.abi,
    provider
  );

  const stakingRewardsContract = "0x1c65b1763eEE90fca83E65F14bB1d63c5280c651";
  let transferEvents = await bpt.queryFilter(
    bpt.filters.Transfer(),
    0,
    PRE_HACK_END
  );
  let transferToStakingRewards = [];
  let transferFromStakingRewards = [];

  // record all transfers to and from pool (all go through balancer pool)
  for (let i = 0; i < transferEvents.length; ++i) {
    let data = {
      value: transferEvents[i].args.value,
      from: transferEvents[i].args.from,
      to: transferEvents[i].args.to,
    };
    if (data.from == stakingRewardsContract) {
      transferFromStakingRewards.push(data);
    }
    if (data.to == stakingRewardsContract) {
      transferToStakingRewards.push(data);
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

  let totalAllocated = new ethers.BigNumber.from(0);
  let addressCount = 0;
  for (let address of Object.keys(totalBalance)) {
    // remove 0 balance addresses and address 0x0 which is < 0 balance
    if (totalBalance[address].lte(0)) {
      delete totalBalance[address];
      continue;
    }
    totalBalance[address] = totalBalance[address].toString();
    totalAllocated = totalAllocated.add(totalBalance[address]);
    addressCount++;
  }
  console.log(
    "total xsnx pre hack staking rewards stakers count:",
    addressCount
  );
  console.log(
    "total staked in rewards contract:",
    ethers.utils.formatEther(totalAllocated)
  );

  return totalBalance;
}

module.exports = { getStakingRewardsStakers };
