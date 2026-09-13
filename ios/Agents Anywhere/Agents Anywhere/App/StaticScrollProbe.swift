#if STATIC_SCROLL_PROBE
import SwiftUI
import UIKit
import Textual
import Darwin

@main struct StaticScrollProbeApp: App {
    private let setup = StaticScrollSetup()
    var body: some Scene { WindowGroup { StaticScrollProbeView(setup: setup) } }
}

@MainActor final class StaticScrollSetup {
    let mode = ProcessInfo.processInfo.environment["AA_PERF_MODE"] ?? "markdown"
    let scenario = ProcessInfo.processInfo.environment["AA_PERF_SCENARIO"] ?? "mixed"
    let chat: SessionChatModel
    let groups: [ChatTimelineGroup]
    let actions: [String: TimelineTurnAction]
    let messages: [String]

    init() {
        let api = V2APIClient(serverURL: URL(string: "http://127.0.0.1:1")!, tokenProvider: StaticAuthTokenProvider(token: nil))
        let repository = V2SessionRepository(scope: .init(serverURL: api.serverURL, accountID: "probe"),
            detail: .init(sessionAPI: api.sessions, runtimeAPI: api.runtime, realtimeAPI: api.realtime),
            interactions: .init(runtimeAPI: api.runtime))
        chat = SessionChatModel(session: repository.session(id: "probe"), repository: repository,
            attachments: .init(attachmentAPI: api.attachments))
        let paragraph = "这是用于验证静态滚动性能的离线测试内容。页面已经停止输出，所有工具记录默认折叠。正文包含普通中文、English words、数字和常见的标点符号。我们记录实际布局次数，而不是根据代码结构猜测性能。每次对照使用相同的内容与滚动速度，不连接任何服务，也不会发送消息。"
        let code = (0..<18).map { "const item\($0) = await repository.load({ id: \($0), active: true }); // 静态代码测试" }.joined(separator: "\n")
        let scenario = self.scenario
        messages = (0..<3).map { turn in
            if scenario == "prose" {
                return (0..<10).map { "第 \(turn + 1) 轮第 \($0 + 1) 段。\(paragraph)" }.joined(separator: "\n\n")
            }
            return "第 \(turn + 1) 轮静态回复\n\n" + (0..<5).map { _ in paragraph }.joined(separator: "\n\n")
                + "\n\n```typescript\n\(code)\n```\n\n完成。所有内容保持不变。"
        }
        var items: [V2TimelineItem] = []
        func item(_ type: String, role: String? = nil, content: [String: Any]) -> V2TimelineItem {
            var object: [String: Any] = ["id": "row-\(items.count)", "sessionId": "probe", "type": type,
                "status": "done", "content": content, "orderSeq": items.count, "updatedSeq": items.count]
            if let role { object["role"] = role }
            return try! JSONDecoder().decode(V2TimelineItem.self, from: JSONSerialization.data(withJSONObject: object))
        }
        for (index, text) in messages.enumerated() {
            items.append(item("message", role: "user", content: ["text": "请检查第 \(index + 1) 部分。工具全部折叠。 "]))
            for number in 0..<4 {
                items.append(item("tool", content: ["kind": "command", "command": "rg test source-\(number)",
                    "output": String(repeating: "Finished tool output.\n", count: 120)]))
            }
            if scenario == "patches" {
                items.append(item("file_change", content: ["kind": "file_change", "changes": [["path": "src/file\(index).ts",
                    "action": "add", "content": code]]]))
            }
            items.append(item("message", role: "assistant", content: ["text": text]))
        }
        chat.timeline.presentOpening(items, pendingMessages: [])
        chat.prepareStaticScrollProbe()
        groups = TimelineGrouping.groups(chat.timeline.rows, interactionTargets: [])
        actions = TimelineTurnActions.build(groups: groups, suppressLatest: false)
        report(["event": "fixture", "mode": mode, "scenario": scenario,
            "visibleTextCharacters": messages.reduce(0) { $0 + $1.count }, "items": items.count,
            "toolsExpanded": false, "streaming": false, "selection": !TextualPerfProbe.noSelection])
    }
}

struct StaticScrollProbeView: View {
    let setup: StaticScrollSetup
    var body: some View {
        VStack(spacing: 0) {
            Text("\(setup.mode) · \(setup.scenario) · 静态滚动诊断").font(.caption).padding(8)
            if setup.mode == "timeline" {
                ChatTimelineView(model: setup.chat, onAttachment: { _ in }, onFile: { _ in })
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if setup.mode == "plain" {
                            ForEach(Array(setup.messages.enumerated()), id: \.offset) { _, text in
                                Text(verbatim: text).frame(maxWidth: .infinity, alignment: .leading)
                            }
                        } else if setup.mode == "groups" {
                            ForEach(setup.groups) { group in
                                SessionTimelineGroupView(group: group, chat: setup.chat, onAttachment: { _ in }, onFile: { _ in },
                                    turnAction: setup.actions[group.id])
                            }
                        } else {
                            ForEach(Array(setup.messages.enumerated()), id: \.offset) { _, text in
                                ChatMarkdownView(text: text)
                            }
                        }
                    }.padding(.horizontal, 24).padding(.vertical, 16)
                }
            }
        }
        .background(ProbeDriverView())
    }
}

