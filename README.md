# Linked Avatar Registry Protocol (LARP)

`src/LARPToken.sol:LARPToken` is a fixed-supply ERC-20 for the Ethereum IMD custom-token launch.

| Parameter | Value |
| --- | --- |
| Name | Linked Avatar Registry Protocol |
| Symbol | LARP |
| Decimals | 18 |
| Supply in whole tokens | 1,000,000,000 |
| Supply in smallest units | 1000000000000000000000000000 |
| Constructor arguments | None (`[]`) |
| Initial recipient | Immediate deployer (`msg.sender`), which is the launch factory |
| Solidity compiler | 0.8.26 |
| EVM target | Cancun |

The constructor mints the complete supply once and emits `Transfer(address(0), deployer, supply)`.
There is no callable mint or burn function, owner, pause, blacklist, transfer tax, upgrade mechanism,
or configuration step. The token name does not imply an avatar registry application: this assignment
specifies the token only.

## Interface and behavior

The contract inherits the vendored OpenZeppelin ERC-20 implementation without changing its transfer
or allowance logic. It exposes `name`, `symbol`, `decimals`, `totalSupply`, `balanceOf`, `allowance`,
`transfer`, `approve`, and `transferFrom`, plus the constant getter `INITIAL_SUPPLY`.

- Successful transfers deliver the exact requested amount and emit `Transfer`. Self-transfers and
  zero-value transfers between nonzero addresses are supported.
- Transfers to the zero address, insufficient balances, and insufficient allowances revert with
  ERC-6093 custom errors. A failed operation rolls back all balance and allowance changes.
- `approve` replaces the previous allowance and emits `Approval`. A zero allowance revokes permission.
  The zero address cannot be approved as a spender.
- `transferFrom` requires the caller's allowance, even when the caller is the holder. Finite
  allowances decrease; `type(uint256).max` allowances stay unchanged. OpenZeppelin does not emit
  `Approval` when spending an allowance, so indexers should query `allowance` for current values.
- There are no receiver callbacks or external calls in token operations. The factory, distributor,
  PoolManager, and ordinary holders all use the same transfer rules.
- The contract accepts no ordinary ETH payments and exposes no asset-recovery function. Tokens sent
  to the token's own address or another contract unable to transfer them out cannot be recovered
  through an administrator. Forced ETH is likewise not recoverable.

## Offline build and verification

Foundry 1.8.3 and a locally installed Solidity 0.8.26 compiler are the only build requirements.
Every Solidity dependency is included as an ordinary file under `lib/`; no installation, RPC,
environment variables, filesystem cheatcodes, or FFI is needed by the tests.

```sh
forge build --offline
forge test --offline
forge fmt --check
forge build --offline --sizes
```

For the complete local check, including a fresh source copy, a second fuzz seed and Slither 0.11.6:

```sh
bash scripts/check.sh
```

The suite tests metadata, constructor allocation and events, direct and delegated transfers,
approval replacement/revocation, exact errors, failed-operation atomicity, edge amounts, absence of
administrative functions, and bytecode size/opcodes. Six fuzz tests cover arbitrary deployment
callers, recipients, transfer amounts, and allowances. Two stateful invariants compare balances
and allowances to an independent ledger over randomized action sequences (128 runs, depth 64).

The launch-flow test checks exact 10%/80%/10% distribution, contributor claims, and token movement
in both trading directions using local test actors. It does not initialize a real Uniswap pool or
execute swaps. The network's protected harness performs that integration after manifest assembly.

## Deployment and operational responsibilities

The target launch chain is Ethereum, chain ID 1. Deploy the compiled `LARPToken` creation code
directly, with no constructor arguments, through the IMD custom-token factory. The factory must
be the immediate creator so it receives all tokens; a wrapper that creates the token would receive
the supply instead. The constructor makes no external calls and needs no chain addresses.

For operator preparation, obtain the creation code and ABI with:

```sh
forge inspect src/LARPToken.sol:LARPToken bytecode
forge inspect src/LARPToken.sol:LARPToken abi
```

The network operator supplies this creation code to its reviewed `ProjectFactory.launchCustom`
workflow after acceptance. This repository contains no signing or broadcast script. No deployment
transaction has been sent. The separate manifest step writes `launch.json` with contract identifier
`LARPToken`, no constructor arguments, and the exact supply above.

The factory, not the token constructor, distributes 10% to the network's MerkleDistributor,
80% to pool liquidity, and 10% to the requester's specified remainder recipient. The launch policy
sets the IMD pair, fee, and opening market cap. The manifest/deployment steps must copy those
request parameters exactly; the token does not embed or manage that policy.

Before launch, the network operator must independently review the source, run the protected
factory/pool integration checks with the actual manifest, and verify the deployed source and
metadata. After launch, there are no token settings or privileged maintenance actions. The
factory/distributor handle distribution and claims; holders manage transfers and allowances.
Applications should request bounded approvals and account for the standard ERC-20 allowance
replacement race (a spender can use the old allowance before a replacement is mined).

See `REVIEW.md` for local review results and limits, and `DEPENDENCIES.md` for vendored provenance.
