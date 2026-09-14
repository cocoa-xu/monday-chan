import AppKit
import AVFoundation
import FlowingDayControls
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class OnboardingWindow: NSWindow {
    private let model: MondayOnboardingModel
    private let onCancel: () -> Void

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    init(destination: URL, localization: AppLocalization, initialState: MondayOnboardingModel.State = .selection,
         onCancel: @escaping () -> Void, onImported: @escaping () -> Void) {
        self.onCancel = onCancel
        model = MondayOnboardingModel(destination: destination, errorText: { localization.text.error($0) },
                                      initialState: initialState, onImported: onImported)
        super.init(contentRect: NSRect(x: 0, y: 0, width: 780, height: 540), styleMask: [.borderless],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        center()
        contentView = NSHostingView(rootView: MondayOnboardingView(model: model, localization: localization, window: self))
    }

    func show() {
        center()
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func cancel() { model.cancel() }

    override func close() {
        model.cancel()
        super.close()
        onCancel()
    }
}

@MainActor
final class MondayOnboardingModel: ObservableObject {
    enum State: Equatable { case selection, importing, failed(String) }
    enum MediaValidation: Equatable { case empty, checking, valid, invalid(String) }
    typealias ValidateMedia = @Sendable (URL) async throws -> Void

    @Published var gameFolder: URL?
    @Published var mediaFile: URL?
    @Published private(set) var state: State = .selection
    @Published private(set) var mediaValidation: MediaValidation = .empty
    @Published private(set) var progress = MondayImportProgress(phase: .locating, fraction: 0)
    @Published private(set) var isPreviewing = false
    let destination: URL
    private let importer = MondayImporter()
    private let errorText: (Error) -> String
    private let validateMedia: ValidateMedia
    private let onImported: () -> Void
    private var task: Task<Void, Never>?
    private var mediaValidationTask: Task<Void, Never>?
    private var previewPlayer: AVPlayer?
    private var previewObservers: [NSObjectProtocol] = []
    private var generation = 0
    private var mediaGeneration = 0

    init(destination: URL, errorText: @escaping (Error) -> String = { $0.localizedDescription },
         initialState: State = .selection,
         validateMedia: @escaping ValidateMedia = { try await MondayAudioImporter.validateMondayMedia($0) },
         onImported: @escaping () -> Void) {
        self.destination = destination
        self.errorText = errorText
        state = initialState
        self.validateMedia = validateMedia
        self.onImported = onImported
    }

    var canImport: Bool { gameFolder != nil && mediaFile != nil && mediaValidation == .valid && state != .importing }
    var mediaIsChecking: Bool { mediaValidation == .checking }
    var mediaHasError: Bool {
        if case .invalid = mediaValidation { return true }
        return false
    }
    var errorMessage: String? {
        if case .invalid(let message) = mediaValidation { return message }
        if case .failed(let message) = state { return message }
        return nil
    }

    func chooseGameFolder(text: LocalizedText) {
        let panel = NSOpenPanel()
        panel.title = text("Choose Game or Export Folder")
        panel.message = text("Select the folder that contains Kanade’s model, motions, and expressions.")
        panel.prompt = text("Choose Folder")
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        guard panel.runModal() == .OK else { return }
        gameFolder = panel.url
        if case .failed = state { state = .selection }
    }

    func chooseMediaFile(text: LocalizedText) {
        let panel = NSOpenPanel()
        panel.title = text("Choose Monday Video or Audio")
        panel.message = text("Select the separate media file that contains the Monday performance audio.")
        panel.prompt = text("Choose Media")
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.audiovisualContent, .audio, .movie]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        selectMedia(url)
    }

    func acceptMedia(_ urls: [URL]) -> Bool {
        guard let url = urls.first, ["mp4", "mov", "m4a", "mp3", "wav"].contains(url.pathExtension.lowercased()) else { return false }
        selectMedia(url)
        return true
    }

    func togglePreview() {
        if isPreviewing { stopPreview(); return }
        guard let mediaFile else { return }
        let item = AVPlayerItem(url: mediaFile)
        let player = AVPlayer(playerItem: item)
        previewPlayer = player
        previewObservers.append(NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification,
                                                                        object: item, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.stopPreview() }
        })
        previewObservers.append(NotificationCenter.default.addObserver(forName: AVPlayerItem.failedToPlayToEndTimeNotification,
                                                                        object: item, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.stopPreview()
                self.state = .failed(self.errorText(MondayImportError.invalidMedia))
            }
        })
        isPreviewing = true
        player.play()
    }

    func stopPreview() {
        previewPlayer?.pause()
        previewPlayer = nil
        previewObservers.forEach(NotificationCenter.default.removeObserver)
        previewObservers.removeAll()
        isPreviewing = false
    }

    func startImport() {
        guard let gameFolder, let mediaFile, canImport else { return }
        state = .importing
        stopPreview()
        progress = MondayImportProgress(phase: .locating, fraction: 0)
        generation += 1
        let generation = generation
        task = Task { [weak self, importer, destination] in
            guard let self else { return }
            do {
                _ = try await importer.importAssets(gameFolder: gameFolder, mediaFile: mediaFile,
                                                    destination: destination) { progress in
                    Task { @MainActor in
                        guard self.generation == generation else { return }
                        self.progress = progress
                    }
                }
                try Task.checkCancellation()
                guard self.generation == generation else { return }
                self.task = nil
                self.onImported()
            } catch is CancellationError {
                guard self.generation == generation else { return }
                self.task = nil
                self.state = .selection
            } catch {
                guard self.generation == generation else { return }
                self.task = nil
                self.state = .failed(self.errorText(error))
            }
        }
    }

    func cancel() {
        stopPreview()
        mediaValidationTask?.cancel()
        mediaValidationTask = nil
        if mediaValidation == .checking {
            mediaFile = nil
            mediaValidation = .empty
        }
        generation += 1
        task?.cancel()
        task = nil
        if state == .importing { state = .selection }
    }

    private func selectMedia(_ url: URL) {
        stopPreview()
        mediaValidationTask?.cancel()
        mediaGeneration += 1
        let generation = mediaGeneration
        mediaFile = url
        mediaValidation = .checking
        if case .failed = state { state = .selection }
        mediaValidationTask = Task { [weak self, validateMedia] in
            guard let self else { return }
            do {
                try await validateMedia(url)
                try Task.checkCancellation()
                guard self.mediaGeneration == generation else { return }
                self.mediaValidation = .valid
                self.mediaValidationTask = nil
            } catch is CancellationError {
                return
            } catch {
                guard self.mediaGeneration == generation else { return }
                self.mediaValidation = .invalid(self.errorText(error))
                self.mediaValidationTask = nil
            }
        }
    }
}

