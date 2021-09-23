const { getHoldersSnapshot } = require("./getHoldersSnapshot");
const { getStakersSnapshot } = require("./getStakersSnapshot");
const { getFinalSnapshot } = require("./getFinalSnapshot");

async function getPostHackSnapshot(blockNumber, provider) {
  let holdersSnapshot = await getHoldersSnapshot(blockNumber, provider);
  let stakersSnapshot = await getStakersSnapshot(blockNumber, provider);
  return await getFinalSnapshot(holdersSnapshot, stakersSnapshot);
}

module.exports = { getPostHackSnapshot };
