"use strict";

const fs = require("fs");

async function sort() {
  const data = JSON.parse(
    fs.readFileSync("scripts/snx-data/historical_snx.json")
  );

  const accountsValues = [];
  for (const [key, value] of Object.entries(data)) {
    accountsValues.push({ address: key, amount: value });
  }

  accountsValues.sort((a, b) => b.amount - a.amount);

  const sortedData = {};
  for (const key of Object.keys(accountsValues)) {
    sortedData[accountsValues[key]["address"]] = accountsValues[key]["amount"];
  }

  fs.writeFileSync(
    "scripts/snx-data/sorted_historical_snx.json",
    JSON.stringify(sortedData),
    function (err) {
      if (err) return console.log(err);
    }
  );
}

sort()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
