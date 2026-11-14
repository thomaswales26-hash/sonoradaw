import AppKit
import AVFoundation
import AudioToolbox
import UniformTypeIdentifiers

private let sessionDocumentType = UTType(filenameExtension: "sonora", conformingTo: .json) ?? .json

private enum Theme {
    static let background = NSColor(calibratedRed: 0.055, green: 0.060, blue: 0.078, alpha: 1)
    static let panel = NSColor(calibratedRed: 0.085, green: 0.090, blue: 0.115, alpha: 1)
    static let raised = NSColor(calibratedRed: 0.115, green: 0.122, blue: 0.150, alpha: 1)
    static let muted = NSColor(calibratedRed: 0.51, green: 0.54, blue: 0.62, alpha: 1)
    static let accent = NSColor(calibratedRed: 0.66, green: 0.49, blue: 1, alpha: 1)
    static let mint = NSColor(calibratedRed: 0.36, green: 0.88, blue: 0.71, alpha: 1)
    static let separator = NSColor.white.withAlphaComponent(0.08)
    static let trackColors: [NSColor] = [
        NSColor(calibratedRed: 0.40, green: 0.74, blue: 1, alpha: 1),
        NSColor(calibratedRed: 0.34, green: 0.88, blue: 0.69, alpha: 1),
        NSColor(calibratedRed: 1, green: 0.64, blue: 0.39, alpha: 1),
        NSColor(calibratedRed: 0.84, green: 0.55, blue: 1, alpha: 1),
        NSColor(calibratedRed: 1, green: 0.47, blue: 0.58, alpha: 1),
        NSColor(calibratedRed: 0.94, green: 0.80, blue: 0.40, alpha: 1)
    ]
}

private enum EffectKind: String, CaseIterable, Codable {
    case equalizer = "Parametric EQ"
    case compressor = "Compressor"
    case reverb = "Reverb"
    case delay = "Stereo Delay"
    case distortion = "Distortion"
    case pitch = "Pitch Shifter"

    var symbol: String {
        switch self {
        case .equalizer: "slider.horizontal.3"
        case .compressor: "waveform.path"
        case .reverb: "water.waves"
        case .delay: "arrow.trianglehead.2.clockwise"
        case .distortion: "waveform"
        case .pitch: "tuningfork"
        }
    }
    func makeAudioUnit() -> AVAudioUnit {
        switch self {
        case .equalizer:
            return AVAudioUnitEQ(numberOfBands: 4)
        case .compressor:
            let description = AudioComponentDescription(
                componentType: kAudioUnitType_Effect,
                componentSubType: kAudioUnitSubType_DynamicsProcessor,
                componentManufacturer: kAudioUnitManufacturer_Apple,
                componentFlags: 0,
                componentFlagsMask: 0
            )
            return AVAudioUnitEffect(audioComponentDescription: description)
        case .reverb:
            let unit = AVAudioUnitReverb()
            unit.loadFactoryPreset(.mediumRoom)
            unit.wetDryMix = 22
            return unit
        case .delay:
            let unit = AVAudioUnitDelay()
            unit.delayTime = 0.32
            unit.feedback = 24
            unit.wetDryMix = 18
            return unit
        case .distortion:
            let unit = AVAudioUnitDistortion()
            unit.loadFactoryPreset(.multiBrokenSpeaker)
            unit.wetDryMix = 12
            return unit
        case .pitch:
            let unit = AVAudioUnitTimePitch()
            unit.pitch = 2
            unit.rate = 1
            return unit
        }
    }
}

private struct EffectInstance: Codable, Identifiable {
    var id = UUID()
    var kind: EffectKind
    var enabled = true
}

private final class AudioTrack: Identifiable {
    let id: UUID
    var name: String
    var colorIndex: Int
    var filePath: String?
    var duration: Double
    var volume: Float = 0.82
    var pan: Float = 0
    var muted = false
    var solo = false
    var effects: [EffectInstance] = []
    let player = AVAudioPlayerNode()
    let mixer = AVAudioMixerNode()
    var audioFile: AVAudioFile?

    init(id: UUID = UUID(), name: String, colorIndex: Int, filePath: String? = nil, duration: Double = 0) {
        self.id = id
        self.name = name
        self.colorIndex = colorIndex
        self.filePath = filePath
        self.duration = duration
        if let filePath, let file = try? AVAudioFile(forReading: URL(fileURLWithPath: filePath)) {
            audioFile = file
            self.duration = Double(file.length) / file.fileFormat.sampleRate
            self.name = URL(fileURLWithPath: filePath).deletingPathExtension().lastPathComponent
        }
    }
}

private struct TrackRecord: Codable {
    var id: UUID
    var name: String
    var colorIndex: Int
    var filePath: String?
    var duration: Double
    var volume: Float
    var pan: Float
    var muted: Bool
    var effects: [EffectInstance]
}

private struct SessionDocument: Codable {
    var title: String
    var tempo: Int
    var tracks: [TrackRecord]
}

private final class AudioStudio {
    let engine = AVAudioEngine()
    var tracks: [AudioTrack] = []
    var selectedTrackID: UUID?
    var title = "Untitled Session"
    var tempo = 120
    var playhead = 0.0
    var isPlaying = false
    var status = "Ready"
    var onChange: (() -> Void)?
    private var effectNodes: [UUID: [AVAudioUnit]] = [:]
    private var timer: Timer?
    private var startedAt: Date?
    private var startOffset = 0.0

    var selectedTrack: AudioTrack? { tracks.first { $0.id == selectedTrackID } }
    var duration: Double { max(30, tracks.map(\.duration).max() ?? 30) }

    func addTrack() {
        let track = AudioTrack(name: "Audio \(tracks.count + 1)", colorIndex: tracks.count % Theme.trackColors.count)
        tracks.append(track)
        selectedTrackID = track.id
        attach(track)
        status = "Track added"
        onChange?()
    }

