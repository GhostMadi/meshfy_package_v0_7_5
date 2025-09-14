import 'dart:typed_data';

class MsgKind {
  static const int userText  = 1;
  static const int userBinary = 2;
  static const int userJson  = 3;
  static const int mediaMeta = 10;
  static const int mediaChunk = 11;
}

class Flags {
  static const int broadcast = 0x01;
  static const int needsAck = 0x02;
}

class Envelope {
  final int kind;
  final int channelId;
  final Uint8List payload;
  Envelope(this.kind, this.channelId, Uint8List data) : payload = data;
  Uint8List toBytes() {
    final b = BytesBuilder();
    b.add([0x4D, 0x46, 0x01]); // 'M','F',version=1
    b.add([kind & 0xFF]);
    b.add([channelId & 0xFF, (channelId >> 8) & 0xFF]);
    final len = payload.length;
    b.add([len & 0xFF, (len>>8)&0xFF, (len>>16)&0xFF, (len>>24)&0xFF]);
    b.add(payload);
    return Uint8List.fromList(b.toBytes());
  }
}

class MeshHeader {
  final int version;
  final int ttl;
  final int flags;
  final int chunkIndex;
  final int chunkCount;
  final Uint8List messageId;
  final Uint8List src;
  final Uint8List dst;
  MeshHeader({
    required this.version,
    required this.ttl,
    required this.flags,
    required this.chunkIndex,
    required this.chunkCount,
    required this.messageId,
    required this.src,
    required this.dst,
  });
  Uint8List toBytes() {
    final b = BytesBuilder();
    b.add([version & 0xFF, ttl & 0xFF, flags & 0xFF]);
    b.add([chunkIndex & 0xFF, (chunkIndex>>8)&0xFF]);
    b.add([chunkCount & 0xFF, (chunkCount>>8)&0xFF]);
    b.add(messageId);
    b.add(src);
    b.add(dst);
    return Uint8List.fromList(b.toBytes());
  }
}

class Frame {
  final MeshHeader header;
  final Uint8List payload;
  Frame(this.header, this.payload);
  Uint8List toBytes() {
    final b = BytesBuilder();
    b.add(header.toBytes());
    b.add(payload);
    return Uint8List.fromList(b.toBytes());
  }
}
