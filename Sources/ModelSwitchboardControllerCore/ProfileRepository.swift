import Foundation

public struct ControllerProfile: Sendable, Equatable {
  public let name: String
  public let values: [String: String]

  public init(name: String, values: [String: String]) throws {
    var normalized = values
    normalized["PROFILE_NAME"] = normalized["PROFILE_NAME"] ?? name
    normalized["DISPLAY_NAME"] = normalized["DISPLAY_NAME"] ?? name
    guard let requestModel = normalized["REQUEST_MODEL"], !requestModel.isEmpty else {
      throw ControllerError.invalidProfile("\(name): missing REQUEST_MODEL")
    }
    guard normalized["PORT"] != nil || normalized["BASE_URL"] != nil else {
      throw ControllerError.invalidProfile("\(name): missing PORT or BASE_URL")
    }
    normalized["REQUEST_MODEL"] = requestModel
    self.name = name
    self.values = normalized
  }

  public subscript(key: String) -> String? { values[key] }
  public var displayName: String { values["DISPLAY_NAME"] ?? name }
  public var runtime: String { RuntimeCatalog.canonical(values["RUNTIME"]) }
  public var runtimeSpec: RuntimeSpec { RuntimeCatalog.spec(for: self) }
  public var runtimeTags: [String] { RuntimeCatalog.tags(for: self) }
  public var requestModel: String { values["REQUEST_MODEL"] ?? name }
  public var serverModelID: String { values["SERVER_MODEL_ID"] ?? requestModel }
  public var healthcheckMode: String {
    (values["HEALTHCHECK_MODE"] ?? "openai-models").lowercased()
  }
  public var endpointHost: String {
    if let host = values["HOST"], !host.isEmpty { return host }
    return URL(string: baseURL)?.host ?? ControllerConfiguration.defaultHost
  }
  public var endpointPort: String {
    if let port = values["PORT"], !port.isEmpty { return port }
    return URL(string: baseURL)?.port.map(String.init) ?? ""
  }
  public var baseURL: String {
    if let configured = values["BASE_URL"]?.trimmingCharacters(in: .whitespacesAndNewlines),
      !configured.isEmpty
    {
      return configured.hasSuffix("/") ? String(configured.dropLast()) : configured
    }
    guard let port = values["PORT"], !port.isEmpty else { return "" }
    let configuredHost =
      values["HOST"]?.trimmingCharacters(in: .whitespacesAndNewlines)
      ?? ControllerConfiguration.defaultHost
    let host =
      ControllerConfiguration.isLoopback(configuredHost)
      ? configuredHost : ControllerConfiguration.defaultHost
    let literal = host.contains(":") && !host.hasPrefix("[") ? "[\(host)]" : host
    return "http://\(literal):\(port)/v1"
  }
  public var healthcheckURL: String {
    if let configured = values["HEALTHCHECK_URL"], !configured.isEmpty { return configured }
    if healthcheckMode == "openai-models" {
      if let configured = values["MODEL_LIST_URL"], !configured.isEmpty { return configured }
      return baseURL.isEmpty ? "" : "\(baseURL)/models"
    }
    return baseURL
  }
  public var logPath: String {
    let raw = values["LOG_ALIAS"] ?? values["MODEL_ALIAS"] ?? name
    let safe = raw.map { $0.isLetter || $0.isNumber || "_.-".contains($0) ? $0 : "_" }
    return "/tmp/\(String(safe)).log"
  }
  public var endpointIdentity: String? {
    guard !endpointPort.isEmpty else { return nil }
    let host =
      ControllerConfiguration.isLoopback(endpointHost)
      ? "localhost"
      : endpointHost.trimmingCharacters(in: CharacterSet(charactersIn: "[]")).lowercased()
    return "\(host):\(endpointPort)"
  }
}

public final class ProfileRepository: @unchecked Sendable {
  public let directory: URL
  private let fileManager: FileManager

  public init(directory: URL, fileManager: FileManager = .default) {
    self.directory = directory
    self.fileManager = fileManager
  }

