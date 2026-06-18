# Pool Wallet Rotation — in-place `""` reset (shrink `wallet.dat`)

> Status: **implemented** as `tools/wallet-maintenance.sh` and **validated on
> regtest** (`tools/regnet-wallet-maintenance.sh`): immature coinbase recovered, tracker
> address `ismine` on the fresh `""`, full balance preserved, tx history and
> `wallet.dat` both shrink. Live `status` and `--dry-run` confirmed on the
> pool. Not yet run live (a real rotation moves funds — operator's call).
>
> This document is the design + the under-the-hood procedure. The tool automates
> all of it; the manual steps below are the reference for what each phase does.

## Why this exists

The pool's **operational wallet is the `""` (default) wallet** on each coin's
daemon:

- **Coinbase IN** lands on a *fixed* eloipool tracker address that is `ismine`
  on `""` (the eloipool unit's `-tracker-address`).
- **Payouts OUT** go through MPOS's `/wallet/` endpoint
  (`$config['wallet']['host'] = '…/wallet/'`, no `wallet_name`) which is the
  `""` wallet.

So `""` carries every coinbase + payout transaction forever, and its
`wallet.dat` only grows — Bitcoin Core has no "compact/vacuum wallet" RPC, and
**coin selection is not FIFO**, so payouts won't drain it in order. The only way
to get a small wallet again is a *fresh* one.

This procedure **resets `""` to a fresh, small `wallet.dat` while keeping the
same keychain** — so the tracker address stays `ismine` on `""` and MPOS keeps
paying from `/wallet/` = `""`. **eloipool and MPOS need zero changes** (no
tracker repoint, no `global.inc.php` edit, no service restart).

Contrast with the alternatives (rejected): repointing the tracker to a *new
named* wallet would also require moving MPOS's payout endpoint + restarting
eloipool/mergeminer + MPOS, with a coinbase-loss gap and multi-wallet payout
errors. Keeping `""` operational avoids all of that.

## Facts this relies on (Bitcoin Core 26.2 / "25.2")

- Wallets are **descriptor** wallets and **load/unload live** over RPC — no
  daemon restart, like the Qt Open/Close Wallet menu.
- With **2+ wallets loaded**, every wallet RPC must name the wallet
  (`/wallet/<name>` URL or `-rpcwallet=<name>`) or it errors
  (`Wallet file not specified`).
- A wallet only ever spends **its own** UTXOs, selected by the wallet (BnB +
  random fallback, **not** oldest-first). So old funds must be *explicitly
  swept* into the active wallet, never "left to drain."
- **Coinbase maturity:** ELT = **460** blocks; the others ≈ **100–120** blocks.
  Immature coinbase can't be spent and won't be picked up by a rescan that
  starts after it was mined — this is why the rescan window matters.

## Per-coin reference

| coin | cli | datadir | RPC port | coinbase maturity |
| --- | --- | --- | --- | --- |
| blc  | blakecoin-cli         | /root/.blakecoin         | 8772  | ~100 |
| pho  | photon-cli            | /root/.photon            | 8984  | ~100 |
| bbtc | blakebitcoin-cli      | /root/.blakebitcoin      | 8243  | ~100 |
| elt  | electron-cli          | /root/.electron          | 6852  | **460** |
| lit  | lithium-cli           | /root/.lithium           | 12000 | ~100 |
| umo  | universalmolecule-cli | /root/.universalmolecule | 5921  | ~100 |

(Adjust maturity per the actual chainparams; ELT is the long one.)

## Running it (the tool)

`tools/wallet-maintenance.sh` does the whole procedure below. The wallet files
live in each daemon's **host data folder** (the datadir bind mount), so the tool
locates and moves `wallet.dat` there directly.

`wallet-maintenance.sh` is the **mainnet** tool (the regtest validator is the
separate `tools/regnet-wallet-maintenance.sh`); a bare run opens the live menu.

```
sudo tools/wallet-maintenance.sh                               # menu: pick coins + toggles
sudo tools/wallet-maintenance.sh rotate --coin blc --dry-run   # preview the plan
sudo tools/wallet-maintenance.sh rotate --coin blc             # rotate (after typed YES)
```

It runs the three phases across the selected coins with **one** mining-pause
window (on by default; `--no-pause` to skip — the scoped rescan covers the window
either way). The manual steps below are exactly what it does.

## The procedure (run per coin)

All `cli` calls are `docker exec <coin> <cli> -datadir=<datadir> …`; the
`wallet.dat` moves happen in the host data folder (the datadir bind mount).

### 0. Pre-flight
- Confirm only `""` is loaded for the coin (`listwallets`). If a previous
  rotation's wallets are still loaded, finish/clean those first.
- Note the current balance: `getbalances` (record `mine.trusted +
  untrusted_pending + immature`).
- **Back up first:** `backupwallet "/root/rotate-backups/<coin>-<ts>.dat"`.

### 1. Consolidation is automatic
No separate consolidate step is needed: the step-2 sweep to the temp wallet uses
`sendall` (and batched sends for large wallets), which collapses all of `""`'s
spendable UTXOs into the temp wallet — so the funds come back to the fresh `""`
already consolidated.

### 2. Capture the keychain + sweep the funds to a temp wallet
- Save the private descriptors (the keychain we'll re-import):
  ```
  <cli> -rpcwallet="" listdescriptors true   > /root/rotate-backups/<coin>-desc-<ts>.json
  ```
  (Treat this file as secret — it contains the wallet's private keys. 0600, never leaves the host.)
- Create a temp wallet and sweep the consolidated UTXO into it:
  ```
  <cli> createwallet "rotate-temp-<coin>" false false "" false true true
  TMPADDR=$(<cli> -rpcwallet="rotate-temp-<coin>" getnewaddress)
  <cli> -rpcwallet="" sendtoaddress "$TMPADDR" <amount> "" "" true   # subtractfee, all funds
  ```
  (Or use the existing sweep mechanic targeting the temp wallet.)

### 3. Swap the wallet file (mining paused)
**Pause mining for the swap** — removes the window where the
tracker address is owned by no loaded wallet. eloipool drives the parent
stratum *and* the merged aux, so stopping it pauses all six coins — do steps 3–4
for **every** coin you're rotating inside one pause window:
```
systemctl stop blakestream-mpos-eloipool blakestream-mpos-mergeminer
```
Then, per coin:
- `unloadwallet ""` (daemon stays up).
- Move the old wallet dir aside (backup):
  ```
  mv <datadir>/wallets/wallet.dat <datadir>/wallets/_rotated-<ts>/   # keep as backup
  ```
- `createwallet ""` fresh + blank:
  ```
  <cli> createwallet "" false true "" false true true   # blank=true (no auto keys)
  ```

### 4. Re-import the keychain with a **scoped** rescan
Re-import the saved private descriptors so the fresh `""` re-derives the **same**
addresses (incl. the tracker address) and picks up only the still-unspent
**immature** coinbase — *not* the whole historical coinbase set (which would
re-bloat `wallet.dat`):
```
RESCAN_TS=$(<cli> getblockheader $(<cli> getblockhash $(( $(<cli> getblockcount) - RESCAN_DEPTH )) ) | jq .time)
<cli> -rpcwallet="" importdescriptors '<private descriptors from step 2, with "timestamp": '"$RESCAN_TS"', "active": true>'
```
- **`RESCAN_DEPTH` = coinbase maturity + 100-block margin**:
  deep enough to recover all immature coinbase, shallow enough not to re-add
  already-spent coinbase history. So ELT ≈ **560** blocks, the others ≈ **200**.
  The timestamp is the block time of `tip − RESCAN_DEPTH`; `importdescriptors`
  takes a unix timestamp (not a height), and unix times are exact — no precision
  pitfall.

### 5. Restart mining + sweep the funds back into the fresh `""`
Once **every** rotated coin's fresh `""` has imported the keychain (step 4),
restart mining:
```
systemctl start blakestream-mpos-eloipool blakestream-mpos-mergeminer
```
Then sweep the funds back, per coin:
```
NEWADDR=$(<cli> -rpcwallet="" getnewaddress)
<cli> -rpcwallet="rotate-temp-<coin>" sendtoaddress "$NEWADDR" <amount> "" "" true
# once confirmed:
<cli> unloadwallet "rotate-temp-<coin>"
```

### 6. Verify
- `getbalances` on `""` ≈ the pre-flight total (incl. immature).
- `getaddressinfo <tracker-address>` on `""` → `ismine: true`.
- `getnewaddress` works (fresh `""` derives new addresses normally).
- Do a small MPOS payout cycle (or `sendtoaddress` a dust amount) to confirm
  `/wallet/` = `""` still sends.
- `listwallets` shows only `""` loaded.
- Only after confirming, optionally remove `_rotated-<ts>/` and the temp wallet
  dir (keep the `backupwallet` copy offline).

## Safety / gotchas

**A. The swap window (step 3).** Between `unloadwallet ""` and the fresh `""`
importing the keychain, the tracker address is owned by *no loaded wallet* for a
few seconds. **We pause mining (stop eloipool/mergeminer) for the swap**
to remove that gap; even without it the scoped rescan in step 4
covers the window and recovers anything mined (low reorg risk) — but pausing is
the clean choice. Restart mining once the fresh `""` has imported the key.

**B. Rescan depth.** Too shallow → miss immature coinbase (stranded until a
deeper re-import). Too deep → re-import spent coinbase history (bloat). Settled:
`RESCAN_DEPTH` = coinbase maturity + 100 blocks.

**C. The descriptor file is secret.** `listdescriptors true` output contains
private keys. Keep it 0600, on-host, delete after the rotation, never send it
anywhere off-host.

**D. Always keep the `backupwallet` copy** (step 0) and the `_rotated-<ts>/` dir
until you've fully verified the new `""` holds the right balance and pays out.

## Regtest test (proves it before live)

`tools/regnet-wallet-maintenance.sh` is the **regtest** tool — the same menu as
the mainnet `wallet-maintenance.sh` (pick coins + Rotate/Combine), but each runs
on an isolated regtest daemon (its own name/datadir — never the live pool). For
Rotate it mines coinbase to a tracker address with **`setmocktime`** so blocks get
spread-out timestamps (mainnet-like), which is what lets the timestamp-scoped
rescan actually scope — in a burst-mined regtest chain every block shares ~one
timestamp, so a timestamp-based rescan from "tip − depth" would scan from genesis
and not shrink anything. It then runs the full procedure and asserts:

- the fresh `""` recovers the immature coinbase,
- the tracker address is `ismine` on the fresh `""`,
- `getnewaddress` still works (the keychain derives normally),
- tx history shrinks (e.g. 612 → 163) and `wallet.dat` shrinks (e.g. 294912 →
  172032 bytes),
- the full balance is preserved after sweeping the temp funds back.

(Combine asserts the spendable UTXO set consolidates, e.g. 30 → 2, balance preserved.)

```
sudo tools/regnet-wallet-maintenance.sh                  # menu: pick coins + Rotate/Combine
sudo tools/regnet-wallet-maintenance.sh rotate  blc      # rotate smoke, one coin
sudo tools/regnet-wallet-maintenance.sh combine          # combine smoke, all coins
```

All checks pass for BLC on `sidgrip/blakecoin:25.2`. The live `wallet.dat` files
are smaller than a real-pool worst case (BLC 172 KB, ELT 549 KB today), but the
same scoped rescan shrinks them the same way — the regtest test deliberately
out-grows its rescan window to show the shrink.
