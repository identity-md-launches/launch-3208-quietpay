# QuietPay (QUIETPAY)

A fixed-supply ERC-20 token for an IdentityMD custom-token launch on Ethereum (chain id 1).

| Parameter        | Value                                                        |
|------------------|--------------------------------------------------------------|
| Contract name    | `QuietPayToken` (`src/QuietPayToken.sol`)                     |
| Token name       | `QuietPay`                                                   |
| Token symbol     | `QUIETPAY`                                                   |
| Decimals         | 18                                                           |
| Total supply     | 1,000,000,000 QUIETPAY = `1000000000000000000000000000` minor units |
| Minted to        | `msg.sender` of the constructor, once (the launch factory)   |
| Constructor args | none                                                         |
| Owner / admin    | none                                                         |

## What the contract does

`QuietPayToken` inherits OpenZeppelin v5 `ERC20` and adds nothing but constants and a
constructor. The constructor mints the whole supply to the address that creates the
contract and that is the only mint that can ever happen: there is no `mint`, no `owner`,
no minter role, no pause, no blocklist, no fee on transfer, no burn hook and no upgrade
path. Ordinary `transfer`, `approve` and `transferFrom` behave exactly as the ERC-20
standard says, with OpenZeppelin's custom errors on failure.

The contract has no `receive` or `fallback`, so it refuses ether. Its runtime code contains
no `DELEGATECALL`, `CALLCODE` or `SELFDESTRUCT`, which a test checks by scanning the
reachable opcodes the same way the launch floor does.

## Assumptions and design decisions

- **Deployer receives the supply.** The brief asks for the supply to be minted once to the
  deployer. On the launch the deployer is IMD's `ProjectFactory`, which pays the supply out
  (10% to the launch's MerkleDistributor, 80% to the pool, 10% to the requester's address
  from the launch economics). Nothing is reserved for, or sent to, any other address in the
  constructor, and no address is baked in.
- **Nothing is exempt because nothing is taxed.** The launch flows (factory to distributor,
  distributor to claimant, factory to PoolManager, swaps either way) move exactly the amount
  requested, so the token takes none of the optional `$factory`, `$poolManager` or
  `$launchNumber` constructor arguments.
- **No privileged functions.** The custom-token floor refuses any privileged call that
  moves or freezes a holder's balance, and any way for the supply to grow. The simplest way
  to satisfy that is to have no privileged functions, so the contract does not inherit
  `Ownable` at all. This is deliberate, not an omission: there is nothing an owner would
  need to do.
- **Constants, not arguments.** Name, symbol, decimals and supply are compile-time
  constants (`TOKEN_NAME`, `TOKEN_SYMBOL`, `DECIMALS`, `TOTAL_SUPPLY`), so the manifest's
  `constructorArgs` is empty and `token.totalSupply` is the value in the table above.
- **Numbers the brief left open.** None. Name, symbol, decimals and supply were all given.
- **Dependencies are vendored as ordinary files**, with no git submodules, so an offline
  build finds them:
  - `lib/forge-std` — foundry-rs/forge-std v1.9.7 (`77041d2ce690e692d6e03cc812b57d1ddaa4d505`),
    `src/` only.
  - `lib/openzeppelin-contracts` — OpenZeppelin/openzeppelin-contracts v5.2.0
    (`acd4ff74de833399287ed6b31b4debf6b2b35527`), only the files `ERC20` needs:
    `ERC20.sol`, `IERC20.sol`, `IERC20Metadata.sol`, `Context.sol`, `draft-IERC6093.sol`,
    plus the MIT licence.

## Deployment parameters

The launch (`ProjectFactory.launchCustom`) deploys the token from its built bytecode. The
values the manifest step will need, all of which come from this repository or from the
launch's own terms:

- `token.contract`: `QuietPayToken`
- `token.name`: `QuietPay`
- `token.symbol`: `QUIETPAY`
- `token.decimals`: `18`
- `token.constructorArgs`: `[]`
- `token.totalSupply`: `1000000000000000000000000000`
- `contracts`: `[]` (no application contracts)
- Pool and economics are the launch's: pair IMD
  (`0xd34a99bc0f67ae1bbd63c660e6d0b0dd03e263b7`), fee `12500`, tick spacing `60`,
  `poolBps` 8000, `initialMarketCapWei` 4,500 IMD, remainder to
  `0x612a9bb008e16ef2d24f41dae9fc661831d93367`. These are copied by the manifest step, not
  by anything in this repository, and no `launch.json` is written here.

