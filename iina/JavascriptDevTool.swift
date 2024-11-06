//
//  JavasctiptDevTool.swift
//  iina
//
//  Created by Hechen Li on 11/30/22.
//  Copyright © 2022 lhc. All rights reserved.
//

import SwiftUI
import JavaScriptCore
import WebKit
import Carbon


// MARK: - Menu Controller

@available(macOS 12.0, *)
extension MenuController {
  func menuItem(forPluginInstance inst: JavascriptPluginInstance, tag: Int) -> NSMenuItem {
    let item = NSMenuItem()
    item.title = inst.plugin.name + (inst.isGlobal ? " (Global)" : "")
    item.representedObject = inst
    item.tag = JavasctiptDevTool.JSMenuItemInstance
    item.target = self
    item.action = #selector(openJavascriptDevTool)
    return item
  }

  @objc func openJavascriptDevTool(_ sender: NSMenuItem) {
    switch (sender.tag) {
    case JavasctiptDevTool.JSMenuItemInstance:
      let inst = sender.representedObject as! JavascriptPluginInstance
      createJavascriptDevToolWindow(forInstance: inst, title: sender.title)
    default:
      assertionFailure("Unhandled menu item type")
    }
  }
}


// MARK: - Data

@available(macOS 12.0, *)
fileprivate struct ResultItem: Identifiable {
  enum ResultType {
    case number(NSNumber)
    case string(String)
    case boolean(Bool)
    case array(String, [(String, String)])
    case null
    case undefined
    case opaqueObject(String)
    case object(String, [(String, String)])
    case exception(String, String)
    case log(String, Logger.Level)
  }
  let id: Int
  let index: Int
  let result: ResultType?
  let prompt: String?

  var isMessage: Bool {
    switch self.result {
    case .exception(_, _), .log(_, _):
      return true
    default:
      return false
    }
  }
}

@available(macOS 12.0, *)
fileprivate class JSEventsContainer : ObservableObject {
  @Published var idCounter = 0
  @Published var counter = 0
  @Published var data = [ResultItem]()
  @Published var idChanged = 0

  func addPrompt(_ prompt: String) {
    idCounter += 1
    counter += 1
    data.append(ResultItem(id: idCounter, index: counter, result: nil, prompt: prompt))
  }

  func addResult(_ result: ResultItem.ResultType) {
    idCounter += 1
    data.append(ResultItem(id: idCounter, index: counter, result: result, prompt: nil))
    postChange()
  }

  func addException(message: String, stack: String) {
    idCounter += 1
    data.append(
      ResultItem(id: idCounter, index: counter, result: .exception(message, stack), prompt: nil))
    postChange()
  }

  func addLog(message: String, level: Logger.Level) {
    idCounter += 1
    data.append(
      ResultItem(id: idCounter, index: counter, result: .log(message, level), prompt: nil))
    postChange()
  }
  
  func clearAll() {
    data.removeAll()
    postChange()
  }

  func postChange() {
    Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false) { _ in
      self.idChanged = self.idCounter
    }
  }
}


// MARK: - Dev Tool Window


@available(macOS 12.0, *)
struct JavasctiptDevTool: View {
  // NSMenuItem
  static let JSMenuItemInstance = 1
  static let JSMenuItemWebView = 2

  // SwiftUI
  unowned let jsContext: JSContext
  @ObservedObject fileprivate var events = JSEventsContainer()

  var body: some View {
    VSplitView {
      ScrollViewReader { proxy in
        // Message history
        List(events.data, id: \.id) { item in
          // Message item
          if item.prompt != nil {
            // Prompt
            PromptView(result: item).id(item.id)
          } else if item.isMessage {
            // Message
            ResultView(result: item).id(item.id)
          } else {
            // Result
            ReturnValueView(result: item).id(item.id)
          }
        }
        .onReceive(events.$idChanged) { id in
          proxy.scrollTo(id, anchor: .bottom)
        }
      }
      ConsoleView(jsContext: jsContext)
        .environmentObject(events)
    }
    .listStyle(.plain)
  }
}


