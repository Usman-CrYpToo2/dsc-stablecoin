# DSC

[![CI](https://github.com/Usman-CrYpToo2/Stable-Coin/actions/workflows/test.yml/badge.svg)](https://github.com/Usman-CrYpToo2/Stable-Coin/actions/workflows/test.yml)

An overcollateralized, USD-pegged stablecoin backed by WETH and WBTC and priced with Chainlink feeds. Users lock collateral to mint DSC; positions that fall below the required collateralization can be liquidated by any caller for a bonus.

> [!WARNING]
> Educational code. Unaudited, with known design limitations documented under [Security](#security).

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
git clone --recurse-submodules https://github.com/Usman-CrYpToo2/Stable-Coin.git
cd Stable-Coin
forge test
```

The suite contains 22 unit tests and 3 invariants. CI runs formatting, build, and tests on every push.

## Security

### Resolved

Identified while building the test suite and fixed in [`0468135`](https://github.com/Usman-CrYpToo2/Stable-Coin/commit/0468135).

| ID | Severity | Title |
|---|---|---|
| C-01 | Critical | `DStablecoin.mint` reverts unless the minter already holds the amount |
| M-01 | Medium | Non-positive oracle answers cast to `uint256` |
| L-01 | Low | `transferFrom` return value unchecked in `_burnDsc` |

**C-01.** `mint` checked `balanceOf(msg.sender) >= amount`, a check carried over from `burn`. The engine holds no DSC, so every call to `mintDsc` reverted and the protocol could not issue its token. *Fix:* removed the balance check.

**M-01.** Prices were cast with `uint256(price)` without validation. A zero answer valued all collateral at zero, making every position liquidatable; a negative answer wrapped to a value near `2^256` and caused arithmetic reverts. *Fix:* `OracleLib` reverts with `Oracle_invalidPrice` when `answer <= 0`.

**L-01.** The burn path ignored the return value of `transferFrom`. Not exploitable with the current token, but inconsistent with the other transfer paths. *Fix:* revert on `false`.

### Known Limitations

Design-level issues, acknowledged and not addressed in this implementation.

| ID | Severity | Title |
|---|---|---|
| H-01 | High | Positions below 110% collateralization cannot be fully liquidated |
| H-02 | High | Price math assumes 18-decimal collateral |
| M-02 | Medium | A stale oracle halts liquidations |
| M-03 | Medium | No mechanism to absorb bad debt |

**H-01.** A full liquidation transfers collateral worth the debt plus 10%. Below 110% collateralization, the position does not hold that much, so `_redeemCollateral` underflows and the liquidation reverts. Demonstrated by `test_knownLimitation_cannotLiquidateBelow110Percent`.

**H-02.** `getUsdValue` and `getTokenAmountFromUsd` treat every token as 18 decimals. WBTC uses 8, so it would be undervalued by a factor of `1e10`. Token decimals should be read and normalized per collateral.

**M-02.** `OracleLib` reverts on stale data, and every pricing path depends on it. During an oracle outage, liquidations are blocked when they may be most needed.

**M-03.** There is no reserve, auction, or socialization mechanism. Losses from positions that cannot be liquidated in time remain unbacked supply.

The invariant suite holds prices constant; price movement is covered by unit tests only.

## Acknowledgements

Protocol design based on the Cyfrin Updraft *Advanced Foundry* course. Implementation, fixes, and the test suite in this repository are original.

## License

MIT, see [`LICENSE`](LICENSE).
