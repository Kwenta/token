const fs = require("fs");
const { getAugustHackSnapshot } = require("./august-hack-snapshot/getSnapshot");
const { getPostHackSnapshot } = require("./post-hack-snapshot/getSnapshot");
const { getPreHackSnapshot } = require("./pre-hack-snapshot/getSnapshot");

/**
 * Get snapshot of xsnx holders + LP stakers either pre-hack or post-hack
 */
async function getSnapshot(provider) {
  const preHackSnapshot = await getPreHackSnapshot(provider);
  const augustHackSnapshot = await getAugustHackSnapshot(provider);
  const postHackSnapshot = await getPostHackSnapshot(provider);

  const snapshot = {};
  for (let [address, amount] of Object.entries(preHackSnapshot)) {
    snapshot[address] = amount;
  }
  for (let [address, amount] of Object.entries(augustHackSnapshot)) {
    if (snapshot[address]) {
      snapshot[address] = snapshot[address].add(amount);
    } else {
      snapshot[address] = amount;
    }
  }
  for (let [address, amount] of Object.entries(postHackSnapshot)) {
    if (snapshot[address]) {
      snapshot[address] = snapshot[address].add(amount);
    } else {
      snapshot[address] = amount;
    }
  }
  fs.writeFileSync(
    "scripts/snx-data/xsnx-snapshot/snapshot.json",
    JSON.stringify(snapshot)
  );
  return snapshot;
}

module.exports = {
  getSnapshot,
};

//getSnapshot(13118314);
