import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'meshfy_api.dart';
import 'protocol.dart';

class MediaDescriptor {
  final String fileId; // base64(16B)
  final String name;
  final String mime;
  final int size;
  final int chunkSize;
  final int totalChunks;
  final String? thumbnailBase64;
  MediaDescriptor({
    required this.fileId,
    required this.name,
    required this.mime,
    required this.size,
    required this.chunkSize,
    required this.totalChunks,
    this.thumbnailBase64,
  });

  Map<String, dynamic> toJson() => {
    'fileId': fileId,
    'name': name,
    'mime': mime,
    'size': size,
    'chunkSize': chunkSize,
    'totalChunks': totalChunks,
    'thumbnailBase64': thumbnailBase64,
  };

  static MediaDescriptor fromJson(Map<String, dynamic> m) => MediaDescriptor(
    fileId: m['fileId'] as String,
    name: m['name'] as String,
    mime: m['mime'] as String,
    size: (m['size'] as num).toInt(),
    chunkSize: (m['chunkSize'] as num).toInt(),
    totalChunks: (m['totalChunks'] as num).toInt(),
    thumbnailBase64: m['thumbnailBase64'] as String?,
  );
}

abstract class MediaDelegate {
  void onMediaProgress(String fileId, int receivedChunks, int totalChunks, {bool outgoing = false}) {}
  void onMediaCompleted(String fileId, File file, MediaDescriptor meta, {bool outgoing = false}) {}
  void onMediaFailed(String fileId, Object error, {bool outgoing = false}) {}
}

class MediaTransfer {
  final Meshfy mesh;
  final MediaDelegate delegate;
  final int appChunkSize; // default ~24KB
  MediaTransfer(this.mesh, this.delegate, {this.appChunkSize = 24 * 1024});

  Future<void> sendFile(File file, {required MeshfySendOptions options, String? displayName, String mime = 'application/octet-stream', String? thumbnailBase64}) async {
    final bytes = await file.readAsBytes();
    final size = bytes.length;
    final chunk = appChunkSize;
    final total = (size / chunk).ceil();
    final fileIdBytes = randomMsgId(); // 16B
    final fileId = base64.encode(fileIdBytes);
    final meta = MediaDescriptor(
      fileId: fileId,
      name: displayName ?? file.uri.pathSegments.last,
      mime: mime,
      size: size,
      chunkSize: chunk,
      totalChunks: total,
      thumbnailBase64: thumbnailBase64,
    );
    final metaJson = Uint8List.fromList(utf8.encode(jsonEncode(meta.toJson())));
    await mesh.sendKind(metaJson, kind: MsgKind.mediaMeta, options: options.copyWith(binary: true));

    int sent = 0;
    for (int i = 0; i < total; i++) {
      final start = i * chunk;
      final end = (start + chunk <= size) ? start + chunk : size;
      final part = bytes.sublist(start, end);
      final body = BytesBuilder();
      body.add(base64.decode(fileId));
      body.add([i & 0xff, (i>>8)&0xff, (i>>16)&0xff, (i>>24)&0xff]);
      body.add(part);
      try {
        await mesh.sendKind(Uint8List.fromList(body.toBytes()), kind: MsgKind.mediaChunk, options: options.copyWith(binary: true, requireAck: true));
        sent += 1;
        delegate.onMediaProgress(fileId, sent, total, outgoing: true);
      } catch (e) {
        delegate.onMediaFailed(fileId, e, outgoing: true);
        rethrow;
      }
    }
    delegate.onMediaCompleted(fileId, file, meta, outgoing: true);
  }

  final Map<String, _RxMedia> _rx = {};

  Future<void> onEnvelope(MeshfyMessage msg) async {
    if (msg.kind == MsgKind.mediaMeta) {
      try {
        final meta = MediaDescriptor.fromJson(jsonDecode(utf8.decode(msg.data)) as Map<String, dynamic>);
        final tmp = await _tmpFile(meta.fileId, meta.name);
        _rx[meta.fileId] = _RxMedia(meta: meta, file: tmp);
      } catch (_) {}
    } else if (msg.kind == MsgKind.mediaChunk) {
      final data = msg.data;
      if (data.length < 16 + 4) return;
      final fileId = base64.encode(data.sublist(0,16));
      final idx = data[16] | (data[17]<<8) | (data[18]<<16) | (data[19]<<24);
      final bytes = data.sublist(20);
      final rx = _rx[fileId];
      if (rx == null) return;
      await rx.put(idx, bytes);
      delegate.onMediaProgress(fileId, rx.receivedChunks, rx.meta.totalChunks, outgoing: false);
      if (rx.isComplete) {
        await rx.flushAndClose();
        delegate.onMediaCompleted(fileId, rx.file, rx.meta, outgoing: false);
        _rx.remove(fileId);
      }
    }
  }

  Future<File> _tmpFile(String fileId, String name) async {
    final dir = await getTemporaryDirectory();
    final safe = name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    return File('${dir.path}/mf_${fileId.substring(0,8)}_$safe.part');
  }
}

class _RxMedia {
  final MediaDescriptor meta;
  final File file;
  RandomAccessFile? _raf;
  final Set<int> _have = {};
  int receivedChunks = 0;
  _RxMedia({required this.meta, required this.file});

  Future<void> put(int idx, List<int> bytes) async {
    if (_raf == null) {
      await file.create(recursive: true);
      _raf = await file.open(mode: FileMode.write);
    }
    final pos = idx * meta.chunkSize;
    await _raf!.setPosition(pos);
    await _raf!.writeFrom(bytes);
    if (_have.add(idx)) {
      receivedChunks += 1;
    }
  }

  bool get isComplete => receivedChunks >= meta.totalChunks;

  Future<void> flushAndClose() async {
    await _raf?.flush();
    await _raf?.close();
    _raf = null;
  }
}
