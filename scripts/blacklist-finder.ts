import stakerDistribution from './distribution/staker-distribution.json';
import traderDistribution from './distribution/trader-distribution.json';
import exploitedWallets from './distribution/gnosis_safe_wallets/exploited-wallets.json';
import savedWallets1 from './distribution/gnosis_safe_wallets/saved-wallets-1.json';
import savedWallets2 from './distribution/gnosis_safe_wallets/saved-wallets-2.json';
import { mergeDistributions } from './distribution/utils';
import { NewFormat } from './parse-balance-map';
import { ethers } from 'ethers';

// to run:
// npx hardhat run --network localhost scripts/blacklist-finder.ts

async function main() {
    let distributions: NewFormat[] = mergeDistributions(
        stakerDistribution,
        traderDistribution
    );

    let savedWalletCount = 0;
    let exploitedWalletCount = 0;

    // hash savedWallets for quick look-up
    let savedWalletsMap = new Map<string, string>();
    savedWallets1.forEach(({ data }) => {
        let address = data.multisig.slice(49, 91);

        // will throw if invalid address
        ethers.utils.getAddress(address);

        if (savedWalletsMap.has(address)) {
            console.log("savedWalletsMap REPEAT");
        }

        savedWalletsMap.set(address, address);
        savedWalletCount++;
    });
    savedWallets2.forEach(({ data }) => {
        let address = data.multisig.slice(49, 91);

        // will throw if invalid address
        ethers.utils.getAddress(address);

        if (savedWalletsMap.has(address)) {
            console.log("savedWalletsMap REPEAT");
        }

        savedWalletsMap.set(address, address);
        savedWalletCount++;
    });

    // hash exploitedWallets for quick look-up
    let exploitedWalletsMap = new Map<string, string>();
    exploitedWallets.forEach(({ data }) => {
        let address = data.multisig.slice(49, 91);

        // will throw if invalid address
        ethers.utils.getAddress(address);

        if (exploitedWalletsMap.has(address)) {
            console.log("exploitedWalletsMap REPEAT");
        }

        exploitedWalletsMap.set(address, address);
        exploitedWalletCount++;
    });

    // determine whitelisted and blacklisted multisig addresses
    let whitelisted: string[] = [];
    let blacklisted: string[] = [];
    let unaccounted: string[] = [];

    distributions.forEach(({ address }) => {
        // will throw if invalid address
        ethers.utils.getAddress(address);

        if (exploitedWalletsMap.has(address)) {
            blacklisted.push(address);
        } else if (savedWalletsMap.has(address)) {
            whitelisted.push(address);
        } else {
            unaccounted.push(address);
        }
    });

    // log total number of addresses that are:
    // (1) eligible for KWENTA
    // (2) saved by OE
    // (3) exploited by hack
    console.log('\n');
    console.log('# of distributions: ' + distributions.length);
    console.log('# of savedWallets: ' + savedWalletCount);
    console.log('# of exploitedWallets: ' + exploitedWalletCount);
    console.log('\n');

    // log total number of *eligible for KWENTA* addresses that are:
    // (1) whitelisted
    // (2) blacklisted
    // (3) neither
    console.log('# of distributions that are whitelisted: ' + whitelisted.length);
    console.log('# of distributions that are blacklisted: ' + blacklisted.length);
    console.log('# of distributions that are unaccounted for: ' + unaccounted.length);
    console.log('\n');
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
