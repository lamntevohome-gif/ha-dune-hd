import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_svg/flutter_svg.dart';
import 'package:knx_config/knx_config.dart';

/// Icon keys used in project files (shared with the web editor) mapped to
/// Material icons.
const Map<String, IconData> kIconData = {
  // lights
  'bulb': Icons.lightbulb_outline,
  'downlight': Icons.light,
  'spot': Icons.highlight,
  'ceiling': Icons.light_outlined,
  'pendant': Icons.emoji_objects_outlined,
  'chandelier': Icons.wb_iridescent_outlined,
  'wall': Icons.wb_incandescent_outlined,
  'strip': Icons.linear_scale,
  'flood': Icons.flashlight_on,
  'table': Icons.emoji_objects,
  'sun': Icons.wb_sunny_outlined,
  // devices
  'blind': Icons.blinds,
  'curtain': Icons.curtains,
  'thermo': Icons.thermostat,
  'drop': Icons.water_drop_outlined,
  'snow': Icons.ac_unit,
  'fan': Icons.air,
  'tv': Icons.tv,
  'camera': Icons.videocam_outlined,
  'plug': Icons.power_outlined,
  'power': Icons.power_settings_new,
  'door': Icons.door_front_door_outlined,
  'button': Icons.radio_button_checked,
  'star': Icons.star_outline,
  'link': Icons.link,
  'globe': Icons.language,
  'layout': Icons.grid_view,
  'flame': Icons.local_fire_department_outlined,
  'acauto': Icons.autorenew,
  // rooms / floors
  'home': Icons.home_outlined,
  'sofa': Icons.weekend_outlined,
  'bed': Icons.bed_outlined,
  'kids': Icons.child_care_outlined,
  'kitchen': Icons.kitchen_outlined,
  'dining': Icons.dining_outlined,
  'bath': Icons.bathtub_outlined,
  'desk': Icons.desk,
  'cinema': Icons.theaters_outlined,
  'gym': Icons.fitness_center,
  'laundry': Icons.local_laundry_service_outlined,
  'stairs': Icons.stairs_outlined,
  'garage': Icons.garage_outlined,
  'balcony': Icons.balcony,
  'leaf': Icons.yard_outlined,
  'pool': Icons.pool,
};

IconData iconOf(String? key) => kIconData[key] ?? Icons.lightbulb_outline;

/// The App shows MDI icons only. Older projects (and card type defaults)
/// use these short keys, which are drawn with the matching MDI icon.
const Map<String, String> kLegacyToMdi = {
  'bulb': 'lightbulb-outline',
  'downlight': 'ceiling-light-outline',
  'spot': 'spotlight-beam',
  'ceiling': 'ceiling-light',
  'pendant': 'ceiling-light-multiple-outline',
  'chandelier': 'chandelier',
  'wall': 'wall-sconce-outline',
  'strip': 'led-strip-variant',
  'flood': 'flashlight',
  'table': 'desk-lamp',
  'sun': 'weather-sunny',
  'blind': 'blinds',
  'curtain': 'curtains',
  'thermo': 'thermostat',
  'drop': 'water-outline',
  'snow': 'snowflake',
  'fan': 'fan',
  'tv': 'television',
  'camera': 'cctv',
  'plug': 'power-socket-eu',
  'power': 'power',
  'door': 'door',
  'button': 'gesture-tap-button',
  'star': 'star-outline',
  'link': 'link-variant',
  'globe': 'web',
  'layout': 'view-grid-outline',
  'flame': 'fire',
  'acauto': 'autorenew',
  'home': 'home-outline',
  'sofa': 'sofa-outline',
  'bed': 'bed-outline',
  'kids': 'teddy-bear',
  'kitchen': 'stove',
  'dining': 'silverware-fork-knife',
  'bath': 'bathtub-outline',
  'desk': 'desk',
  'cinema': 'theater',
  'gym': 'dumbbell',
  'laundry': 'washing-machine',
  'stairs': 'stairs',
  'garage': 'garage-variant',
  'balcony': 'balcony',
  'leaf': 'sprout-outline',
  'pool': 'pool',
};

