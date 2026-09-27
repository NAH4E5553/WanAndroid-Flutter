import Flutter
import ImageIO
import Photos
import UIKit
import UniformTypeIdentifiers

/// 头像「保存到相册」与备份排除的最小原生通道。
/// 只申请 PhotoKit `.addOnly` 权限；不读取相册内容。
@objc class AvatarGalleryPlugin: NSObject, FlutterPlugin {
  static let channelName = "dev.flutter.local.avatar_gallery"
  static let imageChannelName = "dev.flutter.local.avatar_image"

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: channelName,
      binaryMessenger: registrar.messenger()
    )
    let instance = AvatarGalleryPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
    let imageChannel = FlutterMethodChannel(
      name: imageChannelName,
      binaryMessenger: registrar.messenger()
    )
    registrar.addMethodCallDelegate(instance, channel: imageChannel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "savePng":
      handleSavePng(call, result)
    case "excludeFromBackup":
      handleExcludeFromBackup(call, result)
    case "normalizeToPng":
      handleNormalizeToPng(call, result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func handleNormalizeToPng(
    _ call: FlutterMethodCall,
    _ result: @escaping FlutterResult
  ) {
    guard let arguments = call.arguments as? [String: Any],
      let sourcePath = arguments["sourcePath"] as? String,
      let destinationPath = arguments["destinationPath"] as? String,
      let maxDimension = arguments["maxDimension"] as? Int,
      let maxPixelCount = arguments["maxPixelCount"] as? Int,
      let maxFileBytes = arguments["maxFileBytes"] as? Int
    else {
      result("failure")
      return
    }
    let sourceUrl = URL(fileURLWithPath: sourcePath).standardizedFileURL
    let destinationUrl = URL(fileURLWithPath: destinationPath).standardizedFileURL
    let homeUrl = URL(fileURLWithPath: NSHomeDirectory()).standardizedFileURL
    guard destinationUrl.path.hasPrefix(homeUrl.path + "/") else {
      result("failure")
      return
    }
    do {
      let attributes = try FileManager.default.attributesOfItem(atPath: sourceUrl.path)
      guard let byteCount = attributes[.size] as? NSNumber,
        byteCount.intValue > 0,
        byteCount.intValue <= maxFileBytes,
        let source = CGImageSourceCreateWithURL(sourceUrl as CFURL, nil),
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
          as? [CFString: Any],
        let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
        let height = properties[kCGImagePropertyPixelHeight] as? NSNumber
      else {
        result("rejected")
        return
      }
      let pixelWidth = width.intValue
      let pixelHeight = height.intValue
      guard pixelWidth > 0, pixelHeight > 0,
        pixelWidth <= maxDimension, pixelHeight <= maxDimension,
        Int64(pixelWidth) * Int64(pixelHeight) <= Int64(maxPixelCount)
      else {
        result("rejected")
        return
      }
      let options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: maxDimension,
        kCGImageSourceShouldCacheImmediately: true,
      ]
      guard let normalized = CGImageSourceCreateThumbnailAtIndex(
        source,
        0,
        options as CFDictionary
      ) else {
        result("failure")
        return
      }
      try FileManager.default.createDirectory(
        at: destinationUrl.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      let temporaryUrl = URL(fileURLWithPath: destinationUrl.path + ".normalizing")
      try? FileManager.default.removeItem(at: temporaryUrl)
      guard let destination = CGImageDestinationCreateWithURL(
        temporaryUrl as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
      ) else {
        result("failure")
        return
      }
      CGImageDestinationAddImage(destination, normalized, nil)
      guard CGImageDestinationFinalize(destination) else {
        try? FileManager.default.removeItem(at: temporaryUrl)
        result("failure")
        return
      }
      try? FileManager.default.removeItem(at: destinationUrl)
      try FileManager.default.moveItem(at: temporaryUrl, to: destinationUrl)
      result("success")
    } catch {
      result("failure")
    }
  }

  private func handleSavePng(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    guard let arguments = call.arguments as? [String: Any],
      let fileName = arguments["fileName"] as? String,
      let bytes = arguments["bytes"] as? FlutterStandardTypedData
    else {
      result("failure")
      return
    }
    let temporaryDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("avatar_save_\(UUID().uuidString)")
    let temporaryDirectoryUrl = temporaryDirectory.deletingLastPathComponent()
    do {
      try FileManager.default.createDirectory(
        at: temporaryDirectoryUrl, withIntermediateDirectories: true)
      try bytes.data.write(to: temporaryDirectory, options: .atomic)
    } catch {
      result("failure")
      return
    }
    // 请求前先查授权状态：已拒绝的后续请求仍返回 denied，若不区分，
    // “前往设置”分支永远不可达。notDetermined 才发起请求，其拒绝视为首次拒绝。
    let currentStatus = PHPhotoLibrary.authorizationStatus(for: .addOnly)
    if currentStatus == .denied || currentStatus == .restricted {
      try? FileManager.default.removeItem(at: temporaryDirectory)
      result("permissionPermanentlyDenied")
      return
    }

    PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
      DispatchQueue.main.async {
        switch status {
        case .authorized, .limited:
          PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.creationRequestForAssetFromImage(
              atFileURL: temporaryDirectory)
          }) { success, _ in
            try? FileManager.default.removeItem(at: temporaryDirectory)
            DispatchQueue.main.async {
              result(success ? "success" : "failure")
            }
          }
        case .denied, .restricted, .notDetermined:
          try? FileManager.default.removeItem(at: temporaryDirectory)
          result("permissionDenied")
        @unknown default:
          try? FileManager.default.removeItem(at: temporaryDirectory)
          result("failure")
        }
      }
    }
  }

  private func handleExcludeFromBackup(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    guard let arguments = call.arguments as? [String: Any],
      let rawPath = arguments["path"] as? String
    else {
      result("failure")
      return
    }
    var url = URL(fileURLWithPath: rawPath)
    do {
      var values = try url.resourceValues(forKeys: [.isExcludedFromBackupKey])
      values.isExcludedFromBackup = true
      try url.setResourceValues(values)
      result("success")
    } catch {
      result("failure")
    }
  }
}

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(
      forPlugin: "AvatarGalleryPlugin"
    ) {
      AvatarGalleryPlugin.register(with: registrar)
    }
  }
}