#if DEBUG
@available(macOS 12.0, *)
struct JavasctiptDevTool_Previews: PreviewProvider {
  static let jsContext = JSContext()
  static fileprivate let events: JSEventsContainer = {
    let events_ = JSEventsContainer()
    events_.addPrompt("1 + 1")
    events_.addResult(.number(2))
    events_.addLog(message: "Log Message", level: .debug)
    return events_
  }()
  static var previews: some View {
    var view = JavasctiptDevTool(jsContext: jsContext!)
    view.events = events
    return view
  }
}
#endif


// MARK: - Views

/// The text editor view in the console
@available(macOS 12.0, *)
struct CommandEditor: NSViewRepresentable {
  @Binding var text: String

  init(text: Binding<String>) {
    _text = text
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(self)
  }

  func makeNSView(context: Context) -> NSView {
    let view = TextView()
    view.delegate = context.coordinator
    view.parent = self
    view.translatesAutoresizingMaskIntoConstraints = false
    view.backgroundColor = .clear
    return view
  }

  func updateNSView(_ nsView: NSView, context: Context) {
    let textView = nsView as! NSTextView
    textView.string = text
    textView.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize(for: .regular), weight: .regular)
    textView.isAutomaticDashSubstitutionEnabled = false
    textView.isAutomaticQuoteSubstitutionEnabled = false
    textView.isAutomaticSpellingCorrectionEnabled = false
    guard !context.coordinator.selectedRanges.isEmpty else {
      return
    }
    textView.selectedRanges = context.coordinator.selectedRanges
    Utility.quickConstraints(["H:|[v]|", "V:|[v]|"], ["v": textView])
  }

  class TextView: NSTextView {
    var parent: CommandEditor!
    var recallIndex: Int? = nil

    override func keyDown(with event: NSEvent) {
      super.keyDown(with: event)
      // Display history commands when up arrow pressed
      if event.keyCode == kVK_UpArrow {
        if self.string.isEmpty {
          recallIndex = 0
        }
        if let idx = recallIndex {
          let data = (self.window as! JSDevToolWindow).rootView.events.data
            .compactMap({ $0.prompt }).reversed()
          let dataIdx = data.index(data.startIndex, offsetBy: idx)
          if data.indices.contains(dataIdx) {
            let prompt = data[dataIdx]
            self.string = prompt
            parent.text = self.string
            recallIndex = idx + 1
            return
          }
        }
      }
      recallIndex = nil
    }

    override func preferredPasteboardType(from availableTypes: [NSPasteboard.PasteboardType], restrictedToTypesFrom allowedTypes: [NSPasteboard.PasteboardType]?) -> NSPasteboard.PasteboardType? {
      if availableTypes.contains(.string) {
        return .string
      }
      return super.preferredPasteboardType(from: availableTypes, restrictedToTypesFrom: allowedTypes)
    }
  }

  class Coordinator: NSObject, NSTextViewDelegate {
    var parent: CommandEditor
    var selectedRanges = [NSValue]()

    init(_ parent: CommandEditor) {
      self.parent = parent
    }

    func textDidChange(_ notification: Notification) {
      guard let textView = notification.object as? NSTextView else { return }
      parent.text = textView.string
      selectedRanges = textView.selectedRanges
    }
  }
}


/// Display the content of a JavaScript array or object
@available(macOS 12.0, *)
struct ObjectView: View {
  enum ViewType {
    case array, object
  }
  let viewType: ViewType
  let title: String
  let arrayDisplayLimit = 100
  let data: [(String, String)]

  @State var isExpanded = false