/// The MDI key an icon key is drawn with ('bulb' → 'mdi:lightbulb-outline').
String? mdiKeyOf(String? key) {
  if (key == null) return null;
  final m = kLegacyToMdi[key];
  return m == null ? key : 'mdi:$m';
}

const List<(String, String)> kLightIcons = [
  ('bulb', 'Bóng đèn'),
  ('downlight', 'Đèn downlight'),
  ('spot', 'Đèn spotlight'),
  ('ceiling', 'Đèn ốp trần'),
  ('pendant', 'Đèn thả'),
  ('chandelier', 'Đèn chùm'),
  ('wall', 'Đèn tường'),
  ('strip', 'Đèn LED dây'),
  ('flood', 'Đèn pha'),
  ('table', 'Đèn bàn'),
  ('sun', 'Ánh sáng'),
];

const List<(String, String)> kDeviceIcons = [
  ('blind', 'Rèm cuốn'),
  ('curtain', 'Rèm vải'),
  ('thermo', 'Nhiệt độ'),
  ('drop', 'Độ ẩm'),
  ('snow', 'Máy lạnh'),
  ('fan', 'Quạt'),
  ('tv', 'TV'),
  ('camera', 'Camera'),
  ('plug', 'Ổ cắm'),
  ('power', 'Nguồn'),
  ('door', 'Cửa'),
  ('button', 'Nút'),
  ('star', 'Cảnh'),
  ('link', 'Liên kết'),
  ('globe', 'Trang web'),
  ('layout', 'Khung lưới'),
];

const List<(String, String)> kRoomIcons = [
  ('home', 'Cả nhà'),
  ('sofa', 'Phòng khách'),
  ('bed', 'Phòng ngủ'),
  ('kids', 'Phòng trẻ em'),
  ('kitchen', 'Bếp'),
  ('dining', 'Phòng ăn'),
  ('bath', 'Phòng tắm'),
  ('desk', 'Phòng làm việc'),
  ('cinema', 'Phòng giải trí'),
  ('gym', 'Phòng gym'),
  ('laundry', 'Phòng giặt'),
  ('stairs', 'Cầu thang'),
  ('door', 'Sảnh, lối vào'),
  ('garage', 'Garage'),
  ('balcony', 'Ban công'),
  ('leaf', 'Sân vườn'),
  ('pool', 'Hồ bơi'),
];

const List<(String, String)> kFloorIcons = [
  ('stairs', 'Cầu thang'),
  ('home', 'Nhà'),
  ('door', 'Sảnh'),
  ('garage', 'Tầng hầm, garage'),
  ('balcony', 'Sân thượng, ban công'),
  ('leaf', 'Sân vườn'),
];

String iconName(String? key) {
  for (final l in [kLightIcons, kDeviceIcons, kRoomIcons]) {
    for (final i in l) {
      if (i.$1 == key) return i.$2;
    }
  }
  return key ?? '';
}

// ------------------------------------------------------------------ custom icons

/// A user-uploaded icon stored in the project (`icons` list), shared with
/// the web editor format: {id, name, data: data URL (SVG or PNG)}.
class CustomIcon {
  CustomIcon(this.id, this.name, this.data, this.bytes, this.svg);
  final String id, name, data;
  final Uint8List bytes;
  final bool svg;
}

final Map<String, CustomIcon> _custom = {};

/// Decodes a data URL (base64 or plain text SVG). Returns null if invalid.
({Uint8List bytes, bool svg})? decodeIconData(String data) {
  final m = RegExp(r'^data:image/(svg\+xml|png)(;[^,]*)?,(.*)$', dotAll: true).firstMatch(data);
  if (m == null) return null;
  final svg = m[1] == 'svg+xml';
  try {
    final payload = m[3]!;
    final bytes = (m[2] ?? '').contains('base64') ? base64Decode(payload) : Uint8List.fromList(utf8.encode(Uri.decodeComponent(payload)));
    return (bytes: bytes, svg: svg);
  } catch (_) {
    return null;
  }
}

