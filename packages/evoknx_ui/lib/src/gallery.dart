import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:knx_config/knx_config.dart';

import 'i18n.dart' show tr;
import 'icons.dart';
import 'model.dart';
import 'tiles.dart';

final Map<String, MemoryImage> _covers = {};

MemoryImage? _coverOf(String data) {
  final i = data.indexOf('base64,');
  if (i < 0) return null;
  return _covers['${data.length}:${data.hashCode}'] ??= MemoryImage(base64Decode(data.substring(i + 7)));
}

/// The room gallery: a grid of room cards (cover image or color, icon, name).
/// Tapping a card opens the room. Used by the App and by the Editor preview.
class RoomGallery extends StatelessWidget {
  const RoomGallery({super.key, required this.doc, required this.rooms, required this.pal, required this.onOpen, this.unlocked});
  final Json doc;
  final List<Json> rooms;
  final AppPalette pal;
  final void Function(String roomId) onOpen;

  /// Ids of the locks that are open (a card with a lock that is not in this set shows a padlock).
  final Set<String>? unlocked;

  @override
  Widget build(BuildContext context) {
    if (rooms.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: Text(
            tr('This floor has no rooms yet.'),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: pal.sMuted),
          ),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, bc) {
        final w = bc.maxWidth;
        // One column of 16:9 cards (two columns on a wide tablet).
        final cols = w >= 760 ? 2 : 1;
        return GridView.builder(
          padding: EdgeInsets.all(pal.safeMargin),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: cols, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 16 / 9),
          itemCount: rooms.length,
          itemBuilder: (context, i) => _RoomCard(
            doc: doc,
            room: rooms[i],
            pal: pal,
            locked: RegExp(r'^\d{4}$').hasMatch((rooms[i]['lock'] ?? '').toString()) && !(unlocked?.contains(rooms[i]['id']) ?? false),
            onTap: () => onOpen(rooms[i]['id'] as String),
          ),
        );
      },
    );
  }
}

class _RoomCard extends StatelessWidget {
  const _RoomCard({required this.doc, required this.room, required this.pal, required this.onTap, this.locked = false});
  final bool locked;
  final Json doc, room;
  final AppPalette pal;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(pal.radius + 4);
    final cover = (room['cover'] ?? '').toString();
    final img = cover.isEmpty ? null : _coverOf(cover);
    final f = tfs(doc, 'galleryTitle');
    final fg = img != null ? Colors.white : pal.ink;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        border: Border.all(color: pal.edge),
      ),
      child: Material(
        color: img != null ? Colors.black : pal.tile,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (img != null)
                Image(image: img, fit: BoxFit.cover, gaplessPlayback: true)
              else
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [pal.tileOn ?? pal.accentSoft, pal.tile]),
                  ),
                ),
              if (img != null)
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black.withValues(alpha: 0.62)],
                      stops: const [0.45, 1],
                    ),
                  ),
                ),
              Positioned(left: 12, top: 12, child: iconWidget(room['icon'] as String?, f * 1.65, fg)),
              if (locked)
                Positioned(
                  right: 10,
                  top: 10,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.35), shape: BoxShape.circle),
                    child: const Icon(Icons.lock_outline, size: 16, color: Colors.white),
                  ),
                ),
              Positioned(
                left: 14,
                right: 12,
                bottom: 12,
                child: Text(
                  (room['title'] ?? '').toString(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: f,
                    fontWeight: FontWeight.w600,
                    color: fg,
                    shadows: img != null ? const [Shadow(blurRadius: 6, color: Colors.black54)] : null,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
