import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flick/core/theme/lokal_tokens.dart';
import 'package:flick/core/theme/lokal_theme.dart';
import 'package:flick/services/soulseek_service.dart';

/// Data > Accounts, first provider. The user only needs a network username
/// and password; the embedded native client is bundled with Lokal.
class SoulseekAccountSettingsTile extends StatefulWidget {
  const SoulseekAccountSettingsTile({super.key, this.service});
  @visibleForTesting
  final SoulseekService? service;
  @override
  State<SoulseekAccountSettingsTile> createState() => _SoulseekAccountSettingsTileState();
}

class _SoulseekAccountSettingsTileState extends State<SoulseekAccountSettingsTile> {
  late final SoulseekService _service;
  final _user = TextEditingController();
  final _password = TextEditingController();
  bool _share = false, _working = false;
  String _problem = '';

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? SoulseekService.instance;
    _service.addListener(_refresh);
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    try {
      await _service.loadAccount();
      if (!mounted) return;
      _user.text = _service.username;
      setState(() => _share = _service.sharePreference);
      if (_service.username.isNotEmpty) {
        await _service.ensureConnected();
        if (mounted) setState(() {});
      }
    } catch (e) {
      if (mounted) setState(() => _problem = e is StateError ? e.message : '$e');
    }
  }

  void _refresh() { if (mounted) setState(() {}); }

  Future<void> _login() async {
    if (_working) return;
    setState(() { _working = true; _problem = ''; });
    try {
      await _service.signIn(_user.text, _password.text, share: _share);
      _password.clear();
    } catch (e) {
      if (mounted) setState(() => _problem = e.toString());
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _logout() async {
    if (_working) return;
    setState(() { _working = true; _problem = ''; });
    try {
      await _service.signOut();
      _password.clear();
    } catch (e) {
      if (mounted) setState(() => _problem = e.toString());
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _changeShare(bool enabled) async {
    if (_working || _service.sharingBusy) return;
    setState(() => _problem = '');
    try {
      await _service.setSharing(enabled);
      if (mounted) setState(() => _share = enabled);
    } catch (e) {
      if (mounted) setState(() =>
          _problem = e is StateError ? e.message : '$e');
    }
  }

  @override
  void dispose() {
    _service.removeListener(_refresh);
    _user.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.lokal;
    final working = _working || _service.busy;
    final signed = _service.connected;
    final description = signed
        ? 'Connected as ${_service.username}'
        : 'Search and download music from Soulseek.';
    final shareDescription = _service.sharingBusy
        ? '${_service.sharingStatus} Large libraries may take a while.'
        : signed && _service.shareEnabled
            ? 'Sharing ${_service.sharedFiles} files on Soulseek.'
            : 'Optional. All files in this folder become visible to other users, including covers and lyrics.';
    final supportingStyle = TextStyle(
      fontFamily: LokalTheme.sans, color: t.muted, fontSize: 12.5,
      height: 1.35,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.hub_outlined, size: 20, color: t.accent),
          const SizedBox(width: 10),
          Expanded(child: Text('Soulseek',
              style: TextStyle(
                fontFamily: LokalTheme.sans, fontSize: 15,
                fontWeight: FontWeight.w600, color: t.text,
              ))),
          if (signed) TextButton(onPressed: working ? null : _logout,
              child: const Text('Sign out')),
        ]),
        const SizedBox(height: 5),
        Text(description, style: supportingStyle),
        if (!signed) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _user, enabled: !working, autocorrect: false,
            onChanged: (_) => setState(() {}),
            textCapitalization: TextCapitalization.none,
            decoration: const InputDecoration(
                labelText: 'Username', isDense: true, border: OutlineInputBorder()),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _password, enabled: !working, obscureText: true,
            onSubmitted: (_) => unawaited(_login()),
            decoration: const InputDecoration(
                labelText: 'Password', isDense: true, border: OutlineInputBorder()),
          ),
          const SizedBox(height: 8),
          Text('Use a separate account if Soulseek is already open on desktop.',
              style: supportingStyle),
        ],
        const SizedBox(height: 10),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Text('Share main music folder',
              style: TextStyle(
                fontFamily: LokalTheme.sans, fontSize: 14,
                fontWeight: FontWeight.w600, color: t.text,
              )),
          subtitle: Text(shareDescription, style: supportingStyle),
          value: signed && !_service.sharingBusy
              ? _service.shareEnabled : _share,
          onChanged: working || _service.sharingBusy ? null : (value) {
            if (signed) {
              unawaited(_changeShare(value));
            } else {
              setState(() => _share = value);
            }
          },
        ),
        if (_service.sharingBusy)
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 8),
            child: Row(children: [
              SizedBox(width: 16, height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: t.accent)),
              const SizedBox(width: 10),
              Expanded(child: Text(_service.sharingStatus,
                  style: supportingStyle)),
            ]),
          ),
        if (!signed) ...[
          const SizedBox(height: 5),
          FilledButton.tonalIcon(
            onPressed: working || _user.text.trim().isEmpty ? null : _login,
            icon: working ? const SizedBox(width: 16, height: 16,
                child: CircularProgressIndicator(strokeWidth: 2)) :
                const Icon(Icons.login, size: 17),
            label: Text(working ? 'Connecting…' : 'Sign in'),
          ),
        ],
        if (signed && _service.uploads.isNotEmpty) Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text('Uploads: ' +
              _service.uploads.where((row) =>
                  (row['status'] as String? ?? '').startsWith('InProgress'))
                  .length.toString() + ' active',
              style: TextStyle(color: t.muted, fontSize: 11)),
        ),
        const SizedBox(height: 8),
        Text('Background sharing may be limited by Android. The Soulseek engine updates with Lokal.',
            style: supportingStyle),
        if (_problem.isNotEmpty || _service.error.isNotEmpty) Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(_problem.isNotEmpty ? _problem : _service.error,
              style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
        ),
      ]),
    );
  }
}
