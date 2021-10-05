const queryFilterHelper = async (
  contract,
  fromBlock,
  toBlock,
  filter,
  prevTransfers = [],
  attempt = 0
) => {
  const MAX_RETRIES = 5;
  try {
    const NUM_BLOCKS = 100000;
    const tempToBlock =
      fromBlock + NUM_BLOCKS >= toBlock ? toBlock : fromBlock + NUM_BLOCKS;
    console.log(`getting data from ${fromBlock} to ${tempToBlock}`);
    let events = await contract.queryFilter(filter, fromBlock, tempToBlock);
    let transfers = [];
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
    console.log("transfers.length", transfers.length);
    return queryFilterHelper(
      contract,
      fromBlock + NUM_BLOCKS,
      toBlock,
      filter,
      updatedTransfers
    );
  } catch (e) {
    console.log("failed on attempt", attempt, " with error", e.message);
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
};

const zeroBN = new ethers.BigNumber.from(0);

module.exports = {
  queryFilterHelper,
  zeroBN,
};
