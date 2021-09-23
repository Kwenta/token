const { getHoldersSnapshot } = require("./getHoldersSnapshot");
const { getStakersSnapshot } = require("./getStakersSnapshot");
const { getFinalSnapshot } = require("./getFinalSnapshot");

async function getAugustHackSnapshot(provider) {
  let holdersSnapshot = await getHoldersSnapshot(provider);
  let stakersSnapshot = await getStakersSnapshot(provider);
  return await getFinalSnapshot(holdersSnapshot, stakersSnapshot);
}

module.exports = { getAugustHackSnapshot };