/// Refreshes the icon registry from the project (cheap when unchanged).
void syncCustomIcons(Json doc) {
  final seen = <String>{};
  for (final i in jsonList(doc['icons'])) {
    final id = (i['id'] ?? '').toString();
    final data = (i['data'] ?? '').toString();
    final name = (i['name'] ?? id).toString();
    if (id.isEmpty) continue;
    seen.add(id);
    final cur = _custom[id];
    if (cur != null && cur.data == data) {
      if (cur.name != name) _custom[id] = CustomIcon(id, name, data, cur.bytes, cur.svg);
      continue;
    }
    final dec = decodeIconData(data);
    if (dec != null) _custom[id] = CustomIcon(id, name, data, dec.bytes, dec.svg);
  }
  _custom.removeWhere((k, _) => !seen.contains(k));
}

List<CustomIcon> get customIcons => _custom.values.toList();
bool isCustomIcon(String? key) => key != null && _custom.containsKey(key);

/// Draws an icon by key: built-in Material icon or a custom (tinted) icon.
/// The icon key meaning "no icon": nothing is drawn.
const String kNoIcon = 'none';
bool isNoIcon(String? key) => key == kNoIcon;

Widget iconWidget(String? key, double size, Color color) {
  if (isNoIcon(key)) return const SizedBox.shrink();
  key = mdiKeyOf(key);
  if (key != null && key.startsWith('mdi:')) {
    final m = Mdi.byName[key.substring(4)];
    // MDI code points are loaded from bundled metadata at runtime.
    // ignore: non_const_argument_for_const_parameter
    final IconData icon = m == null ? Icons.help_outline : IconData(m.cp, fontFamily: 'MDI', fontPackage: 'evoknx_ui');
    return Icon(icon, size: size, color: color);
  }
  final c = key == null ? null : _custom[key];
  if (c == null) return iconWidget('mdi:lightbulb-outline', size, color);
  return SizedBox(
    width: size,
    height: size,
    child: c.svg
        ? SvgPicture.memory(c.bytes, fit: BoxFit.contain, colorFilter: ColorFilter.mode(color, BlendMode.srcIn))
        : Image.memory(c.bytes, fit: BoxFit.contain, color: color, colorBlendMode: BlendMode.srcIn, filterQuality: FilterQuality.medium, gaplessPlayback: true),
  );
}

String iconLabel(String? key) {
  if (isNoIcon(key)) return 'None';
  if (kLegacyToMdi.containsKey(key)) return iconName(key);
  if (key != null && key.startsWith('mdi:')) return key.substring(4);
  return _custom[key]?.name ?? iconName(key);
}

// ------------------------------------------------------------------ MDI library

/// One icon of Material Design Icons (Pictogrammers, Apache 2.0).
class MdiIcon {
  MdiIcon(this.name, this.cp, this.tags, this.search);
  final String name;
  final int cp;
  final List<int> tags;

  /// Lower-case name + aliases, used for searching.
  final String search;
  String get key => 'mdi:$name';
}

/// The bundled Material Design Icons set (font + searchable metadata).
class Mdi {
  static List<MdiIcon> all = const [];
  static List<String> tags = const [];
  static Map<String, MdiIcon> byName = const {};
  static String version = '';

  static Future<void> load() async {
    if (all.isNotEmpty) return;
    try {
      final j = jsonDecode(await rootBundle.loadString('packages/evoknx_ui/assets/mdi/mdi_meta.json')) as Map<String, dynamic>;
      version = (j['version'] ?? '').toString();
      tags = (j['tags'] as List).cast<String>();
      all = [
        for (final e in (j['icons'] as List).cast<List>())
          MdiIcon(e[0] as String, e[1] as int, (e[2] as List).cast<int>(), '${e[0]} ${(e[3] as String).toLowerCase()}'),
      ];
      byName = {for (final i in all) i.name: i};
    } catch (_) {
      all = const [];
    }
  }

