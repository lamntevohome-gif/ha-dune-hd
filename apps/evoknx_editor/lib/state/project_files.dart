import 'dart:io';

/// Project folder layout and save history (pure Dart, no Flutter).
///
///   <Tên dự án>/
///     <Tên dự án>.evoknx                         file chính
///     <Tên dự án> 2026-11-01/                    folder ngày
///       <Tên dự án> 2026-11-01 21-03-40.evoknx   bản lịch sử (Ctrl+S)
///
/// Dates follow ISO 8601 (year-month-day) so Windows sorts them in time
/// order; ':' is not allowed in file names, so times use '-'.

final String _sep = Platform.pathSeparator;

String two(int v) => v.toString().padLeft(2, '0');
String dayStamp(DateTime t) => '${t.year}-${two(t.month)}-${two(t.day)}';
String timeStamp(DateTime t) => '${two(t.hour)}-${two(t.minute)}-${two(t.second)}';

/// A Windows-safe file/folder name that keeps Vietnamese letters.
String safeName(String s) {
  var r = s.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '-').replaceAll(RegExp(r'\s+'), ' ').trim();
  r = r.replaceAll(RegExp(r'[. ]+$'), '');
  if (r.length > 80) r = r.substring(0, 80).trim();
  const reserved = {'CON', 'PRN', 'AUX', 'NUL', 'COM1', 'COM2', 'COM3', 'COM4', 'LPT1', 'LPT2', 'LPT3'};
  if (r.isEmpty || reserved.contains(r.toUpperCase())) r = 'EvoKNX project';
  return r;
}

String baseName(String p) => p.split(RegExp(r'[\\/]')).where((x) => x.isNotEmpty).last;
String dirName(String p) {
  final i = p.lastIndexOf(RegExp(r'[\\/]'));
  return i <= 0 ? p : p.substring(0, i);
}

String stem(String p) => baseName(p).replaceAll(RegExp(r'\.evoknx$', caseSensitive: false), '');

/// From the path chosen in the Save dialog, the project folder and main file.
/// Picking a file inside an existing folder of the same name reuses it.
({String dir, String main}) projectLocation(String chosenPath) {
  final parent = dirName(chosenPath);
  final name = safeName(stem(chosenPath));
  final dir = baseName(parent) == name ? parent : '$parent$_sep$name';
  return (dir: dir, main: '$dir$_sep$name.evoknx');
}

/// True when [mainPath] already sits in its own project folder.
bool isProjectLayout(String mainPath) => baseName(dirName(mainPath)) == stem(mainPath);

/// Where the history copy of a manual save goes.
String snapshotPath(String mainPath, String projectName, DateTime t) {
  final n = safeName(projectName);
  final d = dayStamp(t);
  return '${dirName(mainPath)}$_sep$n $d$_sep$n $d ${timeStamp(t)}.evoknx';
}

final _dayDir = RegExp(r'^(.+) (\d{4})-(\d{2})-(\d{2})$');
final _snapFile = RegExp(r'^(.+) (\d{4})-(\d{2})-(\d{2}) (\d{2})-(\d{2})-(\d{2})$');

/// If [path] is a history copy, its project's main file and the save time.
({String main, DateTime at})? snapshotInfo(String path) {
  final f = _snapFile.firstMatch(stem(path));
  final dayDir = dirName(path);
  if (f == null || _dayDir.firstMatch(baseName(dayDir)) == null) return null;
  final projDir = dirName(dayDir);
  final main = '$projDir$_sep${baseName(projDir)}.evoknx';
  if (!File(main).existsSync()) return null;
  final at = DateTime(int.parse(f[2]!), int.parse(f[3]!), int.parse(f[4]!), int.parse(f[5]!), int.parse(f[6]!), int.parse(f[7]!));
  return (main: main, at: at);
}

/// Cleans old history in [projectDir]:
/// - day folders older than [keepDays] are removed (0 = keep forever);
/// - with [thin], days older than [thinAfterDays] keep only their last save.
/// Only history files are deleted; the main file is never touched.
Future<int> pruneHistory(String projectDir, {required int keepDays, required bool thin, int thinAfterDays = 7, DateTime? now}) async {
  final today = now ?? DateTime.now();
  final d0 = DateTime(today.year, today.month, today.day);
  var removed = 0;
  final dir = Directory(projectDir);
  if (!await dir.exists()) return 0;
  await for (final e in dir.list()) {
    if (e is! Directory) continue;
    final m = _dayDir.firstMatch(baseName(e.path));
    if (m == null) continue;
    final day = DateTime(int.parse(m[2]!), int.parse(m[3]!), int.parse(m[4]!));
    final age = d0.difference(day).inDays;
    final snaps = <File>[];
    await for (final f in e.list()) {
      if (f is File && f.path.toLowerCase().endsWith('.evoknx') && _snapFile.hasMatch(stem(f.path))) snaps.add(f);
    }
    snaps.sort((a, b) => stem(a.path).substring(stem(a.path).length - 8).compareTo(stem(b.path).substring(stem(b.path).length - 8)));
    final List<File> toDelete;
    if (keepDays > 0 && age > keepDays) {
      toDelete = snaps;
    } else if (thin && age > thinAfterDays && snaps.length > 1) {
      toDelete = snaps.sublist(0, snaps.length - 1);
    } else {
      continue;
    }
    for (final f in toDelete) {
      try {
        await f.delete();
        removed++;
      } catch (_) {}
    }
    try {
      if (await e.list().isEmpty) await e.delete();
    } catch (_) {}
  }
  return removed;
}
