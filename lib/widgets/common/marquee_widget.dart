import 'dart:async';

import 'package:flutter/material.dart';

class MarqueeWidget extends StatefulWidget {
  final Widget child;
  final Axis direction;
  final Duration animationDuration;
  final Duration backDuration;
  final Duration pauseDuration;

  const MarqueeWidget({
    super.key,
    required this.child,
    this.direction = Axis.horizontal,
    this.animationDuration = const Duration(milliseconds: 6000),
    this.backDuration = const Duration(milliseconds: 800),
    this.pauseDuration = const Duration(milliseconds: 800),
  });

  @override
  State<MarqueeWidget> createState() => _MarqueeWidgetState();
}

class _MarqueeWidgetState extends State<MarqueeWidget> {
  late ScrollController _scrollController;
  Timer? _pauseTimer;
  Completer<bool>? _pauseReply;
  bool _scrolling = false;

  Future<bool> _pause() {
    if (!mounted || !_scrollController.hasClients) return Future.value(false);
    final reply = Completer<bool>();
    _pauseReply = reply;
    _pauseTimer = Timer(widget.pauseDuration, () {
      _pauseTimer = null;
      _pauseReply = null;
      reply.complete(true);
    });
    return reply.future;
  }

  void _scheduleScroll() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_scrolling) unawaited(_scroll());
    });
  }

  @override
  void didUpdateWidget(covariant MarqueeWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    _scheduleScroll();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scheduleScroll();
  }

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _scheduleScroll();
  }

  @override
  void dispose() {
    _pauseTimer?.cancel();
    _pauseReply?.complete(false);
    _pauseReply = null;
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _scroll() async {
    if (_scrolling) return;
    _scrolling = true;
    try {
      while (mounted && _scrollController.hasClients) {
        if (MediaQuery.maybeOf(context)?.disableAnimations == true ||
            !TickerMode.valuesOf(context).enabled ||
            _scrollController.position.maxScrollExtent <= 1) return;
        if (!await _pause()) return;
        if (!mounted || !_scrollController.hasClients) return;
        await _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: widget.animationDuration,
          curve: Curves.ease,
        );
        if (!await _pause()) return;
        if (!mounted || !_scrollController.hasClients) return;
        await _scrollController.animateTo(0.0,
          duration: widget.backDuration, curve: Curves.easeOut);
      }
    } finally {
      _scrolling = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      controller: _scrollController,
      scrollDirection: widget.direction,
      physics: const NeverScrollableScrollPhysics(),
      child: widget.child,
    );
  }
}