    func importAudio() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio, .movie]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.prompt = "Import"
        guard panel.runModal() == .OK else { return }
        var imported = 0
        for url in panel.urls {
            do {
                let file = try AVAudioFile(forReading: url)
                let track = AudioTrack(name: url.deletingPathExtension().lastPathComponent,
                                       colorIndex: tracks.count % Theme.trackColors.count,
                                       filePath: url.path,
                                       duration: Double(file.length) / file.fileFormat.sampleRate)
                track.audioFile = file
                tracks.append(track)
                selectedTrackID = track.id
                attach(track)
                imported += 1
            } catch {
                status = "Could not import \(url.lastPathComponent): \(error.localizedDescription)"
            }
        }
        if imported > 0 { status = "Imported \(imported) audio file\(imported == 1 ? "" : "s")" }
        onChange?()
    }

    private func attach(_ track: AudioTrack) {
        engine.attach(track.player)
        engine.attach(track.mixer)
        track.mixer.outputVolume = track.volume
        track.mixer.pan = track.pan
        rebuildEffects(track)
        if !engine.isRunning {
            do { try engine.start() }
            catch { status = "Audio engine error: \(error.localizedDescription)" }
        }
    }

    private func rebuildEffects(_ track: AudioTrack) {
        engine.disconnectNodeOutput(track.player)
        effectNodes[track.id]?.forEach {
            engine.disconnectNodeOutput($0)
            engine.detach($0)
        }
        let units = track.effects.map { $0.kind.makeAudioUnit() }
        units.forEach(engine.attach)
        effectNodes[track.id] = units
        var source: AVAudioNode = track.player
        for (index, unit) in units.enumerated() {
            if let effect = unit as? AVAudioUnitEffect {
                effect.bypass = !track.effects[index].enabled
            } else if let pitch = unit as? AVAudioUnitTimePitch, !track.effects[index].enabled {
                pitch.pitch = 0
            }
            engine.connect(source, to: unit, format: nil)
            source = unit
        }
        engine.connect(source, to: track.mixer, format: nil)
        engine.connect(track.mixer, to: engine.mainMixerNode, format: nil)
    }

    func addEffect(_ kind: EffectKind, to track: AudioTrack) {
        guard !track.effects.contains(where: { $0.kind == kind }) else {
            status = "\(kind.rawValue) is already on this track"
            onChange?()
            return
        }
        track.effects.append(EffectInstance(kind: kind))
        rebuildEffects(track)
        status = "\(kind.rawValue) added to \(track.name)"
        onChange?()
    }

    func toggleEffect(_ effect: EffectInstance, track: AudioTrack) {
        guard let index = track.effects.firstIndex(where: { $0.id == effect.id }) else { return }
        track.effects[index].enabled.toggle()
        let unit = effectNodes[track.id]?[index]
        if let effect = unit as? AVAudioUnitEffect {
            effect.bypass = !track.effects[index].enabled
        } else if let pitch = unit as? AVAudioUnitTimePitch {
            pitch.pitch = track.effects[index].enabled ? 2 : 0
        }
        onChange?()
    }

    func removeEffect(_ effect: EffectInstance, track: AudioTrack) {
        track.effects.removeAll { $0.id == effect.id }
        rebuildEffects(track)
        onChange?()
    }

    func setMix(_ track: AudioTrack) {
        let hasSolo = tracks.contains(where: \.solo)
        track.mixer.outputVolume = (track.muted || (hasSolo && !track.solo)) ? 0 : track.volume
        track.mixer.pan = track.pan
    }

    func setMuted(_ track: AudioTrack) {
        track.muted.toggle()
        updateAllMixes()
        onChange?()
    }

    func setSolo(_ track: AudioTrack) {
        track.solo.toggle()
        updateAllMixes()
        onChange?()
    }

    private func updateAllMixes() { tracks.forEach(setMix) }

    func play() {
        guard !tracks.isEmpty else { status = "Add a track or import audio to begin"; onChange?(); return }
        do {
            if !engine.isRunning { try engine.start() }
            for track in tracks {
                guard let file = track.audioFile else { continue }
                track.player.stop()
                let startFrame = AVAudioFramePosition(playhead * file.fileFormat.sampleRate)
                guard startFrame < file.length else { continue }
                let count = AVAudioFrameCount(min(file.length - startFrame, AVAudioFramePosition(UInt32.max)))
                track.player.scheduleSegment(file, startingFrame: startFrame, frameCount: count, at: nil)
                setMix(track)
                track.player.play()
            }
            startedAt = Date()
            startOffset = playhead
            isPlaying = true
            status = "Playing"
            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: 0.04, repeats: true) { [weak self] _ in
                guard let self, let startedAt = self.startedAt else { return }
                self.playhead = self.startOffset + Date().timeIntervalSince(startedAt)
                if self.playhead >= self.duration { self.stop() } else { self.onChange?() }
            }
            onChange?()
        } catch {
            status = "Playback error: \(error.localizedDescription)"
            onChange?()
        }
    }

    func pause() {
        tracks.forEach { $0.player.pause() }
        timer?.invalidate()
        timer = nil
        isPlaying = false
        status = "Paused"
        onChange?()
    }

    func stop() {
        tracks.forEach { $0.player.stop() }
        timer?.invalidate()
        timer = nil
        isPlaying = false
        playhead = 0
        status = "Stopped"
        onChange?()
    }

    func save() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [sessionDocumentType]
        panel.nameFieldStringValue = "\(title).sonora"
        panel.prompt = "Save Session"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let records = tracks.map {
            TrackRecord(id: $0.id, name: $0.name, colorIndex: $0.colorIndex, filePath: $0.filePath,
                        duration: $0.duration, volume: $0.volume, pan: $0.pan,
                        muted: $0.muted, effects: $0.effects)
        }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(SessionDocument(title: title, tempo: tempo, tracks: records)).write(to: url, options: .atomic)
            status = "Session saved"
        } catch { status = "Save failed: \(error.localizedDescription)" }
        onChange?()
    }

    func open() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [sessionDocumentType]
        panel.prompt = "Open Session"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let document = try JSONDecoder().decode(SessionDocument.self, from: Data(contentsOf: url))
            stop()
            tracks.forEach(detach)
            tracks = []
            title = document.title
            tempo = document.tempo
            for record in document.tracks {
                let track = AudioTrack(id: record.id, name: record.name, colorIndex: record.colorIndex,
                                       filePath: record.filePath, duration: record.duration)
                track.volume = record.volume
                track.pan = record.pan
                track.muted = record.muted
                track.effects = record.effects
                tracks.append(track)
                attach(track)
            }
            selectedTrackID = tracks.first?.id
            status = "Session opened"
        } catch { status = "Could not open session: \(error.localizedDescription)" }
        onChange?()
    }

    func newSession() {
        stop()
        tracks.forEach(detach)
        tracks = []
        selectedTrackID = nil
        title = "Untitled Session"
        tempo = 120
        status = "New session"
        onChange?()
    }

    private func detach(_ track: AudioTrack) {
        track.player.stop()
        engine.detach(track.player)
        engine.detach(track.mixer)
        effectNodes[track.id]?.forEach(engine.detach)
        effectNodes[track.id] = nil
    }
}

