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
const PROXY_FEE_POOL_START_BLOCK = 6834821;
const XSNX_ADMIN_PROXY = 0x7cd5e2d0056a7a7f09cbb86e540ef4f6dccc97dd;
const YEARN_STAKING_ADDRESS = 0xc9a62e09834cedcff8c136f33d0ae3406aea66bd;
const YEARN_STAKING_START_BLOCK = 12272748;
const YEARN_STAKING_ESTIMATED_YEARS_TOTAL = 0.5;
const L2_TRANSFER_START_BLOCK = 11656238;
const EST_L2_AND_YEARN_REWARDS_APY = 0.15;
const MAX_GET_BLOCK_FAILS = 5;

let l1txCount = 0;
let totalScores = 0;
let accountsScores = {};

async function getBlocksInChunks(
  provider,
  fromBlock,
  storedBlocks,
  attempt = 1
) {
  try {
    const blocks = [...storedBlocks];
    console.log("blocks so far", blocks);
    const toBlock = fromBlock + 400000;

    const filter = {
      address: PROXY_FEE_POOL_ADDRESS,
      fromBlock,
      toBlock,
      topics: [ethers.utils.id("FeePeriodClosed(uint256)")],
    };
    const logs = await provider.getLogs(filter);
    if (logs.length === 0) {
      return blocks;
    }
    for (const key in logs) {
      blocks.push(logs[key].blockNumber);
    }
    fs.writeFileSync(
      "scripts/snx-data/latest_block_set.json",
      JSON.stringify(blocks),
      function (err) {
        if (err) return console.log(err);
      }
    );
    return getBlocksInChunks(provider, toBlock + 1, blocks);
  } catch (e) {
    console.log(`get block failure # ${attempt + 1}: ${e.message}`);
    if (attempt < MAX_GET_BLOCK_FAILS) {
      return getBlocksInChunks(provider, fromBlock, storedBlocks, attempt + 1);
    }
  }
}

