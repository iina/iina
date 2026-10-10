// SPDX-License-Identifier: GPL-3.0-only
// Experimental iPadOS contribution added 2026-10-10.

import SwiftUI

struct VideoSettingsView: View {
    @ObservedObject var model: PlayerModel

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                card {
                    trackRow("None", selected: model.videoID == "no") { model.selectVideo("no") }
                    if model.videoTracks.isEmpty {
                        Text("No video tracks.").foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ForEach(model.videoTracks) { track in
                        trackRow(track.videoLabel, selected: model.videoID == String(track.id)) {
                            model.selectVideo(String(track.id))
                        }
                    }
                }
                .disabled(!model.hasMedia || model.loading)

                card {
                    title("Aspect Ratio", symbol: "rectangle.split.3x1")
                    ratioPicker(value: model.videoSettings.aspect, original: "Default") { value in
                        edit { $0.aspect = value }
                    }
                    title("Crop", symbol: "crop")
                    ratioPicker(value: model.videoSettings.crop, original: "None") { value in
                        edit { $0.crop = value }
                    }
                    title("Rotation", symbol: "rotate.right")
                    HStack(spacing: 4) {
                        ForEach([0, 90, 180, 270], id: \.self) { value in
                            choice("\(value)°", selected: model.videoSettings.rotation == value) {
                                edit { $0.rotation = value }
                            }
                        }
                    }
                }
                .disabled(model.videoTracks.isEmpty)

                card {
                    title("Speed", symbol: "forward")
                    PlaybackSpeedEditor(model: model)
                }
                .disabled(!model.hasMedia)

                card {
                    Toggle(isOn: Binding(get: { model.videoSettings.hardwareDecoding }, set: { value in
                        edit { $0.hardwareDecoding = value }
                    })) {
                        Label("Hardware Decoding", systemImage: "cpu").fontWeight(.semibold)
                    }
                    .accessibilityIdentifier("hardwareDecoding")
                    Text(decoderDescription).font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .disabled(model.videoTracks.isEmpty)

                card {
                    ForEach(VideoAdjustment.allCases, id: \.self) { adjustment in
                        HStack(spacing: 8) {
                            Text(adjustment.rawValue).font(.callout).frame(width: 86, alignment: .leading)
                            Slider(value: Binding(get: { model.videoSettings[adjustment] }, set: { value in
                                edit(debounce: true) { $0[adjustment] = value }
                            }), in: -100...100, step: 1)
                            .accessibilityLabel(adjustment.rawValue)
                            .accessibilityValue(model.videoSettings[adjustment].formatted())
                            Button {
                                edit { $0[adjustment] = 0 }
                            } label: {
                                Image(systemName: "arrow.counterclockwise").frame(width: 44, height: 44)
                            }
                            .accessibilityLabel("Reset \(adjustment.rawValue)")
                        }
                    }
                    Button("Reset All Video Settings") { model.updateVideoSettings(VideoSettings()) }
                        .font(.footnote).frame(maxWidth: .infinity, minHeight: 44)
                }
                .disabled(model.videoTracks.isEmpty)

                card {
                    title("Media Information", symbol: "info.circle")
                    info("Playback engine", model.backend?.rawValue ?? "—")
                    if let track = model.selectedVideoTrack {
                        info("Video codec", track.codec.isEmpty ? model.codec : track.codec)
                        info("Resolution", track.width > 0 ? "\(track.width)×\(track.height)" : "—")
                        info("Frame rate", track.fps > 0 ? "\(track.fps.formatted(.number.precision(.fractionLength(0...2)))) fps" : "—")
                        if track.bitrate > 0 {
                            info("Video bitrate", "\(Int(track.bitrate / 1000)) kb/s")
                        }
                    } else { info("Video codec", model.codec.isEmpty ? "—" : model.codec) }
                    info("Decoder", model.decoder.isEmpty ? "—" : model.decoder == "no" ? "Software" : model.decoder)
                    if model.outputVideoSize.width > 0 && model.outputVideoSize.height > 0 {
                        info("Filtered frame", "\(Int(model.outputVideoSize.width))×\(Int(model.outputVideoSize.height))")
                    }
                    if !model.routingReason.isEmpty {
                        Text(model.routingReason).font(.footnote).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                card { PlaybackDiagnosticsView(model: model) }
            }
            .padding(16)
        }
        .tint(.blue)
        .accessibilityIdentifier("videoSettingsPanel")
    }

    private var decoderDescription: String {
        if model.backend == .native { return "AVPlayer manages decoding. Turning this off selects mpv software decoding." }
        #if targetEnvironment(simulator)
        return "This simulator uses software decoding."
        #else
        return model.decoder.isEmpty ? "Automatic hardware decode with codec-dependent fallback." :
            "Active: \(model.decoder == "no" ? "Software" : model.decoder)"
        #endif
    }

    private func edit(debounce: Bool = false, _ change: (inout VideoSettings) -> Void) {
        var value = model.videoSettings
        change(&value)
        model.updateVideoSettings(value, debounce: debounce)
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10, content: content)
            .padding(14).frame(maxWidth: .infinity)
            .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 14))
            .overlay { RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.09), lineWidth: 0.5) }
    }

    private func title(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol).font(.callout.weight(.semibold))
            .foregroundStyle(.white.opacity(0.82)).padding(.top, 2)
    }

    private func trackRow(_ text: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 3).fill(selected ? Color.blue : .clear).frame(width: 4, height: 28)
                Text(text).font(.callout).multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func ratioPicker(value: VideoAspect, original: String, select: @escaping (VideoAspect) -> Void) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: true) {
                HStack(spacing: 4) {
                    ForEach(VideoAspect.allCases, id: \.self) { aspect in
                        choice(aspect == .original ? original : aspect.rawValue, selected: value == aspect) { select(aspect) }
                            .id(aspect)
                    }
                }
            }
            .onAppear { proxy.scrollTo(value, anchor: .center) }
            .onChange(of: value) { _, selection in proxy.scrollTo(selection, anchor: .center) }
        }
    }

    private func choice(_ text: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text).font(.system(size: 14, weight: .semibold)).padding(.horizontal, 10)
                .frame(minHeight: 44)
                .background(selected ? Color.blue : Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func info(_ name: String, _ value: String) -> some View {
        LabeledContent(name) { Text(value).multilineTextAlignment(.trailing) }
            .font(.caption).foregroundStyle(.secondary)
    }
}

