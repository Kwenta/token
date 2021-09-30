const { ethers } = require("hardhat");
const XSNX = require("../xSNX.json");
const { POST_HACK_START, AUGUST_SNAP } = require("../blocks");

/**
 * Get snapshot of all addresses staking xSNX Balancer Pool Token in Staking Rewards contract
 * Used in getStakersSnapshot to retrieve the total xSNX value of LP Stakers
 */
async function getStakingRewardsStakers(provider) {
  console.log("---Get Staking Rewards LP Stakers Snapshot---");
  const bpt = new ethers.Contract(
    "0xEA39581977325C0833694D51656316Ef8A926a62",
    XSNX.abi,
    provider
  );
  const stakingRewardsContract = "0x9AA731A7302117A16e008754A8254fEDE2C35f8D";
  const transferEvents = await bpt.queryFilter(
    bpt.filters.Transfer(),
    POST_HACK_START,
    AUGUST_SNAP - 1
  );
  const transferToStakingRewards = [];
  const transferFromStakingRewards = [];

  // record all transfers to and from staking rewards (all go through contract)
  for (let i = 0; i < transferEvents.length; ++i) {
    const data = {
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
    if (totalBalance[address] <= 0) {
      delete totalBalance[address];
      continue;
    }
    totalBalance[address] = totalBalance[address].toString();
    totalAllocated = totalAllocated.add(totalBalance[address]);
    addressCount++;
  }
  console.log("total post hack staking rewards stakers count:", addressCount);
  console.log(
    "total staked in rewards contract:",
    ethers.utils.formatEther(totalAllocated)
  );

  return totalBalance;
}

module.exports = { getStakingRewardsStakers };
