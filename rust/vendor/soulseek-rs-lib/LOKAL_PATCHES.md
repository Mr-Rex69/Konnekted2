# Pinned source and local compatibility patch

Upstream: https://github.com/michel/soulseek-rs
Revision: 3c5f1d12f25f98730ad8f1ca57621250d7c3bd41
Crate: soulseek-rs-lib 20.0.0 (MIT; full notice in LICENSE).

The crate source, examples and tests are copied from that revision. Workspace
package metadata and lint settings are expanded in Cargo.toml so this snapshot
builds independently of the upstream workspace.

The only protocol-source change is in src/client/connection.rs:

```diff
-    if limit < COMFORTABLE_OPEN_FILES {
+    if u64::from(limit) < COMFORTABLE_OPEN_FILES {
```

Android libc exposes rlim_t with a different width from desktop targets. Widen
the observed limit before comparing it with the u64 warning threshold. This
retains the existing diagnostic and does not change limits or network behavior.
The application retains its upstream revision pin and selects this snapshot
with a Cargo source patch. Host-contract checks use the same source patch.
