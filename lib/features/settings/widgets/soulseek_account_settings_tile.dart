import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flick/core/theme/lokal_tokens.dart';
import 'package:flick/services/soulseek_service.dart';

/// Data > Accounts, first provider. The user only needs a network username
/// and password; the embedded native client is bundled with Lokal.
class SoulseekAccountSettingsTile extends StatefulWidget {
  const SoulseekAccountSettingsTile({super.key});
  @override
  State<SoulseekAccountSettingsTile> createState() => _SoulseekAccountSettingsTileState();
}

class _SoulseekAccountSettingsTileState extends State<SoulseekAccountSettingsTile> {
  final _service = SoulseekService.instance;
  final _user = TextEditingController();
  final _password = TextEditingController();
  bool _share = false, _working = false;
  String _problem = '';

  @override
  void initState() {
    super.initState();
    _service.addListener(_refresh);
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    await _service.loadAccount();
    if (!mounted) return;
    _user.text = _service.username;
    setState(() => _share = _service.shareEnabled);
    if (_service.username.isNotEmpty) {
      await _service.ensureConnected();
      if (mounted) setState(() {});
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
    if (_working) return;
    setState(() { _working = true; _problem = ''; });
    try {
      await _service.setSharing(enabled);
      if (mounted) setState(() => _share = enabled);
    } catch (e) {
      if (mounted) setState(() => _problem = e.toString());
    } finally {
      if (mounted) setState(() => _working = false);
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
        ? 'Connected as ' + _service.username
        : 'Sign in with a Soulseek username and password.';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.hub_outlined, size: 20, color: t.accent),
          const SizedBox(width: 10),
          Expanded(child: Text('Soulseek',
              style: TextStyle(fontWeight: FontWeight.w600, color: t.text))),
          if (signed) TextButton(onPressed: working ? null : _logout,
              child: const Text('Sign out')),
        ]),
        const SizedBox(height: 5),
        Text(description, style: TextStyle(color: t.muted, fontSize: 12)),
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
          Text('New username? Soulseek creates it on first sign-in if available. '
              'Use a different account if desktop Soulseek is signed in simultaneously.',
              style: TextStyle(color: t.muted, fontSize: 11)),
        ],
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Text('Share my main Lokal music folder',
              style: TextStyle(fontSize: 13, color: t.text)),
          subtitle: Text(signed
              ? 'Visible on Soulseek · ' + _service.sharedFiles.toString() + ' audio files'
              : 'Off by default. Other users can browse and download ALL files in the selected folder, including covers, lyrics and other documents.',
              style: TextStyle(fontSize: 11, color: t.muted)),
          value: signed ? _service.shareEnabled : _share,
          onChanged: working ? null : (value) {
            if (signed) {
              unawaited(_changeShare(value));
            } else {
              setState(() => _share = value);
            }
          },
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
        const SizedBox(height: 6),
        Text('Sharing stays on while the foreground notification is active. '
            'Android may limit long-running background sharing.',
            style: TextStyle(color: t.muted, fontSize: 11)),
        const SizedBox(height: 5),
        Text('Native Soulseek engine 20.0.0 · Updated with Lokal releases.',
            style: TextStyle(color: t.muted, fontSize: 11)),
        if (_problem.isNotEmpty || _service.error.isNotEmpty) Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(_problem.isNotEmpty ? _problem : _service.error,
              style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
        ),
      ]),
    );
  }
}
