# DSC

[![CI](https://github.com/Usman-CrYpToo2/dsc-stablecoin/actions/workflows/test.yml/badge.svg)](https://github.com/Usman-CrYpToo2/dsc-stablecoin/actions/workflows/test.yml)

An overcollateralized, USD-pegged stablecoin backed by WETH and WBTC and priced with Chainlink feeds. Users lock collateral to mint DSC; positions that fall below the required collateralization can be liquidated by any caller for a bonus.

## Parameters

| Parameter | Value |
|---|---|
| Collateral | WETH, WBTC |
| Price source | Chainlink, via [`OracleLib`](src/OracleLib.sol) |
| Liquidation threshold | 50% (200% minimum collateralization) |
| Liquidation bonus | 10% of the debt covered, paid in collateral |
| Oracle timeout | 3 hours |

The health factor of a position is `collateralUsd × LIQUIDATION_THRESHOLD / 100 × 1e18 / debt`. Positions with a health factor below `1e18` are liquidatable.

## Architecture

| Contract | Responsibility |
|---|---|
| [`DSCEngine`](src/DSCEngine.sol) | Collateral accounting, minting, burning, redemption, liquidation, and health factor enforcement |
| [`DStablecoin`](src/DStablecoin.sol) | ERC-20 token; mint and burn restricted to the engine (owner) |
| [`OracleLib`](src/OracleLib.sol) | Wraps `latestRoundData`; reverts on stale or non-positive answers |

Primary entry points on `DSCEngine`:

| Function | Description |
|---|---|
| `depositCollateralAndMintDsc` | Deposits collateral and mints DSC atomically |
| `redeemCollateralForDsc` | Burns DSC and withdraws collateral atomically |
| `liquidate` | Repays part of an unhealthy position's debt in exchange for its collateral plus the bonus |

## Invariants

Verified with stateful fuzzing in [`test/invariant`](test/invariant). With prices held constant, across any sequence of deposits, mints, burns, and redemptions from multiple actors:

| ID | Property |
|---|---|
| I-1 | Total collateral value held by the engine is at least the DSC total supply |
| I-2 | No actor's health factor falls below `1e18` |
| I-3 | Price getters never revert |

Each invariant runs 256 sequences of depth 64 (16,384 calls) with `fail_on_revert` enabled.

## Usage

Requires [Foundry](https://book.getfoundry.sh/getting-started/installation).

```bash
git clone --recurse-submodules https://github.com/Usman-CrYpToo2/dsc-stablecoin.git
cd dsc-stablecoin
forge test
```

The suite contains 22 unit tests and 3 invariants. CI runs formatting, build, and tests on every push.

## Security

A self-review found 7 issues. Three were fixed, including a critical bug that prevented minting entirely; four are acknowledged design limitations. See [`audits/2026-10-self-review.md`](audits/2026-10-self-review.md).

## Acknowledgements

Protocol design based on the Cyfrin Updraft *Advanced Foundry* course. Implementation, fixes, and the test suite in this repository are original.

## Safety

Not audited by a third party. Provided as is, without warranty.

## License

MIT, see [`LICENSE`](LICENSE).
