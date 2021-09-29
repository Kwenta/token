// const fs = require("fs");
const { ethers } = require("hardhat");
const SNX = require("../SNX.json");

const SNX_ADDRESS = "0xc011a73ee8576fb46f5e1c5751ca3b9fe0af2a6f";
const L2_NEW_BRIDGE = "0x5fd79d46eba7f351fe49bff9e87cdea6c821ef9f";
const L2_OLD_BRIDGE = "0x045e507925d2e05D114534D0810a1abD94aca8d6";

async function getL2Snapshot(minBlock, maxBlock, provider) {
  const snx = new ethers.Contract(SNX_ADDRESS, SNX.abi, provider);
  const filterFromNew = snx.filters.Transfer(L2_NEW_BRIDGE);
  const filterFromOld = snx.filters.Transfer(L2_OLD_BRIDGE);
  const filterToNew = snx.filters.Transfer(null, L2_NEW_BRIDGE);
  const filterToOld = snx.filters.Transfer(null, L2_OLD_BRIDGE);

  const transfersInNew = await getSNXTransfers(
    snx,
    minBlock,
    maxBlock,
    filterToNew
  );
  console.log("[new l2 bridge] transfers in count", transfersInNew.length);

  const transfersOutNew = await getSNXTransfers(
    snx,
    minBlock,
    maxBlock,
    filterFromNew
  );
  console.log("[new l2 bridge] transfers out count", transfersOutNew.length);

  const transfersInOld = await getSNXTransfers(
    snx,
    minBlock,
    maxBlock,
    filterToOld
  );
  console.log("[old l2 bridge] transfers in count", transfersInOld.length);

  const transfersOutOld = await getSNXTransfers(
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
      throw new Error(
        `a: unexepected l2 transfer error from address ${address}`
      );
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
      throw new Error(
        `b: unexepected l2 transfer error from address ${address}`
      );
    }
  }

  let balanceSum = new ethers.BigNumber.from(0);
  for (const address of Object.keys(totalBalance)) {
    // remove 0 balance addresses and address 0x0 which is < 0 balance
    if (totalBalance[address].lte(0)) {
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

async function getSNXTransfers(snx, fromBlock, toBlock, filter) {
  let transferEvents = await snx.queryFilter(filter, fromBlock, toBlock);
  let transfers = [];
  for (let i = 0; i < transferEvents.length; i++) {
    const data = {
      value: transferEvents[i].args.value,
      from: transferEvents[i].args.from,
    };
    transfers.push(data);
  }

  return transfers;
}

module.exports = {
  getL2Snapshot,
};

// async function main() {
// 	const data = await getL2Snapshot(0, 'latest');
// 	fs.writeFileSync('scripts/snx-data/L2/L2_snapshot.json', JSON.stringify(data));
// }

// main()
// 	.then(() => process.exit(0))
// 	.catch(error => {
// 		console.error(error);
// 		process.exit(1);
// 	});
