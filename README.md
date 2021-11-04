# Kwenta Tokenomics Repo

This is the main repository for the Kwenta token and respective system contracts (staking, distribution, bridge, buyback & burn, etc..).

The following architecture diagram is still in flux, but provides a general overview of the system.

![Kwenta Token System Architecture Diagram](img/architecture-diagram.png)

## Testing

```
npm run test
```
```
npm run test:unit
```
```
npm run test:integration
```

## Deployment

```
npx hardhat run ./scripts/deploy-kwenta.ts
```