/// Reused by the Video and Audio tabs so music has the same rate controls.
struct PlaybackSpeedEditor: View {
    @ObservedObject var model: PlayerModel
    @State private var number = "1"
    @State private var slider = 0.0
    @State private var dragging = false
    @FocusState private var editingNumber: Bool

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 4) {
                ForEach(PlaybackRates.quick, id: \.self) { rate in
                    Button { model.setSpeed(rate) } label: {
                        Text("\(rate.formatted())×").font(.system(size: 13, weight: .semibold))
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(abs(model.speed - rate) < 0.001 ? Color.blue : Color.white.opacity(0.06),
                                        in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Play at \(rate.formatted()) times speed")
                    .accessibilityIdentifier("speedPreset\(rate)")
                }
            }
            HStack(spacing: 8) {
                Slider(value: Binding(get: { dragging ? slider : log2(model.speed) }, set: { slider = $0 }),
                       in: -2...4) { active in
                    if active { slider = log2(model.speed); dragging = true }
                    else { model.setSpeed(pow(2, slider)); dragging = false }
                }
                .accessibilityLabel("Playback speed")
                .accessibilityValue("\((dragging ? pow(2, slider) : model.speed).formatted()) times")
                TextField("Rate", text: $number)
                    .keyboardType(.decimalPad).focused($editingNumber)
                    .textFieldStyle(.roundedBorder).frame(width: 54)
                    .accessibilityLabel("Numeric playback speed")
                    .onSubmit(applyNumber)
                Button(action: applyNumber) {
                    Image(systemName: "checkmark").frame(width: 44, height: 44)
                }.accessibilityLabel("Apply playback speed")
            }
            HStack {
                Text("0.25×"); Spacer(); Text("\((dragging ? pow(2, slider) : model.speed).formatted(.number.precision(.fractionLength(0...2))))×")
                Spacer(); Text("16×")
            }.font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
        .onAppear { number = model.speed.formatted() }
        .onChange(of: model.speed) { _, value in
            if !editingNumber { number = value.formatted() }
        }
    }

    private func applyNumber() {
        guard let value = Double(number.replacingOccurrences(of: ",", with: ".")) else {
            model.report("Enter a playback speed between 0.25 and 16."); return
        }
        model.setSpeed(value)
        if value.isFinite && PlaybackRates.range.contains(value) {
            number = value.formatted()
            editingNumber = false
        }
    }
}
