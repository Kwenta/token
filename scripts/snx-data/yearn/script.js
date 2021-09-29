// const fs = require("fs");
const { ethers } = require("hardhat");

const SNX_ADDRESS = "0xc011a73ee8576fb46f5e1c5751ca3b9fe0af2a6f";
const SNX_YEARN_VAULT = "0xF29AE508698bDeF169B89834F76704C3B205aedf";

const SNX = require("../SNX.json");

async function getYearnData(minBlock, maxBlock, provider) {
  const snx = new ethers.Contract(SNX_ADDRESS, SNX.abi, provider);
  const filterTo = snx.filters.Transfer(null, SNX_YEARN_VAULT);
  const filterFrom = snx.filters.Transfer(SNX_YEARN_VAULT);
  const transfersIn = await getSNXTransfers(snx, minBlock, maxBlock, filterTo);
  console.log("[new bridge] transfers in count", transfersIn.length);

  const transfersOut = await getSNXTransfers(
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
      throw new Error(
        `a: unexepected yearn transfer error from address ${address}`
      );
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

async function getSNXTransfers(snx, fromBlock, toBlock, filter) {
  let transferEvents = await snx.queryFilter(filter, fromBlock, toBlock);
  let transfers = [];

  for (let i = 0; i < transferEvents.length; ++i) {
    let data = {
      value: transferEvents[i].args.value,
      from: transferEvents[i].args.from,
      to: transferEvents[i].args.to,
    };
    transfers.push(data);
  }

  return transfers;
}

module.exports = {
  getYearnData,
};

// async function main() {
// 	const data = await getYearnData(0, 'latest');
// 	fs.writeFileSync('scripts/snx-data/yearn/yearn_snapshot.json', JSON.stringify(data));
// }

// main()
// 	.then(() => process.exit(0))
// 	.catch(error => {
// 		console.error(error);
// 		process.exit(1);
// 	});
