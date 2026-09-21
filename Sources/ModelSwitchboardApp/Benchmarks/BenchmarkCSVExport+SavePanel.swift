import AppKit
import UniformTypeIdentifiers
import ModelSwitchboardCore

extension BenchmarkCSVExport {
    @MainActor
    static func presentSavePanel(
        for latest: BenchmarkLatestReport,
        onComplete: @escaping (Notice) -> Void
    ) {
        guard !latest.rows.isEmpty else {
            onComplete(Notice(message: "No benchmark data to export yet.", isError: true))
            return
        }

        let panel = NSSavePanel()
        panel.title = "Export Benchmark CSV"
        panel.prompt = "Export"
        panel.nameFieldStringValue = defaultFileName(latest.generatedAt)
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false

        Task { @MainActor in
            let response = await panel.begin()
            guard response == .OK, let url = panel.url else { return }
            do {
                try makeCSV(from: latest).write(to: url, atomically: true, encoding: .utf8)
                onComplete(Notice(message: "Exported CSV to \(url.lastPathComponent).", isError: false))
            } catch {
                onComplete(Notice(message: "CSV export failed: \(error.localizedDescription)", isError: true))
            }
        }
    }
}