struct MondayOnboardingView: View {
    @ObservedObject var model: MondayOnboardingModel
    @ObservedObject var localization: AppLocalization
    unowned let window: OnboardingWindow
    private var text: LocalizedText { localization.text }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            HStack(spacing: 0) {
                rail
                ZStack {
                    FlowingPalette.canvas
                    content.padding(40)
                }
            }
            Button { window.close() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(FlowingPalette.muted)
                    .frame(width: 28, height: 28)
                    .background(FlowingPalette.card, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(text("Close setup"))
            .padding(14)
        }
        .frame(width: 780, height: 540)
        .background(FlowingPalette.canvas)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(FlowingPalette.hairline) }
        .environment(\.locale, text.locale)
        .environment(\.flowingStrings, text.controls)
        .flowingAccent(MondayTheme.accent)
        .tint(MondayTheme.accent.fill)
    }

    private var rail: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                if let image = NSApp.applicationIconImage {
                    Image(nsImage: image).resizable().scaledToFit().frame(width: 34, height: 34)
                }
                Text("Monday-chan").font(.system(size: 18, weight: .bold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.8)
            }
            Spacer().frame(height: 54)
            Text(text("Mondays can use\na little sparkle."))
                .font(.system(size: 24, weight: .semibold, design: .rounded))
            Text(text("Import the resources for Kanade’s Monday performance."))
                .font(.system(size: 12)).foregroundStyle(FlowingPalette.muted).lineSpacing(3).padding(.top, 12)
            Spacer()
            VStack(alignment: .leading, spacing: 18) {
                step("01", text("Choose resources"), active: model.state != .importing)
                step("02", text("Import and verify"), active: model.state == .importing)
                step("03", text("Brace for Monday"), active: false)
            }
        }
        .padding(.horizontal, 28).padding(.vertical, 40)
        .frame(width: 232)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(FlowingPalette.card)
        .overlay(alignment: .trailing) { Rectangle().fill(FlowingPalette.hairline).frame(width: 1) }
    }

    private func step(_ number: String, _ title: String, active: Bool) -> some View {
        HStack(spacing: 10) {
            Text(number).font(.system(.caption, design: .monospaced)).foregroundStyle(active ? MondayTheme.accent.foreground : FlowingPalette.faint)
            Text(title).font(.caption).foregroundStyle(active ? FlowingPalette.ink : FlowingPalette.muted)
        }
    }

    private var content: some View {
        ZStack {
            selection
            if model.state == .importing {
                FlowingPalette.canvas.opacity(0.96)
                importing
            }
        }
    }

    private var selection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(text("Set up Monday-chan"))
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .lineLimit(1).minimumScaleFactor(0.72).padding(.trailing, 42)
            Text(text("Choose two sources. The performance media is separate from the game or export folder."))
                .foregroundStyle(FlowingPalette.muted)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    sourceCard(title: text("Game or export folder"), detail: model.gameFolder?.path(percentEncoded: false),
                               empty: text("Contains the model, motions, and expressions"), action: { model.chooseGameFolder(text: text) })
                    sourceCard(title: text("Monday Video or Audio"), detail: model.mediaFile?.lastPathComponent,
                               empty: text("Contains the Monday performance audio"), isChecking: model.mediaIsChecking,
                               hasError: model.mediaHasError, action: { model.chooseMediaFile(text: text) })
                        .dropDestination(for: URL.self) { urls, _ in model.acceptMedia(urls) }
                    HStack {
                        Button(text("Open Original Video")) {
                            NSWorkspace.shared.open(URL(string: "https://x.com/YouTubeJapan/status/2091495920311414921")!)
                        }.buttonStyle(FlowingSoftButtonStyle())
                        if model.mediaFile != nil {
                            Button(text(model.isPreviewing ? "Stop Preview" : "Preview Audio"), action: model.togglePreview)
                                .buttonStyle(FlowingSoftButtonStyle())
                        }
                    }
                    Text(text("Download the original clip yourself, then choose or drop the MP4 or MOV here. The app extracts a local audio copy and leaves your video unchanged."))
                        .font(.caption).foregroundStyle(FlowingPalette.faint)
                    if let message = model.errorMessage {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(text(model.mediaHasError ? "Check Your Video" : "Import failed")).font(.headline).foregroundStyle(.red)
                            Text(message).font(.caption).foregroundStyle(FlowingPalette.muted).textSelection(.enabled)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Text(text("Nothing is uploaded. Imported files stay on this Mac."))
                    .font(.caption).foregroundStyle(FlowingPalette.faint)
                Spacer()
                Button(text(model.state == .selection ? "Import" : "Retry"), action: model.startImport)
                    .buttonStyle(FlowingSoftButtonStyle()).disabled(!model.canImport)
            }
        }
    }

    private var importing: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(text("Preparing Monday-chan…")).font(.system(size: 28, weight: .bold, design: .rounded))
            Text(phaseName(model.progress.phase)).foregroundStyle(FlowingPalette.muted)
            ProgressView(value: model.progress.fraction).progressViewStyle(.linear)
            Text(String(format: text("%.0f%% complete"), model.progress.fraction * 100))
                .font(.caption).foregroundStyle(FlowingPalette.faint)
            Spacer()
            HStack {
                Spacer()
                Button(text("Cancel"), action: model.cancel).buttonStyle(FlowingSoftButtonStyle())
            }
        }
    }

    private func sourceCard(title: String, detail: String?, empty: String, isChecking: Bool = false,
                            hasError: Bool = false, action: @escaping () -> Void) -> some View {
        HStack(spacing: 14) {
            Group {
                if isChecking {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: detail == nil ? "circle.dashed" : hasError ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(hasError ? AnyShapeStyle(Color.red) : AnyShapeStyle(detail == nil ? FlowingPalette.muted : MondayTheme.accent.foreground))
                }
            }
            .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail ?? empty).font(.caption).foregroundStyle(FlowingPalette.muted).lineLimit(2)
            }
            Spacer()
            Button(text(detail == nil ? "Choose…" : "Change…"), action: action).buttonStyle(FlowingSoftButtonStyle())
        }
        .padding(16).background(FlowingPalette.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(FlowingPalette.hairline) }
    }

    private func phaseName(_ phase: MondayImportProgress.Phase) -> String {
        switch phase {
        case .locating: text("Finding source files…")
        case .extractingModel: text("Extracting Kanade’s model…")
        case .extractingMotions: text("Extracting motions…")
        case .extractingMouths: text("Extracting expressions…")
        case .convertingMedia: text("Preparing performance audio…")
        case .validating: text("Checking imported resources…")
        case .installing: text("Installing resources…")
        }
    }
}
