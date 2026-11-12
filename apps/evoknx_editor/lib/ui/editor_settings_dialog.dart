import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:evoknx_ui/evoknx_ui.dart' show Text, tr;

import '../app/theme.dart';
import '../state/app_settings.dart';
import 'common.dart';

/// ⚙ Cài đặt Editor: theme, autosave, default folder, about.
class EditorSettingsDialog extends StatelessWidget {
  const EditorSettingsDialog({super.key});

  static Future<void> show(BuildContext context) => showDialog<void>(context: context, builder: (_) => const EditorSettingsDialog());

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appSettings,
      builder: (context, _) {
        final c = context.evo;
        Widget section(String title, List<Widget> children) => Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                style: TextStyle(fontSize: kUiText, fontWeight: FontWeight.w600, color: c.muted),
              ),
              const SizedBox(height: 10),
              ...children,
            ],
          ),
        );
        final folder = appSettings.defaultFolder;
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.settings_outlined, color: c.accent),
              const SizedBox(width: 10),
              const Text('Editor settings', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ],
          ),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  section('Appearance', [
                    Seg<ThemeMode>(
                      items: const [(ThemeMode.light, 'Light'), (ThemeMode.dark, 'Dark')],
                      value: appSettings.themeMode,
                      onChanged: appSettings.setThemeMode,
                    ),
                  ]),
                  section('Auto-save to the project file', [
                    EvoDropdown<int>(
                      value: appSettings.autosaveMinutes,
                      items: const [(0, 'Off'), (1, 'Every 1 minute'), (2, 'Every 2 minutes'), (5, 'Every 5 minutes'), (10, 'Every 10 minutes')],
                      onChanged: appSettings.setAutosaveMinutes,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Applies only to projects saved as a file. The Editor also silently backs up the working session, so if the computer shuts down suddenly the project is intact the next time you open it.',
                      style: TextStyle(fontSize: 13.5, color: c.muted),
                    ),
                  ]),
                  section('Default save folder', [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: c.paper,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: c.line),
                      ),
                      child: Text(
                        folder ?? 'Not set (use the folder suggested by Windows)',
                        style: TextStyle(fontSize: kUiText, color: folder == null ? c.muted : c.ink),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        EvoButton(
                          label: 'Select folder',
                          icon: Icons.folder_open_outlined,
                          small: true,
                          onPressed: () async {
                            final d = await getDirectoryPath(initialDirectory: folder, confirmButtonText: tr('Select'));
                            if (d != null) await appSettings.setDefaultFolder(d);
                          },
                        ),
                        const SizedBox(width: 8),
                        if (folder != null) EvoButton(label: 'Deselect', small: true, onPressed: () => appSettings.setDefaultFolder(null)),
                      ],
                    ),
                  ]),
                  section('About', [
                    Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: c.led,
                            shape: BoxShape.circle,
                            boxShadow: [BoxShadow(color: c.led.withValues(alpha: 0.25), spreadRadius: 3)],
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Text('EvoKNX Editor', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                        const SizedBox(width: 8),
                        Text('version $kEditorVersion', style: TextStyle(color: c.muted)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Design tool for KNX smart-home control interfaces.\n© ${DateTime.now().year} Evohome. All rights reserved.\n\nIcons: Material Design Icons by Pictogrammers, Apache 2.0 license.\nFont: Inter by Rasmus Andersson, SIL Open Font License.',
                      style: TextStyle(fontSize: kUiText, color: c.muted),
                    ),
                  ]),
                ],
              ),
            ),
          ),
          actions: [EvoButton(label: 'Close', primary: true, onPressed: () => Navigator.pop(context))],
        );
      },
    );
  }
}
