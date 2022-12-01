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


// MARK: - Menu Controller

@available(macOS 12.0, *)
extension MenuController {
  func createMenuItem(fromPluginInstance inst: JavascriptPluginInstance, tag: Int) -> NSMenuItem {
    let item = NSMenuItem()
    if inst.isGlobal {
      item.title = "\(inst.plugin.name) (Global)"
    } else {
      item.title = inst.plugin.name
    }
    item.representedObject = inst
    item.tag = JavasctiptDevTool.JSMenuItemInstance
    item.target = self
    item.action = #selector(openJavascriptDevTool)
    return item
  }

  @objc func openJavascriptDevTool(_ sender: NSMenuItem) {
    switch (sender.tag) {
    case JavasctiptDevTool.JSMenuItemInstance:
      if let inst = sender.representedObject as? JavascriptPluginInstance {
        createJavascriptDevToolWindow(forInstance: inst, title: sender.title)
      }
      //    case JSMenuItemWebView:
      //      is let webView = sender.representedObject as? WKWebView {
      //        createJavascriptDevToolWindow(forWebView: webView)
      //      }
    default:
      break
    }
  }
}

protocol JavascriptExecutable {
  func evaluateJavaScript(
    _ javaScriptString: String,
    completionHandler: ((Any?, Error?) -> Void)?
  )
}

extension WKWebView: JavascriptExecutable {
  
}


// MARK: - Data

fileprivate struct JSEvent: Identifiable {
  enum Result {
    case nothing
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
  let prompt: String?
  let result: Result

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
fileprivate class JSCommandsContainer : ObservableObject{
  @Published var idCounter = 0
  @Published var counter = 0
  @Published var data = [JSEvent]()
  @Published var idChanged = 0

  func addPrompt(_ prompt: String) {
    idCounter += 1
    counter += 1
    data.append(JSEvent(id: idCounter, index: counter, prompt: prompt, result: .nothing))
  }

  func addResult(_ result: JSEvent.Result) {
    idCounter += 1
    data.append(JSEvent(id: idCounter, index: counter, prompt: nil, result: result))
    postChange()
  }

  func addException(message: String, stack: String) {
    idCounter += 1
    data.append(
      JSEvent(id: idCounter, index: counter, prompt: nil,
                result: .exception(message, stack)))
    postChange()
  }

  func addLog(message: String, level: Logger.Level) {
    idCounter += 1
    data.append(
      JSEvent(id: idCounter, index: counter, prompt: nil,
                result: .log(message, level)))
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
  static let JSMenuItemWebView = 3

  // SwiftUI
  unowned let jsContext: JSContext

  @ObservedObject fileprivate var commands = JSCommandsContainer()

  @State private var input: String = ""

  var body: some View {
    VSplitView {
      ScrollViewReader { proxy in
        // Message history
        List(commands.data, id: \.id) { command in
          // Message item
          if command.isMessage {
            ResultView(command: command).id(command.id)
          } else if let prompt = command.prompt {
            // Prompt
            HStack(alignment: .top, spacing: 8) {
              Text("[\(command.index)]:")
                .frame(width: 50, alignment: .trailing)
                .mono()
                .foregroundColor(.green)
              Text(prompt)
                .mono()
            }.id(command.id)
          } else {
            // Result
            HStack(alignment: .top, spacing: 8) {
              Text("→")
                .frame(width: 50, alignment: .trailing)
                .mono()
                .foregroundColor(.secondary)
              ResultView(command: command)
            }.id(command.id)
          }
        }
        .onReceive(commands.$idChanged) { id in
          proxy.scrollTo(id, anchor: .bottom)
        }
      }
      VStack(alignment: .leading, spacing: 0) {
        HStack {
          Button(action: executePrompt) {
            Image(systemName: "play.circle")
              .renderingMode(.template)
              .foregroundColor(.accentColor)
          }
          .buttonStyle(PlainButtonStyle())
          .keyboardShortcut(.return, modifiers: .command)
          Spacer()
          Text("Cmd+Return to run code")
            .font(.footnote)
            .foregroundColor(.secondary)
        }
        .padding([.top, .horizontal], 8)
        CommandEditor(text: $input)
          .frame(maxHeight: 100)
          .padding(.all, 8)

      }
    }
    .listStyle(.plain)
  }

  private func executePrompt() {
    let source = input.trimmingCharacters(in: .whitespacesAndNewlines)
    if source.isEmpty {
      return
    }
    commands.addPrompt(source)
    commands.postChange()

    let jsResult: JSEvent.Result

    if let result = jsContext.evaluateScript(source) {
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
            result.toString(), dict.keys.map { ($0, "\(dict[$0] ?? "nil")") })
        } else {
          jsResult = .opaqueObject(result.toString())
        }
      }
      commands.addResult(jsResult)
      commands.postChange()
    }

    input = ""
  }
}

@available(macOS 12.0, *)
struct JavasctiptDevTool_Previews: PreviewProvider {
  static var previews: some View {
    JavasctiptDevTool(jsContext: JSContext())
  }
}


