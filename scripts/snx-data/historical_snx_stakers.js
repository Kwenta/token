"use strict";

const fs = require("fs");
const ethers = require("ethers");
const {
  feesClaimed,
  getXSNXSnapshot,
  getYearnSnapshot,
} = require("./utils.js");
const { getL2Snapshot } = require("./l2/script.js");

const PROXY_FEE_POOL_ADDRESS = "0xb440dd674e1243644791a4adfe3a2abb0a92d309";
const XSNX_ADMIN_PROXY = 0x7cd5e2d0056a7a7f09cbb86e540ef4f6dccc97dd;
const YEARN_STAKING_ADDRESS = 0xc9a62e09834cedcff8c136f33d0ae3406aea66bd;

let txCount = 0;
let totalScores = 0;
let accountsScores = {};

async function getBlocks() {
  const blocks = [];

  const provider = new ethers.providers.JsonRpcProvider({
    url: process.env.ARCHIVE_NODE_URL,
    user: process.env.ARCHIVE_NODE_USER,
    password: process.env.ARCHIVE_NODE_PASS,
  });

  const filter = {
    address: PROXY_FEE_POOL_ADDRESS,
    fromBlock: 0,
    topics: [ethers.utils.id("FeePeriodClosed(uint256)")],
  };
  const logs = await provider.getLogs(filter);
  for (let key in logs) {
    blocks.push(logs[key].blockNumber);
  }
  return blocks;
}

async function fetchData() {
  const blocks = await getBlocks();

  for (let i = 0; i < blocks.length; i++) {
    if (!blocks[i + 1]) break;

    const result = await feesClaimed(blocks[i], blocks[i + 1]);

    const resultL2 = await getL2Snapshot(blocks[i], blocks[i + 1]);

    let data = [],
      dataL2 = [];
    let weeklyReward = 0,
      weeklyRewardL2 = 0;
    for (var element in result) {
      weeklyReward += result[element].rewards;
      data.push({
        account: result[element].account.toLowerCase(),
        rewards: result[element].rewards,
      });
    }

    for (let [key, value] of Object.entries(resultL2)) {
      weeklyRewardL2 += value / 1e18;
      dataL2.push({ account: key.toLowerCase(), rewards: value / 1e18 });
    }

    if (dataL2.length) {
      // distribute 95% of weekly rewards to L1 and 5% to L2
      getWeeklyData(data, 95, weeklyReward);
      getWeeklyData(dataL2, 5, weeklyRewardL2);
    } else {
      getWeeklyData(data, 100, weeklyReward);
    }

    console.log("total scores", totalScores);
    console.log("tx count for week " + (i + 1) + " -", result.length);
    console.log(
      "min block",
      blocks[i],
      "max block",
      blocks[i + 1],
      "diff",
      blocks[i + 1] - blocks[i]
    );
    txCount += result.length;
  }

  // xSNX & Yearn snapshot
  for (let [key, value] of Object.entries(accountsScores)) {
    if (key == XSNX_ADMIN_PROXY) {
      console.log("XSNX_ADMIN_PROXY score", value);

      let finalValue = 0;
      //const snapshot = await getXSNXSnapshot(value, blocks[blocks.length - 1]);
      const snapshot = await getXSNXSnapshot(value, 13118314);
      for (let [snapshotKey, snapshotValue] of Object.entries(snapshot)) {
        if (accountsScores[snapshotKey.toLowerCase()]) {
          accountsScores[snapshotKey.toLowerCase()] += snapshotValue;
        } else {
          accountsScores[snapshotKey.toLowerCase()] = snapshotValue;
        }
        finalValue += snapshotValue;
      }

      // should be roughly the same value as XSNX_ADMIN_PROXY score
      console.log("finalValue", finalValue);

      accountsScores[key] = 0;
    } else if (key == YEARN_STAKING_ADDRESS) {
      console.log("YEARN_STAKING_ADDRESS score", value);

      let finalValueYearn = 0;
      const yearnSnapshot = await getYearnSnapshot(
        value,
        0,
        blocks[blocks.length - 1]
      );
      for (let [snapshotKey, snapshotValue] of Object.entries(yearnSnapshot)) {
        if (accountsScores[snapshotKey.toLowerCase()]) {
          accountsScores[snapshotKey.toLowerCase()] += snapshotValue;
        } else {
          accountsScores[snapshotKey.toLowerCase()] = snapshotValue;
        }
        finalValueYearn += snapshotValue;
      }

      // should be roughly the same value as YEARN_STAKING_ADDRESS score
      console.log("finalValue yearn", finalValueYearn);

      accountsScores[key] = 0;
    }
  }

  return accountsScores;
}

function getWeeklyData(data, percent, weeklyReward) {
  Object.keys(data).map(function (key, index) {
    const weeklyPercent = (data[index].rewards * percent) / weeklyReward;

    if (accountsScores[data[index].account]) {
      accountsScores[data[index].account] += weeklyPercent;
    } else {
      accountsScores[data[index].account] = weeklyPercent;
    }

    totalScores += weeklyPercent;
  });
}

async function main() {
  const data = await fetchData();

  fs.writeFileSync(
    "scripts/snx-data/historical_snx.json",
    JSON.stringify(data),
    function (err) {
      if (err) return console.log(err);
    }
  );

  console.log("accounts scores length", Object.keys(data).length);
  console.log("tx total count", txCount);
  console.log("total scores", totalScores);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
