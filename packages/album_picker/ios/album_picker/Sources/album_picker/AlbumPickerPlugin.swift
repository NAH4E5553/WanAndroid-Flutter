import Flutter
import UIKit
import Photos
import PhotosUI
import ImageIO

public final class AlbumPickerPlugin: NSObject, FlutterPlugin, FlutterStreamHandler, PHPhotoLibraryChangeObserver {
    private let worker = DispatchQueue(label: "portable.album.export")
    private let io = DispatchQueue(label: "portable.album.metadata", qos: .userInitiated)
    private let manager = PHImageManager()
    private var sink: FlutterEventSink?
    private var jobs: [String: ExportTask] = [:]
    private var leases: [String: URL] = [:]
    private var thumbnails: [String: Set<PHImageRequestID>] = [:]
    private var requesting = false
    private var root: URL {
        let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("portable_album_exports", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        var excluded = url; var values = URLResourceValues(); values.isExcludedFromBackup = true
        try? excluded.setResourceValues(values)
        return url
    }
    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = AlbumPickerPlugin()
        let channel = FlutterMethodChannel(name: "dev.portable.album_picker", binaryMessenger: registrar.messenger())
        registrar.addMethodCallDelegate(instance, channel: channel)
        FlutterEventChannel(name: "dev.portable.album_picker/changes", binaryMessenger: registrar.messenger()).setStreamHandler(instance)
        instance.cleanup()
    }
    private func cleanup() {
        let root = root
        io.async {
            let files = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.contentModificationDateKey, .isSymbolicLinkKey])) ?? []
            for file in files {
                guard let values = try? file.resourceValues(forKeys: [.contentModificationDateKey, .isSymbolicLinkKey]),
                      values.isSymbolicLink != true,
                      let date = values.contentModificationDate, Date().timeIntervalSince(date) > 86400 else { continue }
                try? FileManager.default.removeItem(at: file)
            }
        }
    }
    private func permission() -> String {
        switch PHPhotoLibrary.authorizationStatus(for: .readWrite) {
        case .authorized: return "full"
        case .limited: return "limited"
        case .notDetermined: return "unknown"
        case .denied: return "blocked"
        case .restricted: return "restricted"
        @unknown default: return "restricted"
        }
    }
    private func requireRead() throws {
        guard ["full", "limited"].contains(permission()) else { throw ExportFailure("permissionDenied") }
    }
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any] ?? [:]
        switch call.method {
        case "permission": result(permission())
        case "request":
            guard !requesting else { return result(error("busy")) }
            requesting = true
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { _ in
                DispatchQueue.main.async { self.requesting = false; result(self.permission()) }
            }
        case "manage":
            guard let view = controller(), permission() == "limited" else { return result(error("unavailable")) }
            PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: view) { _ in result(nil) }
        case "settings":
            guard let url = URL(string: UIApplication.openSettingsURLString) else { return result(error("unavailable")) }
            UIApplication.shared.open(url) { ok in result(ok ? nil : self.error("unavailable")) }
        case "snapshot":
            io.async { do { let snapshot = try self.snapshot(); DispatchQueue.main.async { result(snapshot) } }
                catch { self.fail(result, error) } }
        case "thumbnail": thumbnail(args, result)
        case "clearThumbnails":
            let session = args["session"] as? String ?? ""
            for id in thumbnails.removeValue(forKey: session) ?? [] { manager.cancelImageRequest(id) }
            result(nil)
        case "cancel": jobs[args["token"] as? String ?? ""]?.cancel(); result(nil)
        case "release":
            let token = args["token"] as? String ?? ""
            guard let url = leases[token] else { return result(nil) }
            io.async {
                do { if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
                    DispatchQueue.main.async { self.leases.removeValue(forKey: token); result(nil) }
                } catch { self.fail(result, ExportFailure("cleanupFailed")) }
            }
        case "export":
            guard jobs.isEmpty else { return result(error("exportUnavailable")) }
            guard let token = args["token"] as? String,
                  token.range(of: "^[A-Za-z0-9_]+$", options: .regularExpression) != nil else { return result(error("invalidRequest")) }
            let task = ExportTask(seconds: (args["timeoutMs"] as? Double ?? 60000) / 1000)
            jobs[token] = task
            let dir = root.appendingPathComponent(token, isDirectory: true)
            worker.async {
                do {
                    let output = try self.export(args, dir, task)
                    DispatchQueue.main.async { self.leases[token] = dir; self.jobs.removeValue(forKey: token); result(output) }
                } catch {
                    try? FileManager.default.removeItem(at: dir)
                    DispatchQueue.main.async { self.jobs.removeValue(forKey: token); result(self.error((error as? ExportFailure)?.code ?? "readFailed")) }
                }
            }
        default: result(FlutterMethodNotImplemented)
        }
    }
    private func error(_ code: String) -> FlutterError { FlutterError(code: code, message: "Photo operation failed", details: nil) }
    private func fail(_ result: @escaping FlutterResult, _ failure: Error) {
        DispatchQueue.main.async { result(self.error((failure as? ExportFailure)?.code ?? "readFailed")) }
    }
    private func controller() -> UIViewController? {
        var view = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }.first { $0.isKeyWindow }?.rootViewController
        while let presented = view?.presentedViewController { view = presented }
        return view
    }
    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        sink = events; PHPhotoLibrary.shared().register(self); return nil
    }
    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        PHPhotoLibrary.shared().unregisterChangeObserver(self); sink = nil; return nil
    }
    public func photoLibraryDidChange(_ changeInstance: PHChange) { DispatchQueue.main.async { self.sink?(nil) } }
    private func options() -> PHFetchOptions {
        let options = PHFetchOptions(); options.includeHiddenAssets = false
        options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        return options
    }
    private func revision(_ asset: PHAsset) -> String {
        "\(Int64((asset.modificationDate?.timeIntervalSince1970 ?? 0) * 1000)):\(asset.pixelWidth):\(asset.pixelHeight)"
    }
    private func asset(_ id: String) throws -> PHAsset {
        try requireRead()
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: options()).firstObject else { throw ExportFailure("resourceChanged") }
        return asset
    }
    private func snapshot() throws -> [String: Any] {
        try requireRead()
        var assets: [String: [String: Any]] = [:]
        var memberships: [String: [String]] = [:]
        var groups: [[String: Any]] = []
        PHAsset.fetchAssets(with: options()).enumerateObjects { asset, _, _ in
            assets[asset.localIdentifier] = ["id": asset.localIdentifier, "revision": self.revision(asset),
                "width": asset.pixelWidth, "height": asset.pixelHeight,
                "time": Int64(((asset.creationDate ?? asset.modificationDate)?.timeIntervalSince1970 ?? 0) * 1000)]
        }
        var visited = Set<String>()
        func add(_ collection: PHAssetCollection, _ parent: String) {
            guard collection.assetCollectionSubtype != .albumCloudShared, visited.insert(collection.localIdentifier).inserted else { return }
            var count = 0
            PHAsset.fetchAssets(in: collection, options: options()).enumerateObjects { a, _, _ in
                if assets[a.localIdentifier] != nil { memberships[a.localIdentifier, default: []].append(collection.localIdentifier); count += 1 }
            }
            if count > 0 { groups.append(["id": collection.localIdentifier, "name": collection.localizedTitle ?? "未命名相册", "detail": parent]) }
        }
        func walk(_ collections: PHFetchResult<PHCollection>, _ parent: String) {
            collections.enumerateObjects { collection, _, _ in
                if let album = collection as? PHAssetCollection { add(album, parent) }
                else if let folder = collection as? PHCollectionList {
                    let label = [parent, folder.localizedTitle ?? ""].filter { !$0.isEmpty }.joined(separator: " / ")
                    walk(PHCollection.fetchCollections(in: folder, options: nil), label)
                }
            }
        }
        walk(PHCollectionList.fetchTopLevelUserCollections(with: nil), "")
        for subtype: PHAssetCollectionSubtype in [.smartAlbumFavorites, .smartAlbumScreenshots] {
            PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: subtype, options: nil).enumerateObjects { c, _, _ in add(c, "") }
        }
        return ["assets": assets.map { id, value -> [String: Any] in var value = value; value["albums"] = memberships[id] ?? []; return value }, "groups": groups]
    }
    private func thumbnail(_ args: [String: Any], _ result: @escaping FlutterResult) {
        do {
            let asset = try asset(args["id"] as? String ?? "")
            let session = args["session"] as? String ?? ""
            let size = max(32, min(args["size"] as? Int ?? 128, 512))
            let options = PHImageRequestOptions(); options.version = .current
            options.isNetworkAccessAllowed = false; options.deliveryMode = .highQualityFormat; options.resizeMode = .fast
            var request: PHImageRequestID = PHInvalidImageRequestID
            var completed = false
            request = manager.requestImage(for: asset, targetSize: CGSize(width: size, height: size), contentMode: .aspectFill, options: options) { image, info in
                DispatchQueue.main.async {
                    guard !completed, (info?[PHImageResultIsDegradedKey] as? Bool) != true else { return }
                    completed = true; self.thumbnails[session]?.remove(request)
                    if (info?[PHImageCancelledKey] as? Bool) == true { result(nil); return }
                    result(image?.jpegData(compressionQuality: 0.85).map { FlutterStandardTypedData(bytes: $0) })
                }
            }
            thumbnails[session, default: []].insert(request)
        } catch { fail(result, error) }
    }
    private func export(_ args: [String: Any], _ dir: URL, _ task: ExportTask) throws -> [String: Any] {
        let selected = try asset(args["id"] as? String ?? "")
        guard revision(selected) == args["revision"] as? String else { throw ExportFailure("resourceChanged") }
        let inputLimit = args["inputBytes"] as? Int ?? 33554432
        let outputLimit = args["outputBytes"] as? Int ?? 67108864
        let dimension = args["maxDimension"] as? Int ?? 8192
        let pixels = args["maxPixels"] as? Int ?? 16000000
        try ImageExport.bounds(selected.pixelWidth, selected.pixelHeight, dimension, pixels)
        let resources = PHAssetResource.assetResources(for: selected)
        // Never quietly use the original when adjustments exist without a rendered photo.
        let edited = resources.first { $0.type == .fullSizePhoto }
        if edited == nil && resources.contains(where: { $0.type == .adjustmentData }) { throw ExportFailure("currentRepresentationUnavailable") }
        guard let resource = edited ?? resources.first(where: { $0.type == .photo }) else { throw ExportFailure("unsupportedFormat") }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: false)
        let space = try FileManager.default.attributesOfFileSystem(forPath: dir.path)[.systemFreeSize] as? NSNumber
        guard let available = space?.int64Value, available >= Int64(inputLimit + outputLimit + 8388608) else { throw ExportFailure("insufficientSpace") }
        let source = dir.appendingPathComponent("input.partial")
        let writer = try BoundedImageWriter(url: source, limit: inputLimit, task: task)
        let options = PHAssetResourceRequestOptions()
        let network = args["allowNetwork"] as? Bool ?? false
        options.isNetworkAccessAllowed = network
        let done = DispatchSemaphore(value: 0)
        let outcomeLock = NSLock()
        var outcome: Error?
        let resourceManager = PHAssetResourceManager.default()
        let request = resourceManager.requestData(for: resource, options: options, dataReceivedHandler: { chunk in
            do { try writer.write(chunk) }
            catch { outcomeLock.lock(); if outcome == nil { outcome = error }; outcomeLock.unlock(); task.cancel() }
        }, completionHandler: { error in
            outcomeLock.lock(); if outcome == nil { outcome = error }; outcomeLock.unlock(); done.signal()
        })
        task.onCancel { resourceManager.cancelDataRequest(request) }
        // A missing completion must not leave the application writer open forever.
        while done.wait(timeout: .now() + 0.1) == .timedOut {
            do { if let failure = writer.failure { throw failure }; try task.check() }
            catch { resourceManager.cancelDataRequest(request); try? writer.close(); throw error }
        }
        try writer.close()
        outcomeLock.lock(); let failure = outcome; outcomeLock.unlock()
        if let failure = failure {
            if let own = failure as? ExportFailure { throw own }
            let error = failure as NSError
            if !network && error.domain == PHPhotosErrorDomain && error.code == PHPhotosError.Code.networkAccessRequired.rawValue {
                throw ExportFailure("networkRequired")
            }
            throw ExportFailure(network ? "networkFailed" : "readFailed")
        }
        try task.check()
        let partial = dir.appendingPathComponent("output.partial")
        let (width, height, bytes) = try ImageExport.normalize(source: source, destination: partial, inputLimit: inputLimit,
            outputLimit: outputLimit, maxDimension: dimension, maxPixels: pixels, task: task)
        guard revision(try asset(selected.localIdentifier)) == revision(selected) else { throw ExportFailure("resourceChanged") }
        let output = dir.appendingPathComponent("image.png")
        try FileManager.default.moveItem(at: partial, to: output)
        try FileManager.default.removeItem(at: source); try task.check()
        let kind = selected.mediaSubtypes.contains(.photoLive) ? "livePhotoStill" : resource.uniformTypeIdentifier == "com.compuserve.gif" ? "gifFirstFrame" : "photo"
        return ["path": output.path, "bytes": bytes, "width": width, "height": height, "kind": kind]
    }
}