private final class ActionButton: NSButton {
    var handler: (() -> Void)?
    convenience init(_ title: String, symbol: String? = nil, handler: @escaping () -> Void) {
        self.init(title: title, target: nil, action: nil)
        self.handler = handler
        target = self
        action = #selector(invoke)
        isBordered = false
        bezelStyle = .rounded
        focusRingType = .none
        font = .systemFont(ofSize: 10, weight: .semibold)
        contentTintColor = .white
        if let symbol { image = NSImage(systemSymbolName: symbol, accessibilityDescription: title); imagePosition = .imageLeading }
    }
    @objc private func invoke() { handler?() }
}

private final class ValueSlider: NSSlider {
    var handler: ((Double) -> Void)?
    convenience init(min: Double, max: Double, value: Double, handler: @escaping (Double) -> Void) {
        self.init(value: value, minValue: min, maxValue: max, target: nil, action: nil)
        self.handler = handler
        target = self
        action = #selector(changed)
        isContinuous = true
        controlSize = .small
    }
    @objc private func changed() { handler?(doubleValue) }
}

@main
private enum SonoraMain {
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) {
            application.run()
        }
    }
}

private final class AppDelegate: NSObject, NSApplicationDelegate {
    private let studio = AudioStudio()
    private var window: NSWindow!
    private var trackStack: NSStackView!
    private var inspectorStack: NSStackView!
    private var timeline: TimelineView!
    private var ruler: RulerView!
    private var statusLabel: NSTextField!
    private var titleField: NSTextField!
    private var tempoField: NSTextField!
    private var transportButton: ActionButton!
    private var engineIndicator: NSView!

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildWindow()
        buildMenu()
        studio.onChange = { [weak self] in self?.refresh() }
        refresh()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    private func buildWindow() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1440, height: 900),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        window.title = "Sonora"
        window.titlebarAppearsTransparent = true
        window.backgroundColor = Theme.background
        window.minSize = NSSize(width: 1120, height: 700)
        window.center()

        let root = NSView()
        root.wantsLayer = true
        root.layer?.backgroundColor = Theme.background.cgColor
        window.contentView = root
        let titleBar = makeTitleBar()
        let transport = makeTransport()
        let content = makeContent()
        let status = makeStatusBar()
        [titleBar, transport, content, status].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview($0)
        }
        NSLayoutConstraint.activate([
            titleBar.topAnchor.constraint(equalTo: root.topAnchor), titleBar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            titleBar.trailingAnchor.constraint(equalTo: root.trailingAnchor), titleBar.heightAnchor.constraint(equalToConstant: 55),
            transport.topAnchor.constraint(equalTo: titleBar.bottomAnchor), transport.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            transport.trailingAnchor.constraint(equalTo: root.trailingAnchor), transport.heightAnchor.constraint(equalToConstant: 64),
            content.topAnchor.constraint(equalTo: transport.bottomAnchor), content.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: root.trailingAnchor), content.bottomAnchor.constraint(equalTo: status.topAnchor),
            status.leadingAnchor.constraint(equalTo: root.leadingAnchor), status.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            status.bottomAnchor.constraint(equalTo: root.bottomAnchor), status.heightAnchor.constraint(equalToConstant: 26)
        ])
    }

    private func makeTitleBar() -> NSView {
        let bar = NSView()
        bar.wantsLayer = true
        bar.layer?.backgroundColor = Theme.panel.cgColor
        let brand = label("◈  SONORA", size: 12, weight: .black, color: Theme.accent)
        brand.layer?.setValue(2.0, forKey: "kern")
        titleField = NSTextField(string: studio.title)
        titleField.isBordered = false
        titleField.drawsBackground = false
        titleField.font = .systemFont(ofSize: 13, weight: .medium)
        titleField.textColor = .white
        titleField.target = self
        titleField.action = #selector(titleChanged)
        let open = styledButton("Open", symbol: "folder", color: Theme.muted) { [weak self] in self?.studio.open() }
        let save = styledButton("Save", symbol: "square.and.arrow.down", color: Theme.muted) { [weak self] in self?.studio.save() }
        let importButton = styledButton("Import Audio", symbol: "plus", color: .white, background: Theme.accent) { [weak self] in self?.studio.importAudio() }
        let stack = horizontal([brand, separatorView(), titleField, flexibleSpace(), open, save, importButton], spacing: 13)
        bar.addSubview(stack)
        pin(stack, to: bar, inset: NSEdgeInsets(top: 0, left: 22, bottom: 0, right: 22))
        return bar
    }

    private func makeTransport() -> NSView {
        let bar = NSView()
        let back = iconButton("backward.end.fill") { [weak self] in self?.studio.stop() }
        transportButton = styledButton("Play", symbol: "play.fill", color: .white, background: Theme.accent) { [weak self] in
            guard let self else { return }
            self.studio.isPlaying ? self.studio.pause() : self.studio.play()
        }
        let stop = iconButton("stop.fill") { [weak self] in self?.studio.stop() }
        tempoField = NSTextField(string: "120")
        tempoField.isBordered = false
        tempoField.drawsBackground = false
        tempoField.textColor = .white
        tempoField.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        tempoField.alignment = .center
        tempoField.target = self
        tempoField.action = #selector(tempoChanged)
        let tempoBox = horizontal([label("♩", size: 13, weight: .regular, color: Theme.muted), tempoField, label("BPM", size: 8, weight: .bold, color: Theme.muted)], spacing: 7)
        tempoBox.wantsLayer = true
        tempoBox.layer?.backgroundColor = Theme.raised.cgColor
        tempoBox.layer?.cornerRadius = 6
        tempoField.widthAnchor.constraint(equalToConstant: 38).isActive = true
        tempoBox.heightAnchor.constraint(equalToConstant: 32).isActive = true
        let time = label("00:00.00", size: 17, weight: .medium, color: Theme.mint)
        time.font = .monospacedDigitSystemFont(ofSize: 17, weight: .medium)
        time.identifier = NSUserInterfaceItemIdentifier("playheadTime")
        engineIndicator = NSView()
        engineIndicator.wantsLayer = true
        engineIndicator.layer?.backgroundColor = Theme.muted.cgColor
        engineIndicator.layer?.cornerRadius = 3.5
        engineIndicator.widthAnchor.constraint(equalToConstant: 7).isActive = true
        engineIndicator.heightAnchor.constraint(equalToConstant: 7).isActive = true
        let active = label("AUDIO ENGINE READY", size: 8, weight: .bold, color: Theme.muted)
        active.identifier = NSUserInterfaceItemIdentifier("engineStatus")
        let spacer = flexibleSpace()
        let rate = label("44.1 kHz", size: 9, weight: .medium, color: Theme.muted)
        let stack = horizontal([back, transportButton, stop, separatorView(), tempoBox, separatorView(), time, spacer, rate, engineIndicator, active], spacing: 12)
        bar.addSubview(stack)
        pin(stack, to: bar, inset: NSEdgeInsets(top: 0, left: 22, bottom: 0, right: 22))
        bar.layer?.backgroundColor = Theme.background.cgColor
        return bar
    }

    private func makeContent() -> NSView {
        let content = NSView()
        let tracksPanel = NSView()
        tracksPanel.wantsLayer = true
        tracksPanel.layer?.backgroundColor = Theme.panel.withAlphaComponent(0.65).cgColor
        let tracksHeader = sectionHeader("TRACKS", button: "+") { [weak self] in self?.studio.addTrack() }
        trackStack = NSStackView()
        trackStack.orientation = .vertical
        trackStack.alignment = .leading
        trackStack.spacing = 7
        trackStack.edgeInsets = NSEdgeInsets(top: 9, left: 9, bottom: 9, right: 9)
        let trackScroll = NSScrollView()
        trackScroll.drawsBackground = false
        trackScroll.hasVerticalScroller = true
        trackScroll.documentView = trackStack
        [tracksHeader, trackScroll].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; tracksPanel.addSubview($0) }
        NSLayoutConstraint.activate([
            tracksHeader.topAnchor.constraint(equalTo: tracksPanel.topAnchor), tracksHeader.leadingAnchor.constraint(equalTo: tracksPanel.leadingAnchor),
            tracksHeader.trailingAnchor.constraint(equalTo: tracksPanel.trailingAnchor), tracksHeader.heightAnchor.constraint(equalToConstant: 42),
            trackScroll.topAnchor.constraint(equalTo: tracksHeader.bottomAnchor), trackScroll.leadingAnchor.constraint(equalTo: tracksPanel.leadingAnchor),
            trackScroll.trailingAnchor.constraint(equalTo: tracksPanel.trailingAnchor), trackScroll.bottomAnchor.constraint(equalTo: tracksPanel.bottomAnchor)
        ])
        let center = NSView()
        ruler = RulerView(frame: .zero)
        timeline = TimelineView(frame: .zero)
        timeline.studio = studio
        timeline.onSelect = { [weak self] id in self?.studio.selectedTrackID = id; self?.refresh() }
        let timelineScroll = NSScrollView()
        timelineScroll.drawsBackground = false
        timelineScroll.hasHorizontalScroller = true
        timelineScroll.hasVerticalScroller = true
        timelineScroll.documentView = timeline
        [ruler, timelineScroll].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; center.addSubview($0) }
        NSLayoutConstraint.activate([
            ruler.topAnchor.constraint(equalTo: center.topAnchor), ruler.leadingAnchor.constraint(equalTo: center.leadingAnchor),
            ruler.trailingAnchor.constraint(equalTo: center.trailingAnchor), ruler.heightAnchor.constraint(equalToConstant: 38),
            timelineScroll.topAnchor.constraint(equalTo: ruler.bottomAnchor), timelineScroll.leadingAnchor.constraint(equalTo: center.leadingAnchor),
            timelineScroll.trailingAnchor.constraint(equalTo: center.trailingAnchor), timelineScroll.bottomAnchor.constraint(equalTo: center.bottomAnchor)
        ])
        let inspector = NSView()
        inspector.wantsLayer = true
        inspector.layer?.backgroundColor = Theme.panel.withAlphaComponent(0.65).cgColor
        let inspectorHeader = sectionHeader("CHANNEL", button: "+") { [weak self] in self?.showEffectMenu() }
        inspectorStack = NSStackView()
        inspectorStack.orientation = .vertical
        inspectorStack.alignment = .leading
        inspectorStack.spacing = 12
        inspectorStack.edgeInsets = NSEdgeInsets(top: 14, left: 13, bottom: 14, right: 13)
        let inspectorScroll = NSScrollView()
        inspectorScroll.drawsBackground = false
        inspectorScroll.hasVerticalScroller = true
        inspectorScroll.documentView = inspectorStack
        [inspectorHeader, inspectorScroll].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; inspector.addSubview($0) }
        NSLayoutConstraint.activate([
            inspectorHeader.topAnchor.constraint(equalTo: inspector.topAnchor), inspectorHeader.leadingAnchor.constraint(equalTo: inspector.leadingAnchor),
            inspectorHeader.trailingAnchor.constraint(equalTo: inspector.trailingAnchor), inspectorHeader.heightAnchor.constraint(equalToConstant: 42),
            inspectorScroll.topAnchor.constraint(equalTo: inspectorHeader.bottomAnchor), inspectorScroll.leadingAnchor.constraint(equalTo: inspector.leadingAnchor),
            inspectorScroll.trailingAnchor.constraint(equalTo: inspector.trailingAnchor), inspectorScroll.bottomAnchor.constraint(equalTo: inspector.bottomAnchor)
        ])
        let split = NSStackView(views: [tracksPanel, center, inspector])
        split.orientation = .horizontal
        split.alignment = .top
        split.spacing = 1
        split.translatesAutoresizingMaskIntoConstraints = false
        tracksPanel.widthAnchor.constraint(equalToConstant: 220).isActive = true
        inspector.widthAnchor.constraint(equalToConstant: 240).isActive = true
        split.setHuggingPriority(.defaultHigh, for: .horizontal)
        content.addSubview(split)
        pin(split, to: content, inset: NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0))
        return content
    }

    private func makeStatusBar() -> NSView {
        let bar = NSView()
        bar.wantsLayer = true
        bar.layer?.backgroundColor = Theme.panel.cgColor
        let dot = NSView()
        dot.wantsLayer = true
        dot.layer?.backgroundColor = Theme.mint.cgColor
        dot.layer?.cornerRadius = 3
        dot.widthAnchor.constraint(equalToConstant: 6).isActive = true
        dot.heightAnchor.constraint(equalToConstant: 6).isActive = true
        statusLabel = label("Ready", size: 9, weight: .medium, color: Theme.muted)
        let count = label("0 TRACKS", size: 8, weight: .bold, color: Theme.muted)
        count.identifier = NSUserInterfaceItemIdentifier("trackCount")
        let stack = horizontal([dot, statusLabel, flexibleSpace(), count], spacing: 7)
        bar.addSubview(stack)
        pin(stack, to: bar, inset: NSEdgeInsets(top: 0, left: 15, bottom: 0, right: 15))
        return bar
    }

    private func buildMenu() {
        let main = NSMenu()
        let app = NSMenuItem()
        main.addItem(app)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Sonora", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        app.submenu = appMenu
        let file = NSMenuItem()
        main.addItem(file)
        let fileMenu = NSMenu(title: "File")
        let new = fileMenu.addItem(withTitle: "New Session", action: #selector(newSession), keyEquivalent: "n")
        new.target = self
        let open = fileMenu.addItem(withTitle: "Open Session…", action: #selector(openSession), keyEquivalent: "o")
        open.target = self
        let save = fileMenu.addItem(withTitle: "Save Session…", action: #selector(saveSession), keyEquivalent: "s")
        save.target = self
        let importItem = fileMenu.addItem(withTitle: "Import Audio…", action: #selector(importAudio), keyEquivalent: "i")
        importItem.target = self
        file.submenu = fileMenu
        NSApp.mainMenu = main
    }

    private func refresh() {
        titleField?.stringValue = studio.title
        tempoField?.stringValue = "\(studio.tempo)"
        statusLabel?.stringValue = studio.status
        if let count = window?.contentView?.find(identifier: NSUserInterfaceItemIdentifier("trackCount")) {
            (count as? NSTextField)?.stringValue = "\(studio.tracks.count) TRACK\(studio.tracks.count == 1 ? "" : "S")"
        }
        if let time = window?.contentView?.find(identifier: NSUserInterfaceItemIdentifier("playheadTime")) as? NSTextField {
            time.stringValue = formatTime(studio.playhead)
        }
        if let state = window?.contentView?.find(identifier: NSUserInterfaceItemIdentifier("engineStatus")) as? NSTextField {
            state.stringValue = studio.isPlaying ? "AUDIO ENGINE ACTIVE" : "AUDIO ENGINE READY"
        }
        engineIndicator?.layer?.backgroundColor = (studio.isPlaying ? Theme.mint : Theme.muted).cgColor
        transportButton?.title = studio.isPlaying ? "Pause" : "Play"
        transportButton?.image = NSImage(systemSymbolName: studio.isPlaying ? "pause.fill" : "play.fill", accessibilityDescription: nil)
        rebuildTrackRows()
        rebuildInspector()
        timeline?.setFrameSize(NSSize(width: max(750, studio.duration * 42), height: max(300, CGFloat(studio.tracks.count) * 76)))
        timeline?.needsDisplay = true
        ruler?.needsDisplay = true
    }

    private func rebuildTrackRows() {
        guard trackStack != nil else { return }
        trackStack.arrangedSubviews.forEach { trackStack.removeArrangedSubview($0); $0.removeFromSuperview() }
        if studio.tracks.isEmpty {
            let empty = vertical([
                label("Your session starts here", size: 10, weight: .medium, color: Theme.muted),
                styledButton("Import audio", symbol: "plus", color: .white, background: Theme.accent) { [weak self] in self?.studio.importAudio() }
            ], spacing: 10)
            trackStack.addArrangedSubview(empty)
        } else {
            for (index, track) in studio.tracks.enumerated() {
                let row = makeTrackCard(track, index: index)
                trackStack.addArrangedSubview(row)
                row.widthAnchor.constraint(equalTo: trackStack.widthAnchor, constant: -18).isActive = true
            }
        }
        trackStack.setFrameSize(NSSize(width: 202, height: max(60, CGFloat(studio.tracks.count) * 73 + 20)))
    }

    private func makeTrackCard(_ track: AudioTrack, index: Int) -> NSView {
        let view = ClosureClickView()
        view.handler = { [weak self] in self?.studio.selectedTrackID = track.id; self?.refresh() }
        view.wantsLayer = true
        let selected = studio.selectedTrackID == track.id
        let color = Theme.trackColors[track.colorIndex % Theme.trackColors.count]
        view.layer?.backgroundColor = (selected ? color.withAlphaComponent(0.12) : Theme.raised.withAlphaComponent(0.7)).cgColor
        view.layer?.cornerRadius = 8
        view.layer?.borderWidth = selected ? 1 : 0
        view.layer?.borderColor = color.withAlphaComponent(0.4).cgColor
        let strip = NSView()
        strip.wantsLayer = true
        strip.layer?.backgroundColor = color.cgColor
        strip.layer?.cornerRadius = 2
        strip.widthAnchor.constraint(equalToConstant: 3).isActive = true
        let name = label(track.name, size: 10, weight: .semibold, color: .white)
        name.lineBreakMode = .byTruncatingTail
        let meta = label(String(format: "%02d  ·  AUDIO", index + 1), size: 7, weight: .bold, color: Theme.muted)
        let info = vertical([name, meta], spacing: 3)
        let fileIcon = track.filePath == nil ? NSView() : imageView("waveform", color: color)
        fileIcon.widthAnchor.constraint(equalToConstant: 14).isActive = true
        let top = horizontal([strip, info, flexibleSpace(), fileIcon], spacing: 8)
        let mute = miniButton("M", active: track.muted, color: NSColor.orange) { [weak self] in self?.studio.setMuted(track) }
        let solo = miniButton("S", active: track.solo, color: Theme.mint) { [weak self] in self?.studio.setSolo(track) }
        let db = label(String(format: "%.0f dB", 20 * log10(max(track.volume, 0.001))), size: 7, weight: .medium, color: Theme.muted)
        let bottom = horizontal([mute, solo, flexibleSpace(), db], spacing: 5)
        let inner = vertical([top, bottom], spacing: 9)
        view.addSubview(inner)
        pin(inner, to: view, inset: NSEdgeInsets(top: 9, left: 9, bottom: 9, right: 9))
        view.heightAnchor.constraint(equalToConstant: 66).isActive = true
        return view
    }

    private func rebuildInspector() {
        guard inspectorStack != nil else { return }
        inspectorStack.arrangedSubviews.forEach { inspectorStack.removeArrangedSubview($0); $0.removeFromSuperview() }
        guard let track = studio.selectedTrack else {
            inspectorStack.addArrangedSubview(label("Select a track", size: 10, weight: .medium, color: Theme.muted))
            return
        }
        let color = Theme.trackColors[track.colorIndex % Theme.trackColors.count]
        let title = label(track.name, size: 14, weight: .semibold, color: .white)
        title.lineBreakMode = .byTruncatingTail
        let sub = label(track.filePath == nil ? "EMPTY AUDIO TRACK" : "STEREO AUDIO", size: 8, weight: .bold, color: Theme.muted)
        inspectorStack.addArrangedSubview(vertical([title, sub], spacing: 4))
        let mix = NSView()
        mix.wantsLayer = true
        mix.layer?.backgroundColor = Theme.raised.withAlphaComponent(0.75).cgColor
        mix.layer?.cornerRadius = 9
        let volumeLabel = label("LEVEL", size: 8, weight: .bold, color: Theme.muted)
        let volumeValue = label("\(Int(track.volume * 100))%", size: 8, weight: .medium, color: .white)
        let volume = ValueSlider(min: 0, max: 1.25, value: Double(track.volume)) { [weak self, weak track] value in
            guard let self, let track else { return }
            track.volume = Float(value)
            self.studio.setMix(track)
            volumeValue.stringValue = "\(Int(track.volume * 100))%"
        }
        volumeValue.alignment = .right
        let panLabel = label("PAN", size: 8, weight: .bold, color: Theme.muted)
        let panValue = label(panText(track.pan), size: 8, weight: .medium, color: .white)
        let pan = ValueSlider(min: -1, max: 1, value: Double(track.pan)) { [weak self, weak track] value in
            guard let self, let track else { return }
            track.pan = Float(value)
            self.studio.setMix(track)
            panValue.stringValue = panText(track.pan)
        }
        panValue.alignment = .right
        let mute = miniButton("M", active: track.muted, color: .orange) { [weak self] in self?.studio.setMuted(track) }
        let solo = miniButton("S", active: track.solo, color: Theme.mint) { [weak self] in self?.studio.setSolo(track) }
        let time = label(formatTime(track.duration), size: 8, weight: .medium, color: Theme.muted)
        let mixContent = vertical([
            horizontal([volumeLabel, flexibleSpace(), volumeValue], spacing: 5), volume,
            horizontal([panLabel, flexibleSpace(), panValue], spacing: 5), pan,
            horizontal([mute, solo, flexibleSpace(), time], spacing: 6)
        ], spacing: 6)
        mix.addSubview(mixContent)
        pin(mixContent, to: mix, inset: NSEdgeInsets(top: 11, left: 11, bottom: 11, right: 11))
        inspectorStack.addArrangedSubview(mix)
        mix.widthAnchor.constraint(equalTo: inspectorStack.widthAnchor, constant: -26).isActive = true
        let effectsHead = horizontal([label("EFFECTS", size: 9, weight: .bold, color: Theme.muted), flexibleSpace(), label("\(track.effects.count)", size: 9, weight: .medium, color: Theme.muted)], spacing: 5)
        inspectorStack.addArrangedSubview(effectsHead)
        for effect in track.effects {
            inspectorStack.addArrangedSubview(makeEffectRow(effect, track: track))
        }
        if track.effects.isEmpty {
            let empty = label("No effects added", size: 9, weight: .medium, color: Theme.muted)
            inspectorStack.addArrangedSubview(empty)
            let browse = styledButton("Browse effects", symbol: "plus", color: Theme.accent, background: Theme.accent.withAlphaComponent(0.14)) { [weak self] in self?.showEffectMenu() }
            inspectorStack.addArrangedSubview(browse)
            browse.widthAnchor.constraint(equalTo: inspectorStack.widthAnchor, constant: -26).isActive = true
        }
        inspectorStack.setFrameSize(NSSize(width: 214, height: max(150, CGFloat(track.effects.count) * 55 + 220)))
        _ = color
    }

    private func makeEffectRow(_ effect: EffectInstance, track: AudioTrack) -> NSView {
        let row = NSView()
        row.wantsLayer = true
        row.layer?.backgroundColor = Theme.raised.withAlphaComponent(0.8).cgColor
        row.layer?.cornerRadius = 8
        let icon = imageView(effect.kind.symbol, color: effect.enabled ? Theme.accent : Theme.muted)
        icon.widthAnchor.constraint(equalToConstant: 18).isActive = true
        let title = label(effect.kind.rawValue, size: 9, weight: .semibold, color: .white)
        let state = label(effect.enabled ? "INSERT · ACTIVE" : "BYPASSED", size: 7, weight: .bold, color: effect.enabled ? Theme.mint : Theme.muted)
        let captions = vertical([title, state], spacing: 3)
        let power = styledButton("", symbol: "power", color: effect.enabled ? Theme.mint : Theme.muted) { [weak self] in self?.studio.toggleEffect(effect, track: track) }
        let remove = styledButton("", symbol: "xmark", color: Theme.muted) { [weak self] in self?.studio.removeEffect(effect, track: track) }
        let content = horizontal([icon, captions, flexibleSpace(), power, remove], spacing: 7)
        row.addSubview(content)
        pin(content, to: row, inset: NSEdgeInsets(top: 9, left: 9, bottom: 9, right: 7))
        row.heightAnchor.constraint(equalToConstant: 45).isActive = true
        row.widthAnchor.constraint(equalTo: inspectorStack.widthAnchor, constant: -26).isActive = true
        return row
    }

    private func showEffectMenu() {
        guard let track = studio.selectedTrack else { studio.addTrack(); return }
        let menu = NSMenu()
        for kind in EffectKind.allCases {
            let item = NSMenuItem(title: kind.rawValue, action: #selector(addEffectFromMenu(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = kind.rawValue
            item.isEnabled = !track.effects.contains { $0.kind == kind }
            menu.addItem(item)
        }
        if let button = window.contentView?.find(identifier: NSUserInterfaceItemIdentifier("addEffectButton")) as? NSButton {
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height), in: button)
        } else {
            menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        }
    }

    @objc private func addEffectFromMenu(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String,
              let kind = EffectKind(rawValue: name), let track = studio.selectedTrack else { return }
        studio.addEffect(kind, to: track)
    }

    @objc private func titleChanged() { studio.title = titleField.stringValue }
    @objc private func tempoChanged() { studio.tempo = max(1, min(999, Int(tempoField.stringValue) ?? 120)); tempoField.stringValue = "\(studio.tempo)" }
    @objc private func newSession() { studio.newSession() }
    @objc private func openSession() { studio.open() }
    @objc private func saveSession() { studio.save() }
    @objc private func importAudio() { studio.importAudio() }

    private func sectionHeader(_ title: String, button: String, action: @escaping () -> Void) -> NSView {
        let label = self.label(title, size: 9, weight: .bold, color: Theme.muted)
        let add = ActionButton(button, handler: action)
        add.font = .systemFont(ofSize: 12, weight: .bold)
        add.contentTintColor = Theme.muted
        add.identifier = title == "CHANNEL" ? NSUserInterfaceItemIdentifier("addEffectButton") : nil
        let stack = horizontal([label, flexibleSpace(), add], spacing: 8)
        let container = NSView()
        container.addSubview(stack)
        pin(stack, to: container, inset: NSEdgeInsets(top: 0, left: 15, bottom: 0, right: 15))
        return container
    }

    private func styledButton(_ title: String, symbol: String? = nil, color: NSColor,
                              background: NSColor? = nil, action: @escaping () -> Void) -> ActionButton {
        let button = ActionButton(title, symbol: symbol, handler: action)
        button.contentTintColor = color
        button.font = .systemFont(ofSize: 9, weight: .semibold)
        if let background {
            button.wantsLayer = true
            button.layer?.backgroundColor = background.cgColor
            button.layer?.cornerRadius = 6
        }
        button.setContentHuggingPriority(.required, for: .horizontal)
        return button
    }

    private func iconButton(_ symbol: String, action: @escaping () -> Void) -> ActionButton {
        let button = ActionButton("", symbol: symbol, handler: action)
        button.contentTintColor = Theme.muted
        button.widthAnchor.constraint(equalToConstant: 28).isActive = true
        return button
    }

    private func miniButton(_ title: String, active: Bool, color: NSColor, action: @escaping () -> Void) -> ActionButton {
        let button = ActionButton(title, handler: action)
        button.font = .systemFont(ofSize: 8, weight: .black)
        button.contentTintColor = active ? Theme.background : Theme.muted
        button.wantsLayer = true
        button.layer?.backgroundColor = (active ? color : Theme.panel).cgColor
        button.layer?.cornerRadius = 4
        button.widthAnchor.constraint(equalToConstant: 19).isActive = true
        button.heightAnchor.constraint(equalToConstant: 17).isActive = true
        return button
    }

    private func label(_ text: String, size: CGFloat, weight: NSFont.Weight, color: NSColor) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = .systemFont(ofSize: size, weight: weight)
        field.textColor = color
        field.lineBreakMode = .byTruncatingTail
        return field
    }

    private func imageView(_ name: String, color: NSColor) -> NSImageView {
        let view = NSImageView()
        view.image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        view.contentTintColor = color
        view.imageScaling = .scaleProportionallyDown
        return view
    }

    private func horizontal(_ views: [NSView], spacing: CGFloat) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = spacing
        return stack
    }

    private func vertical(_ views: [NSView], spacing: CGFloat) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = spacing
        return stack
    }

    private func flexibleSpace() -> NSView {
        let view = NSView()
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return view
    }

    private func separatorView() -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = Theme.separator.cgColor
        view.widthAnchor.constraint(equalToConstant: 1).isActive = true
        view.heightAnchor.constraint(equalToConstant: 22).isActive = true
        return view
    }

    private func pin(_ child: NSView, to parent: NSView, inset: NSEdgeInsets) {
        child.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            child.topAnchor.constraint(equalTo: parent.topAnchor, constant: inset.top),
            child.leadingAnchor.constraint(equalTo: parent.leadingAnchor, constant: inset.left),
            child.trailingAnchor.constraint(equalTo: parent.trailingAnchor, constant: -inset.right),
            child.bottomAnchor.constraint(equalTo: parent.bottomAnchor, constant: -inset.bottom)
        ])
    }
}

