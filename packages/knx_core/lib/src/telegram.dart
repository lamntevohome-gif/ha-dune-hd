import 'address.dart';

enum TelegramType { read, response, write }

/// A group telegram seen on (or sent to) the bus.
class KnxTelegram {
  final DateTime time;
  final IndividualAddress source;
  final GroupAddress destination;
  final TelegramType type;

  /// Data: for short (≤6 bit) values a single element list; otherwise bytes.
  final List<int> data;
  final bool outgoing;

  KnxTelegram({
    DateTime? time,
    required this.source,
    required this.destination,
    required this.type,
    this.data = const [],
    this.outgoing = false,
  }) : time = time ?? DateTime.now();

  @override
  String toString() => '$source -> $destination ${type.name} ${data.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}';
}
