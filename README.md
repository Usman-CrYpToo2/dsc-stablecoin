# DSC: Overcollateralized Stablecoin

[![CI](https://github.com/Usman-CrYpToo2/Stable-Coin/actions/workflows/test.yml/badge.svg)](https://github.com/Usman-CrYpToo2/Stable-Coin/actions/workflows/test.yml)

A decentralized stablecoin pegged to $1, backed by WETH and WBTC, in the style of MakerDAO's DAI. Users lock crypto as collateral and mint DSC against it. If a position becomes undercollateralized, anyone can liquidate it for a bonus.

Built while following the Cyfrin Updraft advanced Foundry course. The design follows the course; the implementation, the bug fixes, and the test suite below are my own.

## How it works

| Rule | Value |
|---|---|
| Collateral | WETH, WBTC, priced with Chainlink feeds |
| Minimum collateral | 200% of the DSC you mint (50% liquidation threshold) |
| Health factor | `(collateral value × 50%) / DSC minted`. Below 1, the position can be liquidated |
| Liquidation bonus | 10% of the debt covered, paid in collateral |
| Stale price guard | Every price read reverts if the feed has not updated in 3 hours, or reports zero or less |

The main flows, all in [`DSCEngine`](src/DSCEngine.sol):

- `depositCollateralAndMintDsc`: lock collateral and mint in one transaction
- `redeemCollateralForDsc`: burn DSC and withdraw collateral in one transaction
- `liquidate`: repay part or all of someone's unhealthy debt and receive their collateral plus 10%

[`DStablecoin`](src/DStablecoin.sol) is the ERC-20 token. Only the engine can mint or burn it.

## Testing

```bash
git clone --recurse-submodules https://github.com/Usman-CrYpToo2/Stable-Coin.git
cd Stable-Coin
forge test
```

- **22 unit tests** ([`test/unit`](test/unit)) covering every flow: deposits, minting up to the limit, burning, redeeming, liquidation with the bonus, stale and invalid prices, and access control.
- **3 invariants** ([`test/invariant`](test/invariant)), fuzzed over 256 runs of 64 random actions each (16,384 calls per invariant). A handler drives random deposits, mints, burns and redemptions from three users, and after every call the tests check that:
  1. the protocol always holds more collateral value than the DSC in circulation,
  2. no user is ever left with a health factor below 1,
  3. the price getters never revert.

## Bugs found while writing the tests

The original version had no real tests. Writing them found these, all now fixed:

| Bug | Impact |
|---|---|
| `DStablecoin.mint` checked that the **minter** already held the amount being minted, a check copied from `burn` | **Minting never worked.** The engine holds no DSC, so every mint reverted. The stablecoin could not be used at all. |
| Test imports used the wrong letter case (`MockV3Aggregator.sol`, `Console.sol`) | Tests only compiled on case-insensitive systems like Windows and macOS. CI on Linux could not build. |
| Oracle prices were cast to `uint256` without checking they were positive | A zero or negative answer from a feed would wrap into an enormous price. `OracleLib` now rejects it. |
| `transferFrom` result unchecked when burning | Safe with this token, but now checked anyway. |
| The mock token used 8 decimals | The engine's price math assumes 18, so the mock did not match real WETH. |

## Known limitations

These are design limits I would raise in an audit. They are documented, not fixed, to keep the design aligned with the course.

- **Positions below 110% collateral cannot be liquidated.** Liquidating the full debt needs the debt's value plus a 10% bonus in collateral, which the user no longer has. The bad debt stays in the system. A test, `test_knownLimitation_cannotLiquidateBelow110Percent`, shows this.
- **Assumes 18-decimal collateral.** The price math treats every token as 18 decimals. Real WBTC has 8, so it would be undervalued by a factor of 10^10. Each token's decimals should be read and normalized.
- **A stale oracle freezes everything.** Once a feed is more than 3 hours old, every action that reads its price reverts, including liquidations, exactly when they may be needed most.
- **No bad debt handling or reserve.** If collateral falls faster than liquidators can act, nothing covers the shortfall.
- **The invariants hold prices constant.** Price movements are covered by the unit tests, not the fuzzer.

## License

MIT, see [LICENSE](LICENSE).
