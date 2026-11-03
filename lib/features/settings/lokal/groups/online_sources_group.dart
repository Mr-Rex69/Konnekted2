import 'package:flick/l10n/l10n.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flick/features/internet_radio/internet_radio_page.dart';
import 'package:flick/features/settings/screens/network_sources_screen.dart';
import 'package:flick/features/settings/widgets/http_addons_settings_panel.dart';
import 'package:flick/features/settings/widgets/playback_source_priority_panel.dart';
import 'package:flick/features/settings/widgets/global_catalogue_selector.dart';
import 'package:flick/features/morneye/morneye_addons_screen.dart';
import 'package:flick/widgets/lokal/settings/lokal_settings_kit.dart';

import '../lokal_settings_group.dart';

void _push(BuildContext context, Widget page) => unawaited(
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page)),
);

/// Online sources controls playback search, add-ons, servers and radio.
/// Account connections live under Data → Accounts.
List<LokalSettingsSection> onlineSourcesSettings(
  BuildContext context,
  WidgetRef ref,
) => [
  LokalSettingsSection(
    title: LokalOnlineSections.streaming,
    children: [
      LokalSettingCustom(
        label: lokalText('Global search catalogue'),
        description: lokalText('Choose the source of Global results; this does not affect playback source priority.'),
        child: const GlobalCatalogueSelector(),
      ),
      LokalSettingCustom(
        label: lokalText('Playback search priority'),
        description: lokalText(
          'Try sources from top to bottom when finding a song to play. Installed add-ons appear here too.',
        ),
        child: const PlaybackSourcePriorityPanel(),
      ),
      LokalSettingLink(
        label: lokalText('Network servers'),
        description: lokalText(
          'Subsonic, Jellyfin, WebDAV and other servers you run.',
        ),
        onTap: () => _push(context, const NetworkSourcesScreen()),
      ),
    ],
  ),
  LokalSettingsSection(
    title: LokalOnlineSections.addons,
    children: [
      const MorneyeAddonsPanel(),
      LokalSettingCustom(
        label: lokalText('HTTP music add-ons'),
        description: lokalText(
          'Add HTTPS music catalogues using their manifest.json link.',
        ),
        child: HttpAddonsSettingsPanel(),
      ),
    ],
  ),
  const LokalSettingsSection(
    title: LokalOnlineSections.repositories,
    children: [MorneyeRepositoriesPanel()],
  ),
  LokalSettingsSection(
    title: LokalOnlineSections.radioVideos,
    children: [
      LokalSettingLink(
        label: lokalText('Stations'),
        description: lokalText('Worldwide stations · 256 kbps+ and lossless'),
        onTap: () => _push(context, const InternetRadioPage()),
      ),
    ],
  ),
];