struct ProbeDriverView: UIViewRepresentable {
    func makeUIView(context: Context) -> DriverView { DriverView() }
    func updateUIView(_ view: DriverView, context: Context) {}
}

final class DriverView: UIView {
    private var driver: StaticScrollDriver?
    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil, driver == nil else { return }
        driver = StaticScrollDriver(view: self)
        driver?.start()
    }
}

@MainActor final class StaticScrollDriver: NSObject {
    weak var view: UIView?
    weak var scroll: UIScrollView?
    var displayLink: CADisplayLink?
    var startTime: CFTimeInterval = 0
    var previous: CFTimeInterval = 0
    var phase: String = ""
    var intervals: [Double] = []
    var cpuStart: Double = 0
    var y: CGFloat = 0
    var direction: CGFloat = 1
    var heights: Set<Int> = []
    var offsetChanges = 0
    init(view: UIView) { self.view = view }
    func start() {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard let self, let root = self.view?.window else { return }
            @MainActor func descendants(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(descendants) }
            let views = descendants(root)
            self.scroll = views.compactMap { $0 as? UIScrollView }.filter { $0.contentSize.height > $0.bounds.height + 100 }
                .max { $0.bounds.height < $1.bounds.height }
            report(["event": "mounted", "views": views.count,
                "selectionViews": views.filter { String(describing: type(of: $0)).contains("UITextInteractionView") }.count,
                "scrollHeight": self.scroll?.contentSize.height ?? 0, "viewportHeight": self.scroll?.bounds.height ?? 0,
                "initialCounters": TextualPerfProbe.take()])
            guard self.scroll != nil else { report(["event": "error", "reason": "no scroll view"]); return }
            self.begin("idle")
            let link = CADisplayLink(target: self, selector: #selector(self.tick(_:)))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 60, preferred: 60)
            self.displayLink = link; link.add(to: .main, forMode: .common)
        }
    }
    func begin(_ phase: String) {
        self.phase = phase; startTime = CACurrentMediaTime(); previous = 0
        intervals = []; heights = []; offsetChanges = 0; cpuStart = cpuTime(); _ = TextualPerfProbe.take()
        report(["event": "begin", "phase": phase])
    }
    @objc func tick(_ link: CADisplayLink) {
        let now = CACurrentMediaTime()
        if previous > 0 { intervals.append((now - previous) * 1000) }
        previous = now
        if let scroll {
            heights.insert(Int(scroll.contentSize.height.rounded()))
            if phase == "scroll" {
                let limit = max(0, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
                y += direction * 20
                if y >= limit { y = limit; direction = -1 }
                if y <= -scroll.adjustedContentInset.top { y = -scroll.adjustedContentInset.top; direction = 1 }
                scroll.setContentOffset(CGPoint(x: 0, y: y), animated: false)
                offsetChanges += 1
            }
        }
        let duration: Double = phase == "idle" ? 3 : 12
        guard now - startTime >= duration else { return }
        let ordered = intervals.sorted()
        report(["event": "result", "phase": phase, "wallSeconds": now - startTime,
            "cpuSeconds": cpuTime() - cpuStart, "callbacks": intervals.count,
            "callbackP50ms": ordered.isEmpty ? 0 : ordered[ordered.count / 2],
            "callbackP95ms": ordered.isEmpty ? 0 : ordered[Int(Double(ordered.count - 1) * 0.95)],
            "callbackMaxms": ordered.last ?? 0, "callbacksOver25ms": ordered.filter { $0 > 25 }.count,
            "contentHeights": heights.sorted(), "offsetChanges": offsetChanges, "counters": TextualPerfProbe.take()])
        if phase == "idle" { y = scroll?.contentOffset.y ?? 0; begin("scroll") }
        else {
            link.invalidate(); displayLink = nil
            report(["event": "finished"])
        }
    }
}

@MainActor private func cpuTime() -> Double {
    var usage = rusage(); getrusage(RUSAGE_SELF, &usage)
    return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec)
        + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
}

@MainActor private func report(_ object: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
          let line = String(data: data, encoding: .utf8) else { return }
    print("AA_PERF \(line)")
    fflush(stdout)
    let url = URL.documentsDirectory.appending(path: "static-scroll.jsonl")
    if !FileManager.default.fileExists(atPath: url.path) { FileManager.default.createFile(atPath: url.path, contents: nil) }
    if let file = try? FileHandle(forWritingTo: url) {
        defer { try? file.close() }; _ = try? file.seekToEnd(); try? file.write(contentsOf: Data((line + "\n").utf8))
    }
}
#endif
