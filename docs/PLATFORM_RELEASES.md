# Platform releases

The public download pages have permanent tags:

- [Android](https://github.com/lokal-music/mobile/releases/tag/android): latest signed stable APK, package metadata and checksums.
- [iOS](https://github.com/lokal-music/mobile/releases/tag/ios): latest audited unsigned IPA, matching source, crash symbols, licenses and qualification report. This remains a prerelease.

Successful publications update the existing release, move only that platform's tag to the package's source commit, and remove superseded assets after upload verification. Version and build numbers remain inside the packages and manifests. Android's updater reads those manifests, so a new version tag is unnecessary. Android version calculation reads the published manifest before incrementing the version and versionCode.

To publish Android, run **Release Lokal Mobile** on `main`. The default bumps the patch version; **replace_existing** keeps the version while issuing a newer build. **draft** builds workflow artifacts without changing the public release. **Build Lokal Mobile Nightly (artifacts only)** produces preview artifacts without replacing the stable APK.

To publish iOS, run **iPhone build and sideload package** on `main` with **publish** enabled. Both installed simulator suites, external background tests and the independent package audit must pass before publication. Explicit `release/ios-sideload-*` pushes also publish after those checks. Pull requests and manual runs with publication disabled produce artifacts only.

**Keep platform releases tidy** reconciles completed publications and can also be run manually. Its cleanup first validates both platforms' retained manifests and required asset sets, then preserves the current release assets while consolidating older entries. It removes only superseded mobile releases and unreferenced legacy `vX.Y.Z...` / `ios-sideload-beta-N-attemptN` tags. Draft releases, unrelated tag names, branches and the two platform tags are preserved. The workflow always executes `main` code and does not consume artifacts from its triggering run.

For a read-only preview with authenticated `gh`:

```sh
python3 tool/platform_releases.py consolidate --cleanup --dry-run
```

In-app release notes fetch the platform tag and verify the platform/version marker before displaying them. Older minor versions use their bundled fallback notes.
