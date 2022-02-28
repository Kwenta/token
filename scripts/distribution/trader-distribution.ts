import * as mainnetMain from "./generated/mainnet-main";
import * as optimismMain from "./generated/optimism-main";
import preRegenesisSynthExchanges from "./preregenesis_snapshots/l2-trades-preregenesis.json";
import { ethers } from "ethers";
import { wei } from "@synthetixio/wei";

const L1_SUBGRAPH =
    "https://api.thegraph.com/subgraphs/name/synthetixio-team/mainnet-main";
const L2_SUBGRAPH =
    "https://api.thegraph.com/subgraphs/name/synthetixio-team/optimism-main";

const getSynthExchangers = async (isOptimism?: boolean) => {
    console.log("Gathering synth exchanges...");

    const synthExchanges = await (isOptimism
        ? optimismMain
        : mainnetMain
    ).getSynthExchanges(
        isOptimism ? L2_SUBGRAPH : L1_SUBGRAPH,
        {
            first: 999999999999999,
            orderBy: "timestamp",
            orderDirection: "desc",
            where: {
                timestamp_gt: /*1577836800*/ /*1598918400*/ 1630454400,
                timestamp_lt: 1642716000,
            },
        },
        {
            id: true,
            /*account: true,
            fromSynth: true,
            toSynth: true,*/
            fromAmount: true,
            fromAmountInUSD: true,
            toAmount: true,
            toAmountInUSD: true,
            feesInUSD: true,
            toAddress: true,
            timestamp: true,
            gasPrice: true,
        }
    );
    console.log(synthExchanges.length, "synth exchange events gathered.");

    return synthExchanges;
};

const getPreRegenesisSynthTraders = () => {
    console.log("Gathering pre-regenesis synth exchanges...");

    type SerializedWei = {
        p: number;
        bn: {
            type: string;
            hex: string;
        };
    };

    const reconstructWei = (weiObject: SerializedWei) =>
        wei(
            ethers.BigNumber.from(weiObject.bn.hex).toString(),
            weiObject.p,
            true
        );

    const cleanedPreRegenesisSynthTraders = (
        preRegenesisSynthExchanges as any
    ).map((synthExchange: any) => {
        return {
            id: synthExchange.id,
            /*account: true,
            fromSynth: true,
            toSynth: true,*/
            fromAmount: reconstructWei(synthExchange.fromAmount).toNumber(),
            fromAmountInUSD: reconstructWei(
                synthExchange.fromAmountInUSD
            ).toNumber(),
            toAmount: reconstructWei(synthExchange.toAmount).toNumber(),
            toAmountInUSD: reconstructWei(
                synthExchange.toAmountInUSD
            ).toNumber(),
            feesInUSD: reconstructWei(synthExchange.feesInUSD).toNumber(),
            toAddress: synthExchange.toAddress,
            timestamp: reconstructWei(synthExchange.timestamp).toNumber(),
            gasPrice: reconstructWei(synthExchange.gasPrice).toNumber(),
        };
    });

    console.log(
        cleanedPreRegenesisSynthTraders.length,
        "pre-regenesis synth exchange events gathered."
    );
    return cleanedPreRegenesisSynthTraders;
};

const filterTraders = (synthExchanges: any, minTrades = 1, minVolume = 0) => {
    console.log("Begin aggregating unique traders");
    const addressesMapping = synthExchanges.reduce((acc: any, curr: any) => {
        return {
            ...acc,
            [curr.toAddress]: acc[curr.toAddress]
                ? {
                      trades: acc[curr.toAddress].trades + 1,
                      fromAmountInUSD:
                          acc[curr.toAddress].fromAmountInUSD +
                          Number(curr.fromAmountInUSD),
                  }
                : {
                      trades: 1,
                      fromAmountInUSD: Number(curr.fromAmountInUSD),
                  },
        };
    }, {});

    const filter = (obj: Object, predicate: ([]) => boolean) =>
        Object.fromEntries(Object.entries(obj).filter(predicate));

    console.log("Begin filtering address");
    const filteredAddressesMapping = filter(
        addressesMapping,
        ([address, stats]) =>
            stats.trades >= minTrades && stats.fromAmountInUSD >= minVolume
    );

    console.log(
        Object.keys(addressesMapping).length,
        "before filtering and",
        Object.keys(filteredAddressesMapping).length,
        "traders after filtering."
    );
    return filteredAddressesMapping;
};

const main = async () => {
    console.log("\n--Grabbing L1 Set--");
    const synthExchangesL1 = await getSynthExchangers();
    filterTraders(synthExchangesL1, 5, 1000);
    console.log("\n--Grabbing L2 Set--");
    const synthExchangesL2PreRegenesis = getPreRegenesisSynthTraders();
    const synthExchangesL2 = await getSynthExchangers(true);
    filterTraders(
        [...synthExchangesL2PreRegenesis, ...synthExchangesL2],
        5,
        1000
    );
};

main();