  var body: some View {
    VStack(alignment: .leading) {
      HStack {
        Image(systemName: "chevron.\(isExpanded ? "down" : "forward").circle.fill")
          .frame(width: 10, height: 10)
        Text(title).font(.monospacedSystem)
      }
      .onTapGesture {
        isExpanded.toggle()
      }
      let dataToDisplay = viewType == .array ? Array(data.prefix(arrayDisplayLimit)) : data
      if isExpanded {
        ForEach(dataToDisplay, id: \.0) { item in
          HStack {
            Text("\(item.0):").font(.monospacedSystem).foregroundColor(.secondary)
              .padding(.leading, 8)
            Text(item.1).font(.monospacedSystem)
              .lineLimit(1)
          }
        }
        if viewType == .array && data.count > 100 {
          Text("... (\(data.count - 100)) more").font(.monospacedSystem).foregroundColor(.secondary)
        }
      }
    }
  }
}


/// Display a JavaScript command entered by user
@available(macOS 12.0, *)
fileprivate struct PromptView: View {
  var result: ResultItem
  
  var body: some View {
    HStack(alignment: .top, spacing: 8) {
      Text("[\(result.index)]:")
        .frame(width: 50, alignment: .trailing)
        .font(.monospacedSystem)
        .foregroundColor(.green)
      Text(result.prompt ?? "")
        .font(.monospacedSystem)
    }
  }
}


/// Display the return value of the JavaScript command
@available(macOS 12.0, *)
fileprivate struct ReturnValueView: View {
  var result: ResultItem
  
  var body: some View {
    HStack(alignment: .top, spacing: 8) {
      Text("→")
        .frame(width: 50, alignment: .trailing)
        .font(.monospacedSystem)
        .foregroundColor(.secondary)
      ResultView(result: result)
    }
  }
}


@available(macOS 12.0, *)
fileprivate struct ConsoleView: View {
  unowned let jsContext: JSContext
  @EnvironmentObject fileprivate var events: JSEventsContainer
  @State private var input: String = ""

  
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      // Toolbar
      HStack {
        // Run code
        Button(action: { executePrompt() }) {
          Image(systemName: "play.circle")
            .renderingMode(.template)
            .foregroundColor(.accentColor)
        }
        .help("Run code")
        .buttonStyle(PlainButtonStyle())
        .keyboardShortcut(.return, modifiers: .command)
        // Show global objects
        Button(action: { executePrompt(printGlobalObject: true) }) {
          Image(systemName: "point.3.filled.connected.trianglepath.dotted")
            .renderingMode(.template)
            .foregroundColor(.secondary)
        }
        .buttonStyle(PlainButtonStyle())
        .help("Print global objects")
        // Clear history
        Button(action: {events.clearAll()} ) {
          Image(systemName: "clear")
            .renderingMode(.template)
            .foregroundColor(.secondary)
        }
        .buttonStyle(PlainButtonStyle())
        .help("Clear history")
        Spacer()
        Text("Cmd+Return to run code")
          .font(.footnote)
          .foregroundColor(.secondary)
      }
      .padding([.top, .horizontal], 8)
      // Editor
      CommandEditor(text: $input)
        .frame(maxHeight: 100)
        .padding(.all, 8)
    }.background(.ultraThickMaterial)
  }
  
  private func executePrompt(printGlobalObject: Bool = false) {
    let source = printGlobalObject ? "$global" : input.trimmingCharacters(in: .whitespacesAndNewlines)
    if source.isEmpty {
      return
    }
    events.addPrompt(source)
    events.postChange()

    let jsResult: ResultItem.ResultType

    let result = source == "$global" ?
    jsContext.globalObject :
    jsContext.evaluateScript(source)

    if let result = result {
      if result.isNumber {
        jsResult = .number(result.toNumber())
      } else if result.isString {
        jsResult = .string(result.toString())
      } else if result.isBoolean {
        jsResult = .boolean(result.toBool())
      } else if result.isNull {
        jsResult = .null
      } else if result.isUndefined {
        jsResult = .undefined
      } else if result.isArray {
        let array = result.toArray()!
        jsResult = .array(
          "Array (\(array.count))", array.enumerated().map { ("\($0.offset)", "\($0.element)") } )
      } else {
        let object = result.toObject()!
        if let dict = object as? [String: Any] {
          jsResult = .object(
            result.toString() ?? "", dict.keys.map { ($0, "\(dict[$0] ?? "nil")") })
        } else {
          jsResult = .opaqueObject(result.toString())
        }
      }
      events.addResult(jsResult)
      events.postChange()
    }

    if !printGlobalObject {
      input = ""
    }
  }

}


