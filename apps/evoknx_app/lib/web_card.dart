import 'dart:async';

import 'package:evoknx_ui/evoknx_ui.dart';
import 'package:flutter/foundation.dart' show Factory;
import 'package:flutter/gestures.dart' show OneSequenceGestureRecognizer, VerticalDragGestureRecognizer;
import 'package:flutter/material.dart' hide Text;
import 'package:knx_config/knx_config.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Address as typed in the Editor; "evohome.vn" becomes "https://evohome.vn".
Uri? webUri(Object? url) {
  var s = (url ?? '').toString().trim();
  if (s.isEmpty) return null;
  if (!s.contains('://')) s = 'https://$s';
  return Uri.tryParse(s);
}

WebViewController _controller(Uri uri, {void Function(int)? onProgress, void Function(String?)? onError}) {
  return WebViewController()
    ..setJavaScriptMode(JavaScriptMode.unrestricted)
    ..setBackgroundColor(Colors.transparent)
    ..setNavigationDelegate(
      NavigationDelegate(
        onProgress: onProgress,
        onPageStarted: (_) => onError?.call(null),
        onWebResourceError: (e) {
          if (e.isForMainFrame != false) onError?.call('Could not load the page (${e.description}).');
        },
      ),
    )
    ..loadRequest(uri);
}

/// "Trang web nhúng" card: a live web page inside the card, with the options
/// set in the Editor (header, touch, full screen, auto refresh).
class WebCard extends StatefulWidget {
  const WebCard({super.key, required this.w, required this.pal});
  final Json w;
  final AppPalette pal;

  @override
  State<WebCard> createState() => _WebCardState();
}

class _WebCardState extends State<WebCard> {
  WebViewController? _c;
  Timer? _timer;
  int _progress = 0;
  String? _error;

  Json get _opts => jsonMap(widget.w['web']);
  Uri? get _uri => webUri(widget.w['url']);

  @override
  void initState() {
    super.initState();
    final u = _uri;
    if (u == null) return;
    _c = _controller(
      u,
      onProgress: (p) {
        if (mounted) setState(() => _progress = p);
      },
      onError: (e) {
        if (mounted) setState(() => _error = e);
      },
    );
    final secs = ((_opts['refresh'] as num?) ?? 0).toInt();
    if (secs > 0) _timer = Timer.periodic(Duration(seconds: secs), (_) => _c?.reload());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pal = widget.pal, w = widget.w;
    final showHead = _opts['showHeader'] != false;
    final interactive = _opts['interactive'] != false;
    final full = _opts['fullscreen'] != false && _uri != null;
    final label = (w['label'] ?? '').toString();
    final c = _c;
    Widget fullButton() => IconButton(
      tooltip: tr('Open full screen'),
      visualDensity: VisualDensity.compact,
      icon: Icon(Icons.open_in_full, size: 20, color: pal.muted),
      onPressed: () => openWebPage(context, label, _uri!, pal),
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: raisedDecoration(
        pal,
        pal.fill(pal.tile),
        radius: BorderRadius.circular(pal.radius),
        lift: pal.cardLift,
        border: pal.border <= 0 ? Border.fromBorderSide(BorderSide.none) : Border.all(color: pal.edge, width: pal.border),
        shadow: false,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showHead) ...[
            SizedBox(
              height: 36,
              child: Row(
                children: [
                  iconWidget(w['icon'] as String?, fs(w, 'iconSize'), pal.muted),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: fs(w, 'labelSize'), color: pal.ink),
                    ),
                  ),
                  if (full) fullButton(),
                ],
              ),
            ),
            const SizedBox(height: 4),
          ],
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: c == null
                        ? Center(
                            child: Text('No web address', style: TextStyle(color: pal.muted)),
                          )
                        : IgnorePointer(
                            ignoring: !interactive,
                            // The web page only takes vertical drags (scrolling up
                            // and down). Sideways swipes are left to the App, so
                            // they still change page.
                            child: WebViewWidget(
                              controller: c,
                              gestureRecognizers: {Factory<OneSequenceGestureRecognizer>(() => VerticalDragGestureRecognizer())},
                            ),
                          ),
                  ),
                  if (c != null && _progress < 100 && _error == null)
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: LinearProgressIndicator(value: _progress / 100, minHeight: 2, color: pal.accent, backgroundColor: Colors.transparent),
                    ),
                  if (!showHead && full) Positioned(top: 0, right: 0, child: fullButton()),
                  if (_error != null)
                    Positioned.fill(
                      child: ColoredBox(
                        color: pal.panel,
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _error!,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontSize: 13, color: pal.muted),
                                ),
                                const SizedBox(height: 8),
                                TextButton(
                                  onPressed: () {
                                    setState(() => _error = null);
                                    c?.reload();
                                  },
                                  child: const Text('Retry'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A web page over the whole screen (full-screen web card, or "Mở trang web").
Future<void> openWebPage(BuildContext context, String title, Uri uri, AppPalette pal) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (_) => WebPage(title: title, uri: uri, pal: pal),
  ),
);

class WebPage extends StatefulWidget {
  const WebPage({super.key, required this.title, required this.uri, required this.pal});
  final String title;
  final Uri uri;
  final AppPalette pal;

  @override
  State<WebPage> createState() => _WebPageState();
}

class _WebPageState extends State<WebPage> {
  late final WebViewController _c = _controller(
    widget.uri,
    onProgress: (p) {
      if (mounted) setState(() => _progress = p);
    },
    onError: (e) {
      if (mounted) setState(() => _error = e);
    },
  );
  int _progress = 0;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final pal = widget.pal;
    return Scaffold(
      backgroundColor: pal.screen,
      appBar: AppBar(
        backgroundColor: pal.screen,
        foregroundColor: pal.ink,
        scrolledUnderElevation: 0,
        title: Text(
          widget.title.isEmpty ? widget.uri.host : widget.title,
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: pal.ink),
        ),
        actions: [IconButton(tooltip: tr('Reload'), icon: const Icon(Icons.refresh), onPressed: () => _c.reload())],
      ),
      body: Stack(
        children: [
          Positioned.fill(child: WebViewWidget(controller: _c)),
          if (_progress < 100 && _error == null)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: LinearProgressIndicator(value: _progress / 100, minHeight: 2, color: pal.accent, backgroundColor: Colors.transparent),
            ),
          if (_error != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: pal.muted),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