private final class ClosureClickView: NSView {
    var handler: (() -> Void)?
    override func mouseDown(with event: NSEvent) { handler?() }
}

private final class TimelineView: NSView {
    weak var studio: AudioStudio?
    var onSelect: ((UUID) -> Void)?
    override var isFlipped: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area = trackingAreas.first { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeInKeyWindow], owner: self))
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let studio else { return }
        Theme.background.setFill()
        bounds.fill()
        let width = max(bounds.width, max(750, studio.duration * 42))
        for second in 0...Int(width / 210) {
            let x = CGFloat(second) * 210
            Theme.separator.setStroke()
            let grid = NSBezierPath()
            grid.move(to: NSPoint(x: x, y: 0))
            grid.line(to: NSPoint(x: x, y: bounds.height))
            grid.stroke()
        }
        if studio.tracks.isEmpty {
            drawEmptyState()
            return
        }
        for (index, track) in studio.tracks.enumerated() {
            let y = CGFloat(index) * 76
            if studio.selectedTrackID == track.id {
                NSColor.white.withAlphaComponent(0.025).setFill()
                NSRect(x: 0, y: y, width: width, height: 76).fill()
            }
            Theme.separator.setStroke()
            let line = NSBezierPath()
            line.move(to: NSPoint(x: 0, y: y + 75.5))
            line.line(to: NSPoint(x: width, y: y + 75.5))
            line.stroke()
            guard track.duration > 0 else { continue }
            let color = Theme.trackColors[track.colorIndex % Theme.trackColors.count]
            let clipWidth = max(180, CGFloat(track.duration * 42) - 4)
            let clip = NSRect(x: 4, y: y + 10, width: clipWidth, height: 55)
            color.withAlphaComponent(0.17).setFill()
            NSBezierPath(roundedRect: clip, xRadius: 6, yRadius: 6).fill()
            color.withAlphaComponent(0.45).setStroke()
            NSBezierPath(roundedRect: clip, xRadius: 6, yRadius: 6).stroke()
            let name = track.name as NSString
            name.draw(at: NSPoint(x: clip.minX + 8, y: clip.minY + 6), withAttributes: [
                .font: NSFont.systemFont(ofSize: 8, weight: .semibold), .foregroundColor: NSColor.white
            ])
            let count = max(1, Int(clip.width / 3))
            let wave = NSBezierPath()
            wave.lineWidth = 1
            color.withAlphaComponent(0.9).setStroke()
            for i in 0..<count {
                let x = clip.minX + 8 + CGFloat(i) / CGFloat(count) * (clip.width - 16)
                let phase = Double(i + abs(track.name.hashValue % 101)) * 0.19
                let amplitude = CGFloat(0.16 + 0.68 * abs(sin(phase) * cos(phase * 0.43))) * 28
                wave.move(to: NSPoint(x: x, y: clip.midY - amplitude / 2))
                wave.line(to: NSPoint(x: x, y: clip.midY + amplitude / 2))
            }
            wave.stroke()
        }
        let playX = CGFloat(studio.playhead * 42)
        NSColor(calibratedRed: 1, green: 0.34, blue: 0.43, alpha: 1).setStroke()
        let playhead = NSBezierPath()
        playhead.lineWidth = 1
        playhead.move(to: NSPoint(x: playX, y: 0))
        playhead.line(to: NSPoint(x: playX, y: bounds.height))
        playhead.stroke()
    }

    private func drawEmptyState() {
        let text = "Import audio files to start building your arrangement."
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: Theme.muted
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        (text as NSString).draw(at: NSPoint(x: max(20, (bounds.width - size.width) / 2), y: 135), withAttributes: attributes)
    }

    override func mouseDown(with event: NSEvent) {
        guard let studio else { return }
        let point = convert(event.locationInWindow, from: nil)
        let row = Int(point.y / 76)
        if studio.tracks.indices.contains(row) { onSelect?(studio.tracks[row].id) }
    }
}