async function fetchData(provider, continueFromPrevious) {
  let startingBlock = PROXY_FEE_POOL_START_BLOCK;
  const latestBlockSet = JSON.parse(
    fs.readFileSync("scripts/snx-data/latest_block_set.json")
  );
  if (latestBlockSet && latestBlockSet.length > 0) {
    startingBlock = latestBlockSet[latestBlockSet.length - 1];
  }

  const blocks = await getBlocksInChunks(
    provider,
    startingBlock + 1,
    latestBlockSet
  );
  console.log("final blocks", blocks);

  let startFromIndex = 0;
  if (continueFromPrevious) {
    const latestData = JSON.parse(
      fs.readFileSync("scripts/snx-data/latest_week.json")
    );
    const blockIndex =
      latestData && latestData.latestBlock
        ? blocks.indexOf(latestData.latestBlock)
        : -1;
    startFromIndex = blockIndex === -1 ? 0 : blockIndex;
    accountsScores =
      latestData && latestData.accountsScores ? latestData.accountsScores : {};
  }

  for (let i = startFromIndex; i < blocks.length; i++) {
    if (!blocks[i + 1]) break;

    const result = await feesClaimed(blocks[i], blocks[i + 1]);

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
    console.log("L1 rewards for week " + (i + 1) + " - ", weeklyRewardL1);
    console.log("L1 stakers for week " + (i + 1) + " - ", result.length);

    if (blocks[i + 1] > L2_TRANSFER_START_BLOCK) {
      const resultL2 = await getL2Snapshot(blocks[i], blocks[i + 1], provider);
      for (const [address, holdings] of Object.entries(resultL2)) {
        const newWeeklyRewardL2 =
          (holdings / 1e18) * (EST_L2_AND_YEARN_REWARDS_APY / 52);
        weeklyRewardL2 += newWeeklyRewardL2;
        dataL2.push({
          account: address.toLowerCase(),
          rewards: newWeeklyRewardL2,
        });
      }
      console.log("L2 rewards for week " + (i + 1) + " - ", weeklyRewardL2);
      console.log(
        "L2 stakers for week " + (i + 1) + " - ",
        Object.keys(resultL2).length
      );
    } else {
      console.log("no L2 rewards for week ", i + 1);
    }

    if (dataL2.length) {
      updateAccountAndTotalsWeekly(
        [...data, ...dataL2],
        weeklyRewardL1 + weeklyRewardL2
      );
    } else {
      updateAccountAndTotalsWeekly(data, weeklyRewardL1);
    }

    fs.writeFileSync(
      "scripts/snx-data/latest_week.json",
      JSON.stringify({
        latestBlock: blocks[i + 1],
        accountsScores,
      }),
      function (err) {
        if (err) return console.log(err);
      }
    );

    console.log("total scores", totalScores);
    console.log("L1 tx count for week " + (i + 1) + " -", result.length);
    console.log(
      "min block",
      blocks[i],
      "max block",
      blocks[i + 1],
      "num blocks in week",
      blocks[i + 1] - blocks[i]
    );
    l1txCount += result.length;
  }

  // xSNX & Yearn snapshot
  for (const [key, value] of Object.entries(accountsScores)) {
    if (key == XSNX_ADMIN_PROXY) {
      let xSNXTotal = 0;
      let snapshot;
      const xSNXData = JSON.parse(
        fs.readFileSync("scripts/snx-data/xsnx_snapshot_final.json")
      );
      if (xSNXData && xSNXData.snapshot && Object.keys(snapshot).length > 0) {
        snapshot = xSNXData.snapshot;
      } else {
        snapshot = await getXSNXSnapshot(value, provider);
        fs.writeFileSync(
          "scripts/snx-data/xsnx_snapshot_final.json",
          JSON.stringify({
            snapshot,
          }),
          function (err) {
            if (err) return console.log(err);
          }
        );
      }
      for (const [snapshotKey, snapshotValue] of Object.entries(snapshot)) {
        if (accountsScores[snapshotKey.toLowerCase()]) {
          console.log(
            "current value pre xSNX",
            accountsScores[snapshotKey.toLowerCase()]
          );
          console.log("add'l xSNX snapshot value", snapshotValue);
          accountsScores[snapshotKey.toLowerCase()] += snapshotValue;
        } else {
          accountsScores[snapshotKey.toLowerCase()] = snapshotValue;
        }
        xSNXTotal += snapshotValue;
      }

      // should be roughly the same value as XSNX_ADMIN_PROXY score
      console.log("xSNXTotal", xSNXTotal);
      console.log("xSNX deleted score", accountsScores[XSNX_ADMIN_PROXY]);

      // don't give any score to the xSNX proxy
      accountsScores[key] = 0;
    } else if (key == YEARN_STAKING_ADDRESS) {
      let yearnTotal = 0;
      const yearnSnapshot = await getYearnSnapshot(
        value,
        YEARN_STAKING_START_BLOCK,
        blocks[blocks.length - 1],
        provider
      );
      for (const [snapshotKey, snapshotValue] of Object.entries(
        yearnSnapshot
      )) {
        console.log(
          "yearn total snx balance value",
          ethers.utils.formatEther(snapshotValue)
        );
        const proRataSnapshotValue =
          Number(ethers.utils.formatEther(snapshotValue)) *
          EST_L2_AND_YEARN_REWARDS_APY *
          YEARN_STAKING_ESTIMATED_YEARS_TOTAL;
        console.log("add'l yearn snapshot value", proRataSnapshotValue);
        if (accountsScores[snapshotKey.toLowerCase()]) {
          console.log(
            "current value pre yearn",
            accountsScores[snapshotKey.toLowerCase()]
          );
          accountsScores[snapshotKey.toLowerCase()] += proRataSnapshotValue;
        } else {
          accountsScores[snapshotKey.toLowerCase()] = proRataSnapshotValue;
        }
        yearnTotal += proRataSnapshotValue;
      }

      // should be roughly the same value as YEARN_STAKING_ADDRESS score
      console.log("yearn indiv total", yearnTotal);
      console.log("yearn deleted score", accountsScores[YEARN_STAKING_ADDRESS]);
      // don't give any score to the main yearn address
      accountsScores[key] = 0;
    }
  }

  return accountsScores;
}

function updateAccountAndTotalsWeekly(allUserData, weeklyReward) {
  allUserData.map(({ rewards, account }) => {
    const weeklyPercent = rewards / weeklyReward;

    if (accountsScores[account]) {
      accountsScores[account] += weeklyPercent;
    } else {
      accountsScores[account] = weeklyPercent;
    }

    totalScores += weeklyPercent;
  });
}

async function main() {
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
      timeout: 200000,
    },
    1
  );
  await provider.ready;

  const continueFromPrevious = true;

  const data = await fetchData(provider, continueFromPrevious);

  fs.writeFileSync(
    "scripts/snx-data/historical_snx.json",
    JSON.stringify(data),
    function (err) {
      if (err) return console.log(err);
    }
  );

  console.log("accounts scores length", Object.keys(data).length);
  console.log("tx total count", l1txCount);
  console.log("total scores", totalScores);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
