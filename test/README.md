# LARP token tests

Run `forge build` and `forge test`. The suite uses the repository's vendored dependencies and requires no RPC, environment variables, FFI, or network access.

| File | Coverage |
| --- | --- |
| `LARPToken.t.sol` | Exact metadata, constructor mint and event, immediate deployer ownership, transfer and approval behavior, rejected inputs, and absence of additional minting or administrative entry points. |
| `LARPToken.properties.t.sol` | One-wei and maximum-uint boundaries, address aliasing, approval replacement and revocation, failure rollback followed by retry, transfer round trips, and split versus single delegated transfers. |
| `LARPToken.invariant.t.sol` | Four actors execute 13 actions in random order. Independent balance and allowance ledgers are checked after each handler call. |

Fuzz tests run 1,000 cases each. The invariant campaign runs 256 sequences with a depth of 128, configured in the Solidity file. Unexpected handler reverts fail the campaign; intended failures use exact custom-error expectations.

The handler exercises direct and delegated transfers, full-balance transfers, round trips, arbitrary and boundary approvals, revocation, insufficient balances, insufficient allowances, zero recipients, and zero spenders. Positive delegated transfers have a dedicated action that selects a funded owner, so they do not depend on random approvals coinciding with random balances. A deterministic sequence also exercises every action and checks the positive-transfer and rejected-call counters.

The stateful properties are:

- The sum of all actor balances and `totalSupply()` remain exactly `1_000_000_000 * 10 ** 18`.
- Each actor's balance equals the independent ledger; transfers deliver the exact amount, including self-transfers.
- Every owner/spender allowance matches the ledger. Finite approvals decrease on spending; unlimited approvals persist until replaced or revoked.
- Rejected calls preserve the ledger, including approvals when a delegated transfer fails after its allowance check.
- No balance escapes to the zero address, deployer, handler, or token contract during the campaign. Its transfer destinations are the four actors; the separate token-recipient unit test covers intentional transfers to the token contract.
- After each sequence, all balances can be consolidated, and the entire supply can be transferred out and back.

The existing launch-flow test checks exact ERC-20 movements among test actors. It is not an integration test of a factory, distributor, or Uniswap deployment. These tests exercise the actual `LARPToken` through its public interface without modifying token storage or exposing new mint functions.
