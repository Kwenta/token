const { getHoldersSnapshot } = require("./getHoldersSnapshot");
const { getStakersSnapshot } = require("./getStakersSnapshot");
const { getStakersInOtherPool } = require("./getStakersInOtherPool");
const { mergeTwoPoolSnapshots } = require("./mergeTwoPoolSnaps");
const { getFinalSnapshot } = require("./getFinalSnapshot");

async function getPreHackSnapshot(provider) {
  let holdersSnapshot = await getHoldersSnapshot(provider);
  let stakers1Snapshot = await getStakersSnapshot(provider);
  let stakers2Snapshot = await getStakersInOtherPool(provider);
  let stakersSnapshot = await mergeTwoPoolSnapshots(
    stakers1Snapshot,
    stakers2Snapshot
  );
  return await getFinalSnapshot(holdersSnapshot, stakersSnapshot);
}

module.exports = { getPreHackSnapshot };

async function main() {
  const provider = new ethers.providers.JsonRpcProvider(
    {
      url: process.env.ARCHIVE_NODE_URL,
      user: process.env.ARCHIVE_NODE_USER,
      password: process.env.ARCHIVE_NODE_PASS,
      timeout: 300000,
    },
    1
  );
  await getPreHackSnapshot(provider);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
