import 'dart:io';

import 'package:flutter/material.dart';

import 'app/app.dart';
import 'state/app_settings.dart';
import 'state/bus_controller.dart';
import 'state/ha_link.dart';
import 'state/card_library.dart';
import 'state/project_controller.dart';

import 'package:evoknx_ui/evoknx_ui.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  await appSettings.load();
  await Mdi.load();
  await cardLibrary.load();
  final project = ProjectController();
  // A project file passed on the command line (double-click on a .evoknx
  // file) opens in this new window.
  String? openPath;
  for (final a in args) {
    if (a.toLowerCase().endsWith('.evoknx') && File(a).existsSync()) openPath = a;
  }
  await project.init(openPath: openPath);
  runApp(EvoknxApp(project: project, bus: BusController(project), ha: HaLinkController()));
}
