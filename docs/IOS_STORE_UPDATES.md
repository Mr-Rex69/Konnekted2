# Install and update Lokal with AltStore or SideStore

AltStore Classic and SideStore install Lokal on your iPhone, manage its signing with your Apple account, and show new versions from the Lokal source. You add the source once. Each successful iPhone publication updates the same source with the verified IPA's version, build number, size and permissions.

## 1. Set up a store

Choose one and follow its official installation instructions:

- AltStore Classic ([Windows](https://faq.altstore.io/altstore-classic/how-to-install-altstore-windows) / [macOS](https://faq.altstore.io/altstore-classic/how-to-install-altstore-macos)): install AltServer on your Windows PC or Mac, then install AltStore Classic on your iPhone. Keep AltServer reachable when your store needs it for signing, installation or refresh.
- [SideStore](https://docs.sidestore.io/docs/installation/prerequisites): complete its initial installation, pairing and VPN setup. After setup, it uses the documented on-device signing/refresh flow. Follow its current connectivity and VPN requirements.

Use **AltStore Classic** for this source. AltStore PAL uses a different distribution system.

## 2. Add the Lokal source

Open **Sources** in your store, tap **+**, and paste:

```text
https://github.com/lokal-music/mobile/releases/download/ios/altstore-source.json
```

Confirm adding the source, open the Lokal listing and install it. Both stores use this same source URL. You do not need to add a new source for each release.

Lokal's **About → Updates → Set up store updates** also offers **Add to AltStore**, **Add to SideStore**, and **Copy source URL**. These require a Lokal build containing the new store-update screen; earlier installations can add the URL directly in their store.

## 3. Update Lokal

1. Refresh the source in your store so it sees the latest published build.
2. In **My Apps**, choose **Update** for Lokal. The store downloads the package and signs/installs it using its normal process.
3. Open Lokal again. Keep the same Apple account and app identity to preserve the existing library and settings. Do not uninstall Lokal as an update step. Switching signing accounts, changing the bundle identifier or moving between stores can change app identity; back up your data before doing that.

New Lokal builds check the dedicated iOS release when online and show an update prompt if its build number is higher. **Open AltStore** / **Open SideStore** takes you to your chosen store; finish the update there. You can also check manually in **About → Updates**, and disable automatic checks there. The check follows the dedicated, standard iOS GitHub release and never offers an Android APK.

Build numbers matter: `1.0.0` build `162` is newer than `1.0.0` build `161`. Both stores receive the real version and build from the IPA. A changed GitHub release title or status is not an app update.

## 4. Keep signing current

**Refresh** renews signing for the version already installed. **Update** installs a newer Lokal build. A successful refresh alone does not mean you installed the latest version.

Free-account installations normally expire after seven days. Keep your store's refresh configuration working and check its status before expiry. Automatic source checks and refreshes depend on the store's settings, network access, and iOS background scheduling. Lokal does not silently install updates or handle your Apple credentials.

If a store will not open from Lokal, install/configure it first using the official guide above, then add the source. The source URL is also shown on the [permanent iOS release page](https://github.com/lokal-music/mobile/releases/tag/ios). Manual IPA signing remains available through the [Windows installation guide](IOS_SIDELOADING.md).

## Release maintenance

`tool/ios_sideload_release.py` runs only after the mandatory IPA build, Flutter regressions, first launch and independent package audit. The full two-runtime native simulator suite is an opt-in publication gate; `qualification.json` records whether it ran. It copies the audited package to the public `Lokal.ipa` filename without changing its bytes, generates `altstore-source.json` from the package's own Info.plist and executable entitlements, and prepares the installation preamble and release notes. Publication validates the source against that package before upload; the source is uploaded after the IPA and metadata.

The source publishes only the current build, matching the two-release policy. Its IPA URL includes the build number to distinguish successive downloads at the permanent release URL. Its permissions are extracted from the IPA, including privacy descriptions; unhandled extension or entitlement formats fail publication instead of inventing permissions. Technical audit, source and symbols assets remain attached to each current release.

Format references: [AltStore source specification](https://faq.altstore.io/developers/make-a-source), [AltStore update behavior](https://faq.altstore.io/developers/updating-apps), [SideStore sources](https://docs.sidestore.io/docs/advanced/app-sources), [SideStore URL schemes](https://docs.sidestore.io/docs/advanced/url-schema).
