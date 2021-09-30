const { ethers } = require("hardhat");
const SNX = require("../SNX.json");
const { queryFilterHelper } = require("../utils");

const SNX_ADDRESS = "0xc011a73ee8576fb46f5e1c5751ca3b9fe0af2a6f";
const L2_NEW_BRIDGE = "0x5fd79d46eba7f351fe49bff9e87cdea6c821ef9f";
const L2_OLD_BRIDGE = "0x045e507925d2e05D114534D0810a1abD94aca8d6";

async function getL2Snapshot(minBlock, maxBlock, provider) {
  const snx = new ethers.Contract(SNX_ADDRESS, SNX.abi, provider);
  const filterFromNew = snx.filters.Transfer(L2_NEW_BRIDGE);
  const filterFromOld = snx.filters.Transfer(L2_OLD_BRIDGE);
  const filterToNew = snx.filters.Transfer(null, L2_NEW_BRIDGE);
  const filterToOld = snx.filters.Transfer(null, L2_OLD_BRIDGE);

  const transfersInNew = await queryFilterHelper(
    snx,
    minBlock,
    maxBlock,
    filterToNew
  );
  console.log("[new l2 bridge] transfers in count", transfersInNew.length);

  const transfersOutNew = await queryFilterHelper(
    snx,
    minBlock,
    maxBlock,
    filterFromNew
  );
  console.log("[new l2 bridge] transfers out count", transfersOutNew.length);

  const transfersInOld = await queryFilterHelper(
    snx,
    minBlock,
    maxBlock,
    filterToOld
  );
  console.log("[old l2 bridge] transfers in count", transfersInOld.length);

  const transfersOutOld = await queryFilterHelper(
    snx,
    minBlock,
    maxBlock,
    filterFromOld
  );
  console.log("[old l2 bridge] transfers out count", transfersOutOld.length);

  // add and subtract balance for addresses for each transfer
  let totalBalance = {};
  for (let i = 0; i < transfersInNew.length; ++i) {
    let address = transfersInNew[i].from;
    let value = transfersInNew[i].value;
    if (totalBalance[address]) {
      totalBalance[address] = totalBalance[address].add(value);
    } else {
      totalBalance[address] = value;
    }
  }

  for (let i = 0; i < transfersOutNew.length; ++i) {
    let address = transfersOutNew[i].from;
    let value = transfersOutNew[i].value;
    if (totalBalance[address]) {
      totalBalance[address] = totalBalance[address].sub(value);
    } else {
      // throw new Error(
      //   `a: unexepected l2 transfer error from address ${address}`
      // );
    }
  }

  for (let i = 0; i < transfersInOld.length; ++i) {
    let address = transfersInOld[i].from;
    let value = transfersInOld[i].value;
    if (totalBalance[address]) {
      totalBalance[address] = totalBalance[address].add(value);
    } else {
      totalBalance[address] = value;
    }
  }

  for (let i = 0; i < transfersOutOld.length; ++i) {
    let address = transfersOutOld[i].from;
    let value = transfersOutOld[i].value;
    if (totalBalance[address]) {
      totalBalance[address] = totalBalance[address].sub(value);
    } else {
      // throw new Error(
      //   `b: unexepected l2 transfer error from address ${address}`
      // );
    }
  }

  let balanceSum = new ethers.BigNumber.from(0);
  for (const address of Object.keys(totalBalance)) {
    // remove 0 balance addresses and address 0x0 which is < 0 balance
    if (totalBalance[address] <= 0) {
      delete totalBalance[address];
      continue;
    }
    balanceSum = balanceSum.add(totalBalance[address]);
    totalBalance[address] = totalBalance[address].toString();
  }
  console.log(
    `from blocks ${minBlock} to ${maxBlock} - calculated L2 balance: ${ethers.utils.formatEther(
      balanceSum
    )}`
  );

  return totalBalance;
}

module.exports = {
  getL2Snapshot,
};

// async function main() {
//   const provider = new ethers.providers.JsonRpcProvider(
//     {
//       url: process.env.ARCHIVE_NODE_URL,
//       user: process.env.ARCHIVE_NODE_USER,
//       password: process.env.ARCHIVE_NODE_PASS,
//       timeout: 300000,
//     },
//     1
//   );
//   await getL2Snapshot(12956238, 13328346, provider);
// }

// main()
//   .then(() => process.exit(0))
//   .catch((error) => {
//     console.error(error);
//     process.exit(1);
//   });

// sample results for comparison with other scripts: TODO - remove
// [new l2 bridge] transfers in count 1638
// [new l2 bridge] transfers out count 307
// [old l2 bridge] transfers in count 0
// [old l2 bridge] transfers out count 0
// from blocks 12956238 to 13328346 - calculated L2 balance: 7298560.987011728880954949
