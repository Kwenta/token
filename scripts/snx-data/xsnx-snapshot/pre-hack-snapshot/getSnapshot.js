const { getHoldersSnapshot } = require("./getHoldersSnapshot");
const { getStakersSnapshot } = require("./getStakersSnapshot");
const { getStakersInOtherPool } = require("./getStakersInOtherPool");
const { mergeTwoPoolSnapshots } = require("./mergeTwoPoolSnaps");
const { getFinalSnapshot } = require("./getFinalSnapshot");

async function getPreHackSnapshot(blockNumber, provider) {
  let holdersSnapshot = await getHoldersSnapshot(blockNumber, provider);
  let stakers1Snapshot = await getStakersSnapshot(blockNumber, provider);
  let stakers2Snapshot = await getStakersInOtherPool(blockNumber, provider);
  let stakersSnapshot = await mergeTwoPoolSnapshots(
    stakers1Snapshot,
    stakers2Snapshot
  );
  return await getFinalSnapshot(holdersSnapshot, stakersSnapshot);
}

module.exports = { getPreHackSnapshot };
