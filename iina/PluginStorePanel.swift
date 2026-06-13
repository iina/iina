//
//  PluginStore.swift
//  iina
//
//  Created by Hechen Li on 2026-04-18.
//  Copyright © 2026 lhc. All rights reserved.
//

import SwiftUI
import Combine


fileprivate let defaultPlugins = [
  [
    "name": "Online Media",
    "url": "https://github.com/iina/plugin-online-media",
    "id": "io.iina.ytdl",
    "desc": "Official plugin for playing online media via yt-dlp / youtube-dl. The built-in youtube-dl support will be disabled when this plugin is enabled."
  ],
  [
    "name": "Userscript",
    "url": "https://github.com/iina/plugin-userscript",
    "id": "io.iina.user-script",
    "desc": "User Scripts for IINA"
  ],
  [
    "name": "Online Subtitles",
    "url": "https://github.com/iina/plugin-opensub",
    "id": "io.iina.opensub",
    "desc": "Official OpenSubtitles plugin for IINA"
  ],
]


/// Trigger the refresh of the plugin list.
fileprivate class RefreshIndicator: ObservableObject {
  @Published private(set) var refreshCount = 0

  func refresh() {
    refreshCount += 1
  }
}


@available(macOS 12.0, *)
class PluginStorePanel: NSWindow {
  let l10n: SettingsLocalization.Context
  lazy var pluginManager = PluginManager(window: self)

  init(l10n: SettingsLocalization.Context) {
    self.l10n = l10n

    let style: NSWindow.StyleMask = [.titled, .resizable, .fullSizeContentView]
    let rect = NSRect(x: 0, y: 0, width: 600, height: 500)
    super.init(contentRect: rect, styleMask: style, backing: .buffered, defer: false)

    self.contentView = NSView()

    let indicator = RefreshIndicator()
    let pluginStoreView = PluginStoreView(l10n: l10n, panel: self)
      .environmentObject(indicator)
    let hostingView = NSHostingView(rootView: pluginStoreView)
    hostingView.translatesAutoresizingMaskIntoConstraints = false
    let closeBtn = NSButton(title: NSLocalizedString("general.done", comment: "Done"),
                            target: self, action: #selector(cancelOperation))
    closeBtn.translatesAutoresizingMaskIntoConstraints = false

    contentView?.addSubview(hostingView)
    contentView?.addSubview(closeBtn)

    hostingView.padding(.top(0), .horizontal(0)).spacing(.bottom, to: closeBtn)
    closeBtn.padding(.bottom(16), .trailing(16))
  }

  override func cancelOperation(_ sender: Any?) {
    sheetParent?.endSheet(self, returnCode: .OK)
  }

  func install(_ string: String) async {
    let urlString = if string.starts(with: "https://") {
      string
    } else if Regex.githubRepo.matches(string) {
      "https://github.com/\(string)"
    } else {
      ""
    }
    await pluginManager.install(gitHubString: urlString)
  }
}

struct Plugin: Identifiable, Hashable, Decodable {
  let name: String
  let url: URL
  let id: String
  let desc: String

  var installed: Bool {
    JavascriptPlugin.plugins.contains(where: { $0.identifier == self.id })
  }

  var icon: String {
    installed ? "checkmark.circle.fill" : "square.and.arrow.down"
  }

  init(_ plugin: Dictionary<String, String>) {
    name = plugin["name"]!
    url = URL(string: plugin["url"]!)!
    id = plugin["id"]!
    desc = plugin["desc"]!
  }
}

let officialPlugins = defaultPlugins.map { Plugin($0) }


@available(macOS 12.0, *)
struct PluginStoreView: View {
  let l10n: SettingsLocalization.Context
  let panel: PluginStorePanel

  @EnvironmentObject private var indicator: RefreshIndicator

  @State private var inputURL: String = ""
  @State private var selection: Plugin? = nil
  @State private var listDownloaded = false
  @State private var isInstalling: Bool = false

  @State private var communityPluginList: [Plugin] = []
  @State private var errorMessage: String? = nil

  var inputURLInvalid: Bool {
    !(Regex.githubRepo.matches(inputURL) || Regex.githubURL.matches(inputURL))
  }

  private func installFromURL(_ string: String) {
    isInstalling = true
    Task { @MainActor in
      let prevCount = JavascriptPlugin.plugins.count
      await panel.install(inputURL)
      isInstalling = false
      if JavascriptPlugin.plugins.count > prevCount {
        // dismiss the sheet after installing from URL
        // otherwise there's no indicator of a successful install
        panel.cancelOperation(nil)
      }
    }
  }

