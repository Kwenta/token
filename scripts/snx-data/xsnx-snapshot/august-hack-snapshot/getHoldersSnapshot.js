const { ethers } = require("hardhat");
const fs = require("fs");

const XSNX = require("./xSNX.json");
const { getUnclaimedXSNXaMerkleClaim } = require("./getxSNXMerkleClaim");
const { AUGUST_SNAP, XSNX_POST_HACK_DEPLOYED_BLOCK } = require("../blocks");
const { queryFilterHelper } = require("../../utils");

/**
 * Get snapshot of all addresses holding xSNX at a block before the xSNX hack occurred
 * Need to run with mainnet forking enabled pinned at block 13118314 (6 blocks before the hack)
 */
async function getHoldersSnapshot(provider) {
  console.log("---Get Holders Snapshot---");
  const xsnx = new ethers.Contract(
    "0x1cf0f3aabe4d12106b27ab44df5473974279c524",
    XSNX.abi,
    provider
  );
  const balancerXsnxVault = "0xBA12222222228d8Ba445958a75a0704d566BF2C8"; // balancer vault address
  const merkleClaimXSNXa = "0x1de6Cd47Dfe2dF0d72bff4354d04a79195cABB1C"; // xSNXa Merkle Claim contract
  const transfers = await queryFilterHelper(
    xsnx,
    XSNX_POST_HACK_DEPLOYED_BLOCK,
    AUGUST_SNAP,
    xsnx.filters.Transfer()
  );

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
  let vaultBalance = totalBalance[balancerXsnxVault];
  delete totalBalance[balancerXsnxVault]; // remove balancer vault from snapshot
  delete totalBalance[merkleClaimXSNXa]; // remove merkle claim xSNXa from snapshot

  let merkleClaimSnapshot = await getUnclaimedXSNXaMerkleClaim(provider);

  // merge the two snapshots
  for (let [address, amount] of Object.entries(merkleClaimSnapshot)) {
    if (totalBalance[address]) {
      totalBalance[address] = totalBalance[address].add(amount);
    } else {
      totalBalance[address] = amount;
    }
  }

  let balanceSum = new ethers.BigNumber.from(0);
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
    ethers.utils.formatEther(vaultBalance)
  );
  console.log(
    "calculated holders balance:",
    ethers.utils.formatEther(balanceSum)
  );
  console.log(
    "pool balance + holders balance:",
    ethers.utils.formatEther(vaultBalance) +
      ethers.utils.formatEther(balanceSum)
  );
  let xsnxTotalSupply = await xsnx.totalSupply();
  let xsnxBalanceInBalancer = await xsnx.balanceOf(balancerXsnxVault);
  console.log("xsnx total supply:", ethers.utils.formatEther(xsnxTotalSupply));
  console.log(
    "xsnx balance in balancer vault:",
    ethers.utils.formatEther(xsnxBalanceInBalancer)
  );

  fs.writeFileSync(
    "scripts/snx-data/xsnx-snapshot/august-hack-snapshot/snapshotHolders.json",
    JSON.stringify(totalBalance)
  );
  return totalBalance;
}

module.exports = { getHoldersSnapshot };
