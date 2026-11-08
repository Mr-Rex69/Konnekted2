import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../core/utils/app_log.dart';
import '../../widgets/common/web_sign_in_frame.dart';
import 'youtube_music_account.dart';

const _musicUrl = 'https://music.youtube.com';

/// BitChord's first-party YouTube Music login flow. In particular, do not
/// impersonate desktop Chrome: use the platform WebView's real user agent and let
/// Google's ServiceLogin redirect directly to YouTube Music.
Uri youtubeMusicSignInUri() =>
    Uri.https('accounts.google.com', '/ServiceLogin', {
      'ltmpl': 'music',
      'service': 'youtube',
      'passive': 'true',
      'continue': '$_musicUrl/',
    });

const _ytcfgProbe = r'''
(function () {
  try {
    if (!window.ytcfg || typeof window.ytcfg.get !== 'function') return null;
    var get = function (key) {
      var value = window.ytcfg.get(key);
      return (value === undefined || value === null || value === '') ? null : String(value);
    };
    return {
      loggedIn: String(!!window.ytcfg.get('LOGGED_IN')),
      sessionIndex: get('SESSION_INDEX'),
      delegatedSessionId: get('DELEGATED_SESSION_ID'),
      visitorData: get('VISITOR_DATA'),
      clientVersion: get('INNERTUBE_CLIENT_VERSION'),
      userAgent: navigator.userAgent
    };
  } catch (e) {
    return null;
  }
})()
''';

Map<String, dynamic> _decodeYtcfg(Object? raw) {
  Object? decoded = raw;
  // WebView implementations differ in whether they return a JS object or a
  // JSON-encoded string. Accept either without relying on double encoding.
  for (var i = 0; i < 2 && decoded is String; i++) {
    try {
      decoded = jsonDecode(decoded);
    } on FormatException {
      return {};
    }
  }
  if (decoded is Map) return Map<String, dynamic>.from(decoded);
  return {};
}

/// Interactive sign-in sheet. A session is saved only after the user confirms
/// the selected YouTube Music profile and the live page reports LOGGED_IN.
class YoutubeMusicSignInSheet extends StatefulWidget {
  const YoutubeMusicSignInSheet({super.key, this.fullscreen = false});
  final bool fullscreen;

  static Future<YoutubeMusicSession?> show(BuildContext context) {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return Navigator.of(
        context,
        rootNavigator: true,
      ).push<YoutubeMusicSession>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => const YoutubeMusicSignInSheet(fullscreen: true),
        ),
      );
    }
    return showModalBottomSheet<YoutubeMusicSession>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      enableDrag: false,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const YoutubeMusicSignInSheet(),
    );
  }

  @override
  State<YoutubeMusicSignInSheet> createState() =>
      _YoutubeMusicSignInSheetState();
}

class _YoutubeMusicSignInSheetState extends State<YoutubeMusicSignInSheet> {
  InAppWebViewController? _controller;
  bool _pageReady = false;
  bool _capturing = false;
  String? _error;

  void _log(String event) => AppLog.instance.add('[YouTube sign-in] $event');

  static String _page(WebUri? uri) => switch (uri?.host) {
    'accounts.google.com' => 'google_accounts',
    'music.youtube.com' => 'youtube_music',
    'www.youtube.com' => 'youtube',
    _ => 'other',
  };

  Future<void> _onLoadStop(
    InAppWebViewController controller,
    WebUri? uri,
  ) async {
    _controller = controller;
    if (!mounted) return;
    final isMusicPage =
        uri?.scheme == 'https' && uri?.host == 'music.youtube.com';
    _log('event=load_complete page=${_page(uri)}');
    setState(() {
      _pageReady = isMusicPage;
      if (isMusicPage) _error = null;
    });
  }

