# iPhone build performance

The workflow keeps publication gated on the same source commit's host regressions, device IPA/package audit, production first launch, and both iOS simulator acceptance suites. Faster artifact delivery and parallel validation replace the previous serial schedule.

## Measured baseline

[Build 160](https://github.com/lokal-music/mobile/actions/runs/42516031657) took approximately 70 minutes:

| Work | Duration |
| --- | ---: |
| Host Flutter regressions on the Mac | 7.9 minutes |
| Device compilation | 10.7 minutes |
| Production simulator compilation | 14.2 minutes |
| Integration rebuild after production compilation | 5.0 minutes |
| First Mac job, including setup, controls and iOS 18.6 acceptance | 57.8 minutes |
| Subsequent iOS 26.0 job | 11.7 minutes |

The native cache missed on this run. Its key required an exact source match, and compiled dependencies were saved only after both device and simulator compilation succeeded. Flutter and Cargo caches created in one pull request are also scoped by GitHub; another PR or `main` cannot generally read a cache created under that PR's merge ref.

## New schedule

- **Build iPhone IPA** starts immediately and uploads the IPA before cache packing or simulator checks. Download it from that job's artifacts for early testing.
- **Production entry point and first launch** compiles and checks the regular application independently, retaining its minimal Flutter control and native launch evidence.
- **Compile integration simulator apps** builds the integration application and minimal Flutter control once. Both acceptance jobs use those exact uploaded apps, preserving executable modes.
- **Native acceptance on iOS 18.6 and 26.0** runs concurrently on fresh Macs. Neither waits for the other or recompiles the control application.
- **Flutter regressions** run as three Linux shards, with the same complete selection as before. `tool/ios_flutter_tests.txt` includes files/directories/globs; Flutter partitions suites between shards. Analysis and portable Python checks also leave the Mac compilation path.
- **IPA/source audit** runs as soon as the device package is available. Publication waits for every gate, including all shards and both runtime jobs.

The first run can still have cold caches, and GitHub runner queues vary. Compare actual job/step durations before assigning a new fixed build-time expectation.

## Cache and retry behavior

Device and simulator native caches are isolated by SDK/configuration, runner architecture, Xcode, Rust, dependency/tooling fingerprints and source. A dependency-compatible restore prefix lets Cargo reuse unchanged dependencies after a Rust edit; Cargo still validates fingerprints and rebuilds changed inputs. Final app bundles/IPAs are not restored from these caches.

FFmpeg and SMB archives are cached by the pinned preparation scripts and lockfile, but their checksums and native contents are verified on every use. A corrupt cached archive is never accepted. Successfully compiled native dependencies are saved even if a later runtime assertion fails, so an unrelated test failure does not force another cold compile.

Audit/publication download the device artifact by its returned artifact ID, and runtime jobs use the integration artifact ID. **Re-run failed jobs** can therefore reuse successful builds from the earlier attempt of the same run instead of looking for a nonexistent artifact with the new attempt number. A changed source commit still needs its own build.

Closing/merging a PR cancels its obsolete workflow without starting more Mac builds. This prevents abandoned validation runs from occupying runners needed for a new `main` build. Release publication remains explicit through the existing workflow inputs.
