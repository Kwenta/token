const { ethers } = require("hardhat");
const XSNX = require("./xSNX.json");
const merkleClaimSnapshot = require("./pre-hack-snapshot.json");
const { AUGUST_SNAP, XSNX_POST_HACK_DEPLOYED_BLOCK } = require("../blocks");
const { zeroBN } = require("../utils");

/**
 * Get snapshot of all addresses which haven't claimed xSNXa from Merkle Claim contract
 */
async function getUnclaimedXSNXaMerkleClaim(provider) {
  const bpt = new ethers.Contract(
    "0xEA39581977325C0833694D51656316Ef8A926a62",
    XSNX.abi,
    provider
  );
  const xsnx = new ethers.Contract(
    "0x1cf0f3aabe4d12106b27ab44df5473974279c524",
    XSNX.abi,
    provider
  );
  const merkleClaimsContract = "0x1de6Cd47Dfe2dF0d72bff4354d04a79195cABB1C";
  let transferEvents = await xsnx.queryFilter(
    xsnx.filters.Transfer(),
    XSNX_POST_HACK_DEPLOYED_BLOCK,
    AUGUST_SNAP
  );
  let totalBalance = merkleClaimSnapshot;

  // Remove all addresses which have redeemed their xSNXa from xSNXaMerkleClaim Contract
  for (let i = 0; i < transferEvents.length; ++i) {
    const data = {
      value: transferEvents[i].args.value,
      from: transferEvents[i].args.from,
      to: transferEvents[i].args.to,
    };
    if (data.from == merkleClaimsContract) {
      if (totalBalance[data.to]) {
        delete totalBalance[data.to];
      }
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
  console.log(
    "total addresses which haven't claimed from xSNXMerkleClaim:",
    addressCount
  );
  console.log(
    "total address xSNX value:",
    ethers.utils.formatEther(totalAllocated)
  );

  return totalBalance;
}

module.exports = { getUnclaimedXSNXaMerkleClaim };