  static int tagIndex(String name) => tags.indexOf(name);

  /// Searches by English name/alias/tag, plus common Vietnamese words for
  /// smart-home devices ("đèn", "rèm", "quạt"…). Query must be folded.
  static List<MdiIcon> search(String q, {int? tag}) {
    final terms = <String>{};
    if (q.isNotEmpty) {
      terms.add(q.replaceAll(' ', '-'));
      kMdiVietnamese.forEach((vn, en) {
        if (vn == q || (q.length >= 2 && vn.startsWith(q)) || q.contains(vn)) terms.addAll(en);
      });
    }
    final tagHits = <int>{};
    if (q.length >= 3) {
      for (var i = 0; i < tags.length; i++) {
        if (tags[i].toLowerCase().contains(q)) tagHits.add(i);
      }
    }
    final first = <MdiIcon>[], rest = <MdiIcon>[];
    for (final i in all) {
      if (tag != null && !i.tags.contains(tag)) continue;
      if (terms.isEmpty) {
        rest.add(i);
        continue;
      }
      var hit = false, starts = false;
      for (final t in terms) {
        if (i.search.contains(t)) {
          hit = true;
          if (i.name.startsWith(t)) starts = true;
        }
      }
      if (!hit && tagHits.isNotEmpty && i.tags.any(tagHits.contains)) hit = true;
      if (!hit) continue;
      (starts ? first : rest).add(i);
    }
    return [...first, ...rest];
  }
}

/// Vietnamese names of MDI categories shown in the picker.
const Map<String, String> kMdiTagNames = {
  'Home Automation': 'Nhà thông minh',
  'Weather': 'Thời tiết',
  'Device / Tech': 'Thiết bị công nghệ',
  'Audio': 'Âm thanh',
  'Video / Movie': 'Video, phim',
  'Music': 'Âm nhạc',
  'Lock': 'Khoá, an ninh',
  'Alert / Error': 'Cảnh báo',
  'Notification': 'Thông báo',
  'Battery': 'Pin',
  'Food / Drink': 'Ăn uống',
  'People / Family': 'Người, gia đình',
  'Account / User': 'Tài khoản',
  'Nature': 'Thiên nhiên',
  'Animal': 'Vật nuôi',
  'Automotive': 'Xe hơi',
  'Transportation + Road': 'Giao thông',
  'Places': 'Địa điểm',
  'Sport': 'Thể thao',
  'Medical / Hospital': 'Y tế',
  'Hardware / Tools': 'Dụng cụ',
  'Settings': 'Cài đặt',
  'Date / Time': 'Ngày giờ',
  'Arrow': 'Mũi tên',
  'Shape': 'Hình khối',
  'Holiday': 'Lễ tết',
  'Agriculture': 'Nông nghiệp',
  'Cloud': 'Đám mây',
  'Cellphone / Phone': 'Điện thoại',
  'Photography': 'Ảnh',
  'Gaming / RPG': 'Trò chơi',
  'Shopping': 'Mua sắm',
  'Science': 'Khoa học',
  'Navigation': 'Điều hướng',
  'Alpha / Numeric': 'Chữ, số',
  'Math': 'Toán',
};