// MARK: - Views

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
    return view
  }

  func updateNSView(_ nsView: NSView, context: Context) {
    let textView = nsView as! NSTextView
    textView.string = text
    textView.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize(for: .regular), weight: .regular)
    textView.isAutomaticDashSubstitutionEnabled = false
    textView.isAutomaticQuoteSubstitutionEnabled = false
    textView.isAutomaticSpellingCorrectionEnabled = false
    guard context.coordinator.selectedRanges.count > 0 else {
      return
    }
    textView.selectedRanges = context.coordinator.selectedRanges
  }

  class TextView: NSTextView {
    var parent: CommandEditor!

    override func keyDown(with event: NSEvent) {
      super.keyDown(with: event)
      if event.keyCode == 126 && self.string.isEmpty {
        if let prompt = (self.window as! JSDevToolWindow)
          .rootView.commands.data.last(where: { $0.prompt != nil })?.prompt {
          self.string = prompt
          parent.text = self.string
        }
      }
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


@available(macOS 12.0, *)
struct ObjectView: View {
  enum ViewType {
    case array, object
  }
  let viewType: ViewType
  let title: String
  let data: [(String, String)]

  @State var isExpanded = false

  var body: some View {
    VStack(alignment: .leading) {
      HStack {
        Image(systemName: "chevron.\(isExpanded ? "down" : "forward").circle.fill")
          .frame(width: 10, height: 10)
        Text(title).mono()
      }
      .onTapGesture {
        isExpanded.toggle()
      }
      let dataToDisplay = viewType == .array ? Array(data.first(count: 100)) : data
      if isExpanded {
        ForEach(dataToDisplay, id: \.0) { item in
          HStack {
            Text("\(item.0):").mono().foregroundColor(.secondary)
              .padding(.leading, 8)
            Text(item.1).mono()
              .lineLimit(1)
          }
        }
        if viewType == .array && data.count > 100 {
          Text("... (\(data.count - 100)) more").mono().foregroundColor(.secondary)
        }
      }
    }
  }
}

@available(macOS 12.0, *)
fileprivate struct ResultView: View {
  var command: JSEvent

  var body: some View {
    switch (command.result) {
    case .nothing:
      Text("")

    case .string(let value):
      Text(value).mono().foregroundColor(.brown)

    case .number(let value):
      Text("\(value)").mono().foregroundColor(.blue)

    case .boolean(let value):
      Text(value ? "true" : "false").mono().foregroundColor(.purple)

    case .null:
      Text("null").mono().foregroundColor(.secondary)

    case .undefined:
      Text("undefined").mono().foregroundColor(.secondary)

    case .array(let title, let data):
      ObjectView(viewType: .array, title: title, data: data)

    case .object(let title, let data):
      ObjectView(viewType: .array, title: title, data: data)

    case .opaqueObject(let value):
      Text(value).mono()

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
        .padding(.all, 8)
      }
      .background(Color.red.opacity(0.1))

    case .log(let message, let level):
      ZStack {
        Text(message).mono()
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.all, 8)
      }
      .background(
        ([.error: .red, .debug: .gray, .verbose: .gray, .warning: .orange] as [Logger.Level: Color])[level]!.opacity(0.1))
    }
  }
}


// MARK: - Utils

fileprivate extension Array {
  func first(count len: Int) -> ArraySlice<Self.Element> {
    let cnt = len > self.count ? self.count : len
    return self[0..<cnt]
  }
}

@available(macOS 12.0, *)
struct MonospacedText: ViewModifier {
  func body(content: Content) -> some View {
    content
      .font(.system(.body, design: .monospaced))
  }
}

@available(macOS 12.0, *)
extension View {
  func mono() -> some View {
    modifier(MonospacedText())
  }
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
    let rect = ((NSScreen.main ?? NSScreen.screens.first)?.frame ?? NSRect(x: 0, y: 0, width: 0, height: 0))
      .centeredResize(to: NSSize(width: 500, height: 300))
    let window = JSDevToolWindow(contentRect: rect,
                                 styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                 backing: .buffered,
                                 defer: false)
    window.title = "DevTool: " + title
    window.rootView = JavasctiptDevTool(jsContext: ctx)
    window.contentView = NSHostingView(rootView: window.rootView)
    windows[ctx] = window

    // override exception handler
    let previousHandler = ctx.exceptionHandler
    ctx.exceptionHandler = { context, exception in
      if let previousHandler = previousHandler {
        previousHandler(context, exception)
      }

      let message = exception?.toString() ?? "Unknown exception"
      let stack = exception?.objectForKeyedSubscript("stack")?.toString() ?? "???"
      window.rootView.commands.addException(message: message, stack: stack)
    }

    // add log handler
    inst.logHandler = { message, level in
      Utility.executeOnMainThread {
        window.rootView.commands.addLog(message: message, level: level)
        window.rootView.commands.postChange()
      }
    }

    window.makeKeyAndOrderFront(nil)
  }
}
