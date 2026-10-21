import SwiftUI
import Testing
@testable import Rapid

/// A long model name must never push the composer past the window edge.
///
/// Mounted on a real ``ChatView`` at each detail-pane width the three
/// verified window sizes produce (1440 / 1000 / 720 → 1240 / 800 / 520),
/// in every composer state, and measured through the accessibility frames
/// an assistive client reads. The model chip is the one flexible control:
/// it must truncate so that attach, the picker's info button and Send all
/// stay fully inside the window and do not overlap.
@Suite("Composer layout bounds — long model names")
@MainActor
struct ComposerLayoutBoundsTests {
    static let longAlias = "mlx-community/Qwen3.5-Coder-30B-A3B-Instruct-Distill-4bit-dwq-v2"
    private static let gib: Int64 = 1 << 30

    private static let states: [(String, ModelReadiness, ModelReadiness.ProgressSnapshot?)] = [
        ("needsStart", .needsStart(alias: longAlias), nil),
        ("stopped", .needsDownload(alias: longAlias, sizeText: nil), nil),
        ("downloading", .downloading(alias: longAlias, detail: nil, fraction: 0.12),
         .init(activity: .downloading, fraction: 0.12,
               bytesDownloaded: gib * 2, totalBytes: gib * 16, etaText: "1 h 4 min left")),
        ("loading", .starting(alias: longAlias, detail: nil), .init(activity: .loading)),
        ("failed", .failed(
            alias: longAlias,
            message: "The model process exited while loading. Retry, or open the startup log for details.",
            action: .retry(alias: longAlias)
        ), nil),
        ("ready", .ready(alias: longAlias), nil),
    ]

    private func stage(
        _ readiness: ModelReadiness,
        progress: ModelReadiness.ProgressSnapshot?,
        width: CGFloat
    ) -> GoldenStage {
        let server = ServerManager(testingState: .starting(alias: Self.longAlias))
        let size = CGSize(width: width, height: 560)
        let downloads = DownloadManager()
        if case .downloading = readiness {
            _ = downloads._testingSeedJob(alias: Self.longAlias)
        } else if case .needsDownload = readiness {
            _ = downloads._testingSeedJob(alias: Self.longAlias)
            downloads._testingFinish(alias: Self.longAlias, status: 15, reason: .uncaughtSignal, wasCancelling: true)
        }
        return GoldenStage(
            ChatView(
                viewModel: ChatViewModel(persistsConversations: false),
                server: server,
                alias: .constant(Self.longAlias),
                readiness: readiness,
                loadProgress: progress
            )
            .environment(server)
            .environment(downloads)
            .environment(QuickstartCoordinator())
            .frame(width: size.width, height: size.height),
            size: size
        )
    }

    @Test(
        "Every composer control stays inside the window with a long model name",
        arguments: [
            RapidTheme.Layout.Breakpoint.wide,
            RapidTheme.Layout.Breakpoint.mid,
            RapidTheme.Layout.Breakpoint.floor,
        ]
    )
    func controlsStayInBounds(width: CGFloat) async throws {
        for (name, readiness, progress) in Self.states {
            let stage = stage(readiness, progress: progress, width: width)
            try await stage.waitForIdentifier("ChatView.SendOrStopButton")
            let window = stage.windowFrame
            let ids = [
                "ChatView.AddAttachments",
                "ModelPickerBar.ModelMenu",
                "ModelPickerBar.ModelInfo",
                "ChatView.SendOrStopButton",
            ]
            var frames: [CGRect] = []
            for id in ids {
                let frame = try #require(stage.frame(of: id), "\(name) @\(width): no frame for \(id)")
                #expect(frame.width > 0, "\(name) @\(width): \(id) collapsed to zero width")
                #expect(
                    frame.minX >= window.minX - 0.5 && frame.maxX <= window.maxX + 0.5,
                    "\(name) @\(width): \(id) \(frame) leaves the window \(window)"
                )
                frames.append(frame)
            }
            // Left-to-right with no overlap: attach … picker, info, Send.
            for (left, right) in zip(frames, frames.dropFirst()) {
                #expect(left.maxX <= right.minX + 0.5, "\(name) @\(width): \(left) overlaps \(right)")
            }
            // The full name is never lost — only its rendering truncates.
            #expect(stage.value(of: "ModelPickerBar.ModelMenu") == Self.longAlias)

            if let status = stage.frame(of: "Composer.LoadStatus") {
                #expect(
                    status.minX >= window.minX - 0.5 && status.maxX <= window.maxX + 0.5,
                    "\(name) @\(width): load status \(status) leaves the window"
                )
                #expect(stage.treeText().contains(Self.longAlias), "\(name): full name missing from the status label")
            }
            if name == "downloading" || name == "stopped" {
                let action = try #require(stage.frame(of: "Composer.DownloadAction"))
                #expect(action.minX >= window.minX - 0.5 && action.maxX <= window.maxX + 0.5)
            }
            if name == "failed" {
                let retry = try #require(stage.frame(of: "Readiness.Action"))
                #expect(retry.maxX <= window.maxX + 0.5, "failed @\(width): Retry \(retry) leaves the window")
            }
        }
    }

    /// At a width with room to spare the chip is not truncated for nothing:
    /// it is wider at 1240 than at 520, which is what proves it is the
    /// flexible control rather than a fixed, pre-shortened one.
    @Test("The model chip uses available room before it truncates")
    func chipGrowsWithRoom() async throws {
        func chipWidth(_ width: CGFloat) async throws -> CGFloat {
            let stage = stage(.ready(alias: Self.longAlias), progress: nil, width: width)
            try await stage.waitForIdentifier("ModelPickerBar.ModelMenu")
            return try #require(stage.frame(of: "ModelPickerBar.ModelMenu")).width
        }
        let narrow = try await chipWidth(RapidTheme.Layout.Breakpoint.floor)
        let wide = try await chipWidth(RapidTheme.Layout.Breakpoint.wide)
        #expect(wide > narrow, "chip is \(wide)pt at 1240 and \(narrow)pt at 520")
    }
}
