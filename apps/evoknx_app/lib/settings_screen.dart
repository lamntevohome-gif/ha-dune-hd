import 'package:evoknx_ui/evoknx_ui.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart' hide Text;
import 'package:knx_config/knx_config.dart';

import 'account_panel.dart';
import 'app_store.dart';
import 'knx_link.dart';
import 'receive_dialog.dart';

/// Settings: theme, KNX connection, another configuration, about.
/// "Floor › Room" of a room, or a hint when none is chosen.
String _roomLabel(Json cfg, String? id) {
  for (final f in floorsOf(cfg)) {
    for (final r in roomsOf(cfg, f['id'] as String)) {
      if (r['id'] == id) return '${f['title']} › ${r['title']}';
    }
  }
  return 'Choose a room';
}

/// A list of all the rooms of the project to choose the room to start at.
Future<String?> _pickRoom(BuildContext context, Json cfg) => showDialog<String>(
  context: context,
  builder: (c) => SimpleDialog(
    title: const Text('Choose a room'),
    children: [
      for (final f in floorsOf(cfg))
        for (final r in roomsOf(cfg, f['id'] as String))
          SimpleDialogOption(onPressed: () => Navigator.pop(c, r['id'] as String), child: Text('${f['title']} › ${r['title']}')),
    ],
  ),
);

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.store, required this.knx, this.ha});
  final AppStore store;
  final KnxLink knx;

  /// Link to Home Assistant (null when the project does not use it).
  final HaBridge? ha;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([store, knx]),
      builder: (context, _) {
        final pal = AppPalette.of(store.mode);
        Widget card(String title, List<Widget> rows) => Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 6, bottom: 6),
                child: Text(
                  title.toUpperCase(),
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, letterSpacing: 0.4, color: pal.sMuted),
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  color: pal.tile,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: pal.tileEdge),
                ),
                child: Column(
                  children: [
                    for (var i = 0; i < rows.length; i++) ...[rows[i], if (i < rows.length - 1) Divider(height: 1, indent: 16, color: pal.line)],
                  ],
                ),
              ),
            ],
          ),
        );
        Widget tab(List<Widget> cards) => ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 28), children: cards);
        Widget row(Widget leading, String text, {String? sub, Widget? trailing, VoidCallback? onTap}) => InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                leading,
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(text, style: TextStyle(fontSize: 16, color: pal.ink)),
                      if (sub != null) ...[const SizedBox(height: 2), Text(sub, style: TextStyle(fontSize: 13, color: pal.muted))],
                    ],
                  ),
                ),
                if (trailing != null) trailing,
              ],
            ),
          ),
        );
        final conns = store.connections;
        final cur = store.connection;
        return Theme(
          data: ThemeData(
            brightness: pal.sInk.computeLuminance() > 0.5 ? Brightness.dark : Brightness.light,
            fontFamily: kEvoFont,
            useMaterial3: true,
            colorSchemeSeed: pal.accent,
          ),
          child: DefaultTabController(
            length: 5,
            child: Scaffold(
              backgroundColor: pal.screen,
              appBar: AppBar(
                backgroundColor: pal.screen,
                foregroundColor: pal.sInk,
                elevation: 0,
                scrolledUnderElevation: 0,
                title: Text(
                  'Settings',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: pal.sInk),
                ),
                bottom: TabBar(
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  indicatorColor: pal.accent,
                  labelColor: pal.sInk,
                  unselectedLabelColor: pal.sMuted,
                  dividerColor: pal.line,
                  labelStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  unselectedLabelStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                  tabs: [
                    Tab(text: tr('Account')),
                    Tab(text: tr('Profile')),
                    Tab(text: tr('Appearance')),
                    Tab(text: tr('Connections')),
                    Tab(text: tr('About')),
                  ],
                ),
              ),
              body: TabBarView(
                children: [
                  tab([AccountPanel(account: store.account, pal: pal)]),
                  tab([
                    card('Profile', [
                      for (final pf in store.profiles)
                        row(
                          Icon(pf.id == store.activeId ? Icons.home : Icons.home_outlined, color: pf.id == store.activeId ? pal.accent : pal.muted),
                          pf.name,
                          sub: pf.id == store.activeId
                              ? 'In use · configuration version ${jsonMap(store.config?['project'])['revision'] ?? 0}'
                              : 'Tap to switch to this home',
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (pf.id != store.activeId)
                                TextButton(
                                  onPressed: () async {
                                    await store.switchProfile(pf.id);
                                    if (context.mounted) Navigator.of(context).popUntil((x) => x.isFirst);
                                  },
                                  child: Text(
                                    'Switch',
                                    style: TextStyle(color: pal.accent, fontWeight: FontWeight.w600),
                                  ),
                                ),
                              PopupMenuButton<String>(
                                tooltip: tr('Options'),
                                icon: Icon(Icons.more_vert, color: pal.muted),
                                color: pal.panel,
                                onSelected: (v) async {
                                  if (v != 'del') return;
                                  final ok = await showDialog<bool>(
                                    context: context,
                                    builder: (c) => AlertDialog(
                                      title: Text('Delete the profile “${pf.name}”?'),
                                      content: const Text(
                                        'This home\'s configuration will be removed from the phone. You can add it again from EvoKNX Editor.',
                                      ),
                                      actions: [
                                        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
                                        TextButton(
                                          onPressed: () => Navigator.pop(c, true),
                                          child: Text('Delete', style: TextStyle(color: pal.danger)),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (ok != true) return;
                                  final wasActive = pf.id == store.activeId;
                                  await store.deleteProfile(pf.id);
                                  if (wasActive && context.mounted) Navigator.of(context).popUntil((x) => x.isFirst);
                                },
                                itemBuilder: (_) => [
                                  PopupMenuItem(
                                    value: 'del',
                                    child: Text('Delete profile', style: TextStyle(color: pal.danger)),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          onTap: pf.id == store.activeId
                              ? null
                              : () async {
                                  await store.switchProfile(pf.id);
                                  if (context.mounted) Navigator.of(context).popUntil((x) => x.isFirst);
                                },
                        ),
                      row(
                        Icon(Icons.wifi_tethering, color: pal.muted),
                        'Add a profile from the computer (Wi-Fi)',
                        sub: 'Editor → EvoKNX menu → Send to App over Wi-Fi',
                        onTap: () async {
                          final before = store.profiles.length;
                          final ok = await showReceiveDialog(context, store, pal);
                          if (!ok || !context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                store.profiles.length > before
                                    ? 'Added the profile “${store.projectName}”.'
                                    : 'The profile “${store.projectName}” was updated.',
                              ),
                            ),
                          );
                          Navigator.of(context).popUntil((x) => x.isFirst);
                        },
                      ),
                      row(
                        Icon(Icons.folder_open_outlined, color: pal.muted),
                        'Add a profile from a configuration file',
                        sub: '.evoknx file sent from the computer. Or from a messaging app or Drive: Share → EvoKNX. A project with the same name replaces that profile.',
                        onTap: () async {
                          final before = store.profiles.length;
                          final r = await store.importConfig();
                          if (!context.mounted) return;
                          if (r != null && r.isNotEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(r)));
                          } else if (r == null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  store.profiles.length > before
                                      ? 'Added the profile “${store.projectName}”.'
                                      : 'The profile “${store.projectName}” was updated.',
                                ),
                              ),
                            );
                            Navigator.of(context).popUntil((x) => x.isFirst);
                          }
                        },
                      ),
                    ]),
                  ]),
                  tab([
                    // What the App shows when it opens (kept for each profile on this device).
                    () {
                      final cfg = store.config ?? const <String, dynamic>{};
                      final modern = jsonMap(cfg['theme'])['layout'] == 'modern';
                      final cur = store.startMode ?? (modern ? 'home' : 'last');
                      return card('Start at', [
                        for (final (mode, name) in [if (modern) ('home', 'Home'), ('last', 'Last viewed'), ('room', 'Fixed room')])
                          row(
                            Icon(mode == 'room' ? Icons.push_pin_outlined : (mode == 'home' ? Icons.home_outlined : Icons.history), color: pal.muted),
                            name,
                            sub: mode == 'room' && cur == 'room' ? _roomLabel(cfg, store.startRoom) : null,
                            trailing: cur == mode ? Icon(Icons.check, color: pal.accent) : null,
                            onTap: () async {
                              if (mode != 'room') {
                                store.setStart(mode);
                                return;
                              }
                              final id = await _pickRoom(context, cfg);
                              if (id != null) store.setStart('room', id);
                            },
                          ),
                      ]);
                    }(),
                    card('Appearance', [
                      // Three groups (Sáng, Trung tính, Tối): tap one to show its three themes.
                      for (final (group, items) in kAppThemeGroups)
                        Theme(
                          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                          child: ExpansionTile(
                            key: PageStorageKey('theme-group-$group'),
                            initiallyExpanded: items.any((t) => t.$1 == store.mode),
                            tilePadding: const EdgeInsets.symmetric(horizontal: 16),
                            childrenPadding: EdgeInsets.zero,
                            iconColor: pal.muted,
                            collapsedIconColor: pal.muted,
                            shape: const Border(),
                            collapsedShape: const Border(),
                            title: Text(
                              group,
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: pal.ink),
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Row(
                                children: [
                                  for (final (k, _) in items) ...[ThemeSwatch(AppPalette.of(k), size: 22), const SizedBox(width: 6)],
                                ],
                              ),
                            ),
                            children: [
                              for (final (k, n) in items)
                                row(
                                  ThemeSwatch(AppPalette.of(k)),
                                  n,
                                  sub: k == themeKey(jsonMap(store.config?['theme'])['mode']) ? 'Project default' : null,
                                  trailing: k == store.mode ? Icon(Icons.check, color: pal.accent) : null,
                                  onTap: () => store.setTheme(k),
                                ),
                            ],
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.format_size, color: pal.muted),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Text('Font size', style: TextStyle(fontSize: 16, color: pal.ink)),
                                ),
                                Text(
                                  '${(store.textScale * 100).round()}%',
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: pal.accent),
                                ),
                              ],
                            ),
                            Slider(
                              value: store.textScale,
                              min: 0.8,
                              max: 1.5,
                              divisions: 14,
                              activeColor: pal.accent,
                              onChanged: (v) => store.setTextScale(v, save: false),
                              onChangeEnd: (v) => store.setTextScale(v),
                            ),
                            Text(
                              '100% is the font size designed in the Editor. It does not depend on the phone\'s font size.',
                              style: TextStyle(fontSize: 13, color: pal.muted),
                            ),
                          ],
                        ),
                      ),
                      if (defaultTargetPlatform == TargetPlatform.android)
                        row(
                          Icon(Icons.aspect_ratio, color: pal.muted),
                          'Auto-scale the font to the screen',
                          sub:
                              'Screen ${MediaQuery.sizeOf(context).width.round()} × ${MediaQuery.sizeOf(context).height.round()} dp · scale ${store.uiScaleFor(MediaQuery.sizeOf(context)).toStringAsFixed(2)}',
                          trailing: Switch(value: store.autoScale, onChanged: store.setAutoScale, activeColor: pal.accent),
                        ),
                      row(
                        Icon(Icons.screen_lock_portrait_outlined, color: pal.muted),
                        'Keep the screen on',
                        sub: 'For wall-mounted tablets',
                        trailing: Switch(value: store.keepScreenOn, onChanged: store.setKeepScreenOn, activeColor: pal.accent),
                      ),
                    ]),
                  ]),
                  tab([
                    card('KNX', [
                      for (final c in conns)
                        row(
                          Icon(Icons.router_outlined, color: pal.muted),
                          (c['name'] ?? 'Connections').toString(),
                          sub: '${c['host'] ?? ''}:${c['port'] ?? 3671}${c['natMode'] == true ? ' · NAT' : ''}',
                          trailing: c == cur ? Icon(Icons.check, color: pal.accent) : null,
                          onTap: conns.length > 1
                              ? () async {
                                  await store.setConnection(c['id'] as String);
                                  await knx.connect();
                                }
                              : null,
                        ),
                      row(
                        Icon(knx.connected ? Icons.link : Icons.link_off, color: knx.connected ? pal.accent : pal.muted),
                        knx.statusText,
                        trailing: TextButton(onPressed: knx.connect, child: Text(knx.connected ? 'Reconnect' : 'Retry')),
                      ),
                    ]),
                    // Home Assistant: set up in the Editor ("HA" tab), only its state is shown here.
                    if (ha != null)
                      card('Home Assistant', [
                        row(Icon(ha!.connected ? Icons.link : Icons.link_off, color: ha!.connected ? pal.accent : pal.muted), switch (ha!.state) {
                          HaConnection.connected => 'Connected to Home Assistant',
                          HaConnection.connecting => 'Connecting to Home Assistant…',
                          HaConnection.failed => ha!.error ?? 'Home Assistant connection lost',
                          HaConnection.disconnected => 'Home Assistant not connected',
                        }, sub: ha!.url),
                      ]),
                  ]),
                  tab([
                    card('About', [
                      row(Icon(Icons.info_outline, color: pal.muted), 'EvoKNX', sub: 'Version 0.1.0 · © ${DateTime.now().year} Evohome'),
                      row(Icon(Icons.palette_outlined, color: pal.muted), 'Icon', sub: 'Material Design Icons · Pictogrammers (Apache 2.0)'),
                      row(Icon(Icons.text_fields, color: pal.muted), 'Font', sub: 'Inter · Rasmus Andersson (SIL Open Font License)'),
                    ]),
                  ]),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
