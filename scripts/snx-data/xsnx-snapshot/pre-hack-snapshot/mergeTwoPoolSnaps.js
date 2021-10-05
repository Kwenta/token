const fs = require("fs");
const { ethers } = require("hardhat");
const { zeroBN } = require("../utils");

async function mergeTwoPoolSnapshots(xsnxSnapshot, xsnxAavePool) {
  // merge the two snapshots
  let finalSnapshot = {};
  for (let [address, amount] of Object.entries(xsnxSnapshot)) {
    finalSnapshot[address] = new ethers.BigNumber.from(amount);
  }
  for (let [address, amount] of Object.entries(xsnxAavePool)) {
    if (finalSnapshot[address]) {
      finalSnapshot[address] = finalSnapshot[address].add(amount);
    } else {
      finalSnapshot[address] = amount;
    }
  }

  let totalValue = zeroBN;
  let winnersCount = 0;
  for (let [address, amount] of Object.entries(finalSnapshot)) {
    if (amount == 0) {
      delete finalSnapshot[address];
    } else {
      totalValue = totalValue.add(amount);
      winnersCount++;
      finalSnapshot[address] = finalSnapshot[address].toString();
    }
  }
  fs.writeFileSync(
    "scripts/snx-data/xsnx-snapshot/pre-hack-snapshot/snapshotPoolStakers.json",
    JSON.stringify(finalSnapshot)
  );
  return finalSnapshot;
}

module.exports = { mergeTwoPoolSnapshots };
