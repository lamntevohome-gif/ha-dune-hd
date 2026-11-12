import 'dart:convert';
import 'dart:math';
import 'dart:ui' show ImageFilter, PointerDeviceKind, TileMode;

import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart' show HardwareKeyboard;
import 'package:knx_config/knx_config.dart';

import '../../app/theme.dart';
import '../common.dart';
import 'designer.dart';

import 'package:evoknx_ui/evoknx_ui.dart';

const Map<String, Size> kDeviceSize = {'mobile': Size(393, 852), 'tabletP': Size(820, 1180), 'tabletL': Size(1180, 820)};

double tabletScale(Json doc) {
  final v = (jsonMap(doc['theme'])['tabletScale'] as num?)?.toInt() ?? 120;
  return (v >= 100 && v <= 150 ? v : 120) / 100;
}

/// The simulated phone/tablet screen with the editable grid.
class DesignCanvas extends StatelessWidget {
  const DesignCanvas({super.key, required this.d, required this.issues});
  final Designer d;
  final List<Issue> issues;

  @override
  Widget build(BuildContext context) {
    final doc = d.doc;
    final dev = (doc['activeDev'] as String?) ?? 'mobile';
    final size = kDeviceSize[dev] ?? kDeviceSize['mobile']!;
    final mode = d.previewTheme ?? (jsonMap(doc['theme'])['mode'] ?? 'light').toString();
    final base = AppPalette.of(mode);
    final bg = screenBackground(doc, base);
    final th = jsonMap(doc['theme']);
    // The open page may have its own background over the common one.
    final pageBg = d.view == 'room' ? pageBackground(d.sub, bg, th) : null;
    final pal = base.copyWith(
      onScreenInk: (pageBg ?? bg).ink,
      onScreenMuted: (pageBg ?? bg).muted,
      tileOpacity: ((th['cardOpacity'] as num?) ?? 100).toDouble().clamp(0, 100) / 100,
      edgeOpacity: ((th['cardEdge'] as num?) ?? 100).toDouble().clamp(0, 100) / 100,
      radius: ((th['cardRadius'] as num?) ?? 12).toDouble().clamp(0, 32).toDouble(),
      border: ((th['cardBorder'] as num?) ?? 1).toDouble().clamp(0, 4).toDouble(),
      shadow: ((th['cardShadow'] as num?) ?? 0).toDouble().clamp(0, 20).toDouble(),
      lift: liftOf(((th['btnRaise'] as num?) ?? 60).toDouble().clamp(0, 100)),
    );
    final tablet = dev != 'mobile';
    final scale = tablet ? tabletScale(doc) : 1.0;
    final logical = Size(size.width / scale, size.height / scale);
    final ec = context.evo;
    final roomName = (d.room?['title'] ?? '').toString();
    final subName = (d.sub?['title'] ?? '').toString();
    final frameName = switch (d.view) {
      'overview' => 'Overview',
      'floor' => (d.floor?['title'] ?? '').toString(),
      _ => [roomName, if (subsOf(d.room ?? const {}).length > 1) subName].where((x) => x.isNotEmpty).join(' · '),
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      child: Column(
        children: [
          // Frame name and screen size, like a frame label in design tools.
          SizedBox(
            height: 22,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(frameName, style: TextStyle(fontSize: 13, color: ec.muted)),
                const SizedBox(width: 8),
                Text('${size.width.round()} × ${size.height.round()}', style: TextStyle(fontSize: 13, color: ec.lineStrong)),
              ],
            ),
          ),
          Expanded(
            child: FittedBox(
              fit: BoxFit.contain,
              child: Container(
                width: size.width + 12,
                height: size.height + 12,
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E),
                  borderRadius: BorderRadius.circular(tablet ? 26 : 44),
                  boxShadow: const [BoxShadow(color: Color(0x1F000000), blurRadius: 18, offset: Offset(0, 6))],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(tablet ? 20 : 38),
                  child: DecoratedBox(
                    decoration: bg.decoration,
                    child: FittedBox(
                      child: SizedBox(
                        width: logical.width,
                        height: logical.height,
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 280),
                                child: pageBg == null
                                    ? const SizedBox.expand(key: ValueKey('page-bg-none'))
                                    : ClipRect(
                                        key: ValueKey('page-bg-${pageBg.key}'),
                                        child: ImageFiltered(
                                          enabled: pageBg.blur > 0,
                                          imageFilter: ImageFilter.blur(sigmaX: pageBg.blur, sigmaY: pageBg.blur, tileMode: TileMode.clamp),
                                          child: DecoratedBox(decoration: pageBg.decoration, child: const SizedBox.expand()),
                                        ),
                                      ),
                              ),
                            ),
                            Positioned.fill(
                              child: ScrollConfiguration(
                                behavior: const _DragScroll(),
                                child: _Screen(d: d, pal: pal, issues: issues, size: logical, dev: dev),
                              ),
                            ),
                            if (d.popupFor != null && d.test)
                              Positioned.fill(
                                child: _ScenePopup(d: d, w: d.popupFor!, pal: pal),
                              ),
                            if (d.appSettingsOpen)
                              Positioned.fill(
                                child: _AppSettingsSheet(d: d, pal: pal),
                              ),
                            if (d.splashPreview)
                              Positioned.fill(
                                child: SplashView(splash: jsonMap(d.doc['splash']), onTap: d.skipSplash),
                              ),
                          ],
                        ),
                      ),
                    ),
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

class _Screen extends StatelessWidget {
  const _Screen({required this.d, required this.pal, required this.issues, required this.size, required this.dev});
  final Designer d;
  final AppPalette pal;
  final List<Issue> issues;
  final Size size;
  final String dev;

  bool get tablet => dev != 'mobile';

