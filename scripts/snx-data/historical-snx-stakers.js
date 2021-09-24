"use strict";

const fs = require("fs");
const { ethers } = require("hardhat");
const {
  feesClaimed,
  getXSNXSnapshot,
  getYearnSnapshot,
} = require("./utils.js");
const { getL2Snapshot } = require("./l2/script.js");

const PROXY_FEE_POOL_ADDRESS = "0xb440dd674e1243644791a4adfe3a2abb0a92d309";
const XSNX_ADMIN_PROXY = 0x7cd5e2d0056a7a7f09cbb86e540ef4f6dccc97dd;
const YEARN_STAKING_ADDRESS = 0xc9a62e09834cedcff8c136f33d0ae3406aea66bd;
const EST_L2_REWARDS_APY = 0.2;

let txCount = 0;
let totalScores = 0;
let accountsScores = {};

async function getBlocks(provider) {
  const blocks = [];

  const filter = {
    address: PROXY_FEE_POOL_ADDRESS,
    fromBlock: 6834822,
    topics: [ethers.utils.id("FeePeriodClosed(uint256)")],
  };
  console.log("getting logs");
  const logs = await provider.getLogs(filter);
  console.log("logs", logs);
  for (const key in logs) {
    blocks.push(logs[key].blockNumber);
  }
  return blocks;
}

async function fetchData() {
  if (
    process.env.ARCHIVE_NODE_URL == null ||
    process.env.ARCHIVE_NODE_PASS == null ||
    process.env.ARCHIVE_NODE_USER == null
  ) {
    throw new Error("need credentials to access archive node for script");
  }
  const provider = new ethers.providers.JsonRpcProvider(
    {
      url: process.env.ARCHIVE_NODE_URL,
      user: process.env.ARCHIVE_NODE_USER,
      password: process.env.ARCHIVE_NODE_PASS,
    },
    1
  );
  console.log("provider", provider);
  console.log("connecting to the provider");
  await provider.ready;
  console.log("connected to the provider");

  const blocks = await getBlocks(provider);

  for (const i = 0; i < blocks.length; i++) {
    if (!blocks[i + 1]) break;

    const result = await feesClaimed(blocks[i], blocks[i + 1]);

    const resultL2 = await getL2Snapshot(blocks[i], blocks[i + 1]);

    let data = [],
      dataL2 = [];
    let weeklyRewardL1 = 0,
      weeklyRewardL2 = 0;
    for (const element in result) {
      weeklyRewardL1 += result[element].rewards;
      data.push({
        account: result[element].account.toLowerCase(),
        rewards: result[element].rewards,
      });
    }

    for (const [address, holdings] of Object.entries(resultL2)) {
      weeklyRewardL2 += (holdings / 1e18) * (EST_L2_REWARDS_APY / 52);
      dataL2.push({ account: address.toLowerCase(), rewards: weeklyRewardL2 });
    }
    console.log("L1 rewards for week " + (i + 1) + " - ", weeklyRewardL1);
    console.log("L1 stakers for week " + (i + 1) + " - ", result.length);
    console.log("L2 rewards for week " + (i + 1) + " - ", weeklyRewardL2);
    console.log("L2 stakers for week " + (i + 1) + " - ", resultL2.length);

    if (dataL2.length) {
      updateAccountAndTotalsWeekly(
        [...data, ...dataL2],
        weeklyRewardL1 + weeklyRewardL2
      );
    } else {
      updateAccountAndTotalsWeekly(data, weeklyReward);
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
  for (const [key, value] of Object.entries(accountsScores)) {
    if (key == XSNX_ADMIN_PROXY) {
      console.log("XSNX_ADMIN_PROXY score", value);

      let xSNXTotal = 0;
      //const snapshot = await getXSNXSnapshot(value, blocks[blocks.length - 1], provider);
      const snapshot = await getXSNXSnapshot(value, 13118314, provider);
      for (const [snapshotKey, snapshotValue] of Object.entries(snapshot)) {
        if (accountsScores[snapshotKey.toLowerCase()]) {
          console.log(
            "current value pre xSNX",
            accountsScores[snapshotKey.toLowerCase()]
          );
          console.log("xSNX snapshot value", snapshotValue);
          accountsScores[snapshotKey.toLowerCase()] += snapshotValue;
        } else {
          accountsScores[snapshotKey.toLowerCase()] = snapshotValue;
        }
        xSNXTotal += snapshotValue;
      }

      // should be roughly the same value as XSNX_ADMIN_PROXY score
      console.log("xSNXTotal", xSNXTotal);

      // don't give any score to the xSNX proxy
      accountsScores[key] = 0;
    } else if (key == YEARN_STAKING_ADDRESS) {
      console.log("YEARN_STAKING_ADDRESS score", value);

      let yearnTotal = 0;
      const yearnSnapshot = await getYearnSnapshot(
        value,
        0,
        blocks[blocks.length - 1],
        provider
      );
      for (const [snapshotKey, snapshotValue] of Object.entries(
        yearnSnapshot
      )) {
        if (accountsScores[snapshotKey.toLowerCase()]) {
          console.log(
            "current value pre yearn",
            accountsScores[snapshotKey.toLowerCase()]
          );
          console.log("yearn snapshot value", snapshotValue);
          accountsScores[snapshotKey.toLowerCase()] += snapshotValue;
        } else {
          accountsScores[snapshotKey.toLowerCase()] = snapshotValue;
        }
        yearnTotal += snapshotValue;
      }

      // should be roughly the same value as YEARN_STAKING_ADDRESS score
      console.log("yearnTotal", yearnTotal);

      // don't give any score to the main yearn staking address
      accountsScores[key] = 0;
    }
  }

  return accountsScores;
}

function updateAccountAndTotalsWeekly(allUserData, weeklyReward) {
  Object.keys(allUserData).map((userData) => {
    const weeklyPercent = userData.rewards / weeklyReward;

    if (accountsScores[userData.account]) {
      accountsScores[userData.account] += weeklyPercent;
    } else {
      accountsScores[userData.account] = weeklyPercent;
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
