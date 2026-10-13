# Vendored dependencies

The build uses only the ordinary files in `lib/`. No submodules, compiler binaries, package manager
installation, or network resolution are required. Files were copied without edits from the machine's
provided vendor mirrors. `DEPENDENCIES.sha256` pins every copied source and license by its bytes.

| Dependency | Mirror package version | Included files | License |
| --- | --- | --- | --- |
| OpenZeppelin Contracts | 5.7.0 | `ERC20.sol`, `IERC20.sol`, `IERC20Metadata.sol`, `Context.sol`, `IERC6093.sol` | MIT |
| Forge Standard Library | 1.16.2 | `Test.sol` and its 18 transitive Solidity imports | MIT or Apache-2.0 |

These version labels come from the provided mirrors' package metadata, not a claim that a release
tag was fetched or verified. The OpenZeppelin ERC20 source header says last updated v5.5.0; the
checksums identify the exact snapshot used. Production compilation imports only the five
OpenZeppelin files. Forge Standard Library is test support only.

Upstream projects: https://github.com/OpenZeppelin/openzeppelin-contracts and
https://github.com/foundry-rs/forge-std. The licenses are included in their respective `lib/` folders.

Verify the vendored bytes from the repository root:

```sh
sha256sum --check DEPENDENCIES.sha256
```
