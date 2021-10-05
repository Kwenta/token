const { ethers } = require("hardhat");
const { queryFilterHelper, zeroBN } = require("../xsnx-snapshot/utils");

const SNX_ADDRESS = "0xc011a73ee8576fb46f5e1c5751ca3b9fe0af2a6f";
const SNX_YEARN_VAULT = "0xF29AE508698bDeF169B89834F76704C3B205aedf";

const SNX = require("../SNX.json");

async function getYearnData(minBlock, maxBlock, provider) {
  const snx = new ethers.Contract(SNX_ADDRESS, SNX.abi, provider);
  const filterTo = snx.filters.Transfer(null, SNX_YEARN_VAULT);
  const filterFrom = snx.filters.Transfer(SNX_YEARN_VAULT);
  const transfersIn = await queryFilterHelper(
    snx,
    minBlock,
    maxBlock,
    filterTo
  );
  console.log("[new bridge] transfers in count", transfersIn.length);

  const transfersOut = await queryFilterHelper(
    snx,
    minBlock,
    maxBlock,
    filterFrom
  );
  console.log("[new bridge] transfers out count", transfersOut.length);

  // add and subtract balance for addresses for each transfer
  let totalBalance = [];

  for (let i = 0; i < transfersIn.length; ++i) {
    let address = transfersIn[i].from;
    let value = transfersIn[i].value;
    if (totalBalance[address]) {
      totalBalance[address] = totalBalance[address].add(value);
    } else {
      totalBalance[address] = value;
    }
  }
  for (let i = 0; i < transfersOut.length; ++i) {
    let address = transfersOut[i].from;
    let value = transfersOut[i].value;
    if (totalBalance[address]) {
      totalBalance[address] = totalBalance[address].sub(value);
    } else {
      // throw new Error(
      //   `unexepected yearn transfer error from address: ${address}`
      // );
    }
  }

  let balanceSum = zeroBN;
  let addressCount = 0;
  for (let address of Object.keys(totalBalance)) {
    // remove 0 balance addresses and address 0x0 which is < 0 balance
    if (totalBalance[address] <= 0) {
      delete totalBalance[address];
      continue;
    }
    balanceSum = balanceSum.add(totalBalance[address]);
    totalBalance[address] = totalBalance[address].toString();
    addressCount++;
  }
  console.log("total addresses in snapshot count:", addressCount);
  console.log(
    "calculated Yearn balance:",
    ethers.utils.formatEther(balanceSum)
  );

  return totalBalance;
}

module.exports = {
  getYearnData,
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
//   return getYearnData(12956238, 13328346, provider);
// }

// main()
//   .then(() => process.exit(0))
//   .catch((error) => {
//     console.error(error);
//     process.exit(1);
//   });

// output results for comparison
// [new bridge] transfers in count 665
// getting data from 12956238 to 13328346
// [new bridge] transfers out count 379
// total addresses in snapshot count: 367
// calculated Yearn balance: 1499828.964047605257473434