  Future<void> _capture() async {
    final controller = _controller;
    if (_capturing || !_pageReady || controller == null) return;
    setState(() {
      _capturing = true;
      _error = null;
    });
    _log('event=capture_started');

    try {
      final cookieList = await CookieManager.instance().getCookies(
        url: WebUri(_musicUrl),
      );
      final cookies = <String, String>{
        for (final cookie in cookieList)
          if (cookie.name.isNotEmpty && '${cookie.value ?? ''}'.isNotEmpty)
            cookie.name: '${cookie.value}',
      };

      final contextValues = _decodeYtcfg(
        await controller.evaluateJavascript(source: _ytcfgProbe),
      );
      final loggedInValue = contextValues['loggedIn'];
      final loggedIn =
          loggedInValue == true ||
          '${loggedInValue ?? ''}'.toLowerCase() == 'true';
      if (!loggedIn) {
        _log('event=capture_failed reason=profile_not_confirmed');
        if (mounted) {
          setState(() {
            _error = 'YouTube Music has not confirmed a signed-in profile yet. Finish choosing your account on the page, then try again.';
          });
        }
        return;
      }

      final userAgent = contextValues['userAgent']?.toString().trim() ?? '';
      if (userAgent.isEmpty) {
        _log('event=capture_failed reason=browser_identity_missing');
        if (mounted) {
          setState(() {
            _error = 'Could not read the browser session. Reload YouTube Music and try again.';
          });
        }
        return;
      }

      final session = YoutubeMusicSession(
        cookies: cookies,
        // Keep the actual platform WebView UA. Replacing it with a desktop UA
        // creates a mismatch between the sign-in page and Innertube requests.
        userAgent: userAgent,
        sessionIndex: contextValues['sessionIndex']?.toString(),
        delegatedSessionId: contextValues['delegatedSessionId']?.toString(),
        visitorData: contextValues['visitorData']?.toString(),
        clientVersion: contextValues['clientVersion']?.toString(),
      );
      if (!session.signedIn) {
        _log('event=capture_failed reason=signing_cookie_missing');
        if (mounted) {
          setState(() {
            _error = 'YouTube Music is open, but no signing cookie was found. Finish signing in and try again.';
          });
        }
        return;
      }

      _log('event=capture_complete');
      if (mounted) Navigator.of(context).pop(session);
    } catch (_) {
      _log('event=capture_failed reason=session_read_failed');
      if (mounted) {
        setState(() {
          _error = 'Could not read the YouTube Music session. Reload the page and try again.';
        });
      }
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return WebSignInFrame(
      fullscreen: widget.fullscreen,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
            child: Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Sign in to YouTube Music',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Your session is stored securely on this device.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: Text(
                _error!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 12,
                ),
              ),
            ),
          if (widget.fullscreen && MediaQuery.viewInsetsOf(context).bottom == 0)
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: Text(
                'If Google cannot use your passkey here, choose “Try another way” to use your password or another verification method.',
                style: TextStyle(fontSize: 12),
              ),
            ),
          Expanded(
            child: InAppWebView(
              gestureRecognizers: {
                Factory<OneSequenceGestureRecognizer>(
                  () => EagerGestureRecognizer(),
                ),
              },
              initialUrlRequest: URLRequest(
                url: WebUri(youtubeMusicSignInUri().toString()),
              ),
              initialSettings: InAppWebViewSettings(
                // Deliberately omit userAgent: use the native platform
                // WebView identity, as BitChord does.
                javaScriptEnabled: true,
                thirdPartyCookiesEnabled: true,
                domStorageEnabled: true,
                mediaPlaybackRequiresUserGesture: true,
                // Drawn as a texture: as a hybrid-composition view the page
                // stays black under Impeller on Android 12 and later.
                useHybridComposition: false,
                disableVerticalScroll: false,
                verticalScrollBarEnabled: true,
                isTextInteractionEnabled: true,
              ),
              onWebViewCreated: (controller) => _controller = controller,
              onLoadStop: _onLoadStop,
              onLoadStart: (controller, uri) {
                _log('event=load_started page=${_page(uri)}');
                if (mounted) setState(() => _pageReady = false);
              },
              onReceivedError: (controller, request, error) {
                if (!mounted || request.isForMainFrame != true) return;
                _log(
                  'event=load_failed page=${_page(request.url)} reason=page_load_failed',
                );
                setState(() {
                  _pageReady = false;
                  _error = 'The sign-in page could not be loaded. Check your connection and try again.';
                });
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Choose your YouTube Music profile, then confirm.',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: _pageReady && !_capturing ? _capture : null,
                  child: _capturing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Use this account'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