private final class RulerView: NSView {
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        Theme.panel.withAlphaComponent(0.65).setFill()
        bounds.fill()
        for second in 0...12 {
            let text = "\(second * 5)s" as NSString
            text.draw(at: NSPoint(x: 14 + second * 210, y: 8), withAttributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium),
                .foregroundColor: Theme.muted
            ])
            Theme.separator.setStroke()
            let tick = NSBezierPath()
            tick.move(to: NSPoint(x: 14 + second * 210, y: 25))
            tick.line(to: NSPoint(x: 14 + second * 210, y: 38))
            tick.stroke()
        }
        Theme.separator.setStroke()
        let border = NSBezierPath()
        border.move(to: NSPoint(x: 0, y: bounds.height - 0.5))
        border.line(to: NSPoint(x: bounds.width, y: bounds.height - 0.5))
        border.stroke()
    }
}

private extension NSView {
    func find(identifier: NSUserInterfaceItemIdentifier) -> NSView? {
        if self.identifier == identifier { return self }
        for view in subviews {
            if let found = view.find(identifier: identifier) { return found }
        }
        return nil
    }
}

private func formatTime(_ seconds: Double) -> String {
    let safe = max(0, seconds)
    let whole = Int(safe)
    return String(format: "%02d:%02d.%02d", whole / 60, whole % 60, Int((safe - floor(safe)) * 100))
}

private func panText(_ value: Float) -> String {
    if abs(value) < 0.01 { return "C" }
    return "\(Int(abs(value) * 100))% \(value < 0 ? "L" : "R")"
}
