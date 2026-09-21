import Foundation
import ModelSwitchboardCore

extension BenchmarkService {
    func run(prompt: PromptCase, profile: ControllerProfile) -> [String: Any] {
        guard let endpoint = URL(string: "\(profile.baseURL)/chat/completions") else {
            return ["benchmark": prompt.name, "category": prompt.category, "error": "invalid endpoint"]
        }
        let request: [String: Any] = [
            "model": profile.requestModel,
            "messages": [["role": "user", "content": prompt.prompt]],
            "max_tokens": prompt.maxTokens,
            "stream": false,
            "temperature": 0,
        ]
        guard let requestData = try? JSONSupport.data(request) else {
            return ["benchmark": prompt.name, "category": prompt.category, "error": "encoding failed"]
        }
        return runCurl(prompt: prompt, endpoint: endpoint, requestData: requestData)
    }

    func runCurl(prompt: PromptCase, endpoint: URL, requestData: Data) -> [String: Any] {
        let start = Date()
        let result: ProcessResult
        do {
            result = try ProcessRunner.run(
                "/usr/bin/curl",
                [
                    "--fail", "--silent", "--show-error",
                    "--max-redirs", "0",
                    "--noproxy", "*",
                    "--max-time", "120",
                    "--header", "Content-Type: application/json", "--data-binary",
                    String(decoding: requestData, as: UTF8.self), endpoint.absoluteString,
                ])
        } catch {
            return [
                "benchmark": prompt.name, "category": prompt.category,
                "prompt_est_tokens": prompt.estimatedTokens, "error": String(describing: error),
            ]
        }
        return decodeBenchmark(prompt: prompt, result: result, elapsedMS: Date().timeIntervalSince(start) * 1_000)
    }
}