  public func load() throws -> [String: ControllerProfile] {
    guard fileManager.fileExists(atPath: directory.path) else { return [:] }
    let files = try fileManager.contentsOfDirectory(
      at: directory,
      includingPropertiesForKeys: nil,
      options: [.skipsHiddenFiles]
    ).filter { ["env", "json"].contains($0.pathExtension.lowercased()) }
      .sorted {
        $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent)
          == .orderedAscending
      }
    var profiles: [String: ControllerProfile] = [:]
    for file in files {
      let name = file.deletingPathExtension().lastPathComponent
      let values =
        try file.pathExtension.lowercased() == "json" ? parseJSON(file) : parseEnvironment(file)
      profiles[name] = try ControllerProfile(name: name, values: values)
    }
    return profiles
  }

  public func profile(named name: String) throws -> ControllerProfile {
    guard let profile = try load()[name] else { throw ControllerError.profileNotFound(name) }
    return profile
  }

  public func load(file: URL) throws -> ControllerProfile {
    let name = file.deletingPathExtension().lastPathComponent
    let values = try parseValues(file: file)
    return try ControllerProfile(name: name, values: values)
  }

  public func parseValues(file: URL) throws -> [String: String] {
    try file.pathExtension.lowercased() == "json" ? parseJSON(file) : parseEnvironment(file)
  }

  public func conflicts(in profiles: [String: ControllerProfile]) -> [String: (String, [String])] {
    let groups = Dictionary(
      grouping: profiles.values.compactMap { profile in
        profile.endpointIdentity.map { ($0, profile.name) }
      }, by: \.0)
    var result: [String: (String, [String])] = [:]
    for (endpoint, entries) in groups where entries.count > 1 {
      let names = entries.map(\.1).sorted()
      for name in names {
        result[name] = (endpoint, names.filter { $0 != name })
      }
    }
    return result
  }

  public func ensureUnique(_ name: String, action: String, profiles: [String: ControllerProfile])
    throws
  {
    guard let conflict = conflicts(in: profiles)[name] else { return }
    throw ControllerError.profileConflict(
      "Cannot \(action) \(name): endpoint \(conflict.0) is also configured for \(conflict.1.joined(separator: ", "))."
    )
  }

  private func parseEnvironment(_ file: URL) throws -> [String: String] {
    let content = try String(contentsOf: file, encoding: .utf8)
    var values: [String: String] = [:]
    for (offset, rawLine) in content.components(separatedBy: .newlines).enumerated() {
      var line = rawLine.trimmingCharacters(in: .whitespaces)
      if line.isEmpty || line.hasPrefix("#") { continue }
      if line.hasPrefix("export ") {
        line = String(line.dropFirst(7)).trimmingCharacters(in: .whitespaces)
      }
      guard let equals = line.firstIndex(of: "=") else {
        throw ControllerError.invalidProfile("\(file.path):\(offset + 1): expected KEY=value")
      }
      let key = String(line[..<equals]).trimmingCharacters(in: .whitespaces)
      guard key.range(of: "^[A-Za-z_][A-Za-z0-9_]*$", options: .regularExpression) != nil else {
        throw ControllerError.invalidProfile(
          "\(file.path):\(offset + 1): invalid profile key \(key)")
      }
      let rawValue = String(line[line.index(after: equals)...]).trimmingCharacters(in: .whitespaces)
      values[key] = try parseValue(rawValue, file: file, line: offset + 1)
    }
    return values
  }

  private func parseValue(_ raw: String, file: URL, line: Int) throws -> String {
    guard let first = raw.first, first == "\"" || first == "'" else {
      return raw.split(separator: "#", maxSplits: 1).first.map(String.init)?.trimmingCharacters(
        in: .whitespaces) ?? ""
    }
    guard raw.last == first, raw.count >= 2 else {
      throw ControllerError.invalidProfile("\(file.path):\(line): invalid quoted value")
    }
    let inner = String(raw.dropFirst().dropLast())
    if first == "'" { return inner }
    var value = ""
    var escaped = false
    for character in inner {
      if escaped {
        switch character {
        case "n": value.append("\n")
        case "t": value.append("\t")
        default: value.append(character)
        }
        escaped = false
      } else if character == "\\" {
        escaped = true
      } else {
        value.append(character)
      }
    }
    if escaped { value.append("\\") }
    return value
  }

  private func parseJSON(_ file: URL) throws -> [String: String] {
    let data = try Data(contentsOf: file)
    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw ControllerError.invalidProfile("Profile JSON must be an object: \(file.path)")
    }
    var values: [String: String] = [:]
    for (key, value) in object {
      guard key.range(of: "^[A-Za-z_][A-Za-z0-9_]*$", options: .regularExpression) != nil else {
        throw ControllerError.invalidProfile("\(file.path): invalid profile key \(key)")
      }
      switch value {
      case let string as String: values[key] = string
      case let number as NSNumber: values[key] = number.stringValue
      case is NSNull: values[key] = ""
      case let collection as [Any]:
        values[key] = String(
          decoding: try JSONSerialization.data(withJSONObject: collection), as: UTF8.self)
      case let collection as [String: Any]:
        values[key] = String(
          decoding: try JSONSerialization.data(withJSONObject: collection), as: UTF8.self)
      default: values[key] = String(describing: value)
      }
    }
    return values
  }
}