/// Vietnamese search words (without diacritics) → English MDI terms.
const Map<String, List<String>> kMdiVietnamese = {
  'den': ['light', 'lamp', 'bulb', 'chandelier', 'led-strip', 'track-light', 'wall-sconce', 'spotlight'],
  'bong den': ['lightbulb'],
  'den chum': ['chandelier'],
  'den ban': ['desk-lamp', 'lamp'],
  'den tran': ['ceiling-light'],
  'den tuong': ['wall-sconce'],
  'den led': ['led', 'led-strip'],
  'rem': ['curtains', 'blinds', 'roller-shade', 'window-shutter'],
  'rem cua': ['curtains'],
  'cuon': ['roller-shade', 'window-shutter'],
  'quat': ['fan', 'ceiling-fan'],
  'may lanh': ['air-conditioner', 'snowflake', 'hvac'],
  'dieu hoa': ['air-conditioner', 'hvac', 'thermostat'],
  'nhiet do': ['thermometer', 'thermostat', 'temperature'],
  'do am': ['water-percent', 'humidity'],
  'suoi': ['radiator', 'heat'],
  'loc khi': ['air-filter', 'air-purifier'],
  'cua': ['door', 'gate', 'garage', 'window'],
  'cua so': ['window'],
  'cong': ['gate'],
  'nha xe': ['garage'],
  'khoa': ['lock', 'key'],
  'chia khoa': ['key'],
  'camera': ['cctv', 'camera', 'webcam'],
  'an ninh': ['shield', 'security', 'alarm'],
  'bao dong': ['alarm', 'siren', 'bell'],
  'chuong': ['bell', 'doorbell'],
  'cam bien': ['motion-sensor', 'smoke-detector', 'leak', 'sensor'],
  'chuyen dong': ['motion-sensor', 'walk', 'run'],
  'khoi': ['smoke'],
  'ro ri': ['leak', 'water-alert'],
  'tivi': ['television', 'tv'],
  'tv': ['television'],
  'loa': ['speaker'],
  'am thanh': ['volume', 'speaker', 'music'],
  'nhac': ['music'],
  'phim': ['movie', 'filmstrip', 'theater'],
  'rap': ['theater', 'projector'],
  'may chieu': ['projector'],
  'o cam': ['power-socket', 'power-plug'],
  'cong tac': ['light-switch', 'toggle-switch', 'power'],
  'nguon': ['power'],
  'dien': ['flash', 'lightning-bolt', 'meter-electric', 'transmission-tower'],
  'nang luong': ['solar-power', 'lightning-bolt', 'battery', 'flash'],
  'mat troi': ['weather-sunny', 'solar'],
  'pin': ['battery'],
  'nuoc': ['water', 'faucet', 'shower'],
  'voi': ['faucet'],
  'tam': ['shower', 'bathtub'],
  'nong lanh': ['water-boiler', 'water-thermometer'],
  'ho boi': ['pool'],
  'tuoi': ['sprinkler', 'watering-can'],
  'vuon': ['flower', 'tree', 'grass', 'sprinkler'],
  'bep': ['stove', 'pot', 'chef-hat', 'microwave', 'fridge'],
  'tu lanh': ['fridge'],
  'lo': ['stove', 'microwave', 'toaster-oven'],
  'may giat': ['washing-machine'],
  'may say': ['tumble-dryer'],
  'rua bat': ['dishwasher'],
  'hut bui': ['robot-vacuum', 'vacuum'],
  'robot': ['robot-vacuum', 'robot'],
  'giuong': ['bed'],
  'ngu': ['bed', 'sleep', 'power-sleep'],
  'sofa': ['sofa'],
  'ghe': ['chair', 'seat'],
  'ban': ['table', 'desk'],
  'nha': ['home', 'house'],
  'phong': ['home', 'floor-plan', 'door'],
  'tang': ['stairs', 'floor-plan', 'home-floor'],
  'thang may': ['elevator'],
  'cau thang': ['stairs'],
  'xe': ['car', 'motorbike', 'bicycle'],
  'sac': ['ev-station', 'battery-charging', 'power-plug'],
  'wifi': ['wifi', 'router'],
  'mang': ['lan', 'router', 'network'],
  'canh': ['palette', 'movie-open', 'weather-night', 'home-heart'],
  'dem': ['weather-night', 'moon'],
  'sang': ['weather-sunny', 'brightness'],
  'thoi tiet': ['weather'],
  'mua': ['weather-rainy', 'umbrella'],
  'gio': ['weather-windy', 'fan', 'clock'],
  'dong ho': ['clock', 'timer'],
  'hen gio': ['timer', 'alarm'],
  'cai dat': ['cog', 'tune'],
  'nguoi': ['account', 'human'],
  'tre em': ['baby', 'human-child'],
  'thu cung': ['dog', 'cat', 'paw'],
  'cho': ['dog'],
  'meo': ['cat'],
};
