import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Size;

import 'package:evoknx_ui/evoknx_ui.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:knx_config/knx_config.dart';
import 'package:path_provider/path_provider.dart';

import 'account.dart';

/// One house the person controls (profile). Named after its project.
class Profile {
  Profile(this.id, this.name, {this.projectId});
  final String id;
  String name;

  /// The Editor project's id, to tell updates of the same house from a new one.
  String? projectId;
}

/// Everything the App keeps on the phone: the configuration from the Editor
/// and the user's own choices (theme, last room, connection, screen on).
class AppStore extends ChangeNotifier {
  /// The signed-in account (sign in, sign up, reset password).
  final AccountStore account = AccountStore();

  Json? config;

  /// Grows each time a configuration is opened (a new home screen starts).
  int configVersion = 0;

  /// Ids of the floors, rooms and pages that were opened with their code. Kept while the App runs
  /// (also in the background); everything is locked again when the App is closed.
  final Set<String> unlocked = {};
  int pinFails = 0;
  DateTime? pinWaitUntil;

  /// Theme chosen on this phone (null = the project's default theme).
  String? themeMode;
  bool keepScreenOn = false;

  /// Text size chosen in the App (0.8–1.5, 1 = as designed in the Editor).
  /// The phone's own font-size setting is ignored: cards sit on a fixed grid.
  double textScale = 1;

  /// Scale text and icons to the phone's screen width (Android phones only).
  bool autoScale = true;
  String? lastRoom, lastSub, connectionId;

  /// The introduction of a new installation was shown (phones that already had the App count as having seen it).
  bool introSeen = true;

  /// "Start at": null (the default of the layout), 'home', 'last' or 'room' (then [startRoom]).
  String? startMode, startRoom;

  /// Last address typed when receiving from the Editor (e.g. 192.168.1.20:47800).
  String? editorAddress;

  final Map<String, Json> _views = {};

  /// One profile per house: the name is the project's name. A person can
  /// control two or three houses from the same phone.
  final List<Profile> profiles = [];
  String? activeId;

  /// Last room, page and connection of each profile (by profile id).
  final Map<String, Map<String, dynamic>> _pp = {};

  Future<File> _file(String name) async {
    final d = await getApplicationDocumentsDirectory();
    return File('${d.path}${Platform.pathSeparator}$name');
  }

  Future<File> _profileFile(String id) => _file('profiles${Platform.pathSeparator}$id.json');

  Future<void> load() async {
    Map? p;
    try {
      final f = await _file('evoknx_prefs.json');
      if (await f.exists()) {
        final o = jsonDecode(await f.readAsString());
        if (o is Map) p = o;
      }
    } catch (_) {}
    if (p != null) {
      themeMode = p['theme'] as String?;
      keepScreenOn = p['keepOn'] == true;
      textScale = ((p['textScale'] as num?) ?? 1).toDouble().clamp(0.8, 1.5).toDouble();
      autoScale = p['autoScale'] != false;
      editorAddress = p['editor'] as String?;
      for (final e in (p['profiles'] as List? ?? const [])) {
        if (e is Map && e['id'] is String) profiles.add(Profile(e['id'] as String, (e['name'] ?? 'EvoKNX').toString(), projectId: e['pid'] as String?));
      }
      activeId = p['active'] as String?;
      final pp = p['profilePrefs'];
      if (pp is Map) {
        for (final e in pp.entries) {
          if (e.value is Map) _pp[e.key.toString()] = (e.value as Map).cast<String, dynamic>();
        }
      }
    }
    // Phones that had the single-configuration version: that configuration
    // becomes the first profile.
    if (profiles.isEmpty) {
      try {
        final f = await _file('evoknx_config.json');
        if (await f.exists()) {
          final o = jsonDecode(await f.readAsString());
          if (isProject(o)) {
            final doc = (o as Map).cast<String, dynamic>();
            final proj = jsonMap(doc['project']);
            final pf = Profile('pf_${DateTime.now().millisecondsSinceEpoch}', (proj['name'] ?? 'EvoKNX').toString(), projectId: proj['id'] as String?);
            await _writeProfile(pf.id, doc);
            profiles.add(pf);
            activeId = pf.id;
            _pp[pf.id] = {'room': p?['room'], 'sub': p?['sub'], 'conn': p?['conn']};
            await f.delete();
          }
        }
      } catch (_) {}
    }
    // A fresh install shows the introduction once; phones that already had the App do not.
    introSeen = p != null ? p['introSeen'] != false : profiles.isNotEmpty;
    if (activeId == null || !profiles.any((x) => x.id == activeId)) activeId = profiles.firstOrNull?.id;
    final act = profiles.where((x) => x.id == activeId).firstOrNull;
    if (act != null) {
      final doc = await _readProfile(act.id);
      if (doc != null) {
        config = doc;
        _restorePrefs(act.id);
      }
    }
    if (config == null && profiles.isNotEmpty) {
      // The active file is missing or damaged: fall back to another profile.
      for (final pf in List.of(profiles)) {
        final doc = await _readProfile(pf.id);
        if (doc != null) {
          activeId = pf.id;
          config = doc;
          _restorePrefs(pf.id);
          break;
        }
        profiles.remove(pf);
      }
    }
  }

