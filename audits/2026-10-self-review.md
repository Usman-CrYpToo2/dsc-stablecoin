# Self-Review: DSC

| | |
|---|---|
| Date | October 2026 |
| Commit reviewed | [`ee48339`](https://github.com/Usman-CrYpToo2/dsc-stablecoin/commit/ee48339) |
| Fixes | [`0468135`](https://github.com/Usman-CrYpToo2/dsc-stablecoin/commit/0468135) |
| Scope | [`DSCEngine`](../src/DSCEngine.sol), [`DStablecoin`](../src/DStablecoin.sol), [`OracleLib`](../src/OracleLib.sol) |
| Method | Manual review, unit tests, and stateful invariant fuzzing |

This is a self-review, not an independent audit.

## Summary

| Severity | Count | Fixed | Acknowledged |
|---|---|---|---|
| Critical | 1 | 1 | 0 |
| High | 2 | 0 | 2 |
| Medium | 3 | 1 | 2 |
| Low | 1 | 1 | 0 |

## Resolved

| ID | Severity | Title |
|---|---|---|
| C-01 | Critical | `DStablecoin.mint` reverts unless the minter already holds the amount |
| M-01 | Medium | Non-positive oracle answers cast to `uint256` |
| L-01 | Low | `transferFrom` return value unchecked in `_burnDsc` |

**C-01.** `mint` checked `balanceOf(msg.sender) >= amount`, a check carried over from `burn`. The engine holds no DSC, so every call to `mintDsc` reverted and the protocol could not issue its token. *Fix:* removed the balance check.

**M-01.** Prices were cast with `uint256(price)` without validation. A zero answer valued all collateral at zero, making every position liquidatable; a negative answer wrapped to a value near `2^256` and caused arithmetic reverts. *Fix:* `OracleLib` reverts with `Oracle_invalidPrice` when `answer <= 0`.

**L-01.** The burn path ignored the return value of `transferFrom`. Not exploitable with the current token, but inconsistent with the other transfer paths. *Fix:* revert on `false`.

## Known Limitations

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
