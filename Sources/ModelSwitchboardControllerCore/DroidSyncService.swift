import Foundation

struct DroidSyncService {
  let configuration: ControllerConfiguration
  let profiles: ProfileRepository
  let settingsURL: URL
  private let fileManager = FileManager.default

  func sync() throws {
    let managedProfiles = try profiles.load().values.filter { $0["SYNC_TO_DROID"] == "1" }.sorted {
      $0.name < $1.name
    }
    var settings = try readObject(settingsURL)
    let previous = try readObject(configuration.droidStateFile)
    let removed = try readObject(configuration.droidRemovedStateFile)
    let previousNames = Set(previous["names"] as? [String] ?? [])
    let removedNames = Set(removed["names"] as? [String] ?? [])
    let removedIDs = Set(removed["ids"] as? [String] ?? [])
    let managedNames = Set(managedProfiles.map(\.displayName))
    let managedIDs = Set(managedProfiles.map(droidID))
    let replacementNames = Set(managedProfiles.flatMap { replacements($0) })

    let existing = settings["customModels"] as? [[String: Any]] ?? []
    var replacementsByName: [String: [String: Any]] = [:]
    var customModels: [[String: Any]] = []
    for model in existing {
      let name = model["displayName"] as? String ?? ""
      let id = model["id"] as? String ?? ""
      if removedNames.contains(name) || removedIDs.contains(id) { continue }
      if previousNames.contains(name) && !managedNames.contains(name) { continue }
      if replacementNames.contains(name) {
        replacementsByName[name] = model
        continue
      }
      customModels.append(model)
    }

    var indexByName = Dictionary(
      uniqueKeysWithValues: customModels.enumerated().compactMap { index, model in
        (model["displayName"] as? String).map { ($0, index) }
      })
    var maximumIndex = customModels.compactMap { ($0["index"] as? NSNumber)?.intValue }.max() ?? -1
    for profile in managedProfiles {
      var entry = try buildEntry(profile)
      entry["id"] = droidID(profile)
      if let index = indexByName[profile.displayName] {
        entry["index"] = customModels[index]["index"] ?? index
        customModels[index] = entry
        continue
      }
      let replacement = replacements(profile).compactMap { replacementsByName[$0] }.first
      if let replacement {
        entry["index"] = replacement["index"] ?? maximumIndex + 1
      } else {
        maximumIndex += 1
        entry["index"] = maximumIndex
      }
      indexByName[profile.displayName] = customModels.count
      customModels.append(entry)
    }

    settings["customModels"] = customModels
    try write(settings, to: settingsURL)
    try write(
      ["names": managedNames.sorted(), "ids": managedIDs.sorted()], to: configuration.droidStateFile
    )
  }

  private func buildEntry(_ profile: ControllerProfile) throws -> [String: Any] {
    var entry: [String: Any] = [
      "displayName": profile.displayName,
      "model": profile.requestModel,
      "baseUrl": profile.baseURL,
      "apiKey": "not-needed",
      "provider": "generic-chat-completion-api",
      "maxOutputTokens": Int(profile["DROID_MAX_OUTPUT_TOKENS"] ?? "8192") ?? 8192,
      "noImageSupport": true,
    ]
    if let raw = profile["DROID_TEMPERATURE"], let temperature = Double(raw) {
      entry["extraArgs"] = ["temperature": temperature]
    }
    return entry
  }

  private func droidID(_ profile: ControllerProfile) -> String {
    if let configured = profile["DROID_ID"], !configured.isEmpty { return configured }
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".+-_()$[] "))
    let cleaned = profile.displayName.unicodeScalars.map {
      allowed.contains($0) ? Character(String($0)) : "-"
    }
    let slug = String(cleaned).split(whereSeparator: \.isWhitespace).joined(separator: "-")
    return "custom:\(slug)-0"
  }

  private func replacements(_ profile: ControllerProfile) -> [String] {
    (profile["REPLACES_DISPLAY_NAMES"] ?? "").split(separator: ",")
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
  }

  private func readObject(_ url: URL) throws -> [String: Any] {
    guard fileManager.fileExists(atPath: url.path) else { return [:] }
    let data = try Data(contentsOf: url)
    return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
  }

  private func write(_ object: [String: Any], to url: URL) throws {
    try fileManager.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    var data = try JSONSupport.data(object)
    data.append(0x0A)
    try data.write(to: url, options: .atomic)
  }
}