public struct RuntimeSpec: Sendable, Equatable {
  public let label: String
  public let tags: [String]
  public let launchMode: String
}

public enum RuntimeCatalog {
  private static let aliases: [String: String] = [
    "llamacpp": "llama.cpp", "llama-cpp": "llama.cpp", "mlx-lm": "mlx", "mlx_lm": "mlx",
    "rvllm": "rvllm-mlx", "rvllm_mlx": "rvllm-mlx", "vllm_mlx": "vllm-mlx",
    "ddtree": "ddtree-mlx", "ddtree_mlx": "ddtree-mlx", "mlx_vlm": "mlx-vlm",
    "mlx-omni": "mlx-omni-server", "mlx-openai": "mlx-openai-server", "mlx-engine": "mlxengine",
    "openai": "external", "openai-compatible": "external", "endpoint": "external",
    "custom": "command", "lmstudio": "lm-studio", "local-ai": "localai",
    "text-generation-inference": "tgi", "huggingface-tgi": "tgi",
    "oobabooga": "text-generation-webui",
    "kobold-cpp": "koboldcpp", "exllama": "exllamav2", "exllama-v2": "exllamav2",
    "aphrodite-engine": "aphrodite", "mistralrs": "mistral.rs", "mlc": "mlc-llm",
    "fast-chat": "fastchat", "bentoml-openllm": "openllm", "nexa-sdk": "nexa",
    "nexaai": "nexa", "litellm-proxy": "litellm", "llamaswap": "llama-swap",
    "hf-transformers": "transformers", "huggingface-transformers": "transformers",
    "nvidia-triton": "triton", "tensorrtllm": "tensorrt-llm", "ort-genai": "onnxruntime-genai",
  ]

