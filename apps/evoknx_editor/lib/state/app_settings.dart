import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

/// Version shown in Settings → Giới thiệu.
const String kEditorVersion = '0.4.0';

/// Editor preferences (stored in the app data folder, not in projects).
class AppSettings extends ChangeNotifier {
  ThemeMode themeMode = ThemeMode.light;

  /// Automatic save into the project file, in minutes (0 = off).
  int autosaveMinutes = 5;

  /// Folder suggested by "Lưu thành" for projects that have no file yet.
  String? defaultFolder;

  static const List<int> autosaveChoices = [0, 1, 2, 5, 10];

  /// History copies (made by Ctrl+S): days to keep (0 = forever) and whether
  /// days older than a week keep only their last copy.
  /// Show the explanatory text under fields in the properties panel.

  int historyKeepDays = 90;
  bool historyThin = true;
  static const List<int> historyChoices = [30, 90, 180, 365, 0];

  Future<File> _file() async {
    final d = await getApplicationSupportDirectory();
    return File('${d.path}${Platform.pathSeparator}settings.json');
  }

  Future<void> load() async {
    try {
      final f = await _file();
      if (!await f.exists()) return;
      final j = jsonDecode(await f.readAsString());
      if (j is! Map) return;
      themeMode = switch (j['theme']) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.light,
      };
      final a = (j['autosaveMinutes'] as num?)?.toInt();
      if (a != null && autosaveChoices.contains(a)) autosaveMinutes = a;
      final hk = (j['historyKeepDays'] as num?)?.toInt();
      if (hk != null && historyChoices.contains(hk)) historyKeepDays = hk;
      if (j['historyThin'] is bool) historyThin = j['historyThin'] as bool;
      final dir = j['defaultFolder'];
      if (dir is String && dir.isNotEmpty) defaultFolder = dir;
    } catch (_) {}
  }

  Future<void> _persist() async {
    try {
      final f = await _file();
      await f.parent.create(recursive: true);
      await f.writeAsString(
        jsonEncode({
          'theme': themeMode.name,
          'autosaveMinutes': autosaveMinutes,
          'defaultFolder': defaultFolder,
          'historyKeepDays': historyKeepDays,
          'historyThin': historyThin,
        }),
      );
    } catch (_) {}
  }

  Future<void> setThemeMode(ThemeMode m) async {
    themeMode = m == ThemeMode.dark ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();
    await _persist();
  }

  Future<void> setAutosaveMinutes(int m) async {
    autosaveMinutes = autosaveChoices.contains(m) ? m : 5;
    notifyListeners();
    await _persist();
  }

  Future<void> setHistory({int? keepDays, bool? thin}) async {
    if (keepDays != null && historyChoices.contains(keepDays)) historyKeepDays = keepDays;
    if (thin != null) historyThin = thin;
    notifyListeners();
    await _persist();
  }

  Future<void> setDefaultFolder(String? path) async {
    defaultFolder = (path == null || path.isEmpty) ? null : path;
    notifyListeners();
    await _persist();
  }
}

final AppSettings appSettings = AppSettings();
