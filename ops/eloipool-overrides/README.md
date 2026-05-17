# Eloipool overrides — MPOS-side patches

The deploy bundle rsyncs the upstream `eloipool_Blakecoin`
tree into `/opt/blakestream-mpos/eloipool/` at install time. Files in
this directory get **copied over** that rsync output by
`40-install-pool.sh`, so any edit to a file here is the canonical MPOS
version — the Eliopool checkout stays clean.

Why a vendor-overlay instead of upstreaming: we want to keep
production-tested patches under MPOS version control without forking
the entire Eliopool repo. When an upstream update lands, we re-rsync
+ overlay; the Eliopool tree's history stays intact.

## Files

### `merged-mine-proxy.py3`

Two production fixes layered on the upstream MMP:

1. **`calc_merkle_index_for` guards `chain_id is None`** — pre-fix, an
   aux daemon still in IBD (or any chain whose first
   `getauxblock`/`createauxblock` hadn't returned yet) would have a
   `None` placeholder in `self.chain_ids[chain]`, causing the inline
   `rand += chain_id` to raise `TypeError: unsupported operand type(s)
   for +=: 'int' and 'NoneType'` on every gotwork call. Fix returns
   `None` for unset chain_id; the caller's `if chain_merkle_index is
   not None` guard already handles skip semantics. Companion edit:
   `rpc_gotwork` reordered to skip unhealthy chains BEFORE computing
   the merkle index so we never even reach the call for an unset
   chain.

2. **Per-chain `Failed to get aux block` log debounce** — pre-fix, a
   chain stuck in IBD logged on every poll (= every share submission
   on a busy pool), filling `mmp.log` with hundreds of MB before the
   daemon even finished syncing. Fix piggybacks on the existing
   `chain_health[chain_idx]` dict with a `last_error_log` timestamp;
   the error is emitted at most once every 60 s per chain. Same
   debounce on the `Only N/M aux chains are healthy` summary line,
   plus log-on-transition so a count change emits even within the
   60 s window. `_mark_chain_healthy` clears the flag so a fresh
   outage logs at full volume.

Net effect under the same conditions:
  18 MB / hr   →   ≈40 KB / hr in mmp.log

When upstream Eliopool gains either of these fixes, drop the
relevant block from this overlay file and re-rsync.
