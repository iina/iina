// SPDX-License-Identifier: GPL-3.0-only
// Experimental iPadOS contribution added 2026-10-10.

import SwiftUI
import UIKit

struct SubtitleSettingsView: View {
    @ObservedObject var model: PlayerModel
    let openFile: (SubtitleTarget) -> Void
    let searchOnline: () -> Void
    private static let fonts = UIFont.familyNames.sorted()

    var body: some View {
        Form {
            Section("Subtitle tracks") {
                trackPicker(.primary, selection: model.subtitleID)
                trackPicker(.secondary, selection: model.secondarySubtitleID)
                Menu("Load External Subtitle…", systemImage: "plus") {
                    Button("Primary") { openFile(.primary) }
                    Button("Secondary") { openFile(.secondary) }
                }
                Button("Find Online Subtitles…", systemImage: "magnifyingglass", action: searchOnline)
            }.disabled(!model.hasMedia)
            Section("Synchronization") {
                delay("Primary delay", value: model.subtitleDelay, update: model.setSubtitleDelay)
                delay("Secondary delay", value: model.secondarySubtitleDelay, update: model.setSecondarySubtitleDelay)
                Button("Reset Both Delays") {
                    model.setSubtitleDelay(0); model.setSecondarySubtitleDelay(0)
                }
            }.disabled(!model.hasMedia)
            Section("Appearance") {
                Picker("Font", selection: style(\.font)) {
                    ForEach(Self.fonts, id: \.self) { Text($0).tag($0) }
                }
                valueSlider("Size", value: style(\.size), range: 16...100, suffix: "")
                ColorPicker("Text color", selection: color(\.color), supportsOpacity: true)
                ColorPicker("Outline color", selection: color(\.borderColor), supportsOpacity: true)
                valueSlider("Outline", value: style(\.borderSize), range: 0...8, suffix: "")
                valueSlider("Primary position", value: style(\.primaryPosition), range: 0...100, suffix: "%")
                valueSlider("Secondary position", value: style(\.secondaryPosition), range: 0...100, suffix: "%")
                Toggle("Override ASS styling", isOn: style(\.overrideASS))
                Text("Positions run from top (0%) to bottom (100%). Styling applies to both text tracks. Enable ASS overrides to change a styled subtitle's appearance; bitmap subtitles retain their original font and colors.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("Reset Appearance") {
                    var value = SubtitleStyle()
                    value.encoding = model.subtitleStyle.encoding
                    model.updateSubtitleStyle(value)
                }
            }
            Section("Text encoding") {
                Picker("Encoding", selection: style(\.encoding)) {
                    ForEach(SubtitleStyle.encodings, id: \.0) { Text($0.1).tag($0.0) }
                }
                Button("Reload External Subtitles", action: model.reloadExternalSubtitles)
                    .disabled(!model.tracks.contains { $0.kind == "sub" && !$0.externalPath.isEmpty })
                Text("Encoding affects newly loaded subtitle files. Reload external tracks after changing it.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }.scrollContentBackground(.hidden)
    }

    private func trackPicker(_ target: SubtitleTarget, selection: String) -> some View {
        Picker(target.rawValue, selection: Binding(get: { selection }, set: { model.selectSubtitle($0, target: target) })) {
            Text("None").tag("no")
            if target == .primary { Text("Automatic").tag("auto") }
            ForEach(model.tracks.filter { $0.kind == "sub" }) { track in Text(track.label).tag(String(track.id)) }
        }
    }

    private func style<Value>(_ key: WritableKeyPath<SubtitleStyle, Value>) -> Binding<Value> {
        Binding(get: { model.subtitleStyle[keyPath: key] }, set: {
            var value = model.subtitleStyle
            value[keyPath: key] = $0
            model.updateSubtitleStyle(value)
        })
    }

    private func color(_ key: WritableKeyPath<SubtitleStyle, String>) -> Binding<Color> {
        Binding(get: { Color(mpvColor: model.subtitleStyle[keyPath: key]) }, set: {
            var value = model.subtitleStyle
            value[keyPath: key] = $0.mpvColor
            model.updateSubtitleStyle(value)
        })
    }

    private func valueSlider(_ label: String, value: Binding<Double>, range: ClosedRange<Double>, suffix: String) -> some View {
        VStack(alignment: .leading) {
            HStack { Text(label); Spacer(); Text("\(Int(value.wrappedValue))\(suffix)").monospacedDigit().foregroundStyle(.secondary) }
            Slider(value: value, in: range, step: 1).accessibilityLabel(label)
        }
    }

    private func delay(_ label: String, value: Double, update: @escaping (Double) -> Void) -> some View {
        VStack(alignment: .leading) {
            HStack { Text(label); Spacer(); Text(String(format: "%+.1f s", value)).monospacedDigit().foregroundStyle(.secondary) }
            Slider(value: Binding(get: { value }, set: update), in: -10...10, step: 0.1).accessibilityLabel(label)
        }
    }
}

extension Color {
    init(mpvColor: String) {
        let value = UInt32(mpvColor.dropFirst(), radix: 16) ?? 0xFFFFFFFF
        self.init(.sRGB, red: Double((value >> 16) & 255) / 255,
                  green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255,
                  opacity: Double((value >> 24) & 255) / 255)
    }

    var mpvColor: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X%02X", Int((a * 255).rounded()), Int((r * 255).rounded()),
                      Int((g * 255).rounded()), Int((b * 255).rounded()))
    }
}