/// Display various JavaScript values and log messages
@available(macOS 12.0, *)
fileprivate struct ResultView: View {
  var result: ResultItem

  var body: some View {
    switch (result.result) {
    case .string(let value):
      Text(value).font(.monospacedSystem).foregroundColor(.brown)

    case .number(let value):
      Text("\(value)").font(.monospacedSystem).foregroundColor(.blue)

    case .boolean(let value):
      Text(value ? "true" : "false").font(.monospacedSystem).foregroundColor(.purple)

    case .null:
      Text("null").font(.monospacedSystem).foregroundColor(.secondary)

    case .undefined:
      Text("undefined").font(.monospacedSystem).foregroundColor(.secondary)

    case .array(let title, let data):
      ObjectView(viewType: .array, title: title, data: data)

    case .object(let title, let data):
      ObjectView(viewType: .array, title: title, data: data)

    case .opaqueObject(let value):
      Text(value).font(.monospacedSystem)

    case .exception(let message, let stack):
      ZStack {
        VStack(alignment: .leading) {
          Text("Exception: \(message)")
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundColor(.red)
          Text(stack)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundColor(.secondary)
        }
        .textSelection(.enabled)
        .padding(.all, 8)
      }
      .background(Color.red.opacity(0.1))

    case .log(let message, let level):
      ZStack {
        Text(message).font(.monospacedSystem)
          .frame(maxWidth: .infinity, alignment: .leading)
          .textSelection(.enabled)
          .padding(.all, 8)
      }
      .background(
        ([.error: .red, .debug: .gray, .verbose: .gray, .warning: .orange] as [Logger.Level: Color])[level]!.opacity(0.1))
    case .none:
      Text("")
    }
  }
}


// MARK: - Utils

@available(macOS 12.0, *)
fileprivate extension Font {
  static let monospacedSystem: Font = .system(.body, design: .monospaced)
}

// MARK: - Window

@available(macOS 12.0, *)
fileprivate class JSDevToolWindow: NSWindow {
  var rootView: JavasctiptDevTool!
}

@available(macOS 12.0, *)
fileprivate var windows: [JSContext: JSDevToolWindow] = [:]

@available(macOS 12.0, *)
func createJavascriptDevToolWindow(forInstance inst: JavascriptPluginInstance, title: String) {
  let ctx = inst.js
  if let window = windows[ctx] {
    window.makeKeyAndOrderFront(nil)
  } else {
    // create window
    let window = JSDevToolWindow(contentRect: NSRect(origin: .zero, size: CGSize(width: 500, height: 400)),
                                 styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                 backing: .buffered,
                                 defer: false)
    window.title = "DevTool: " + title
    window.rootView = JavasctiptDevTool(jsContext: ctx)
    window.contentView = NSHostingView(rootView: window.rootView)
    window.center()
    window.backgroundColor = .clear
    windows[ctx] = window

    // override exception handler
    let previousHandler = ctx.exceptionHandler
    ctx.exceptionHandler = { context, exception in
      if let previousHandler = previousHandler {
        previousHandler(context, exception)
      }

      let message = exception?.toString() ?? "Unknown exception"
      let stack = exception?.objectForKeyedSubscript("stack")?.toString() ?? "???"
      window.rootView.events.addException(message: message, stack: stack)
    }

    // add log handler
    inst.logHandler = { message, level in
      Utility.executeOnMainThread {
        window.rootView.events.addLog(message: message, level: level)
        window.rootView.events.postChange()
      }
    }

    window.makeKeyAndOrderFront(nil)
  }
}
