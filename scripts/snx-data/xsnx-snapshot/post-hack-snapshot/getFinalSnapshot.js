const fs = require("fs");
const { ethers } = require("hardhat");
const { zeroBN } = require("../utils");

/**
 * Merge the holders and stakers of xsnx in one final snapshot
 */
async function getFinalSnapshot(xsnxHoldersSnapshot, xsnxStakersSnapshot) {
  console.log("---Get Final Snapshot---");
  const oneEvm = new ethers.BigNumber.from(Math.pow(10, 18).toString());
  // merge the two snapshots
  let finalSnapshot = {};
  for (let [address, amount] of Object.entries(xsnxHoldersSnapshot)) {
    finalSnapshot[address] = zeroBN.add(amount);
  }
  for (let [address, amount] of Object.entries(xsnxStakersSnapshot)) {
    if (finalSnapshot[address]) {
      finalSnapshot[address] = finalSnapshot[address].add(amount);
    } else {
      finalSnapshot[address] = zeroBN.add(amount);
    }
  }

  let totalXSNXTValue = zeroBN;
  let distributionCount = 0;
  for (let [address, amount] of Object.entries(finalSnapshot)) {
    if (amount.lt(new ethers.BigNumber.from(1).mul(oneEvm))) {
      delete finalSnapshot[address];
    } else {
      totalXSNXTValue = totalXSNXTValue.add(amount);
      distributionCount++;
      finalSnapshot[address] = finalSnapshot[address].toString();
    }
  }
  console.log(
    "total xsnx to be distributed:",
    ethers.utils.formatEther(totalXSNXTValue)
  );
  console.log("distribution count:", distributionCount);
  fs.writeFileSync(
    "scripts/snx-data/xsnx-snapshot/post-hack-snapshot/snapshotFinal.json",
    JSON.stringify(finalSnapshot)
  );
  return finalSnapshot;
}

module.exports = { getFinalSnapshot };