  var body: some View {
    VStack(alignment: .leading) {
      HStack() {
        Text(l10n.localized(.text_InputGithubURL))
        TextField("owner/repo", text: $inputURL)
          .textFieldStyle(.roundedBorder)
          .onSubmit {
            installFromURL(inputURL)
          }
        Button(action: { installFromURL(inputURL) }) {
          HStack {
            if isInstalling {
              ProgressView().controlSize(.small).padding(.trailing, 4)
            }
            Text(l10n.localized(isInstalling ? .text_Installing : .text_Install))
          }
        }.disabled(isInstalling)
        .buttonStyle(.borderedProminent)
        .controlSize(.regular)
        .disabled(inputURLInvalid)
      }

      Divider().padding(.top, 8).padding(.bottom, 8)

      Text(l10n.localized(.text_OrSelectFrom))

      let list = List(selection: $selection) {
        Section(l10n.localized(.text_OfficialPlugins)) {
          ForEach(officialPlugins, id: \.self) { plugin in
            HStack {
              Image(systemName: plugin.icon)
              Text(plugin.name)
            }
          }
        }

        Section(l10n.localized(.text_CommunityPlugins)) {
          if let errorMessage {
            Text("Error: \(errorMessage)")
              .lineLimit(5)
              .foregroundColor(.secondary)
              .multilineTextAlignment(.leading)
          } else if listDownloaded {
            ForEach(communityPluginList, id: \.self) { plugin in
              HStack {
                Image(systemName: plugin.icon)
                Text(plugin.name)
              }
            }
          } else {
            ProgressView("Loading…")
          }
        }
      }
      .id(indicator.refreshCount)
      .listStyle(.sidebar)
      .padding(.leading, -12)

      HStack(spacing: 4) {
        VStack(alignment: .leading) {
          if #available(macOS 13.0, *) {
            list.scrollContentBackground(.hidden)
          } else {
            list
          }
        }.frame(width: 240)
        GroupBox {
          ScrollView {
            PluginDetailView(l10n: l10n, plugin: selection, panel: panel)
              .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
              .padding(8)
          }
        }.frame(minWidth: 200)
      }
    }
    .task() {
      do {
        self.communityPluginList = try await GitHubService.fetchPluginList()
      } catch GitHubError.notFound {
        errorMessage = "Repository not found"
      } catch GitHubError.rateLimited {
        errorMessage = "Rate limit exceeded. Try again later or add an API token."
      } catch {
        errorMessage = error.localizedDescription
      }
      listDownloaded = true
    }
    .padding(20)
  }
}


@available(macOS 12.0, *)
struct PluginDetailView: View {
  let l10n: SettingsLocalization.Context
  let plugin: Plugin?
  let panel: PluginStorePanel

  @EnvironmentObject private var indicator: RefreshIndicator
  @State var isInstalling: Bool = false

  var body: some View {
    if let plugin {
      let (owner, repo) = ownerAndRepo(from: plugin.url)
      VStack(alignment: .leading, spacing: 4) {
        Text(plugin.name).font(.system(size: 14)).bold()
        Text(plugin.id).font(.system(size: 11).monospaced())
          .padding(.bottom, 6)
        Text(plugin.desc).foregroundColor(.secondary)
          .padding(.bottom, 4)
        if let owner, let repo {
          Link(destination: plugin.url) {
            Text(plugin.url.absoluteString)
              .font(.system(size: 11))
              .multilineTextAlignment(.leading)
          }
          Button(action: {
            isInstalling = true
            Task { @MainActor in
              await panel.install(plugin.url.absoluteString)
              isInstalling = false
              indicator.refresh()
            }
          }) {
            HStack {
              if isInstalling {
                ProgressView().controlSize(.small).padding(.trailing, 4)
              } else {
                Image(systemName: plugin.icon).padding(.trailing, 4)
              }
              Text(l10n.localized(plugin.installed ? .text_Installed :
                                    isInstalling ? .text_Installing : .text_Install))
            }
          }.buttonStyle(.borderedProminent)
            .disabled(plugin.installed || isInstalling)
            .padding(.vertical, 8)
          Divider().padding(.top, 8).padding(.bottom, 12)
          RepoDetailView(owner: owner, repo: repo)
        } else {
          Text(l10n.localized(.text_ThisPluginIsNot))
            .font(.system(size: 11))
            .padding(.top, 8)
          Link(destination: plugin.url) {
            Text(plugin.url.absoluteString)
              .font(.system(size: 11))
              .multilineTextAlignment(.leading)
          }
        }
      }
    } else {
      Text(l10n.localized(.text_NoSelection))
        .bold().foregroundColor(.secondary)
    }
  }

  private func ownerAndRepo(from url: URL) -> (String?, String?) {
    guard Regex.githubURL.matches(url.absoluteString) else {
      return (nil, nil)
    }
    var elements = url.absoluteString.split(separator: "/")
    guard let repo = elements.popLast(), let owner = elements.last else {
      return (nil, nil)
    }
    return (String(owner), String(repo))
  }
}

struct GitHubRepo: Codable {
  let name: String
  let fullName: String
  let description: String?
  let stargazersCount: Int
  let forksCount: Int
  let openIssuesCount: Int
  let language: String?
  let htmlUrl: URL
  let updatedAt: Date
  let pushedAt: Date?
  let owner: Owner

  struct Owner: Codable {
    let login: String
    let avatarUrl: URL
  }

