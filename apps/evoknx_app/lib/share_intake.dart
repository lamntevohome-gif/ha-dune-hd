import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:evoknx_ui/evoknx_ui.dart' show Text;
import 'package:flutter/services.dart';
import 'package:knx_config/knx_config.dart';

import 'app_store.dart';

/// Takes a project file (.evoknx) that is shared to the App ("Chia sẻ →
/// EvoKNX" from Zalo, Drive, a file manager…) or opened with it. The Android
/// side (MainActivity.kt) copies the file to the cache and tells Dart its path.
class ShareIntake {
  ShareIntake(this.store, this.navigator);
  final AppStore store;
  final GlobalKey<NavigatorState> navigator;

  static const MethodChannel _ch = MethodChannel('evoknx/share');
  bool _busy = false;

  /// Starts listening (App already open) and picks up the file the App was
  /// started with (App was closed).
  void start() {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    _ch.setMethodCallHandler((call) async {
      if (call.method == 'sharedFile' && call.arguments is String) await _take(call.arguments as String);
      return null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final path = await _ch.invokeMethod<String>('initialFile');
        if (path != null) await _take(path);
      } on MissingPluginException {
        // Not the Android build: nothing to do.
      } catch (_) {}
    });
  }

  void _say(String text) {
    final ctx = navigator.currentContext;
    if (ctx != null) ScaffoldMessenger.maybeOf(ctx)?.showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _take(String path) async {
    if (_busy) return;
    _busy = true;
    try {
      Object? o;
      try {
        o = jsonDecode(utf8.decode(await File(path).readAsBytes(), allowMalformed: true));
      } catch (_) {
        _say('The shared file is not an EvoKNX project (.evoknx).');
        return;
      }
      if (!isProject(o)) {
        _say('The shared file is not an EvoKNX project (.evoknx).');
        return;
      }
      final doc = (o as Map).cast<String, dynamic>();
      final name = (jsonMap(doc['project'])['name'] ?? 'EvoKNX').toString();
      final exists = store.hasProfileNamed(name);
      final ctx = navigator.currentContext;
      if (ctx == null) return;
      final ok = await showDialog<bool>(
        context: ctx,
        builder: (c) => AlertDialog(
          title: Text(exists ? 'Replace the profile “$name”?' : 'Add the profile “$name”?'),
          content: Text(
            exists
                ? 'A profile with the same name already exists. The new configuration will replace the old one of that profile.'
                : 'The new profile will be added and opened right away.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(c, true), child: Text(exists ? 'Replace' : 'Add')),
          ],
        ),
      );
      if (ok != true) return;
      final replaced = await store.adopt(doc);
      _say(replaced ? 'The profile “$name” was updated.' : 'Added the profile “$name”.');
    } finally {
      _busy = false;
      try {
        await File(path).delete();
      } catch (_) {}
    }
  }
}
