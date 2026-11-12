import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/material.dart' hide Text;
import 'package:evoknx_ui/evoknx_ui.dart' show Text, tr;
import 'package:flutter/services.dart';
import 'package:knx_config/knx_config.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// Real video for the camera cards: RTSP through media_kit (libmpv), HTTP as
/// an MJPEG stream or a snapshot that is refreshed (Basic and Digest login).
/// The picture stops while the App is in the background.
class LiveCamera extends StatefulWidget {
  const LiveCamera({super.key, required this.cam, this.fit = BoxFit.cover, this.allowFullscreen = true});
  final Json cam;
  final BoxFit fit;

  /// Show the button that opens the picture full screen.
  final bool allowFullscreen;

  @override
  State<LiveCamera> createState() => _LiveCameraState();
}

class _LiveCameraState extends State<LiveCamera> with WidgetsBindingObserver {
  bool _active = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final a = state == AppLifecycleState.resumed;
    if (a != _active && mounted) setState(() => _active = a);
  }

  void _openFullscreen() {
    Navigator.of(context).push(MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => CameraFullscreen(cam: widget.cam)));
  }

  @override
  Widget build(BuildContext context) {
    // A page opened over this one (settings, full screen...) covers it: its
    // tickers are switched off. Close the stream then, open it again after.
    final covered = !TickerMode.of(context);
    if (!_active || covered) return const ColoredBox(color: Colors.black);
    final picture = widget.cam['protocol'] == 'http' ? _HttpCamera(cam: widget.cam, fit: widget.fit) : _RtspCamera(cam: widget.cam, fit: widget.fit);
    if (!widget.allowFullscreen) return picture;
    return Stack(
      fit: StackFit.expand,
      children: [
        picture,
        Positioned(
          right: 6,
          top: 6,
          child: Material(
            color: Colors.black45,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: _openFullscreen,
              child: const Padding(
                padding: EdgeInsets.all(6),
                child: Icon(Icons.fullscreen, size: 20, color: Colors.white),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The camera picture over the whole screen (landscape), with a close button.
class CameraFullscreen extends StatefulWidget {
  const CameraFullscreen({super.key, required this.cam});
  final Json cam;

  @override
  State<CameraFullscreen> createState() => _CameraFullscreenState();
}

class _CameraFullscreenState extends State<CameraFullscreen> {
  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations(const [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    // Back to what the phone decides (portrait or any).
    SystemChrome.setPreferredOrientations(const []);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          LiveCamera(cam: widget.cam, fit: BoxFit.contain, allowFullscreen: false),
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Material(
                  color: Colors.black54,
                  shape: const CircleBorder(),
                  child: IconButton(
                    tooltip: tr('Close'),
                    icon: const Icon(Icons.fullscreen_exit, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown over the picture while loading or after an error.
class _CamMessage extends StatelessWidget {
  const _CamMessage({this.text, this.loading = false});
  final String? text;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (loading) const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70)),
            if (!loading) Icon(Icons.videocam_off_outlined, size: 26, color: Colors.white.withValues(alpha: 0.7)),
            if (text != null) ...[
              const SizedBox(height: 8),
              Text(
                text!,
                textAlign: TextAlign.center,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.8), decoration: TextDecoration.none, fontWeight: FontWeight.w400),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ RTSP

class _RtspCamera extends StatefulWidget {
  const _RtspCamera({required this.cam, required this.fit});
  final Json cam;
  final BoxFit fit;

  @override
  State<_RtspCamera> createState() => _RtspCameraState();
}

class _RtspCameraState extends State<_RtspCamera> {
  late final Player _player = Player();
  // Software decoding: the hardware decoder of many phones cannot open the
  // codec of IP cameras ("Could not open codec").
  late final VideoController _video = VideoController(_player, configuration: const VideoControllerConfiguration(enableHardwareAcceleration: false));
  final List<StreamSubscription<Object?>> _subs = [];
  Timer? _watchdog, _retry;
  String? _lastError;
  String? _error;
  bool _ok = false; // a picture is on screen

  @override
  void initState() {
    super.initState();
    // The player reports many harmless warnings: they are only remembered and
    // judged by the watchdog, they do not restart the stream.
    _subs.add(_player.stream.error.listen((e) => _lastError = e));
    // Several signals, because a stream does not repeat a value it already
    // gave (the size is the same after a reconnect): size, height, or the
    // playback position moving.
    _subs.add(
      _player.stream.width.listen((w) {
        if ((w ?? 0) > 0) _gotPicture();
      }),
    );
    _subs.add(
      _player.stream.height.listen((h) {
        if ((h ?? 0) > 0) _gotPicture();
      }),
    );
    _subs.add(
      _player.stream.position.listen((p) {
        if (p > Duration.zero) _gotPicture();
      }),
    );
    _video.waitUntilFirstFrameRendered.then((_) => _gotPicture());
    _subs.add(
      _player.stream.completed.listen((c) {
        if (c) _fail('Video stream lost.');
      }),
    );
    _open();
  }

  void _gotPicture() {
    _watchdog?.cancel();
    if (_ok && _error == null) return;
    // setState is needed: the spinner is drawn from _ok.
    if (mounted) {
      setState(() {
        _ok = true;
        _error = null;
      });
    } else {
      _ok = true;
    }
  }

  Future<void> _open() async {
    _retry?.cancel();
    _watchdog?.cancel();
    _lastError = null;
    if (mounted) {
      setState(() {
        _ok = false;
        _error = null;
      });
    }
    try {
      // TCP is more reliable than UDP on Wi-Fi; no cache; no sound.
      final platform = _player.platform as dynamic;
      for (final kv in const [('rtsp-transport', 'tcp'), ('cache', 'no'), ('hwdec', 'no')]) {
        try {
          await platform.setProperty(kv.$1, kv.$2);
        } catch (_) {}
      }
      await _player.setVolume(0);
      await _player.open(Media(cameraUrl(widget.cam)), play: true);
      // No picture after 15 s: say why and try again.
      _watchdog = Timer(const Duration(seconds: 15), () {
        if (!_ok) _fail(_describe(_lastError));
      });
    } catch (e) {
      _fail(_describe('$e'));
    }
  }

  static String _describe(String? e) {
    final t = (e ?? '').toLowerCase();
    if (t.contains('codec')) return 'Could not open the video decoder. Choose the H.264 substream in the camera settings.';
    if (t.contains('401') || t.contains('unauthorized') || t.contains('failed to open') || t.contains('connection')) {
      return 'Could not open the stream. Check the IP, port, path and camera account.';
    }
    return (e == null || e.isEmpty) ? 'No picture received from the camera.' : e;
  }

  void _fail(String msg) {
    if (!mounted) return;
    _watchdog?.cancel();
    setState(() => _error = msg);
    _retry?.cancel();
    _retry = Timer(const Duration(seconds: 6), () {
      if (mounted) _open();
    });
  }

  @override
  void dispose() {
    _watchdog?.cancel();
    _retry?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Video(controller: _video, fit: widget.fit, controls: NoVideoControls, fill: Colors.black),
        if (_error != null)
          ColoredBox(
            color: Colors.black54,
            child: _CamMessage(text: '$_error\nRetrying…'),
          )
        else if (!_ok)
          const _CamMessage(loading: true),
      ],
    );
  }
}

// ------------------------------------------------------------------ HTTP

class _HttpCamera extends StatefulWidget {
  const _HttpCamera({required this.cam, required this.fit});
  final Json cam;
  final BoxFit fit;

  @override
  State<_HttpCamera> createState() => _HttpCameraState();
}

class _HttpCameraState extends State<_HttpCamera> {
  _MjpegSource? _src;
  StreamSubscription<Uint8List>? _sub;
  Timer? _retry;
  Uint8List? _frame;
  String? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  void _start() {
    _retry?.cancel();
    _sub?.cancel();
    _src?.close();
    final cam = widget.cam;
    final src = _MjpegSource(Uri.parse(cameraUrl({...cam, 'user': '', 'pass': ''})), (cam['user'] ?? '').toString(), (cam['pass'] ?? '').toString());
    _src = src;
    _sub = src.frames().listen(
      (f) {
        if (mounted) {
          setState(() {
            _frame = f;
            _error = null;
          });
        }
      },
      onError: (Object e) => _fail(_friendly(e)),
      onDone: () => _fail('Camera disconnected.'),
      cancelOnError: true,
    );
  }

  static String _friendly(Object e) {
    if (e is SocketException || e is TimeoutException) return 'Could not connect to the camera. Check the IP, port and Wi-Fi.';
    if (e is HttpException) return 'The camera replied with an error: ${e.message}';
    return '$e';
  }

  void _fail(String msg) {
    if (!mounted) return;
    setState(() => _error = msg);
    _retry?.cancel();
    _retry = Timer(const Duration(seconds: 5), () {
      if (mounted) _start();
    });
  }

  @override
  void dispose() {
    _retry?.cancel();
    _sub?.cancel();
    _src?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final f = _frame;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (f != null) Image.memory(f, fit: widget.fit, gaplessPlayback: true, width: double.infinity, height: double.infinity),
        if (_error != null)
          ColoredBox(
            color: Colors.black54,
            child: _CamMessage(text: '$_error\nRetrying…'),
          )
        else if (f == null)
          const _CamMessage(loading: true),
      ],
    );
  }
}

/// Frames of an HTTP camera: a multipart MJPEG stream, or a single JPEG that
/// is fetched again and again. Handles Basic and Digest (MD5) login.
class _MjpegSource {
  _MjpegSource(this.url, this.user, this.pass);
  final Uri url;
  final String user, pass;

  HttpClient? _client;
  bool _closed = false;
  bool _basic = false;
  Map<String, String>? _digest;
  int _nc = 0;
  final Random _rnd = Random.secure();

  void close() {
    _closed = true;
    _client?.close(force: true);
  }

  Stream<Uint8List> frames() async* {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8)
      ..idleTimeout = const Duration(seconds: 5)
      ..badCertificateCallback = (_, __, ___) => true;
    _client = client;
    try {
      while (!_closed) {
        final res = await _get(client);
        final type = (res.headers.contentType?.mimeType ?? '').toLowerCase();
        if (type.contains('multipart')) {
          yield* _multipart(res);
          if (_closed) break;
          await Future<void>.delayed(const Duration(seconds: 1));
        } else if (type.startsWith('image/')) {
          final b = BytesBuilder(copy: false);
          await for (final c in res) {
            b.add(c);
          }
          final bytes = b.takeBytes();
          if (bytes.isNotEmpty) yield bytes;
          await Future<void>.delayed(const Duration(milliseconds: 700));
        } else {
          await res.drain<void>();
          throw 'The camera returned data that is not an image ($type). Check the path.';
        }
      }
    } finally {
      client.close(force: true);
    }
  }

  Future<HttpClientResponse> _get(HttpClient c) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      final req = await c.getUrl(url);
      req.headers.set(HttpHeaders.userAgentHeader, 'EvoKNX');
      final a = _authorization();
      if (a != null) req.headers.set(HttpHeaders.authorizationHeader, a);
      final res = await req.close().timeout(const Duration(seconds: 10));
      if (res.statusCode == 401 && user.isNotEmpty && attempt == 0) {
        _learn(res.headers[HttpHeaders.wwwAuthenticateHeader]);
        await res.drain<void>();
        if (_digest == null && !_basic) throw 'The camera requires an unsupported authentication method.';
        continue;
      }
      if (res.statusCode == 401) {
        await res.drain<void>();
        throw 'Wrong camera account or password.';
      }
      if (res.statusCode >= 400) {
        await res.drain<void>();
        throw 'The camera reported error ${res.statusCode}. Check the path.';
      }
      return res;
    }
    throw 'Could not sign in to the camera.';
  }

  void _learn(List<String>? headers) {
    _basic = false;
    _digest = null;
    for (final h in headers ?? const <String>[]) {
      final t = h.trim();
      final low = t.toLowerCase();
      if (low.startsWith('digest')) {
        final m = <String, String>{};
        for (final p in RegExp(r'(\w+)=(?:"([^"]*)"|([^\s,]+))').allMatches(t.substring(6))) {
          m[p.group(1)!.toLowerCase()] = p.group(2) ?? p.group(3) ?? '';
        }
        if (m['nonce'] != null) {
          _digest = m;
          _nc = 0;
        }
      } else if (low.startsWith('basic')) {
        _basic = true;
      }
    }
    if (_digest != null) _basic = false;
  }

  String? _authorization() {
    final d = _digest;
    if (d != null) {
      String md5(String s) => crypto.md5.convert(utf8.encode(s)).toString();
      final realm = d['realm'] ?? '', nonce = d['nonce'] ?? '';
      final qop = (d['qop'] ?? '').split(',').map((e) => e.trim()).firstWhere((q) => q == 'auth', orElse: () => '');
      final nc = (++_nc).toRadixString(16).padLeft(8, '0');
      final cnonce = List.generate(8, (_) => _rnd.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
      final path = url.path.isEmpty ? '/' : url.path;
      final uri = url.hasQuery ? '$path?${url.query}' : path;
      final ha1 = md5('$user:$realm:$pass');
      final ha2 = md5('GET:$uri');
      final resp = qop.isEmpty ? md5('$ha1:$nonce:$ha2') : md5('$ha1:$nonce:$nc:$cnonce:$qop:$ha2');
      return 'Digest username="$user", realm="$realm", nonce="$nonce", uri="$uri", response="$resp", algorithm=MD5'
          '${qop.isEmpty ? '' : ', qop=$qop, nc=$nc, cnonce="$cnonce"'}'
          '${d['opaque'] != null ? ', opaque="${d['opaque']}"' : ''}';
    }
    if (_basic) return 'Basic ${base64Encode(utf8.encode('$user:$pass'))}';
    return null;
  }

  /// Cuts JPEG pictures (start FF D8, end FF D9) out of the byte stream.
  Stream<Uint8List> _multipart(HttpClientResponse res) async* {
    var buf = Uint8List(1 << 17);
    var len = 0;
    await for (final chunk in res) {
      if (len + chunk.length > buf.length) {
        final nb = Uint8List(max(buf.length * 2, len + chunk.length));
        nb.setRange(0, len, buf);
        buf = nb;
      }
      buf.setRange(len, len + chunk.length, chunk);
      len += chunk.length;
      while (true) {
        final s = _find(buf, len, 0xD8, 0);
        if (s < 0) {
          if (len > 1) {
            buf[0] = buf[len - 1];
            len = 1;
          }
          break;
        }
        final e = _find(buf, len, 0xD9, s + 2);
        if (e < 0) {
          if (s > 0) {
            buf.setRange(0, len - s, buf, s);
            len -= s;
          }
          if (len > (8 << 20)) len = 0;
          break;
        }
        yield Uint8List.fromList(buf.sublist(s, e + 2));
        buf.setRange(0, len - (e + 2), buf, e + 2);
        len -= e + 2;
      }
    }
  }

  /// Index of the marker 0xFF [second] at or after [from], or -1.
  static int _find(Uint8List b, int len, int second, int from) {
    for (var i = from; i < len - 1; i++) {
      if (b[i] == 0xFF && b[i + 1] == second) return i;
    }
    return -1;
  }
}
