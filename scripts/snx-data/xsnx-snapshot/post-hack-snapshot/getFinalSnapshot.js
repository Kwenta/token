const fs = require("fs");
const { ethers } = require("hardhat");

/**
 * Merge the holders and stakers of xsnx in one final snapshot
 */
async function getFinalSnapshot(xsnxHoldersSnapshot, xsnxStakersSnapshot) {
  console.log("---Get Final Snapshot---");
  // merge the two snapshots
  let finalSnapshot = {};
  for (let [address, amount] of Object.entries(xsnxHoldersSnapshot)) {
    finalSnapshot[address] = new ethers.BigNumber.from(amount);
  }
  for (let [address, amount] of Object.entries(xsnxStakersSnapshot)) {
    if (finalSnapshot[address]) {
      finalSnapshot[address] = finalSnapshot[address].add(amount);
    } else {
      finalSnapshot[address] = amount;
    }
  }

  let totalXSNXTValue = new ethers.BigNumber.from(0);
  let distributionCount = 0;
  for (let [address, amount] of Object.entries(finalSnapshot)) {
    if (amount == 0) {
      delete finalSnapshot[address];
    } else {
      totalXSNXTValue = totalXSNXTValue.add(amount);
      distributionCount++;
      finalSnapshot[address] = finalSnapshot[address].toString();
    }
  }
  console.log("total xsnx to be distributed:", totalXSNXTValue.toString());
  console.log("distribution count:", distributionCount);
  fs.writeFileSync(
    "scripts/snx-data/xsnx-snapshot/post-hack-snapshot/snapshotFinal.json",
    JSON.stringify(finalSnapshot)
  );
  return finalSnapshot;
}

module.exports = { getFinalSnapshot };