Build settings that affect the deployed bytecode are pinned in `foundry.toml`:
`solc = "0.8.26"`, `evm_version = "cancun"`, optimizer on with 200 runs, `via_ir = false`,
`bytecode_hash = "none"` (so the deployed bytes are reproducible without a metadata hash).
`ffi` is off and there are no filesystem permissions.

### Manual deployment (outside the launch)

`script/DeployQuietPayToken.s.sol` is a reviewable script. `deploy()` creates the token and
is what the tests call; `run()` wraps it in a broadcast for a manual deployment, with the
broadcasting account as deployer and therefore as the holder of the whole supply. It reads
no environment variables because the token has no configuration. This repository does not
hold keys and no transaction is sent as part of this work.

## After launch

Nothing to set. The token has no owner-settable values, no setters and no post-deployment
initialization. Once deployed it is final.

## Operational responsibilities

- **The holder of the supply is whoever deployed.** On the launch that is the factory, which
  distributes it. For a manual deployment the deploying account must distribute the supply
  itself; the contract gives it no help and cannot claw anything back.
- **No recovery mechanism.** Tokens sent to a wrong address, including to the token contract
  itself, cannot be recovered by anyone. This is the price of having no privileged hand.
- **No upgrade path.** A bug could only be addressed by deploying a new token; there is no
  proxy and no migration hook.
- **Explorer verification** (for example `forge verify-contract`) with the exact build
  settings above belongs to the network's deployer after the launch; it is an open item for
  that step, not something this repository performs.
- **Approvals are the holder's responsibility.** `approve` overwrites rather than adds, and
  an allowance of `type(uint256).max` is never decremented, both as in OpenZeppelin v5.

## Trust assumptions

There are none beyond the standard ones for an OpenZeppelin v5 ERC-20: the compiler
(solc 0.8.26) and the vendored library at the pinned commit. No address, role or
off-chain service is trusted by the contract.

## Security notes

Written against the eth-security checklist supplied with the task:

- No reentrancy surface: the contract makes no external calls and holds no ether.
- No arithmetic outside the library; Solidity 0.8 checked math throughout.
- No `selfdestruct`, no `delegatecall`, no assembly in the contract itself.
- `transferFrom` moves tokens only with an allowance granted by the `from` address
  (Slither's arbitrary-send-erc20 does not apply).
- No initializer, no upgrade path, no storage pointers, no shifts, no `abi.encodePacked`.
- No library the token calls is public or external, so the bytecode has no link
  placeholders.

Tests passing is not a security audit. Work that will hold other people's funds should get
an independent adversarial review before release; this token holds no funds itself.

## Building and testing

```
forge build
forge fmt --check
forge test
```

The tests use no environment variables, no `ffi`, no filesystem access and no fixed
ordering, so they pass in any order and in parallel. The verifier runs fuzz tests with a
fixed seed; the suite was run locally with the same seed:

```
FOUNDRY_FUZZ_SEED=0x1272b5807ee75ec2353d0e8db5fa6b27b4a5695e944aabc3c05f5bc4cc0606c8 forge test
```

What the tests cover (`test/QuietPayToken.t.sol`, `test/DeployQuietPayToken.t.sol`):

- Metadata (name, symbol, decimals) and the exact supply constant.
- The whole supply is minted to the deployer, with a single `Transfer` from the zero
  address, and goes to whichever address deploys (fuzzed).
- `transfer` success, events, zero amounts, self-transfers; failure on insufficient
  balance and on the zero address (unit and fuzz).
- `approve` / `transferFrom` success, allowance decrement, unlimited allowance; failure
  on insufficient allowance, missing allowance and allowance above balance (unit and fuzz).
- The launch flows arrive whole: 10% to a distributor and on to a claimant, 80% to a
  pool address, 10% to the requester's address, with the supply conserved.
- No common admin call (mint, setOwner, upgradeTo, pause, blacklist, freeze, burnFrom,
  seize, …) succeeds from a stranger or from the deployer; the supply never grows and a
  holder keeps and can move their balance.
- No `owner()`, ether is refused, and reachable runtime code has no `DELEGATECALL`,
  `CALLCODE` or `SELFDESTRUCT` and fits under the EIP-170 size limit.
- The deploy script's `deploy()` function, called directly.