  private static let specs: [String: RuntimeSpec] = {
    let entries: [(String, String, [String], String)] = [
      (
        "llama.cpp", "llama.cpp",
        ["managed", "openai-compatible", "gguf", "metal", "apple-silicon"], "adapter"
      ),
      ("mlx", "MLX", ["managed", "openai-compatible", "mlx", "apple-silicon"], "adapter"),
      (
        "rvllm-mlx", "rVLLM MLX", ["managed", "openai-compatible", "mlx", "continuous-batching"],
        "adapter"
      ),
      ("vllm-mlx", "vLLM-MLX", ["managed", "openai-compatible", "mlx", "server"], "adapter"),
      (
        "ddtree-mlx", "DDTree MLX",
        ["managed", "openai-compatible", "mlx", "speculative-decoding"], "adapter"
      ),
      (
        "turboquant", "TurboQuant", ["managed", "openai-compatible", "gguf", "quantized"], "adapter"
      ),
      ("mlx-vlm", "MLX-VLM", ["managed", "openai-compatible", "mlx", "vision"], "adapter"),
      (
        "mlx-omni-server", "MLX Omni Server",
        ["managed", "openai-compatible", "mlx", "multimodal"], "adapter"
      ),
      (
        "mlx-openai-server", "MLX OpenAI Server", ["managed", "openai-compatible", "mlx"], "adapter"
      ),
      ("mlx-llm-server", "MLX-LLM Server", ["managed", "openai-compatible", "mlx"], "adapter"),
      ("mlx-serve", "MLX Serve", ["managed", "openai-compatible", "mlx", "multimodal"], "adapter"),
      (
        "mlxengine", "MLX Engine", ["managed", "openai-compatible", "mlx", "multimodal"], "adapter"
      ),
      ("ollmlx", "ollmlx", ["external", "openai-compatible", "mlx"], "external"),
      ("omlx", "oMLX", ["managed", "openai-compatible", "mlx", "agent-cache"], "adapter"),
      ("ollama", "Ollama", ["daemon", "openai-compatible", "model-registry"], "adapter"),
      ("vllm", "vLLM", ["managed", "openai-compatible", "server"], "adapter"),
      ("sglang", "SGLang", ["managed", "openai-compatible", "server", "radix-cache"], "adapter"),
      (
        "tgi", "Text Generation Inference",
        ["managed", "openai-compatible", "server", "hugging-face"], "adapter"
      ),
      (
        "llama-cpp-python", "llama-cpp-python", ["managed", "openai-compatible", "gguf", "python"],
        "adapter"
      ),
      (
        "llamafile", "llamafile", ["managed", "openai-compatible", "gguf", "single-binary"],
        "adapter"
      ),
      ("koboldcpp", "KoboldCpp", ["managed", "openai-compatible", "gguf"], "adapter"),
      ("tabbyapi", "TabbyAPI", ["managed", "openai-compatible", "exllamav2"], "adapter"),
      ("exllamav2", "ExLlamaV2", ["managed", "openai-compatible", "exllamav2", "gptq"], "adapter"),
      ("aphrodite", "Aphrodite Engine", ["managed", "openai-compatible", "server"], "adapter"),
      ("lmdeploy", "LMDeploy", ["managed", "openai-compatible", "server", "turbomind"], "adapter"),
      ("mistral.rs", "mistral.rs", ["managed", "openai-compatible", "rust", "gguf"], "adapter"),
      ("mlc-llm", "MLC-LLM", ["managed", "openai-compatible", "mlc", "metal"], "adapter"),
      ("lightllm", "LightLLM", ["managed", "openai-compatible", "server"], "adapter"),
      ("fastchat", "FastChat", ["managed", "openai-compatible", "server"], "adapter"),
      ("openllm", "OpenLLM", ["managed", "openai-compatible", "server", "bentoml"], "adapter"),
      ("nexa", "Nexa SDK", ["managed", "openai-compatible", "multimodal"], "adapter"),
      ("litellm", "LiteLLM", ["external", "openai-compatible", "proxy"], "external"),
      (
        "llama-swap", "llama-swap", ["external", "openai-compatible", "proxy", "on-demand-swap"],
        "external"
      ),
      (
        "transformers", "Transformers", ["managed", "openai-compatible", "python", "hugging-face"],
        "adapter"
      ),
      (
        "triton", "Triton Inference Server", ["external", "openai-compatible", "server"], "external"
      ),
      ("tensorrt-llm", "TensorRT-LLM", ["managed", "openai-compatible", "server"], "adapter"),
      (
        "onnxruntime-genai", "ONNX Runtime GenAI", ["managed", "openai-compatible", "onnx"],
        "adapter"
      ),
      (
        "text-generation-webui", "text-generation-webui",
        ["managed", "openai-compatible", "launcher"], "adapter"
      ),
      ("localai", "LocalAI", ["external", "openai-compatible", "multi-backend"], "external"),
      ("lm-studio", "LM Studio", ["external", "openai-compatible", "desktop"], "external"),
      ("jan", "Jan", ["external", "openai-compatible", "desktop"], "external"),
      ("external", "OpenAI-compatible endpoint", ["external", "openai-compatible"], "external"),
      ("command", "Custom command", ["managed", "custom", "openai-compatible"], "command"),
    ]
    return Dictionary(
      uniqueKeysWithValues: entries.map {
        ($0.0, RuntimeSpec(label: $0.1, tags: $0.2, launchMode: $0.3))
      })
  }()

  public static func canonical(_ value: String?) -> String {
    let normalized = (value ?? "llama.cpp").trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased().replacingOccurrences(of: "_", with: "-")
    return aliases[normalized] ?? normalized
  }

  public static func spec(for profile: ControllerProfile) -> RuntimeSpec {
    var spec =
      specs[profile.runtime]
      ?? RuntimeSpec(label: profile.runtime, tags: ["managed", "custom"], launchMode: "adapter")
    if profile["START_COMMAND"] != nil {
      spec = RuntimeSpec(label: spec.label, tags: spec.tags, launchMode: "command")
    } else if let launchMode = profile["LAUNCH_MODE"]?.lowercased(), !launchMode.isEmpty {
      spec = RuntimeSpec(label: spec.label, tags: spec.tags, launchMode: launchMode)
    }
    return spec
  }

  public static func tags(for profile: ControllerProfile) -> [String] {
    let configured = (profile["RUNTIME_TAGS"] ?? profile["TAGS"] ?? "")
      .replacingOccurrences(of: ",", with: " ").split(whereSeparator: \.isWhitespace).map {
        $0.lowercased()
      }
    var result: [String] = []
    for tag in [profile.runtime] + spec(for: profile).tags + configured where !result.contains(tag)
    {
      result.append(tag)
    }
    return result
  }
}
