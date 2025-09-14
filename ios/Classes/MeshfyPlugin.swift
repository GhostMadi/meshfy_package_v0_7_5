import Flutter
import UIKit

public class MeshfyPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "mesh_ble/peripheral", binaryMessenger: registrar.messenger())
    let instance = MeshfyPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "emitFrame":
      result(true) // stub ack
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
