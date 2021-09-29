"use strict";

const fs = require("fs");
const Big = require("big.js");
const snxData = require("synthetix-data");

const { getSnapshot } = require("./xsnx-snapshot/getSnapshot");
const { getYearnData } = require("./yearn/script");
const deployments = require("./deployments.json");

const MAX_RESULTS = 5000;

const getHashFromId = (id) => id.split("-")[0];

const feesClaimed = async (minBlock, maxBlock) => {
  return snxData
    .pageResults({
      api: snxData.graphAPIEndpoints.snx,
      max: MAX_RESULTS,
      query: {
        entity: "feesClaimeds",
        selection: {
          orderBy: "timestamp",
          orderDirection: "desc",
          where: {
            block_gte: minBlock || undefined,
            block_lte: maxBlock || undefined,
          },
        },
        properties: ["id", "account", "timestamp", "rewards"],
      },
    })
    .then((results) =>
      results.map(({ id, account, timestamp, rewards }) => ({
        hash: getHashFromId(id),
        account,
        timestamp: Number(timestamp * 1000),
        rewards: rewards / 1e18,
        type: "feesClaimed",
      }))
    )
    .catch((err) => console.error(err));
};

const getXSNXSnapshot = async (xsnxScore, provider) => {
  const snapshot = await getSnapshot(provider);

  let totalValue = 0;
  for (const [key, value] of Object.entries(snapshot)) {
    snapshot[key] = value / 1e18;
    totalValue += value / 1e18;
  }

  const data = {};
  for (const [key, value] of Object.entries(snapshot)) {
    data[key] = (value / totalValue) * xsnxScore;
  }

  return data;
};

const getYearnSnapshot = async (
  yearnScore,
  minBlockNumber,
  maxBlockNumber,
  provider
) => {
  const snapshot = await getYearnData(minBlockNumber, maxBlockNumber, provider);

  let totalValue = 0;
  for (const [key, value] of Object.entries(snapshot)) {
    snapshot[key] = value / 1e18;
    totalValue += value / 1e18;
  }

  const data = {};
  for (const [key, value] of Object.entries(snapshot)) {
    data[key] = (value / totalValue) * yearnScore;
  }

  return data;
};

const getTargetAddress = (contractName, network) => {
  return deployments[network][contractName];
};

const setTargetAddress = (contractName, network, address) => {
  deployments[network][contractName] = address;
  fs.writeFileSync(
    "scripts/deployments.json",
    JSON.stringify(deployments),
    function (err) {
      if (err) return console.log(err);
    }
  );
};

// NOTE that our archive node fails on filter requests spanning 500K blocks
// so we are recursively getting data we need from it in 300K intervals
async function queryFilterHelper(
  contract,
  fromBlock,
  toBlock,
  filter,
  prevTransfers = [],
  attempt = 0
) {
  const MAX_RETRIES = 3;
  try {
    const NUM_BLOCKS = 300000;
    const tempToBlock =
      fromBlock + NUM_BLOCKS >= toBlock ? toBlock : fromBlock + NUM_BLOCKS;
    let events = await contract.queryFilter(filter, fromBlock, tempToBlock);
    let transfers = [];
    console.log(`getting data from ${fromBlock} to ${tempToBlock}`);
    for (let i = 0; i < events.length; ++i) {
      let data = {
        value: events[i].args.value,
        from: events[i].args.from,
        to: events[i].args.to,
      };
      transfers.push(data);
    }
    const updatedTransfers = [...prevTransfers, ...transfers];
    if (tempToBlock === toBlock) {
      return updatedTransfers;
    }
    return queryFilterHelper(
      contract,
      fromBlock + NUM_BLOCKS,
      toBlock,
      filter,
      updatedTransfers
    );
  } catch (e) {
    if (attempt + 1 > MAX_RETRIES) {
      throw new Error("too many errors in the queryFilter helper");
    }
    return queryFilterHelper(
      contract,
      fromBlock,
      toBlock,
      filter,
      prevTransfers,
      attempt + 1
    );
  }
}

module.exports = {
  getTargetAddress,
  setTargetAddress,
  feesClaimed,
  getXSNXSnapshot,
  getYearnSnapshot,
  queryFilterHelper,
};
