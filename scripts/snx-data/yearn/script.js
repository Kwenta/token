const { ethers } = require("hardhat");
const { queryFilterHelper } = require("../utils");

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

  let balanceSum = new ethers.BigNumber.from(0);
  let addressCount = 0;
  for (let address of Object.keys(totalBalance)) {
    // remove 0 balance addresses and address 0x0 which is < 0 balance
    if (totalBalance[address].lte(0)) {
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
//   return getYearnData(12572748, 13323457, provider);
// }

// main()
//   .then(() => process.exit(0))
//   .catch((error) => {
//     console.error(error);
//     process.exit(1);
//   });
