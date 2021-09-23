"use strict";

const { gray, green, yellow, bgCyan, black } = require("chalk");
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

const getXSNXSnapshot = async (xsnxScore, blockNumber) => {
  const snapshot = await getSnapshot(blockNumber);

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

const getYearnSnapshot = async (yearnScore, minBlockNumber, maxBlockNumber) => {
  const snapshot = await getYearnData(minBlockNumber, maxBlockNumber);

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

module.exports = {
  getTargetAddress,
  setTargetAddress,
  feesClaimed,
  issued,
  getXSNXSnapshot,
  getYearnSnapshot,
};