  @override
  Widget build(BuildContext context) {
    final doc = d.doc;
    final room = d.room;
    final sub = d.sub;
    final floors = floorsOf(doc);
    final floor = d.floor;
    final theme = jsonMap(doc['theme']);
    final galleryOn = theme['roomPicker'] == 'gallery' && dev != 'tabletL';
    final now = TimeOfDay.now();
    final statusBar = SizedBox(
      height: 38,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 30),
        child: Row(
          children: [
            Text(
              '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: pal.sInk),
            ),
            const Spacer(),
            if (!tablet)
              Container(
                width: 92,
                height: 26,
                decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(14)),
              ),
            const Spacer(),
            Text(
              '100%',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: pal.sInk),
            ),
          ],
        ),
      ),
    );
    // A floor that exists but has no room yet: the empty screen with the
    // floor name, and a note that the room is not created.
    final empty = Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (floor != null)
            Padding(
              padding: EdgeInsets.fromLTRB(18, dev == 'tabletL' ? 10 : 6, 14, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      (floor['title'] ?? '').toString(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: tfs(doc, 'titleSize'), fontWeight: FontWeight.w600, color: pal.sInk),
                    ),
                  ),
                  if (dev != 'tabletL') ...[_pill(), const SizedBox(width: 8), _gear()],
                ],
              ),
            ),
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(30),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.meeting_room_outlined, size: 44, color: pal.sMuted),
                    const SizedBox(height: 12),
                    Text(
                      'The room has not been created',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: pal.sInk),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Right-click a floor in the Structure column and choose Add room.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: pal.sMuted, height: 1.4),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
    Widget grid(Json room, Json s) => Expanded(
      child: _PagedGrid(key: ValueKey<String>('pg-${room['id']}'), d: d, room: room, pal: pal, issues: issues),
    );

    if (dev == 'tabletL') {
      return SizedBox(
        width: size.width,
        height: size.height,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            statusBar,
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _sidebar(doc, room, floors.length > 1),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (room == null || sub == null)
                          empty
                        else ...[
                          _header(doc, room, floor, floors.length > 1, theme, pill: false),
                          _pageTabs(room, sub),
                          grid(room, sub),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // ---- "Modern" layout: Home | Floor | Security with a bar of three buttons.
    if (theme['layout'] == 'modern' && dev != 'tabletL') {
      final special = floor?['special'];
      final normal = normalFloorsOf(doc);
      final inFloors = d.view == 'floors';
      final inRooms = special == null && d.view == 'floor';
      Widget title(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 6, 14, 10),
        child: Text(
          t,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: tfs(doc, 'titleSize'), fontWeight: FontWeight.w600, color: pal.sInk),
        ),
      );
      final tab = !inFloors && special == 'home' ? 0 : (!inFloors && special == 'security' ? 2 : 1);
      final nf = tfs(doc, 'navBar');
      // An icon with a small label; the selected one is filled and tinted.
      Widget barItem(int t, IconData on, IconData off, String label, VoidCallback onTap) {
        final sel = tab == t;
        final col = sel ? pal.accent : pal.muted;
        return Expanded(
          child: PressFade(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(sel ? on : off, size: nf * 2.2, color: col),
                  const SizedBox(height: 2),
                  Text(
                    label,
                    style: TextStyle(fontSize: nf * 0.9, fontWeight: FontWeight.w500, color: col),
                  ),
                ],
              ),
            ),
          ),
        );
      }

      return SizedBox(
        width: size.width,
        height: size.height,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            statusBar,
            if (inFloors) ...[
              title('Area'),
              Expanded(
                child: RoomGallery(doc: doc, rooms: normal, pal: pal, onOpen: d.selectFloor),
              ),
            ] else if (inRooms) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 6, 14, 10),
                child: Row(
                  children: [
                    if (normal.length > 1) ...[
                      InkWell(
                        customBorder: const CircleBorder(),
                        onTap: d.floorsGallery,
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: flatDecoration(pal, pal.chipFill, circle: true),
                          child: Icon(Icons.arrow_back, size: 17, color: pal.ink),
                        ),
                      ),
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      child: Text(
                        (floor?['title'] ?? '').toString(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: tfs(doc, 'titleSize'), fontWeight: FontWeight.w600, color: pal.sInk),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: RoomGallery(doc: doc, rooms: roomsOf(doc, floor?['id'] as String?), pal: pal, onOpen: d.selectRoom),
              ),
            ] else if (room == null || sub == null)
              empty
            else ...[
              _header(doc, room, floor, false, theme, onBack: special == null ? () => d.selectFloor((floor?['id'] ?? '').toString()) : null),
              if (tablet) _pageTabs(room, sub),
              grid(room, sub),
            ],
            Container(
              decoration: BoxDecoration(
                color: Color.lerp(pal.screen, pal.ink, 0.05),
                border: Border(top: BorderSide(color: pal.tileEdge, width: 0.5)),
              ),
              child: Row(
                children: [
                  barItem(0, Icons.home, Icons.home_outlined, 'Home', () => d.selectSpecial('home')),
                  barItem(1, Icons.layers, Icons.layers_outlined, 'Area', () {
                    if (normal.length > 1) {
                      d.floorsGallery();
                    } else if (normal.isNotEmpty) {
                      d.selectFloor(normal.first['id'] as String);
                    }
                  }),
                  barItem(2, Icons.shield, Icons.shield_outlined, 'Security', () => d.selectSpecial('security')),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return SizedBox(
      width: size.width,
      height: size.height,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          statusBar,
          if (galleryOn && d.view == 'gallery') ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 6, 14, 10),
              child: Text(
                (floor?['title'] ?? (doc['project'] is Map ? (doc['project']['name'] ?? '') : '')).toString(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: tfs(doc, 'titleSize'), fontWeight: FontWeight.w600, color: pal.sInk),
              ),
            ),
            Expanded(
              child: RoomGallery(doc: doc, rooms: roomsOf(doc, floor?['id'] as String?), pal: pal, onOpen: d.selectRoom),
            ),
          ] else if (room == null || sub == null)
            empty
          else ...[
            _header(doc, room, floor, floors.length > 1, theme),
            if (!galleryOn) _roomsBar(doc, room, floor),
            if (tablet) _pageTabs(room, sub),
            grid(room, sub),
          ],
          if (floors.length > 1) _floorBar(floors, floor),
        ],
      ),
    );
  }

  Widget _pill() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: pal.panel,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: pal.tileEdge),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: d.live && d.bus?.connected != true ? const Color(0xFFD9463B) : const Color(0xFF2FA36B), shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          'KNX',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: pal.ink),
        ),
      ],
    ),
  );

  Widget _gear() => GestureDetector(
    onTap: () => d.toggleAppSettings(true),
    child: MouseRegion(cursor: SystemMouseCursors.click, child: _gearIcon()),
  );

  Widget _gearIcon() => SizedBox(width: 32, height: 32, child: Icon(Icons.settings_outlined, size: 20, color: pal.ink));

  Widget _header(Json doc, Json room, Json? floor, bool multi, Json theme, {bool pill = true, VoidCallback? onBack}) {
    final hide = theme['hideTitle'] == true && dev != 'tabletL' && theme['layout'] != 'modern';
    return Padding(
      padding: EdgeInsets.fromLTRB(18, dev == 'tabletL' ? 10 : 6, 14, 10),
      child: Row(
        children: [
          // In the gallery style a button returns to the gallery.
          if (onBack != null || (theme['roomPicker'] == 'gallery' && theme['layout'] != 'modern' && dev != 'tabletL')) ...[
            Tooltip(
              message: tr(onBack != null ? 'Back' : 'Room gallery'),
              child: PressFade(
                onTap: onBack ?? d.gallery,
                child: SizedBox(
                  width: 36,
                  height: 36,
                  child: Icon(onBack != null ? Icons.chevron_left : Icons.grid_view, size: onBack != null ? 30 : 19, color: pal.ink),
                ),
              ),
            ),
            const SizedBox(width: 4),
          ],
          Expanded(
            child: hide
                ? Text(
                    multi ? (floor?['title'] ?? '').toString() : '',
                    style: TextStyle(fontSize: tfs(doc, 'crumb') * 1.15, color: pal.sMuted, fontWeight: FontWeight.w500),
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      if (multi)
                        Text(
                          '${floor?['title'] ?? ''} ›  ',
                          style: TextStyle(fontSize: tfs(doc, 'crumb'), color: pal.sMuted, fontWeight: FontWeight.w500),
                        ),
                      Flexible(
                        child: Text(
                          (room['title'] ?? '').toString(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: tfs(doc, 'titleSize'), fontWeight: FontWeight.w600, color: pal.sInk),
                        ),
                      ),
                      // A phone shows the page after the room name: "Living room (1/3)".
                      if (dev == 'mobile' && subsOf(room).length > 1)
                        Text(
                          '  (${max(0, subsOf(room).indexWhere((x) => x['id'] == d.sub?['id'])) + 1}/${subsOf(room).length})',
                          style: TextStyle(fontSize: tfs(doc, 'pageTitle'), color: pal.sMuted, fontWeight: FontWeight.w500),
                        ),
                    ],
                  ),
          ),
          if (pill) ...[_pill(), const SizedBox(width: 8), _gear()],
        ],
      ),
    );
  }

  Widget _sidebar(Json doc, Json? room, bool multi) {
    final now = DateTime.now();
    const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    return Container(
      width: 230,
      margin: const EdgeInsets.fromLTRB(14, 4, 0, 14),
      decoration: BoxDecoration(
        color: pal.panel,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: pal.tileEdge),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
                  style: TextStyle(fontSize: 34, fontWeight: FontWeight.w300, color: pal.ink, height: 1),
                ),
                const SizedBox(height: 6),
                Text('${days[now.weekday - 1]}, ${now.day}/${now.month}', style: TextStyle(fontSize: 13, color: pal.muted)),
                const SizedBox(height: 8),
                Text(
                  greeting(jsonMap(doc['splash'])),
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: pal.ink),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: pal.tileEdge),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(8),
              children: [
                for (final f in floorsOf(doc)) ...[
                  if (multi)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 10, 8, 4),
                      child: Row(
                        children: [
                          if (f['showIcon'] != false && !isNoIcon(f['icon'] as String?)) ...[
                            iconWidget(f['icon'] as String? ?? 'stairs', 14, pal.muted),
                            const SizedBox(width: 6),
                          ],
                          Text(
                            (f['title'] ?? '').toString(),
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: pal.muted),
                          ),
                        ],
                      ),
                    ),
                  for (final r in roomsOf(doc, f['id'] as String?))
                    InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => d.selectRoom(r['id'] as String),
                      child: Container(
                        height: 42,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: flatDecoration(
                          pal,
                          r['id'] == room?['id'] ? pal.chipSel : pal.chipFill,
                          radius: BorderRadius.circular(12),
                          glow: r['id'] == room?['id'] ? pal.chipSel : null,
                        ),
                        child: Row(
                          children: [
                            if (!isNoIcon(r['icon'] as String?)) ...[
                              iconWidget(r['icon'] as String?, 20, r['id'] == room?['id'] ? pal.onChipSel : pal.muted),
                              const SizedBox(width: 10),
                            ],
                            Expanded(
                              child: Text(
                                (r['title'] ?? '').toString(),
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 15, color: r['id'] == room?['id'] ? pal.onChipSel : pal.ink),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
          Divider(height: 1, color: pal.tileEdge),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [_pill(), const Spacer(), _gear()]),
          ),
        ],
      ),
    );
  }

  Widget _roomsBar(Json doc, Json room, Json? floor) {
    final rs = roomsOf(doc, floor?['id'] as String?);
    final f = tfs(doc, 'roomBar');
    return SizedBox(
      height: f * 2.6 + 8,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
        children: [
          for (final r in rs)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => d.selectRoom(r['id'] as String),
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: f * 1.05),
                  decoration: flatDecoration(
                    pal,
                    r['id'] == room['id'] ? pal.chipSel : pal.chipFill,
                    radius: BorderRadius.circular(20),
                    glow: r['id'] == room['id'] ? pal.chipSel : null,
                  ),
                  child: Row(
                    children: [
                      if (!isNoIcon(r['icon'] as String?)) ...[
                        iconWidget(r['icon'] as String?, f * 1.25, r['id'] == room['id'] ? pal.onChipSel : pal.muted),
                        SizedBox(width: f * 0.45),
                      ],
                      Text(
                        (r['title'] ?? '').toString(),
                        style: TextStyle(fontSize: f, fontWeight: FontWeight.w500, color: r['id'] == room['id'] ? pal.onChipSel : pal.ink),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _pageTabs(Json room, Json sub) {
    final ss = subsOf(room);
    if (ss.length < 2 && d.test) return const SizedBox(height: 4);
    final f = tfs(d.doc, 'pageTitle');
    return SizedBox(
      height: f * 2.6 + 12,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
        children: [
          for (final s in ss)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () => d.selectSub(room['id'] as String, s['id'] as String),
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: f * 1.2),
                  alignment: Alignment.center,
                  decoration: flatDecoration(
                    pal,
                    s['id'] == sub['id'] ? pal.chipSel : pal.chipFill,
                    radius: BorderRadius.circular(18),
                    glow: s['id'] == sub['id'] ? pal.chipSel : null,
                  ),
                  child: Text(
                    (s['title'] ?? '').toString(),
                    style: TextStyle(fontSize: f * 1.05, fontWeight: FontWeight.w500, color: s['id'] == sub['id'] ? pal.onChipSel : pal.muted),
                  ),
                ),
              ),
            ),
          if (!d.test)
            InkWell(
              customBorder: const CircleBorder(),
              onTap: d.addSub,
              child: Container(
                width: f * 2.6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: pal.lineStrong),
                ),
                child: Icon(Icons.add, size: 16, color: pal.accent),
              ),
            ),
        ],
      ),
    );
  }

  Widget _floorBar(List<Json> floors, Json? floor) {
    final f = tfs(d.doc, 'floorBar');
    final slots = tablet ? 5 : 3;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      child: Container(
        // Text fills the pill better; the bar keeps a comfortable minimum height.
        height: max(48.0, f * 2.4 + 14),
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color: Color.lerp(pal.screen, pal.ink, 0.07),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: pal.tileEdge),
        ),
        child: LayoutBuilder(
          builder: (context, c) {
            final w = (c.maxWidth - 4 * (slots - 1)) / slots;
            return ListView(
              scrollDirection: Axis.horizontal,
              children: [
                if (floors.length < slots) SizedBox(width: (c.maxWidth - floors.length * (w + 4)) / 2),
                for (final fl in floors)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(26),
                      onTap: () => d.view == 'gallery' ? d.galleryFloor(fl['id'] as String) : d.selectFloor(fl['id'] as String),
                      child: Container(
                        width: w,
                        decoration: flatDecoration(
                          pal,
                          fl['id'] == floor?['id'] ? pal.chipSel : pal.chipFill,
                          radius: BorderRadius.circular(26),
                          glow: fl['id'] == floor?['id'] ? pal.chipSel : null,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (fl['showIcon'] != false && !isNoIcon(fl['icon'] as String?)) ...[
                              iconWidget(fl['icon'] as String? ?? 'stairs', f * 1.25, fl['id'] == floor?['id'] ? pal.onChipSel : pal.muted),
                              SizedBox(width: f * 0.45),
                            ],
                            Flexible(
                              child: Text(
                                (fl['title'] ?? '').toString(),
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: f, fontWeight: FontWeight.w600, color: fl['id'] == floor?['id'] ? pal.onChipSel : pal.ink),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Grid of a subpage or of a grid frame: cells (drop targets) and tiles.
class _GridArea extends StatefulWidget {
  const _GridArea({super.key, required this.d, required this.box, required this.groupId, required this.pal, required this.issues});
  final Designer d;
  final Json box;
  final String? groupId;
  final AppPalette pal;
  final List<Issue> issues;

  @override
  State<_GridArea> createState() => _GridAreaState();
}

class _GridAreaState extends State<_GridArea> {
  ({int x, int y, int w, int h, bool ok})? ghost;

  /// Card being resized with the corner handle (new size in cells).
  ({String id, int w, int h})? resizing;

  /// The grid content (inside the scroll view on scrolling pages), used to
  /// convert drag positions into cells.
  final GlobalKey _content = GlobalKey();

  Designer get d => widget.d;

  /// How much the phone preview is scaled on screen, so the drag feedback
  /// (drawn in the overlay, unscaled) keeps the same size as the tile.
  double _screenScale() {
    final rb = context.findRenderObject();
    if (rb is! RenderBox || !rb.attached) return 1;
    final a = rb.localToGlobal(Offset.zero), b = rb.localToGlobal(const Offset(100, 0));
    final k = (b.dx - a.dx) / 100;
    return k > 0 ? k : 1;
  }

  /// Inner grids of a frame let the page handle frames (no nesting).
  bool _accepts(DragItem it) {
    final g = widget.groupId;
    if (g == null) return true;
    if (it.kind != 'widget') return it.type != 'group';
    if (it.id == g) return false;
    final s = d.sub;
    final w = s == null ? null : findWidget(s, it.id);
    return w?['type'] != 'group';
  }

  void _drop(DragItem it, int x, int y) {
    setState(() => ghost = null);
    final err = d.drop(it, widget.groupId, x, y);
    if (err != null) toast(context, err);
  }

  Future<void> _testAct(Json w, String action, Object? arg) async {
    if (w['type'] == 'camera') {
      if (action == 'tap' && jsonMap(w['cam'])['view'] == 'button') {
        await showDialog<void>(
          context: context,
          builder: (c) => Dialog(
            backgroundColor: Colors.black,
            insetPadding: const EdgeInsets.all(40),
            child: SizedBox(
              width: 640,
              height: 400,
              child: Stack(
                children: [
                  Positioned.fill(child: CameraView(cam: jsonMap(w['cam']), live: true)),
                  Positioned(
                    top: 6,
                    right: 6,
                    child: IconButton(
                      onPressed: () => Navigator.pop(c),
                      icon: const Icon(Icons.close, color: Colors.white),
                    ),
                  ),
                  Positioned(
                    left: 14,
                    top: 14,
                    child: Text(
                      (w['label'] ?? '').toString(),
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }
      return;
    }
    if (action == 'popup') {
      // The ⚙ of an AC card: modes and fan speed (and the slider, for a simple card).
      final simple = w['look'] == 'simple';
      final full = {...w, 'look': simple ? 'controlsSp' : 'controls'};
      await showDialog<void>(
        context: context,
        builder: (c) => Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: SizedBox(
            width: 340,
            height: (jsonMap(jsonMap(w['ac'])['fan'])['enabled'] == true ? 236 : 150) + (simple ? 96 : 0),
            child: ListenableBuilder(
              listenable: d,
              builder: (c, _) =>
                  TileView(w: full, pal: widget.pal, gas: jsonList(d.doc['groupAddresses']), sim: d.sim[w['id']] ?? const {}, act: (a, [x]) => d.act(w, a, x)),
            ),
          ),
        ),
      );
      return;
    }
    if (action == 'tune') {
      await showDialog<void>(
        context: context,
        builder: (c) => _TuneDialog(d: d, w: w),
      );
      return;
    }
    d.act(w, action == 'tap' ? (w['type'] == 'dimmer' ? 'toggle' : (w['type'] == 'ac' ? 'power' : 'tap')) : action, arg);
  }

  @override
  Widget build(BuildContext context) {
    final box = widget.box;
    final test = d.test;
    // Scrolling page (phone): [vis] rows fit the screen, [r] rows in total.
    final scroll = widget.groupId == null && scrollPage(box, d.doc);
    final c = cols(box), vis = rows(box), r = scroll ? pageRows(box, d.doc) : vis;
    final gap = (c >= 6 || vis >= 15) ? 6.0 : 10.0;
    // A shadow never grows past about 1.5 gaps, so it does not fall on the next card.
    final pal = widget.pal.copyWith(shadowCap: gap * 1.5);
    final evo = context.evo;
    final gas = jsonList(d.doc['groupAddresses']);
    return LayoutBuilder(
      builder: (context, bc) {
        final cw = (bc.maxWidth - gap * (c - 1)) / c;
        final ch = (bc.maxHeight - gap * (vis - 1)) / vis;
        final totalH = r * ch + gap * (r - 1);
        Rect rect(int x, int y, int w, int h) => Rect.fromLTWH(x * (cw + gap), y * (ch + gap), w * cw + (w - 1) * gap, h * ch + (h - 1) * gap);
        // Transparent background so the whole grid (gaps included) is a
        // drop area: the ghost no longer flickers between cells.
        final children = <Widget>[const Positioned.fill(child: ColoredBox(color: Colors.transparent))];
        if (!test) {
          for (var y = 0; y < r; y++) {
            for (var x = 0; x < c; x++) {
              if (!isFree(box, x, y, 1, 1)) continue;
              final sel = d.cell != null && d.cell!.g == widget.groupId && d.cell!.x == x && d.cell!.y == y;
              children.add(
                Positioned.fromRect(
                  rect: rect(x, y, 1, 1),
                  child: GestureDetector(
                    onTap: () => d.selectCell(widget.groupId, x, y),
                    child: Container(
                      decoration: BoxDecoration(
                        // Selected cell: outline only (Editor selection blue), no fill.
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(widget.groupId == null ? 14 : 10),
                        border: Border.all(color: sel ? kEditorSelection.withValues(alpha: 0.7) : pal.lineStrong.withValues(alpha: 0.6), width: sel ? 1.25 : 1),
                      ),
                    ),
                  ),
                ),
              );
            }
          }
        }
        // One layer with every card's shadow (and glow), under all the cards.
        for (final w in jsonList(box['widgets'])) {
          final bg = jsonMap(w['style'])['bg'];
          final body = w['type'] == 'group' ? (w['gstyle'] ?? 'card') == 'card' : (bg != 'outline' && bg != 'transparent');
          if (!body) continue;
          children.add(
            Positioned.fromRect(
              rect: rect(pi(w, 'x'), pi(w, 'y'), pi(w, 'w'), pi(w, 'h')),
              child: CardShadow(
                radius: w['type'] == 'group' ? pal.radius + 2 : pal.radius,
                pal: pal,
                glow: tileGlowColor(w, pal, d.sim[w['id'] as String] ?? const {}),
              ),
            ),
          );
        }
        for (final w in jsonList(box['widgets'])) {
          final id = w['id'] as String;
          final rc = rect(pi(w, 'x'), pi(w, 'y'), pi(w, 'w'), pi(w, 'h'));
          final flagged = !test && widget.issues.any((i) => i.error && i.widgetId == id);
          final selected = !test && d.isSelected(id);
          final Widget tile = w['type'] == 'group'
              ? _GroupFrame(d: d, w: w, pal: pal, issues: widget.issues, selected: selected)
              : TileView(
                  w: w,
                  pal: pal,
                  gas: gas,
                  sim: d.sim[id] ?? const {},
                  selected: selected,
                  flagged: flagged,
                  act: test ? (a, [arg]) => _testAct(w, a, arg) : null,
                );
          if (test) {
            children.add(
              Positioned.fromRect(
                rect: rc,
                child: w['type'] == 'group' || (w['type'] == 'value' && !isStateValue(w))
                    ? tile
                    : GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _testAct(w, 'tap', null),
                        child: MouseRegion(
                          cursor: SystemMouseCursors.click,
                          // Whole-card press effect for cards whose main action
                          // is a tap; cards with their own buttons (rèm, máy
                          // lạnh, web) animate those buttons instead.
                          child: PressEffect(
                            radius: pal.radius,
                            enabled:
                                const ['switch', 'dimmer', 'ac', 'button', 'scene', 'link'].contains(w['type']) ||
                                (w['type'] == 'camera' && jsonMap(w['cam'])['view'] == 'button'),
                            dark: (hexColor(jsonMap(w['style'])['bg']) ?? pal.tile).computeLuminance() < 0.35,
                            child: tile,
                          ),
                        ),
                      ),
              ),
            );
            continue;
          }
          children.add(
            Positioned.fromRect(
              rect: rc,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                // Ctrl + click adds the card to the selection (or removes it).
                onTap: () => HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isMetaPressed ? d.toggleSelect(id) : d.selectWidget(id),
                child: Draggable<DragItem>(
                  data: DragItem.widget(id),
                  // Keep the grab point under the cursor at the on-screen scale,
                  // so the dragged card sits exactly where the tile was.
                  dragAnchorStrategy: (draggable, ctx, position) {
                    final rb = ctx.findRenderObject();
                    if (rb is! RenderBox) return Offset.zero;
                    return rb.globalToLocal(position) * _screenScale();
                  },
                  onDragEnd: (_) {
                    if (ghost != null) setState(() => ghost = null);
                  },
                  feedback: Builder(
                    builder: (_) {
                      final k = _screenScale();
                      return Opacity(
                        opacity: 0.85,
                        child: SizedBox(
                          width: rc.width * k,
                          height: rc.height * k,
                          child: FittedBox(
                            alignment: Alignment.topLeft,
                            child: SizedBox(
                              width: rc.width,
                              height: rc.height,
                              child: Material(type: MaterialType.transparency, child: tile),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  childWhenDragging: Opacity(opacity: 0.35, child: tile),
                  child: MouseRegion(cursor: SystemMouseCursors.grab, child: tile),
                ),
              ),
            ),
          );
          // Selection in the style of design tools: blue outline, corner
          // handles and the card size (columns × rows) under it. The
          // bottom-right handle resizes the card by dragging.
          if (selected && !d.hasMulti) {
            const sel = kEditorSelection;
            final rz = resizing?.id == id ? resizing : null;
            final gw = rz?.w ?? pi(w, 'w'), gh = rz?.h ?? pi(w, 'h');
            final rr = rz == null ? rc : rect(pi(w, 'x'), pi(w, 'y'), gw, gh);
            final ok = rz == null || isFree(box, pi(w, 'x'), pi(w, 'y'), gw, gh, id);
            final col = ok ? sel : evo.danger;
            Widget handle() => Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: col, width: 1.2),
              ),
            );
            final below = rr.bottom + 22 <= bc.maxHeight;
            // Always present (invisible when idle) so the drag zones below
            // keep their place and are not rebuilt in the middle of a drag.
            children.add(
              Positioned.fromRect(
                key: const ValueKey('resize-preview'),
                rect: rr,
                child: IgnorePointer(
                  child: Opacity(
                    opacity: rz == null ? 0 : 1,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: col.withValues(alpha: 0.08),
                        border: Border.all(color: col, width: 1.5),
                        borderRadius: BorderRadius.circular(pal.radius),
                      ),
                    ),
                  ),
                ),
              ),
            );
            children.add(
              Positioned(
                left: rr.left - 3,
                top: rr.top - 3,
                width: rr.width + 6,
                height: rr.height + 6 + (below ? 20 : 0),
                child: IgnorePointer(
                  child: Stack(
                    children: [
                      Positioned(left: 0, top: 0, child: handle()),
                      Positioned(right: 0, top: 0, child: handle()),
                      Positioned(left: 0, top: rr.height - 1, child: handle()),
                      Positioned(
                        left: 0,
                        right: 0,
                        top: below ? rr.height + 8 : rr.height - 18,
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(color: col, borderRadius: BorderRadius.circular(3)),
                            child: Text(
                              '$gw × $gh',
                              style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
            // Resize: drag the right edge (width), the bottom edge (height)
            // or the corner (both). Hit areas keep a constant size on the
            // real screen, whatever the zoom of the preview.
            final k = _screenScale();
            final edge = 12 / k, corner = 18 / k, dot = 9 / k;
            final maxW = c - pi(w, 'x'), maxH = r - pi(w, 'y');
            ({int w, int h}) sizeAt(Offset global, String mode) {
              final rb = _content.currentContext?.findRenderObject();
              final cur = resizing ?? (id: id, w: gw, h: gh);
              if (rb is! RenderBox) return (w: cur.w, h: cur.h);
              final p = rb.globalToLocal(global);
              // The card edge snaps to the cell boundary nearest the pointer.
              final nw = ((p.dx - rc.left + gap) / (cw + gap)).round().clamp(1, max(1, maxW)).toInt();
              final nh = ((p.dy - rc.top + gap) / (ch + gap)).round().clamp(1, max(1, maxH)).toInt();
              // Right edge: width only. Bottom edge: height only. Corner: both.
              return (w: mode == 'h' ? cur.w : nw, h: mode == 'w' ? cur.h : nh);
            }

            Widget zone(String mode, MouseCursor cursor, Widget? child) => MouseRegion(
              cursor: cursor,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                dragStartBehavior: DragStartBehavior.down,
                onPanStart: (e) => setState(() => resizing = (id: id, w: pi(w, 'w'), h: pi(w, 'h'))),
                onPanUpdate: (e) {
                  final sz = sizeAt(e.globalPosition, mode);
                  if (sz.w != resizing?.w || sz.h != resizing?.h) setState(() => resizing = (id: id, w: sz.w, h: sz.h));
                },
                onPanCancel: () => setState(() => resizing = null),
                onPanEnd: (_) {
                  final z = resizing;
                  setState(() => resizing = null);
                  if (z == null || (z.w == pi(w, 'w') && z.h == pi(w, 'h'))) return;
                  if (!isFree(box, pi(w, 'x'), pi(w, 'y'), z.w, z.h, id)) {
                    toast(context, 'Not enough room: the new area overlaps another card.');
                    return;
                  }
                  d.editWidget(id, (o) => o['pos'] = {'x': pi(w, 'x'), 'y': pi(w, 'y'), 'w': z.w, 'h': z.h});
                },
                child: child ?? const SizedBox.expand(),
              ),
            );

            // Keep the zones inside the grid so edge cards stay resizable.
            double inX(double x, double size) => x.clamp(0.0, max(0.0, bc.maxWidth - size)).toDouble();
            double inY(double y, double size) => y.clamp(0.0, max(0.0, (scroll ? totalH : bc.maxHeight) - size)).toDouble();
            children.add(
              Positioned(
                key: const ValueKey('resize-right'),
                left: inX(rr.right - edge / 2, edge),
                top: rr.top + corner / 2,
                width: edge,
                height: max(0.0, rr.height - corner),
                child: zone(
                  'w',
                  SystemMouseCursors.resizeLeftRight,
                  Center(
                    child: Container(
                      width: 5 / k,
                      height: min(22 / k, max(8.0, rr.height - corner)),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: col, width: 1.2 / k),
                        borderRadius: BorderRadius.circular(3 / k),
                      ),
                    ),
                  ),
                ),
              ),
            );
            children.add(
              Positioned(
                key: const ValueKey('resize-bottom'),
                left: rr.left + corner / 2,
                top: inY(rr.bottom - edge / 2, edge),
                width: max(0.0, rr.width - corner),
                height: edge,
                child: zone(
                  'h',
                  SystemMouseCursors.resizeUpDown,
                  Center(
                    child: Container(
                      width: min(22 / k, max(8.0, rr.width - corner)),
                      height: 5 / k,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: col, width: 1.2 / k),
                        borderRadius: BorderRadius.circular(3 / k),
                      ),
                    ),
                  ),
                ),
              ),
            );
            children.add(
              Positioned(
                key: const ValueKey('resize-corner'),
                left: inX(rr.right - corner / 2, corner),
                top: inY(rr.bottom - corner / 2, corner),
                width: corner,
                height: corner,
                child: zone(
                  'wh',
                  SystemMouseCursors.resizeDownRight,
                  Center(
                    child: Container(
                      width: dot,
                      height: dot,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: col, width: 1.5 / k),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }
        }
        final g = ghost;
        if (g != null && !test) {
          children.add(
            Positioned.fromRect(
              rect: rect(g.x, g.y, max(1, g.w), max(1, g.h)),
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    color: (g.ok ? pal.accent : evo.danger).withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: g.ok ? pal.accent : evo.danger, width: 2),
                  ),
                ),
              ),
            ),
          );
        }
        // Cell under the dragged card: a moved tile snaps by its top-left
        // corner (nearest cell), a new item from the palette by the cursor.
        ({int x, int y})? cellOf(DragTargetDetails<DragItem> det) {
          final rb = _content.currentContext?.findRenderObject();
          if (rb is! RenderBox || !rb.attached) return null;
          final p = rb.globalToLocal(det.offset);
          final fx = p.dx / (cw + gap), fy = p.dy / (ch + gap);
          final moving = det.data.kind == 'widget';
          final x = (moving ? fx.round() : fx.floor()).clamp(0, c - 1).toInt();
          final y = (moving ? fy.round() : fy.floor()).clamp(0, r - 1).toInt();
          return (x: x, y: y);
        }

        final grid = MouseRegion(
          key: _content,
          onExit: (_) {
            if (ghost != null) setState(() => ghost = null);
          },
          child: DragTarget<DragItem>(
            onWillAcceptWithDetails: (det) => !test && _accepts(det.data),
            onMove: (det) {
              final cell = cellOf(det);
              final g = cell == null ? null : d.footprint(det.data, widget.groupId, cell.x, cell.y);
              if (g != ghost) setState(() => ghost = g);
            },
            onLeave: (_) {
              if (ghost != null) setState(() => ghost = null);
            },
            onAcceptWithDetails: (det) {
              final cell = cellOf(det);
              if (cell == null) {
                setState(() => ghost = null);
                return;
              }
              _drop(det.data, cell.x, cell.y);
            },
            builder: (context, cand, rej) => Stack(clipBehavior: Clip.none, children: children),
          ),
        );
        if (!scroll) return grid;
        return ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(scrollbars: true),
          child: SingleChildScrollView(
            child: SizedBox(height: totalH, child: grid),
          ),
        );
      },
    );
  }
}

class _GroupFrame extends StatelessWidget {
  const _GroupFrame({required this.d, required this.w, required this.pal, required this.issues, required this.selected});
  final Designer d;
  final Json w;
  final AppPalette pal;
  final List<Issue> issues;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final style = (w['gstyle'] ?? 'card').toString();
    // The frame look comes from its style (Kiểu khung); no separate color.
    final titleColor = style == 'card' ? pal.ink : pal.sInk;
    final align = switch (w['titleAlign']) {
      'center' => TextAlign.center,
      'right' => TextAlign.right,
      _ => TextAlign.left,
    };
    final gapT = ((w['titleGap'] as num?) ?? 10).toDouble();
    final showTitle = w['showTitle'] != false && (w['label'] ?? '').toString().isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: style == 'card'
          ? raisedDecoration(
              pal,
              pal.fill(pal.tile),
              radius: BorderRadius.circular(pal.radius + 2),
              lift: pal.cardLift,
              border: !selected && pal.border <= 0
                  ? Border.fromBorderSide(BorderSide.none)
                  : Border.all(color: selected ? kEditorSelection : pal.edge, width: selected ? 1.5 : pal.border),
              shadow: false,
            )
          : BoxDecoration(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(pal.radius + 2),
              border: !selected && style != 'none' && pal.border <= 0
                  ? null
                  : Border.all(
                      color: selected ? kEditorSelection : (style == 'none' ? (d.test ? Colors.transparent : pal.lineStrong.withValues(alpha: 0.5)) : pal.edge),
                      width: selected ? 1.5 : (style == 'none' ? 1 : pal.border),
                    ),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showTitle) ...[
            // Title centred between the frame edge and the grid below it.
            SizedBox(height: max(0.0, gapT - 8)),
            Text((w['label'] ?? '').toString(), textAlign: align, maxLines: 1, overflow: TextOverflow.ellipsis, style: evoLabelStyle(w, titleColor)),
            SizedBox(height: gapT),
          ],
          Expanded(
            child: _GridArea(d: d, box: w, groupId: w['id'] as String, pal: pal, issues: issues),
          ),
        ],
      ),
    );
  }
}

/// Slider sheet for dimmers (brightness, color temperature, RGB) and
/// shutters (position) in test mode.
class _TuneDialog extends StatefulWidget {
  const _TuneDialog({required this.d, required this.w});
  final Designer d;
  final Json w;
  @override
  State<_TuneDialog> createState() => _TuneDialogState();
}

class _TuneDialogState extends State<_TuneDialog> {
  late final Map<String, dynamic> s = widget.d.st(widget.w['id'] as String);

  @override
  Widget build(BuildContext context) {
    final w = widget.w;
    final dim = w['type'] == 'dimmer';
    final f = jsonMap(w['features']);
    final tw = jsonMap(w['tw']);
    final ctMin = ((tw['min'] as num?) ?? 2700).toDouble(), ctMax = ((tw['max'] as num?) ?? 6500).toDouble();
    final val = ((dim ? s['val'] : s['pos']) as num? ?? 0).toDouble();
    const swatches = ['#FFFFFF', '#FFB347', '#FF5E5E', '#FF4FA3', '#9B6BFF', '#4D8DFF', '#36C5D6', '#3DCB7A', '#F5E663'];
    return AlertDialog(
      title: Text((w['label'] ?? '').toString(), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(dim ? 'Brightness: ${val.round()}%' : (w['shStyle'] == 'curtain' ? 'Open ${100 - val.round()}%' : 'Close ${val.round()}%')),
            Slider(
              value: val.clamp(0.0, 100.0),
              max: 100,
              divisions: 100,
              onChanged: (v) => setState(() => dim ? s['val'] = v.round() : s['pos'] = v.round()),
              onChangeEnd: (v) => widget.d.act(w, 'set', v.round()),
            ),
            if (!dim)
              Wrap(
                spacing: 6,
                children: [
                  for (final p in [0, 25, 50, 75, 100])
                    OutlinedButton(
                      onPressed: () {
                        setState(() => s['pos'] = p);
                        widget.d.act(w, 'set', p);
                      },
                      child: Text('$p%'),
                    ),
                ],
              ),
            if (dim && f['tw'] == true) ...[
              const SizedBox(height: 8),
              Text('Color temperature: ${((s['ct'] as num?) ?? ctMin).round()} K'),
              Slider(
                value: (((s['ct'] as num?) ?? ctMin).toDouble()).clamp(ctMin, ctMax),
                min: ctMin,
                max: ctMax,
                onChanged: (v) => setState(() => s['ct'] = (v / 50).round() * 50),
                onChangeEnd: (v) => widget.d.act(w, 'ct', (v / 50).round() * 50),
              ),
            ],
            if (dim && f['rgb'] == true) ...[
              const SizedBox(height: 8),
              const Text('Color'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final hx in swatches)
                    InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () {
                        setState(() => s['rgb'] = hx);
                        widget.d.act(w, 'rgb', hx);
                      },
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: hexColor(hx),
                          shape: BoxShape.circle,
                          border: Border.all(color: s['rgb'] == hx ? Colors.black : const Color(0x33000000), width: s['rgb'] == hx ? 2 : 1),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Done'))],
    );
  }
}

/// Lets horizontal bars (rooms, pages, floors) be dragged with the mouse,
/// like swiping on the phone.
class _DragScroll extends MaterialScrollBehavior {
  const _DragScroll();

  @override
  Set<PointerDeviceKind> get dragDevices => {PointerDeviceKind.touch, PointerDeviceKind.mouse, PointerDeviceKind.trackpad, PointerDeviceKind.stylus};

  @override
  Widget buildScrollbar(BuildContext context, Widget child, ScrollableDetails details) => child;
}

/// Pages of a room in a PageView: follows the mouse/finger while dragging,
/// snaps to the nearest page, and animates when the page is changed from
/// the dots, tabs, arrow buttons, keyboard or the structure tree.
class _PagedGrid extends StatefulWidget {
  const _PagedGrid({super.key, required this.d, required this.room, required this.pal, required this.issues});
  final Designer d;
  final Json room;
  final AppPalette pal;
  final List<Issue> issues;

  @override
  State<_PagedGrid> createState() => _PagedGridState();
}

class _PagedGridState extends State<_PagedGrid> {
  late final PageController _pc = PageController(initialPage: _index());
  bool _animating = false;

  int _index() {
    final ss = subsOf(widget.room);
    final i = ss.indexWhere((x) => x['id'] == widget.d.sub?['id']);
    return i < 0 ? 0 : i;
  }

  @override
  void didUpdateWidget(covariant _PagedGrid old) {
    super.didUpdateWidget(old);
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  Future<void> _sync() async {
    if (!mounted || !_pc.hasClients) return;
    final target = _index();
    final cur = _pc.page ?? target.toDouble();
    if ((cur - target).abs() < 0.01 || _animating) return;
    // Only animate when the change did not come from the user's own drag.
    if (_pc.position.isScrollingNotifier.value) return;
    _animating = true;
    await _pc.animateToPage(target, duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic);
    _animating = false;
  }

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ss = subsOf(widget.room);
    return PageView.builder(
      controller: _pc,
      itemCount: ss.length,
      // Swiping between pages only in test mode; while designing it would
      // get in the way of dragging and resizing cards.
      physics: widget.d.test ? const PageScrollPhysics(parent: ClampingScrollPhysics()) : const NeverScrollableScrollPhysics(),
      onPageChanged: (i) {
        if (_animating || i < 0 || i >= ss.length) return;
        if (ss[i]['id'] != widget.d.sub?['id']) widget.d.selectSub(widget.room['id'] as String, ss[i]['id'] as String);
      },
      itemBuilder: (context, i) => Padding(
        padding: EdgeInsets.all(widget.pal.safeMargin),
        child: _GridArea(key: ValueKey<String>('ga-${ss[i]['id']}'), d: widget.d, box: ss[i], groupId: null, pal: widget.pal, issues: widget.issues),
      ),
    );
  }
}

/// Screen background (default, color or image) and the text colors that
/// stay readable on it.
class ScreenBg {
  const ScreenBg(this.decoration, this.ink, this.muted, {this.blur = 0, this.key = ''});
  final BoxDecoration decoration;
  final Color ink, muted;

  /// Blur of a page background image (0 = sharp).
  final double blur;

  /// Identifies the look, so the fade between pages runs only when it changes.
  final String key;
}

final Map<String, MemoryImage> _pageImages = {};

/// Background of one page (sub-page), drawn over the common background:
/// a color or an image, each with its own opacity. Null = none.
ScreenBg? pageBackground(Json? sub, ScreenBg screen, Json theme) {
  final b = jsonMap(sub?['bg']);
  final mode = (b['mode'] ?? 'default').toString();
  if (mode != 'color' && mode != 'image') return null;
  // One brightness control: 100 = original, below darkens, above lightens.
  // (Older pages stored "dim" instead.)
  final legacyDim = (b['dim'] as num?)?.toDouble();
  final br = ((b['bright'] as num?)?.toDouble() ?? (legacyDim != null ? 100 - legacyDim : 100)).clamp(20, 150).toDouble();
  final textMode = (b['text'] ?? theme['bgText'] ?? 'auto').toString();
  final op = (((b['opacity'] as num?) ?? 100).toDouble().clamp(0, 100)) / 100;
  final under = screen.decoration.color ?? Colors.white;
  ({Color ink, Color muted}) text(bool darkBg) {
    final dark = textMode == 'light' || (textMode == 'auto' && darkBg);
    return dark ? (ink: Colors.white, muted: Colors.white.withValues(alpha: 0.75)) : (ink: const Color(0xFF1B2320), muted: const Color(0xFF55605C));
  }

  Color shade(Color c) => br < 100 ? Color.lerp(c, Colors.black, (100 - br) / 100)! : Color.lerp(c, Colors.white, (br - 100) / 100)!;
  if (mode == 'color') {
    final c = shade(hexColor(b['color']) ?? under).withValues(alpha: op);
    final tx = text(Color.alphaBlend(c, under).computeLuminance() < 0.35);
    return ScreenBg(BoxDecoration(color: c), tx.ink, tx.muted, key: 'c|${sub?['id']}');
  }
  final data = (b['image'] ?? '').toString();
  final i = data.indexOf('base64,');
  if (i <= 0) return null;
  var img = _pageImages[data];
  if (img == null) {
    try {
      img = MemoryImage(base64Decode(data.substring(i + 7)));
      if (_pageImages.length > 20) _pageImages.clear();
      _pageImages[data] = img;
    } catch (_) {
      return null;
    }
  }
  final blur = ((b['blur'] as num?) ?? 0).toDouble().clamp(0, 20).toDouble();
  final overlay = br < 100 ? Colors.black.withValues(alpha: (100 - br) / 100) : Colors.white.withValues(alpha: (br - 100) / 100);
  final tx = text(op >= 0.5 ? br <= 80 : under.computeLuminance() < 0.35);
  return ScreenBg(
    BoxDecoration(
      image: DecorationImage(image: img, fit: BoxFit.cover, opacity: op, colorFilter: ColorFilter.mode(overlay, BlendMode.srcOver)),
    ),
    tx.ink,
    tx.muted,
    blur: blur,
    key: 'i|${sub?['id']}|${data.length}',
  );
}

ScreenBg screenBackground(Json doc, AppPalette base) {
  // Backgrounds are set per page now; the common one follows the App theme.
  return ScreenBg(BoxDecoration(color: base.screen), base.sInk, base.sMuted);
}

/// The App's settings screen, opened from the gear button in the preview.
class _AppSettingsSheet extends StatelessWidget {
  const _AppSettingsSheet({required this.d, required this.pal});
  final Designer d;
  final AppPalette pal;

  @override
  Widget build(BuildContext context) {
    final doc = d.doc;
    final projMode = themeKey(jsonMap(doc['theme'])['mode']);
    final cur = d.previewTheme ?? projMode;
    final online = d.bus?.connected == true && d.live;
    Widget card(String title, List<Widget> children) => Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 6, bottom: 6),
            child: Text(
              title.toUpperCase(),
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.4, color: pal.muted),
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
                for (var i = 0; i < children.length; i++) ...[children[i], if (i < children.length - 1) Divider(height: 1, indent: 16, color: pal.line)],
              ],
            ),
          ),
        ],
      ),
    );
    Widget row(Widget leading, String text, {String? sub, Widget? trailing, VoidCallback? onTap}) => InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            leading,
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(text, style: TextStyle(fontSize: 15, color: pal.ink)),
                  if (sub != null) ...[const SizedBox(height: 2), Text(sub, style: TextStyle(fontSize: 12.5, color: pal.muted))],
                ],
              ),
            ),
            if (trailing != null) trailing,
          ],
        ),
      ),
    );
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 1, end: 0),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => FractionalTranslation(translation: Offset(0, t), child: child),
      child: Container(
        color: pal.screen,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 38),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Settings',
                      style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: pal.ink),
                    ),
                  ),
                  InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => d.toggleAppSettings(false),
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: pal.panel,
                        shape: BoxShape.circle,
                        border: Border.all(color: pal.tileEdge),
                      ),
                      child: Icon(Icons.close, size: 18, color: pal.ink),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                children: [
                  card('Account', [
                    row(
                      CircleAvatar(
                        radius: 18,
                        backgroundColor: pal.accentSoft,
                        child: Icon(Icons.person_outline, color: pal.accent, size: 20),
                      ),
                      'Not signed in',
                      sub: 'Accounts and user permissions will come in a later version',
                    ),
                  ]),
                  card('Appearance', [
                    for (final (group, items) in kAppThemeGroups) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                        child: Text(
                          group.toUpperCase(),
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: pal.muted),
                        ),
                      ),
                      for (final (k, n) in items)
                        row(
                          ThemeSwatch(AppPalette.of(k), size: 26),
                          n,
                          sub: k == projMode ? 'Project default' : null,
                          trailing: k == cur ? Icon(Icons.check, color: pal.accent, size: 20) : null,
                          onTap: () => d.setPreviewTheme(k == projMode ? null : k),
                        ),
                    ],
                  ]),
                  card('KNX connection', [
                    for (final c in jsonList(doc['connections']))
                      row(
                        Icon(Icons.router_outlined, color: pal.muted, size: 22),
                        (c['name'] ?? 'Connections').toString(),
                        sub: '${c['host'] ?? ''}:${c['port'] ?? 3671}${c['natMode'] == true ? ' · NAT' : ''}',
                        trailing: Text(online ? 'Connected' : 'Simulator', style: TextStyle(fontSize: 12.5, color: online ? pal.accent : pal.muted)),
                      ),
                  ]),
                  card('About', [
                    row(Icon(Icons.info_outline, color: pal.muted, size: 22), 'EvoKNX', sub: 'Version 1.0 · © ${DateTime.now().year} Evohome'),
                    row(Icon(Icons.palette_outlined, color: pal.muted, size: 22), 'Icon', sub: 'Material Design Icons · Pictogrammers (Apache 2.0)'),
                    row(
                      Icon(Icons.home_work_outlined, color: pal.muted, size: 22),
                      (jsonMap(doc['project'])['name'] ?? '').toString(),
                      sub: 'Configuration version ${jsonMap(doc['project'])['revision'] ?? 0}',
                    ),
                  ]),
                  Text(
                    'This is a preview. The theme choice here is only for trying: it does not change the project\'s setting; in the App each user picks their own theme.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: pal.muted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Scene confirmation popup: blurs the screen behind, shows the scene's
/// picture/icon and the message, disappears after the set time (max 5 s).
class _ScenePopup extends StatelessWidget {
  const _ScenePopup({required this.d, required this.w, required this.pal});
  final Designer d;
  final Json w;
  final AppPalette pal;

  @override
  Widget build(BuildContext context) {
    final pp = jsonMap(w['popup']);
    final blur = ((pp['blur'] as num?) ?? 8).toDouble().clamp(0, 30).toDouble();
    final size = ((pp['size'] as num?) ?? 20).toDouble().clamp(12, 40).toDouble();
    final label = (w['label'] ?? '').toString();
    final text = ((pp['text'] ?? 'Scene {name} activated').toString()).replaceAll('{name}', label).replaceAll('{tên}', label).replaceAll('{ten}', label);
    final image = w['btnStyle'] == 'image' && w['imgSource'] != 'icon' ? imageFromData((w['image'] ?? '').toString()) : null;
    final iconKey = w['btnStyle'] == 'image' && w['imgSource'] == 'icon' ? (w['imgIcon'] ?? 'mdi:gesture-tap-button').toString() : (w['icon'] as String?);
    return GestureDetector(
      onTap: d.hidePopup,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        builder: (context, t, child) => Opacity(
          opacity: t,
          child: Transform.scale(scale: 0.96 + 0.04 * t, child: child),
        ),
        child: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
            child: ColoredBox(
              color: Colors.black.withValues(alpha: 0.12),
              child: Center(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 260),
                  padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
                  decoration: BoxDecoration(
                    color: pal.tile.withValues(alpha: 0.94),
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 24, offset: Offset(0, 8))],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(width: 64, height: 64, child: image ?? Center(child: iconWidget(iconKey, 44, pal.accent))),
                      const SizedBox(height: 12),
                      Text(
                        text,
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: size, fontWeight: FontWeight.w600, color: pal.ink, height: 1.25),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