  enum CodingKeys: String, CodingKey {
    case name
    case fullName = "full_name"
    case description
    case stargazersCount = "stargazers_count"
    case forksCount = "forks_count"
    case openIssuesCount = "open_issues_count"
    case language
    case htmlUrl = "html_url"
    case updatedAt = "updated_at"
    case pushedAt = "pushed_at"
    case owner
  }
}

extension GitHubRepo.Owner {
  enum CodingKeys: String, CodingKey {
    case login
    case avatarUrl = "avatar_url"
  }
}

enum GitHubError: Error {
  case invalidURL
  case rateLimited
  case notFound
  case decodingError
  case network(Error)
}

class GitHubService {
  private static func request(url: URL) async throws -> Data {
    var request = URLRequest(url: url)
    request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
    request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

    let (data, response) = try await URLSession.shared.data(for: request)

    guard let httpResponse = response as? HTTPURLResponse else {
      throw GitHubError.network(URLError(.badServerResponse))
    }

    switch httpResponse.statusCode {
    case 200:
      return data
    case 403:
      throw GitHubError.rateLimited
    case 404:
      throw GitHubError.notFound
    default:
      throw GitHubError.network(URLError(.badServerResponse))
    }
  }

  func fetchRepo(owner: String, repo: String) async throws -> GitHubRepo {
    guard let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)") else {
      throw GitHubError.invalidURL
    }

    let data = try await GitHubService.request(url: url)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    do {
      return try decoder.decode(GitHubRepo.self, from: data)
    } catch {
      throw GitHubError.decodingError
    }
  }

  static func fetchPluginList() async throws -> [Plugin] {
    guard let url = URL(string: "https://raw.githubusercontent.com/iina/iina/refs/heads/develop/plugins.json") else {
      throw GitHubError.invalidURL
    }

    let data = try await GitHubService.request(url: url)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    do {
      return try decoder.decode([Plugin].self, from: data)
    } catch {
      throw GitHubError.decodingError
    }
  }
}


@available(macOS 12.0, *)
struct RepoDetailView: View {
  let owner: String
  let repo: String

  @State private var repoData: GitHubRepo?
  @State private var isLoading = false
  @State private var errorMessage: String?

  private let service = GitHubService()

  var body: some View {
    Group {
      if isLoading {
        ZStack {
          ProgressView("Loading…")
        }
      } else if let errorMessage {
        if #available(macOS 14.0, *) {
          ContentUnavailableView("Failed to load",
                                 systemImage: "exclamationmark.triangle",
                                 description: Text(errorMessage))
        } else {
          VStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle")
              .font(.title2)
            Text("Failed to load").bold()
            Text(errorMessage)
              .font(.caption)
              .foregroundColor(.secondary)
              .multilineTextAlignment(.center)
          }
        }
      } else if let repoData {
        repoContent(repoData)
      } else {
        Text("No data")
      }
    }
    .padding(0)
    .task(id: "\(owner)/\(repo)") {
      await load()
    }
  }

  @ViewBuilder
  private func repoContent(_ repo: GitHubRepo) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 12) {
        AsyncImage(url: repo.owner.avatarUrl) { image in
          image.resizable()
        } placeholder: {
          Color.gray.opacity(0.2)
        }
        .frame(width: 36, height: 36)
        .clipShape(RoundedRectangle(cornerRadius: 6))

        VStack(alignment: .leading) {
          Text(repo.name)
            .font(.headline)
          Text(repo.owner.login)
            .font(.system(size: 11))
            .foregroundColor(.secondary)
        }
      }

      if let description = repo.description {
        Text(description)
          .foregroundColor(.secondary)
      }

      HStack(spacing: 20) {
        Label("\(repo.stargazersCount)", systemImage: "star.fill")
        Label("\(repo.forksCount)", systemImage: "tuningfork")
        Label("\(repo.openIssuesCount)", systemImage: "exclamationmark.circle")
        if let language = repo.language {
          Label(language, systemImage: "chevron.left.forwardslash.chevron.right")
        }
      }
      .font(.callout)
      .foregroundColor(.secondary)

      Text(formatUpdateDate(repo.pushedAt ?? repo.updatedAt))
        .font(.caption)
        .foregroundColor(.secondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func formatUpdateDate(_ date: Date) -> String {
    let days = Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0
    if days < 30 {
      return "Updated \(Self.relativeFormatter.localizedString(for: date, relativeTo: Date()))"
    } else {
      return "Updated on \(Self.absoluteFormatter.string(from: date))"
    }
  }

  private static let relativeFormatter: RelativeDateTimeFormatter = {
    let f = RelativeDateTimeFormatter()
    f.unitsStyle = .full
    return f
  }()

  private static let absoluteFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateStyle = .medium
    f.timeStyle = .none
    return f
  }()

  private func load() async {
    isLoading = true
    errorMessage = nil
    do {
      repoData = try await service.fetchRepo(owner: owner, repo: repo)
    } catch GitHubError.notFound {
      errorMessage = "Repository not found"
    } catch GitHubError.rateLimited {
      errorMessage = "Rate limit exceeded. Try again later or add an API token."
    } catch {
      errorMessage = error.localizedDescription
    }
    isLoading = false
  }
}
