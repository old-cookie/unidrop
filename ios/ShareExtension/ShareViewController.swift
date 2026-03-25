import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
  private let sharedMediaDefaultsKey = "unidrop_shared_media_payload"
  private let hostUrlSchemeDefaultsKey = "unidrop_host_url_scheme"

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    processIncomingItems()
  }

  private func processIncomingItems() {
    guard let extensionItems = extensionContext?.inputItems as? [NSExtensionItem] else {
      completeExtensionRequest()
      return
    }

    let appGroupId = resolveAppGroupId()
    guard let sharedContainer = FileManager.default.containerURL(
      forSecurityApplicationGroupIdentifier: appGroupId
    ) else {
      completeExtensionRequest()
      return
    }

    let providers = extensionItems
      .flatMap { $0.attachments ?? [] }
      .filter {
        $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) ||
          $0.hasItemConformingToTypeIdentifier(UTType.movie.identifier)
      }

    if providers.isEmpty {
      completeExtensionRequest()
      return
    }

    let dispatchGroup = DispatchGroup()
    let payloadQueue = DispatchQueue(label: "com.oldcokie.unidrop.shareextension.payload")
    var payloads: [[String: String]] = []

    for provider in providers {
      if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
        dispatchGroup.enter()
        loadMediaFromProvider(
          provider,
          typeIdentifier: UTType.image.identifier,
          mimeTypePrefix: "image",
          containerUrl: sharedContainer
        ) { payload in
          if let payload {
            payloadQueue.sync {
              payloads.append(payload)
            }
          }
          dispatchGroup.leave()
        }
      } else if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
        dispatchGroup.enter()
        loadMediaFromProvider(
          provider,
          typeIdentifier: UTType.movie.identifier,
          mimeTypePrefix: "video",
          containerUrl: sharedContainer
        ) { payload in
          if let payload {
            payloadQueue.sync {
              payloads.append(payload)
            }
          }
          dispatchGroup.leave()
        }
      }
    }

    dispatchGroup.notify(queue: .main) {
      guard let firstPayload = payloads.first else {
        self.completeExtensionRequest()
        return
      }

      self.storeSharedPayload([firstPayload], appGroupId: appGroupId)
      self.openHostApp()
      self.completeExtensionRequest()
    }
  }

  private func loadMediaFromProvider(
    _ provider: NSItemProvider,
    typeIdentifier: String,
    mimeTypePrefix: String,
    containerUrl: URL,
    completion: @escaping ([String: String]?) -> Void
  ) {
    provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, _ in
      guard let item else {
        completion(nil)
        return
      }

      if let fileUrl = item as? URL,
         let payload = self.persistSharedFile(
           from: fileUrl,
           fallbackExtension: mimeTypePrefix == "image" ? "jpg" : "mp4",
           mimeTypePrefix: mimeTypePrefix,
           containerUrl: containerUrl
         ) {
        completion(payload)
        return
      }

      if let data = item as? Data,
         let payload = self.persistSharedData(
           data,
           preferredName: "shared_\(Int(Date().timeIntervalSince1970))",
           fileExtension: mimeTypePrefix == "image" ? "jpg" : "mp4",
           mimeTypePrefix: mimeTypePrefix,
           containerUrl: containerUrl
         ) {
        completion(payload)
        return
      }

      if let image = item as? UIImage,
         let imageData = image.jpegData(compressionQuality: 0.95),
         let payload = self.persistSharedData(
           imageData,
           preferredName: "shared_\(Int(Date().timeIntervalSince1970))",
           fileExtension: "jpg",
           mimeTypePrefix: "image",
           containerUrl: containerUrl
         ) {
        completion(payload)
        return
      }

      completion(nil)
    }
  }

  private func persistSharedFile(
    from sourceUrl: URL,
    fallbackExtension: String,
    mimeTypePrefix: String,
    containerUrl: URL
  ) -> [String: String]? {
    let originalName = sourceUrl.lastPathComponent
    let ext = sourceUrl.pathExtension.isEmpty ? fallbackExtension : sourceUrl.pathExtension
    let safeName = sanitizeFileName(sourceUrl.deletingPathExtension().lastPathComponent)
    let destinationName = "shared_\(Int(Date().timeIntervalSince1970))_\(safeName).\(ext)"
    let destinationUrl = containerUrl.appendingPathComponent(destinationName)

    do {
      if FileManager.default.fileExists(atPath: destinationUrl.path) {
        try FileManager.default.removeItem(at: destinationUrl)
      }
      try FileManager.default.copyItem(at: sourceUrl, to: destinationUrl)
      return [
        "path": destinationUrl.path,
        "fileName": destinationName,
        "mimeType": "\(mimeTypePrefix)/\(ext.lowercased())",
      ]
    } catch {
      _ = originalName
      return nil
    }
  }

  private func persistSharedData(
    _ data: Data,
    preferredName: String,
    fileExtension: String,
    mimeTypePrefix: String,
    containerUrl: URL
  ) -> [String: String]? {
    let safeName = sanitizeFileName(preferredName)
    let destinationName = "\(safeName).\(fileExtension)"
    let destinationUrl = containerUrl.appendingPathComponent(destinationName)

    do {
      try data.write(to: destinationUrl, options: .atomic)
      return [
        "path": destinationUrl.path,
        "fileName": destinationName,
        "mimeType": "\(mimeTypePrefix)/\(fileExtension.lowercased())",
      ]
    } catch {
      return nil
    }
  }

  private func storeSharedPayload(_ payload: [[String: String]], appGroupId: String) {
    guard let defaults = UserDefaults(suiteName: appGroupId),
          let data = try? JSONSerialization.data(withJSONObject: payload),
          let json = String(data: data, encoding: .utf8) else {
      return
    }
    defaults.set(json, forKey: sharedMediaDefaultsKey)
    defaults.synchronize()
  }

  private func openHostApp() {
    guard let defaults = UserDefaults(suiteName: resolveAppGroupId()) else {
      return
    }

    let defaultScheme = "ShareMedia-com.oldcokie.unidrop"
    let scheme = defaults.string(forKey: hostUrlSchemeDefaultsKey) ?? defaultScheme

    guard let url = URL(string: "\(scheme)://shared") else {
      return
    }

    extensionContext?.open(url, completionHandler: nil)
  }

  private func resolveAppGroupId() -> String {
    if let appGroupId = Bundle.main.object(forInfoDictionaryKey: "AppGroupId") as? String,
       !appGroupId.isEmpty {
      return appGroupId
    }
    return "group.com.oldcokie.unidrop"
  }

  private func sanitizeFileName(_ value: String) -> String {
    return value
      .replacingOccurrences(of: "\\", with: "_")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: " ", with: "_")
  }

  private func completeExtensionRequest() {
    extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
  }
}
