// Public Meshfy API — v0.7.5 (stub native layer)
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:crypto/crypto.dart' as crypto;

import 'protocol.dart';

typedef DeviceId = Uint8List;

enum QosClass { realtime, normal, background }
enum RoutingMode { simple, adaptive }
enum MeshfyState { stopped, starting, running }

class MeshfyConfig {
  final int ttl;
  final int txRateFps;
  final RoutingMode routingMode;
  final bool persistentOutbox;
  const MeshfyConfig({
    this.ttl = 6,
    this.txRateFps = 45,
    this.routingMode = RoutingMode.adaptive,
    this.persistentOutbox = true,
  });
}

class MeshfySendOptions {
  final DeviceId? to;
  final bool requireAck;
  final int channelId;
  final bool binary;
  final int priority;
  final QosClass qos;
  const MeshfySendOptions({
    this.to,
    this.requireAck = false,
    this.channelId = 0,
    this.binary = false,
    this.priority = 2,
    this.qos = QosClass.normal,
  });
  MeshfySendOptions copyWith({
    DeviceId? to, bool? requireAck, int? channelId, bool? binary, int? priority, QosClass? qos,
  }) => MeshfySendOptions(
        to: to ?? this.to,
        requireAck: requireAck ?? this.requireAck,
        channelId: channelId ?? this.channelId,
        binary: binary ?? this.binary,
        priority: priority ?? this.priority,
        qos: qos ?? this.qos,
      );
}

class MeshfyMessage {
  final Uint8List messageId;
  final DeviceId from;
  final DeviceId? to;
  final Uint8List data;
  final int channelId;
  final int kind;
  final DateTime receivedAt;
  MeshfyMessage({
    required this.messageId,
    required this.from,
    required this.to,
    required this.data,
    required this.channelId,
    required this.kind,
    required this.receivedAt,
  });
}

class MeshfyJsonMessage {
  final Uint8List messageId;
  final DeviceId from;
  final DeviceId? to;
  final Map<String, dynamic> data;
  final String categoryLabel;
  final int channelId;
  final DateTime receivedAt;
  MeshfyJsonMessage({
    required this.messageId,
    required this.from,
    required this.to,
    required this.data,
    required this.categoryLabel,
    required this.channelId,
    required this.receivedAt,
  });
}

abstract class MeshfyDelegate {
  void onStateChanged(MeshfyState state) {}
  void onNeighbor(Uint8List id, bool connected, {int? rssi}) {}
  void onMessage(MeshfyMessage msg) {}
  void onJsonMessage(MeshfyJsonMessage msg) {}
  void onMessageSent(Uint8List messageId) {}
  void onMessageFailed(Uint8List messageId, Object error) {}
  void onError(Object error, [StackTrace? st]) {}
  void onSessionEstablished(Uint8List peerId) {}
}

class Meshfy {
  static const MethodChannel _peripheral = MethodChannel('mesh_ble/peripheral');
  final MeshfyConfig _config;
  final MeshfyDelegate _delegate;

  late DeviceId _myId;
  final Map<int, Uint8List> _channelKeys = {};
  final int _chunkSize = 150;

  Meshfy(this._config, this._delegate);

  DeviceId get myId => _myId;
  Uint8List randomMsgIdGen() => randomMsgId();

  Future<void> initialize({required List<int> uniqueSeed, bool enableE2EE = true}) async {
    final digestBytes = crypto.sha256.convert(uniqueSeed).bytes;
    _myId = Uint8List.fromList(digestBytes.sublist(0, 6));
    _delegate.onStateChanged(MeshfyState.stopped);
  }

  Future<void> start() async {
    _delegate.onStateChanged(MeshfyState.starting);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    _delegate.onStateChanged(MeshfyState.running);
  }

  Future<void> stop() async { _delegate.onStateChanged(MeshfyState.stopped); }

  Future<void> setChannelKey(int channelId, List<int> key) async {
    _channelKeys[channelId] = Uint8List.fromList(key);
  }

  Future<Uint8List> sendSmsText(String text, {MeshfySendOptions? options}) async {
    final data = Uint8List.fromList(utf8.encode(text));
    final opts = (options ?? const MeshfySendOptions());
    return _sendCore(data, opts, forceKind: MsgKind.userText);
  }

  Future<Uint8List> sendJson(Map<String, dynamic> payload, {MeshfySendOptions? options}) async {
    final bytes = Uint8List.fromList(utf8.encode(jsonEncode(payload)));
    final opts = (options ?? const MeshfySendOptions()).copyWith(binary: true);
    return _sendCore(bytes, opts, forceKind: MsgKind.userJson);
  }

  Future<Uint8List> sendQuiz(Map<String, dynamic> quiz, {MeshfySendOptions? options}) =>
      sendJson({'category': 'quiz', 'data': quiz}, options: options);

  Future<Uint8List> sendInvitation(Map<String, dynamic> inv, {MeshfySendOptions? options}) =>
      sendJson({'category': 'invitation', 'data': inv}, options: options);

  Future<Uint8List> sendKind(Uint8List userData, {required int kind, MeshfySendOptions? options}) async =>
      _sendCore(userData, options ?? const MeshfySendOptions(), forceKind: kind);

  Future<Uint8List> send(Uint8List userData, {MeshfySendOptions? options}) async =>
      _sendCore(userData, options ?? const MeshfySendOptions());

  Future<Uint8List> _sendCore(Uint8List userData, MeshfySendOptions opts, {int? forceKind}) async {
    final msgId = randomMsgId();
    final dst = opts.to ?? Uint8List(6);
    final kind = (forceKind != null) ? forceKind : (opts.binary ? MsgKind.userBinary : MsgKind.userText);
    final env = Envelope(kind, opts.channelId, userData).toBytes();

    final totalChunks = (env.length / _chunkSize).ceil();
    int offset = 0, idx = 0;
    while (offset < env.length) {
      final take = (offset + _chunkSize <= env.length) ? _chunkSize : (env.length - offset);
      final payload = Uint8List.fromList(env.sublist(offset, offset + take));
      final header = MeshHeader(
        version: 1,
        ttl: _config.ttl,
        flags: (opts.to == null ? Flags.broadcast : 0) | (opts.requireAck ? Flags.needsAck : 0),
        chunkIndex: idx,
        chunkCount: totalChunks,
        messageId: msgId,
        src: _myId,
        dst: dst,
      );
      final frame = Frame(header, payload);
      try {
        await _peripheral.invokeMethod('emitFrame', {'bytes': frame.toBytes()});
      } on MissingPluginException {
        // In case plugin native side not linked yet; keep API usable.
      }
      idx += 1;
      offset += take;
    }
    _delegate.onMessageSent(msgId);
    return msgId;
  }
}

Uint8List randomMsgId() {
  final r = Random.secure();
  final b = Uint8List(16);
  for (var i = 0; i < 16; i++) b[i] = r.nextInt(256);
  return b;
}
