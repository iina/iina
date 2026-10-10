// SPDX-License-Identifier: GPL-3.0-only
// Experimental iPadOS contribution added 2026-10-10.

import SwiftUI

struct SubtitleSearchView: View {
    @ObservedObject var player: PlayerModel
    @Environment(\.dismiss) private var dismiss
    @State private var credentials = SubtitleCredentials()
    @State private var client: OpenSubtitlesClient?
    @State private var query = ""
    @State private var language = "en"
    @State private var target: SubtitleTarget = .primary
    @State private var results: [OnlineSubtitle] = []
    @State private var page = 0
    @State private var totalPages = 0
    @State private var busy = false
    @State private var error: String?
    @State private var showAccount = false
    @State private var task: Task<Void, Never>?
    @State private var mediaID: UUID?

    private static let languages = [
        ("", "All languages"), ("en", "English"), ("es", "Spanish"), ("fr", "French"),
        ("de", "German"), ("it", "Italian"), ("pt", "Portuguese"), ("pt-br", "Brazilian Portuguese"),
        ("zh-cn", "Simplified Chinese"), ("zh-tw", "Traditional Chinese"), ("ja", "Japanese"),
        ("ko", "Korean"), ("ru", "Russian"), ("ar", "Arabic"), ("hi", "Hindi")
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("OpenSubtitles.com") {
                    TextField("Movie or episode title", text: $query).onSubmit { search() }
                    Picker("Language", selection: $language) {
                        ForEach(Self.languages, id: \.0) { Text($0.1).tag($0.0) }
                    }
                    Picker("Load as", selection: $target) {
                        ForEach(SubtitleTarget.allCases) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented)
                    Button("Search", systemImage: "magnifyingglass") { search() }
                        .disabled(busy || query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if !credentials.canSearch {
                        Button("Set Up OpenSubtitles Account") { showAccount = true }
                    }
                }
                if busy { Section { HStack { ProgressView(); Text("Contacting OpenSubtitles…") } } }
                if let error { Section { Text(error).foregroundStyle(.red) } }
                Section("Results") {
                    if results.isEmpty, !busy, page > 0 { Text("No matching subtitles.").foregroundStyle(.secondary) }
                    ForEach(results) { result in
                        Button { download(result) } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(result.name).foregroundStyle(.primary)
                                Text("\(result.language) · \(result.downloads) downloads\(result.hearingImpaired ? " · Hearing impaired" : "")")
                                    .font(.caption).foregroundStyle(.secondary)
                            }.padding(.vertical, 4)
                        }.disabled(busy)
                    }
                    if page > 0, page < totalPages {
                        Button("Load More Results") { search(more: true) }.disabled(busy)
                    }
                }
                Section {
                    Text("Downloads use your OpenSubtitles allowance and are saved in IINA's Subtitles folder. Your search terms are sent when you tap Search.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Find Subtitles")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .primaryAction) { Button("Account") { showAccount = true }.disabled(busy) }
            }
            .sheet(isPresented: $showAccount) {
                SubtitleAccountView(credentials: credentials) { value in
                    credentials = value
                    client = OpenSubtitlesClient(credentials: value)
                    results = []; page = 0; totalPages = 0; error = nil
                }
            }
            .onAppear {
                mediaID = player.currentID
                query = player.currentURL?.deletingPathExtension().lastPathComponent ?? player.title
                do {
                    credentials = try SubtitleAccountStore.load()
                    client = OpenSubtitlesClient(credentials: credentials)
                } catch { self.error = error.localizedDescription }
            }
            .onDisappear { task?.cancel() }
            .onChange(of: player.currentID) { _, _ in
                task?.cancel(); busy = false
                error = "The current media changed. Close and reopen subtitle search for the new file."
            }
        }
    }

    private func search(more: Bool = false) {
        guard credentials.canSearch else { showAccount = true; return }
        guard let client else { error = SubtitleServiceError.setup.localizedDescription; return }
        task?.cancel()
        busy = true; error = nil
        let nextPage = more ? page + 1 : 1
        let query = query, language = language
        if !more { results = []; page = 0; totalPages = 0 }
        task = Task { @MainActor in
            defer { if !Task.isCancelled { busy = false } }
            do {
                let response = try await client.search(query: query, language: language, page: nextPage)
                try Task.checkCancellation()
                let existing = Set(results.map(\.id))
                results.append(contentsOf: response.results.filter { !existing.contains($0.id) })
                page = response.page; totalPages = response.totalPages
            } catch is CancellationError { /* A dismissed sheet or changed media cancels its request. */ }
            catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }

    private func download(_ subtitle: OnlineSubtitle) {
        guard player.currentID == mediaID else { error = "Reopen search for the current media."; return }
        guard credentials.canDownload else { showAccount = true; return }
        guard let client else { return }
        busy = true; error = nil
        let selectedTarget = target
        task = Task { @MainActor in
            defer { if !Task.isCancelled { busy = false } }
            do {
                let download = try await client.download(subtitle)
                try Task.checkCancellation()
                guard player.currentID == mediaID else { return }
                player.addSubtitle(download.url, target: selectedTarget)
                dismiss()
            } catch is CancellationError { /* Cancellation leaves an already saved download in Files. */ }
            catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }
}

private struct SubtitleAccountView: View {
    @State var credentials: SubtitleCredentials
    let saved: (SubtitleCredentials) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Application") {
                    SecureField("OpenSubtitles API key", text: $credentials.apiKey)
                    TextField("Registered app / User-Agent", text: $credentials.userAgent)
                    Link("Register an API application", destination: URL(string: "https://www.opensubtitles.com/en/consumers")!)
                    Text("Use the API key and application name registered to your account.").font(.footnote).foregroundStyle(.secondary)
                }
                Section("Account for downloads") {
                    TextField("Username", text: $credentials.username)
                    SecureField("Password", text: $credentials.password)
                    Link("OpenSubtitles.com account", destination: URL(string: "https://www.opensubtitles.com")!)
                }
                Section {
                    Text("Credentials are saved in this iPad's Keychain and are sent only to the OpenSubtitles API. The account is used when you download.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("Remove Saved Account", role: .destructive) {
                        do { try SubtitleAccountStore.remove(); saved(SubtitleCredentials()); dismiss() }
                        catch { self.error = error.localizedDescription }
                    }
                }
                if let error { Section { Text(error).foregroundStyle(.red) } }
            }
            .textInputAutocapitalization(.never).autocorrectionDisabled()
            .navigationTitle("Subtitle Account").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        do { try SubtitleAccountStore.save(credentials); saved(credentials); dismiss() }
                        catch { self.error = error.localizedDescription }
                    }.disabled(!credentials.canSearch)
                }
            }
        }
    }
}