  void _restorePrefs(String id) {
    final m = _pp[id] ?? const <String, dynamic>{};
    lastRoom = m['room'] as String?;
    lastSub = m['sub'] as String?;
    connectionId = m['conn'] as String?;
    startMode = m['start'] as String?;
    startRoom = m['startRoom'] as String?;
  }

  Future<Json?> _readProfile(String id) async {
    try {
      final f = await _profileFile(id);
      if (!await f.exists()) return null;
      final o = jsonDecode(await f.readAsString());
      return isProject(o) ? (o as Map).cast<String, dynamic>() : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeProfile(String id, Json doc) async {
    final f = await _profileFile(id);
    await f.parent.create(recursive: true);
    await f.writeAsString(jsonEncode(doc));
  }

  Future<void> savePrefs() async {
    try {
      final id = activeId;
      if (id != null) _pp[id] = {'room': lastRoom, 'sub': lastSub, 'conn': connectionId, 'start': startMode, 'startRoom': startRoom};
      final f = await _file('evoknx_prefs.json');
      await f.writeAsString(
        jsonEncode({
          'theme': themeMode,
          'keepOn': keepScreenOn,
          'textScale': textScale,
          'introSeen': introSeen,
          'autoScale': autoScale,
          'editor': editorAddress,
          'profiles': [
            for (final x in profiles) {'id': x.id, 'name': x.name, 'pid': x.projectId},
          ],
          'active': activeId,
          'profilePrefs': _pp,
        }),
      );
    } catch (_) {}
  }

  /// Picks a configuration file (.json from "Xuất cấu hình", or a .evoknx
  /// project) and keeps it. Returns an error message, '' when cancelled,
  /// or null when loaded.
  Future<String?> importConfig() async {
    final XFile? f;
    try {
      f = await openFile(confirmButtonText: tr('Open'));
    } catch (e) {
      return 'Could not open the file picker: $e';
    }
    if (f == null) return '';
    Object? o;
    try {
      o = jsonDecode(utf8.decode(await f.readAsBytes(), allowMalformed: true));
    } catch (_) {
      return 'The file “${f.name}” is not an EvoKNX project (.evoknx).';
    }
    if (!isProject(o)) return 'The file “${f.name}” is not an EvoKNX project (.evoknx).';
    await adopt((o as Map).cast<String, dynamic>());
    return null;
  }

  /// True when a profile with this project name (ignoring case and extra
  /// spaces) already exists: a file with that name would replace it.
  bool hasProfileNamed(String name) => profiles.any((x) => _key(x.name) == _key(name));

  /// A profile is a house and its name is the project's name: the same name
  /// (ignoring case and extra spaces) is the same house.
  static String _key(String name) => name.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

  /// Keeps a configuration (from a file or received from the Editor) as a
  /// profile and makes it the active one. A configuration with the name of an
  /// existing profile replaces it ("Villa 1" sent again); a new name adds a
  /// new profile ("Villa 2", or "Villa 1" renamed in the Editor).
  /// Returns true when an existing profile was replaced.
  Future<bool> adopt(Json o) async {
    final doc = exportProject(migrate(o));
    final proj = jsonMap(doc['project']);
    final pid = (proj['id'] ?? '').toString();
    final name = (proj['name'] ?? '').toString().trim().isEmpty ? 'EvoKNX' : (proj['name'] as String).trim();
    var pf = profiles.where((x) => _key(x.name) == _key(name)).firstOrNull;
    final updated = pf != null;
    if (pf == null) {
      pf = Profile('pf_${DateTime.now().millisecondsSinceEpoch}', name, projectId: pid);
      profiles.add(pf);
    }
    pf.name = name;
    pf.projectId = pid;
    try {
      await _writeProfile(pf.id, doc);
    } catch (_) {}
    _activate(pf, doc, fresh: !updated);
    await savePrefs();
    notifyListeners();
    return updated;
  }

  void _activate(Profile pf, Json doc, {bool fresh = false}) {
    activeId = pf.id;
    config = doc;
    configVersion++;
    unlocked.clear();
    _views.clear();
    if (fresh) {
      _pp.remove(pf.id);
      lastRoom = null;
      lastSub = null;
      connectionId = null;
    } else {
      _restorePrefs(pf.id);
    }
  }

  /// Switches to another house.
  Future<void> switchProfile(String id) async {
    final pf = profiles.where((x) => x.id == id).firstOrNull;
    if (pf == null || id == activeId) return;
    await savePrefs();
    final doc = await _readProfile(id);
    if (doc == null) {
      profiles.remove(pf);
      await savePrefs();
      notifyListeners();
      return;
    }
    _activate(pf, doc);
    await savePrefs();
    notifyListeners();
  }

  /// Removes a profile from this phone. Deleting the active one switches to
  /// another, or back to the welcome screen when it was the last.
  Future<void> deleteProfile(String id) async {
    final pf = profiles.where((x) => x.id == id).firstOrNull;
    if (pf == null) return;
    try {
      final f = await _profileFile(id);
      if (await f.exists()) await f.delete();
    } catch (_) {}
    profiles.remove(pf);
    _pp.remove(id);
    if (id == activeId) {
      activeId = null;
      config = null;
      configVersion++;
      unlocked.clear();
      _views.clear();
      for (final other in List.of(profiles)) {
        final doc = await _readProfile(other.id);
        if (doc != null) {
          _activate(other, doc);
          break;
        }
        profiles.remove(other);
      }
      if (config == null) {
        lastRoom = null;
        lastSub = null;
        connectionId = null;
      }
    }
    await savePrefs();
    notifyListeners();
  }

  String get projectName => (jsonMap(config?['project'])['name'] ?? 'EvoKNX').toString();

  /// Theme in use: the phone's choice, else the project's default.
  String get mode {
    final m = themeMode ?? (jsonMap(config?['theme'])['mode'] ?? 'light').toString();
    return themeKey(m);
  }

  Future<void> setTheme(String? m) async {
    themeMode = m;
    notifyListeners();
    await savePrefs();
  }

  /// [save] false while the slider is being dragged.
  Future<void> setTextScale(double v, {bool save = true}) async {
    textScale = v.clamp(0.8, 1.5).toDouble();
    notifyListeners();
    if (save) await savePrefs();
  }

  Future<void> setAutoScale(bool v) async {
    autoScale = v;
    notifyListeners();
    await savePrefs();
  }

  /// Factor for text and icons so the screen looks like the Editor preview.
  /// Android phones report widely different logical widths (360–540 dp), so
  /// sizes are scaled by width / 393. iPhones (and tablets) are left as they
  /// are, so the iOS look does not change.
  double uiScaleFor(Size size) {
    if (!autoScale || defaultTargetPlatform != TargetPlatform.android) return 1;
    final w = size.shortestSide;
    if (w >= 600) return 1;
    return (w / EvoScale.phoneDesignWidth).clamp(0.85, 1.7).toDouble();
  }

  Future<void> setKeepScreenOn(bool v) async {
    keepScreenOn = v;
    notifyListeners();
    await savePrefs();
  }

  /// Card palette with the project's card style (corners, border, shadow…).
  AppPalette get palette {
    final t = jsonMap(config?['theme']);
    double n(String k, double d, double lo, double hi) => ((t[k] as num?) ?? d).toDouble().clamp(lo, hi).toDouble();
    return AppPalette.of(mode).copyWith(
      radius: n('cardRadius', 12, 0, 32),
      border: n('cardBorder', 1, 0, 4),
      shadow: n('cardShadow', 0, 0, 20),
      tileOpacity: n('cardOpacity', 100, 0, 100) / 100,
      edgeOpacity: n('cardEdge', 100, 0, 100) / 100,
      lift: liftOf(n('btnRaise', 60, 0, 100)),
    );
  }

  bool hasLayout(String dev) => dev == 'mobile' || jsonMap(config?['devices'])[dev] == true;

  /// The configuration laid out for a device (mobile, tabletP, tabletL).
  Json view(String dev) {
    final c = config!;
    if (dev == 'mobile') return c;
    return _views.putIfAbsent(dev, () {
      final copy = (jsonDecode(jsonEncode(c)) as Map).cast<String, dynamic>();
      swapDevice(copy, dev);
      return copy;
    });
  }

  List<Json> get connections => jsonList(config?['connections']);

  Json? get connection {
    final list = connections;
    return list.where((x) => x['id'] == connectionId).firstOrNull ?? list.firstOrNull;
  }

  Future<void> setConnection(String id) async {
    connectionId = id;
    notifyListeners();
    await savePrefs();
  }

  Future<void> markIntroSeen() async {
    introSeen = true;
    notifyListeners();
    await savePrefs();
  }

  Future<void> setStart(String? mode, [String? room]) async {
    startMode = mode;
    startRoom = mode == 'room' ? room : null;
    notifyListeners();
    await savePrefs();
  }

  void remember(String? room, String? sub) {
    if (room == lastRoom && sub == lastSub) return;
    lastRoom = room;
    lastSub = sub;
    savePrefs();
  }
}
