import 'package:evoknx_ui/evoknx_ui.dart' show LangScope, appLang;
import 'package:flutter/material.dart';

import '../state/app_settings.dart';
import '../state/bus_controller.dart';
import '../state/ha_link.dart';
import '../state/project_controller.dart';
import '../ui/shell.dart';
import 'theme.dart';

class EvoknxApp extends StatelessWidget {
  const EvoknxApp({super.key, required this.project, required this.bus, required this.ha});
  final ProjectController project;
  final BusController bus;
  final HaLinkController ha;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appSettings,
      builder: (context, _) => LangScope(
        lang: appLang,
        child: MaterialApp(
          key: ValueKey(appLang.code),
          title: 'EvoKNX Editor',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(Brightness.light),
          darkTheme: buildTheme(Brightness.dark),
          themeMode: appSettings.themeMode,
          home: Shell(project: project, bus: bus, ha: ha),
        ),
      ),
    );
  }
}
