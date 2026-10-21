import Observation
import SwiftUI
import Testing
@testable import Rapid

/// The composer's load status on a real, mounted ``ChatView``: one surface
/// driven through download → load → failure → retry → ready, asserting on
/// the accessibility tree a VoiceOver user (and the AX golden flows) see.
@Suite("Composer load status — mounted chat")
@MainActor
struct ComposerLoadStatusStageTests {
    private static let alias = "qwen3.5-4b-4bit"
    private static let composeID = AutosizingTextView.composeAccessibilityIdentifier

    @MainActor
    @Observable
    final class Lifecycle {
        var readiness: ModelReadiness = .needsStart(alias: ComposerLoadStatusStageTests.alias)
        var progress: ModelReadiness.ProgressSnapshot?
        var actions: [ModelReadiness.Action] = []
    }

    private struct Host: View {
        let lifecycle: Lifecycle
        let chat: ChatViewModel
        let server: ServerManager

        var body: some View {
            ChatView(
                viewModel: chat,
                server: server,
                alias: .constant(ComposerLoadStatusStageTests.alias),
                readiness: lifecycle.readiness,
                loadProgress: lifecycle.progress,
                onReadinessAction: { lifecycle.actions.append($0) }
            )
            .environment(server)
            .environment(DownloadManager())
            .environment(QuickstartCoordinator())
            .frame(width: 720, height: 560)
        }
    }

    private func node(_ stage: GoldenStage, _ id: String) -> GoldenStage.Node? {
        stage.tree().first { $0.id == id }
    }

    @Test("Download, load, failure and ready all render in the composer and keep the draft")
    func lifecycleInTheComposer() async throws {
        let lifecycle = Lifecycle()
        let chat = ChatViewModel(persistsConversations: false)
        let server = ServerManager(testingState: .starting(alias: Self.alias))
        let stage = GoldenStage(Host(lifecycle: lifecycle, chat: chat, server: server))
        let gib: Int64 = 1 << 30

        // A decision state: the notice above the card, no composer slot.
        try await stage.waitForIdentifier("Readiness.Action")
        #expect(node(stage, "Composer.LoadStatus") == nil)

        // The user drafts before starting.
        try await stage.waitForIdentifier(Self.composeID)
        try stage.setValue("Summarise my notes", for: Self.composeID)
        #expect(chat.composerDraft == "Summarise my notes")

        // Downloading: determinate progress with real numbers.
        lifecycle.progress = .init(
            activity: .downloading, fraction: 0.59,
            bytesDownloaded: gib * 17 / 10, totalBytes: gib * 29 / 10,
            etaText: "< 1 min left"
        )
        lifecycle.readiness = .downloading(alias: Self.alias, detail: nil, fraction: 0.59)
        try await stage.waitForIdentifier("Composer.LoadStatus")
        let downloadingRail = try #require(node(stage, "Composer.LoadProgress"))
        #expect(downloadingRail.role == "AXProgressIndicator")
        #expect(stage.treeText().contains("1.7 GB of 2.9 GB"))
        #expect(stage.treeText().contains("59%"))
        // The banner stood down: one description of the moment, not two.
        #expect(node(stage, "Readiness.Action") == nil)
        #expect(!stage.identifiers().contains("Readiness.Band"))
        #expect(stage.value(of: Self.composeID) == "Summarise my notes")

        // Loading a cached model: indeterminate, and the ~1.0 fraction the
        // byte monitor reports must not appear as a percentage.
        lifecycle.progress = .init(
            activity: .loading, fraction: 1.0,
            bytesDownloaded: gib * 29 / 10, totalBytes: gib * 29 / 10
        )
        lifecycle.readiness = .starting(alias: Self.alias, detail: nil)
        try await stage.wait(for: "the loading title") {
            stage.treeText().contains("Loading the model into memory…")
        }
        // AppKit's role for progress with no value: an indeterminate
        // indicator, never a determinate one pinned at some number.
        #expect(node(stage, "Composer.LoadProgress")?.role == "AXBusyIndicator")
        #expect(!stage.treeText().contains("100%"))
        #expect(stage.value(of: Self.composeID) == "Summarise my notes")

        // A failed start: the recovery action lives in the slot, under the
        // identifier the golden flows already address.
        lifecycle.progress = nil
        lifecycle.readiness = .failed(
            alias: Self.alias, message: "The model process exited while loading.",
            action: .retry(alias: Self.alias)
        )
        try await stage.waitForIdentifier("Readiness.Action")
        try await stage.waitForIdentifierGone("Composer.LoadProgress")
        #expect(stage.treeText().contains("The model process exited while loading."))
        try stage.press("Readiness.Action")
        #expect(lifecycle.actions == [.retry(alias: Self.alias)])
        #expect(stage.value(of: Self.composeID) == "Summarise my notes")

        // Retry → loading → ready: the slot closes in place and the draft is
        // exactly what the user typed, still unsent.
        lifecycle.readiness = .starting(alias: Self.alias, detail: nil)
        try await stage.waitForIdentifier("Composer.LoadProgress")
        lifecycle.readiness = .ready(alias: Self.alias)
        try await stage.waitForIdentifierGone("Composer.LoadStatus")
        #expect(node(stage, "Composer.LoadProgress") == nil)
        #expect(node(stage, "Readiness.Action") == nil)
        #expect(stage.value(of: Self.composeID) == "Summarise my notes")
        #expect(chat.composerDraft == "Summarise my notes")
        #expect(chat.messages.isEmpty)
    }
}
