import AppKit
import NewsKit
import ServiceManagement
import SwiftUI

/// The Settings window (⌘,). Settings the widget follows are stored in the App Group (see `NewsSettings`),
/// and every change reloads the widgets.
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
            ContentSettings()
                .tabItem { Label("Content", systemImage: "line.3.horizontal.decrease.circle") }
            StorageSettings()
                .tabItem { Label("Storage", systemImage: "internaldrive") }
        }
        .frame(width: 500)
    }
}

// MARK: - General

private struct GeneralSettings: View {
    @AppStorage(NewsSettings.Key.appearance, store: AppGroup.defaults) private var appearance = AppearanceOption.system
    @AppStorage(NewsSettings.Key.refreshInterval, store: AppGroup.defaults) private var refreshInterval = RefreshInterval.standard

    var body: some View {
        Form {
            Section {
                LoginItemToggle()
                Picker("Appearance", selection: $appearance) {
                    ForEach(AppearanceOption.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
            }
            Section {
                Picker("Refresh news every", selection: $refreshInterval) {
                    ForEach(RefreshInterval.allCases) { interval in
                        Text(interval.title).tag(interval)
                    }
                }
                WidgetUpdateRow()
            } header: {
                Text("Updates")
            } footer: {
                Text("Applies to the widgets and the TechNews window. To save energy, macOS may update widgets a little later.")
                    .settingsFooter()
            }
        }
        .formStyle(.grouped)
        .onChange(of: appearance) { appearance.apply() }
        .onChange(of: refreshInterval) { WidgetReloader.reloadSoon() }
    }
}

/// "Open at login", in step with the login items in System Settings, where it can also be turned off.
private struct LoginItemToggle: View {
    @State private var status = SMAppService.mainApp.status
    @State private var failure: String?

    var body: some View {
        Toggle(isOn: Binding(get: { status == .enabled || status == .requiresApproval }, set: setOpensAtLogin)) {
            Text("Open at login")
            Text("The widgets keep updating even when TechNews isn't open.")
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            status = SMAppService.mainApp.status
        }
        if status == .requiresApproval {
            LabeledContent {
                Button("Open Login Items…") {
                    SMAppService.openSystemSettingsLoginItems()
                }
            } label: {
                Text("Needs your approval")
                Text("Allow TechNews in Login Items in System Settings.")
            }
        }
        if let failure {
            Text(failure)
                .foregroundStyle(.red)
        }
    }

    private func setOpensAtLogin(_ opensAtLogin: Bool) {
        do {
            if opensAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            failure = nil
        } catch {
            failure = error.localizedDescription
        }
        status = SMAppService.mainApp.status
    }
}

/// When the widgets last downloaded headlines, and a button that makes them download now.
private struct WidgetUpdateRow: View {
    @State private var lastSaved = NewsCache.shared.usage().lastSaved
    /// Set while waiting for the widgets, which download in their own process.
    @State private var requestedAt: Date?

    var body: some View {
        LabeledContent("Widgets last updated") {
            HStack(spacing: 10) {
                if let lastSaved {
                    Text(lastSaved, format: .relative(presentation: .named))
                } else {
                    Text("Never")
                }
                if requestedAt != nil {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button("Update Now") {
                        requestedAt = .now
                        WidgetReloader.refreshNow()
                    }
                }
            }
        }
        .task {
            while !Task.isCancelled {
                lastSaved = NewsCache.shared.usage().lastSaved
                if let requestedAt,
                   lastSaved ?? .distantPast > requestedAt || Date.now.timeIntervalSince(requestedAt) > 30 {
                    self.requestedAt = nil
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}

/// The look of the app's windows, title bars included. Widgets follow the system.
enum AppearanceOption: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    static var saved: AppearanceOption {
        AppGroup.defaults.string(forKey: NewsSettings.Key.appearance).flatMap(Self.init) ?? .system
    }

    func apply() {
        NSApp.appearance = switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

extension RefreshInterval {
    /// "30 minutes", "2 hours", in the user's language.
    var title: String {
        Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes], width: .wide))
    }
}

extension StoryOrder {
    var title: LocalizedStringResource {
        switch self {
        case .topStoriesFirst: "Top Stories First"
        case .bySource: "By Source"
        }
    }
}

// MARK: - Content

private struct ContentSettings: View {
    @AppStorage(NewsSettings.Key.hiddenSources, store: AppGroup.defaults) private var hiddenSources = ""
    @AppStorage(NewsSettings.Key.mutedWords, store: AppGroup.defaults) private var mutedWords = ""
    @AppStorage(NewsSettings.Key.storyOrder, store: AppGroup.defaults) private var storyOrder = StoryOrder.standard

    var body: some View {
        Form {
            Section {
                Picker("Story order", selection: $storyOrder) {
                    ForEach(StoryOrder.allCases) { order in
                        Text(order.title).tag(order)
                    }
                }
            } header: {
                Text("Order")
            } footer: {
                Text("Top Stories First puts the stories that several outlets report on the first page. Applies to the widgets and the TechNews window.")
                    .settingsFooter()
            }
            Section {
                ForEach(NewsSource.all, id: \.id) { source in
                    Toggle(isOn: isShown(source)) {
                        Label {
                            Text(source.name)
                        } icon: {
                            MonogramTile(sourceID: source.id, cornerRadius: 5)
                                .frame(width: 20, height: 20)
                        }
                    }
                }
            } header: {
                Text("Widget Sources")
            } footer: {
                Text("Widgets show headlines from the sources that are on. The TechNews window always shows every source.")
                    .settingsFooter()
            }
            Section {
                MutedWordsEditor(storedWords: $mutedWords)
            } header: {
                Text("Muted Words")
            } footer: {
                Text("Stories whose title or summary mentions one of these words are hidden in the widgets and in the TechNews window. English words match whole words, so “AI” doesn't hide “said”.")
                    .settingsFooter()
            }
        }
        .formStyle(.grouped)
        .onChange(of: hiddenSources) { WidgetReloader.reloadSoon() }
        .onChange(of: mutedWords) { WidgetReloader.reloadSoon() }
        .onChange(of: storyOrder) { WidgetReloader.reloadSoon() }
    }

    private func isShown(_ source: NewsSource) -> Binding<Bool> {
        Binding {
            !NewsSettings.lines(hiddenSources).contains(source.id)
        } set: { isShown in
            var hidden = Set(NewsSettings.lines(hiddenSources))
            if isShown {
                hidden.remove(source.id)
            } else {
                hidden.insert(source.id)
            }
            // In the sources' usual order, so the stored value doesn't depend on the order of the clicks.
            hiddenSources = NewsSource.all.map(\.id).filter(hidden.contains).joined(separator: "\n")
        }
    }
}

/// The muted words as tags with a remove button, and a field that adds more.
private struct MutedWordsEditor: View {
    @Binding var storedWords: String
    @State private var draft = ""

    var body: some View {
        let words = NewsSettings.lines(storedWords)
        if !words.isEmpty {
            FlowLayout(spacing: 6) {
                ForEach(words, id: \.self) { word in
                    WordTag(word: word) { remove(word) }
                }
            }
            .padding(.vertical, 3)
        }
        HStack {
            TextField("Muted word", text: $draft, prompt: Text("Add words, e.g. crypto, 手机"))
                .labelsHidden()
                .onSubmit(add)
            Button("Add", action: add)
                .disabled(Self.words(in: draft).isEmpty)
        }
    }

    /// Adds every comma-separated word in the field that isn't muted yet.
    private func add() {
        var words = NewsSettings.lines(storedWords)
        for word in Self.words(in: draft) where !words.contains(where: { $0.caseInsensitiveCompare(word) == .orderedSame }) {
            words.append(word)
        }
        withAnimation(.snappy) {
            storedWords = words.joined(separator: "\n")
        }
        draft = ""
    }

    private func remove(_ word: String) {
        withAnimation(.snappy) {
            storedWords = NewsSettings.lines(storedWords).filter { $0 != word }.joined(separator: "\n")
        }
    }

    private static func words(in text: String) -> [String] {
        text.components(separatedBy: CharacterSet(charactersIn: ",，、;；\n"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

private struct WordTag: View {
    let word: String
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(word)
                .lineLimit(1)
            Button(action: remove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Remove \(word)"))
        }
        .font(.system(size: 12, weight: .medium))
        .padding(.leading, 9)
        .padding(.trailing, 5)
        .padding(.vertical, 4)
        .background(Capsule().fill(.quaternary))
        .transition(.scale(scale: 0.8).combined(with: .opacity))
    }
}

/// Places its subviews in rows from left to right, starting a new row when one is full.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let frames = frames(of: subviews, width: proposal.width ?? .infinity)
        return CGSize(width: frames.map(\.maxX).max() ?? 0, height: frames.map(\.maxY).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (subview, frame) in zip(subviews, frames(of: subviews, width: bounds.width)) {
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                          proposal: ProposedViewSize(frame.size))
        }
    }

    private func frames(of subviews: Subviews, width: CGFloat) -> [CGRect] {
        var frames: [CGRect] = []
        var origin = CGPoint.zero
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if origin.x > 0, origin.x + size.width > width {
                origin = CGPoint(x: 0, y: origin.y + rowHeight + spacing)
                rowHeight = 0
            }
            frames.append(CGRect(origin: origin, size: size))
            origin.x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return frames
    }
}

// MARK: - Storage

private struct StorageSettings: View {
    @State private var usage = NewsCache.shared.usage()
    @State private var clearFailed = false

    var body: some View {
        Form {
            Section {
                LabeledContent("Headlines", value: Self.bytes(usage.headlineBytes))
                LabeledContent {
                    Text(Self.bytes(usage.thumbnailBytes))
                } label: {
                    Text("Pictures")
                    Text("\(usage.thumbnailCount) thumbnails")
                }
                LabeledContent("Total") {
                    Text(Self.bytes(usage.totalBytes))
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                }
            } header: {
                Text("Widget Cache")
            } footer: {
                Text("The widgets keep the latest headlines and small pictures so they can show news right away. The cache stays under about 400 KB and deletes anything older than 3 days by itself.")
                    .settingsFooter()
            }
            Section {
                LabeledContent {
                    Button("Clear", action: clear)
                        .disabled(usage.totalBytes == 0)
                } label: {
                    Text("Clear the widget cache")
                    Text("The widgets then download fresh headlines and pictures.")
                }
                if clearFailed {
                    Text("Some files couldn't be deleted. Try again in a moment.")
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .task {
            // The widgets write to the cache from their own process.
            while !Task.isCancelled {
                usage = NewsCache.shared.usage()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func clear() {
        clearFailed = !NewsCache.shared.removeAll()
        withAnimation {
            usage = NewsCache.shared.usage()
        }
        WidgetReloader.reloadSoon()
    }

    private static func bytes(_ count: Int) -> String {
        Int64(count).formatted(.byteCount(style: .file, spellsOutZero: false))
    }
}

// MARK: - Pieces

private extension View {
    /// Explanations under a section: small, gray and left-aligned (footers are right-aligned for buttons),
    /// wrapping instead of widening the window.
    func settingsFooter() -> some View {
        font(.callout)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 10)
    }
}
