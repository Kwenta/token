const { getHoldersSnapshot } = require("./getHoldersSnapshot");
const { getStakersSnapshot } = require("./getStakersSnapshot");
const { getFinalSnapshot } = require("./getFinalSnapshot");

async function getAugustHackSnapshot(provider) {
  let holdersSnapshot = await getHoldersSnapshot(provider);
  let stakersSnapshot = await getStakersSnapshot(provider);
  return await getFinalSnapshot(holdersSnapshot, stakersSnapshot);
}

module.exports = { getAugustHackSnapshot };

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
  await getAugustHackSnapshot(provider);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
