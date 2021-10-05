const { getPostHackSnapshot } = require("./post-hack-snapshot/getSnapshot");
const { getPreHackSnapshot } = require("./pre-hack-snapshot/getSnapshot");
const { zeroBN } = require("../utils");

/**
 * Get snapshot of xsnx holders + LP stakers either pre-hack or post-hack
 */
async function getSnapshot(provider) {
  const preHackSnapshot = await getPreHackSnapshot(provider);
  const postHackSnapshot = await getPostHackSnapshot(provider);

  const snapshot = {};
  for (let [address, amount] of Object.entries(preHackSnapshot)) {
    snapshot[address] = zeroBN.add(amount);
  }

  for (let [address, amount] of Object.entries(postHackSnapshot)) {
    if (snapshot[address]) {
      snapshot[address] = snapshot[address].add(amount);
    } else {
      snapshot[address] = zeroBN.add(amount);
    }
  }

  for (let [address, amount] of Object.entries(snapshot)) {
    snapshot[address] = amount.toString();
  }

  return snapshot;
}

module.exports = {
  getSnapshot,
};
