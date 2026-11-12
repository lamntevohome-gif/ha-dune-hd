import 'dart:typed_data';

import 'address.dart';
import 'dpt.dart';
import 'telegram.dart';

/// cEMI message codes.
class CemiCode {
  static const int lDataReq = 0x11;
  static const int lDataCon = 0x2E;
  static const int lDataInd = 0x29;
}

class Apci {
  static const int read = 0x000;
  static const int response = 0x040;
  static const int write = 0x080;
}

/// cEMI L_Data frame (group communication only).
class CemiFrame {
  final int messageCode;
  final int ctrl1;
  final int ctrl2;
  final IndividualAddress source;
  final int destination;
  final bool groupDestination;
  final int apci;
  final List<int> data;
  final bool shortData;

  CemiFrame({
    required this.messageCode,
    this.ctrl1 = 0xBC,
    this.ctrl2 = 0xE0,
    this.source = const IndividualAddress(0),
    required this.destination,
    this.groupDestination = true,
    required this.apci,
    this.data = const [],
    this.shortData = true,
  });

  /// Confirmation flag (ctrl1 bit 0): 0 = OK, 1 = error. Only for L_Data.con.
  bool get confirmError => (ctrl1 & 0x01) != 0;

  /// Builds an L_Data.req for a group read/write/response.
  factory CemiFrame.groupRequest(GroupAddress ga, TelegramType type, [KnxPayload? payload]) {
    final apci = type == TelegramType.read ? Apci.read : (type == TelegramType.write ? Apci.write : Apci.response);
    if (type == TelegramType.read || payload == null) {
      return CemiFrame(messageCode: CemiCode.lDataReq, destination: ga.raw, apci: apci, data: const [], shortData: true);
    }
    return CemiFrame(
      messageCode: CemiCode.lDataReq,
      destination: ga.raw,
      apci: apci,
      data: payload.short ? [payload.shortValue] : payload.bytes,
      shortData: payload.short,
    );
  }

  Uint8List toBytes() {
    final b = BytesBuilder();
    b.addByte(messageCode);
    b.addByte(0x00); // additional info length
    b.addByte(ctrl1);
    b.addByte(ctrl2);
    b.addByte((source.raw >> 8) & 0xFF);
    b.addByte(source.raw & 0xFF);
    b.addByte((destination >> 8) & 0xFF);
    b.addByte(destination & 0xFF);
    if (shortData) {
      b.addByte(1);
      b.addByte((apci >> 8) & 0x03);
      b.addByte((apci & 0xC0) | (data.isEmpty ? 0 : data.first & 0x3F));
    } else {
      b.addByte(1 + data.length);
      b.addByte((apci >> 8) & 0x03);
      b.addByte(apci & 0xC0);
      b.add(data);
    }
    return b.toBytes();
  }

  /// Parses a cEMI L_Data frame. Returns null for unsupported frames.
  static CemiFrame? parse(List<int> bytes) {
    if (bytes.length < 10) return null;
    final code = bytes[0];
    final addLen = bytes[1];
    var i = 2 + addLen;
    if (bytes.length < i + 9) return null;
    final c1 = bytes[i], c2 = bytes[i + 1];
    final src = (bytes[i + 2] << 8) | bytes[i + 3];
    final dst = (bytes[i + 4] << 8) | bytes[i + 5];
    final len = bytes[i + 6];
    final tpci = bytes[i + 7];
    final apciLo = bytes[i + 8];
    final apci = ((tpci & 0x03) << 8) | (apciLo & 0xC0);
    final group = (c2 & 0x80) != 0;
    List<int> data;
    bool short;
    if (len <= 1) {
      data = [apciLo & 0x3F];
      short = true;
    } else {
      final start = i + 9;
      final end = (start + len - 1).clamp(start, bytes.length);
      data = bytes.sublist(start, end);
      short = false;
    }
    return CemiFrame(
      messageCode: code,
      ctrl1: c1,
      ctrl2: c2,
      source: IndividualAddress(src),
      destination: dst,
      groupDestination: group,
      apci: apci & 0x3C0,
      data: data,
      shortData: short,
    );
  }

  TelegramType? get telegramType {
    switch (apci & 0x3C0) {
      case Apci.read:
        return TelegramType.read;
      case Apci.response:
        return TelegramType.response;
      case Apci.write:
        return TelegramType.write;
    }
    return null;
  }

  KnxTelegram? toTelegram({bool outgoing = false}) {
    final t = telegramType;
    if (t == null || !groupDestination) return null;
    return KnxTelegram(
      source: source,
      destination: GroupAddress(destination),
      type: t,
      data: t == TelegramType.read ? const [] : data,
      outgoing: outgoing,
    );
  }
}
