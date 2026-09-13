# iOS 静态滚动性能调查

2026-09-13。被调查的代码基线为 `cee18a69`，包含此前 Markdown 异步解析、静态字形绘制、附件缓存和命中测试优化。用户反馈：真机 iPhone 17，工具全部折叠，几千字、没有输出时滚动明显卡顿；Xcode 运行和 TestFlight / App Store 安装方式均有问题。

本分支是诊断分支，不是可直接合并的修复。它使用独立 bundle ID `com.agentsanywhere.scrollprobe`，替换应用入口展示合成离线内容。没有修改原工作区，没有安装到真机。

## 已确认的结论

1. 静态滚动的额外成本与 Textual 选择层的 `Text.LayoutKey` 读取路径直接相关，不能只看 `ChatMarkdownView.body` 或 Markdown parser 的调用次数。保留全部 27 个原生选择覆盖视图，只移除布局读取订阅，12 秒滚动的 CPU 时间从 2.389–2.524 秒降到 1.182–1.211 秒。应用层解析没有重跑时，SwiftUI 内部仍会进入文本布局查询和 TextKit 布局计算。
2. 原生 UIKit 选择覆盖视图的数量不是本次对照中的主要成本。单独去掉覆盖视图，保留布局读取，CPU 用量几乎不变。
3. 更换布局相等判断、只减少 `setLayoutCollection` 调用、在订阅内部跳过不可见段落的 GeometryReader，都没有取得明确的 CPU 改善，不能当作修复采纳。
4. 另有一个独立问题：消息仍标记为 running 时，即使不再收到文字，`isRevealing` 也不会按最后一批字形的截止时间结束，导致绘制时钟继续工作。它不依赖工具详情是否展开。
5. 在本次完全结束、离线的静态对照中，Markdown 解析、代码高亮、文件变更汇总没有随滚动持续执行。不能将这些路径定为本场景的持续滚动根因。

## 测试方法和边界

- iPhone 17 模拟器，iOS 27.0；Xcode beta；arm64 Release 构建，保留 Textual 的 `TEXTUAL_ENABLE_TEXT_SELECTION` 和 `TEXTUAL_ENABLE_LINKS` 编译条件。
- 固定的中文与英文合成内容。正文场景 4,347 字符、30 段；代码场景 6,072 字符，含 3 个 TypeScript 代码块。时间线场景复用真实 `ChatTimelineView`、消息行和折叠工具分组，包含 18 条记录；文件修改场景包含 21 条记录。
- 不连接服务，不接收 socket 事件，不播放附件，不加载真实账号数据。工具默认全部折叠。
- 首次挂载后等待 8 秒，再记录 3 秒静止和 12 秒往返滚动。CADisplayLink 请求 60 Hz，每次对原生 UIScrollView 调整 20 点 offset。
- CPU 秒数由进程 `getrusage` 用户时间与内核时间相加得到，是该段测试期间进程消耗的 CPU 时间，不是耗电量、单帧耗时或真机 FPS。
- 回调间隔用于发现主线程延迟，不能代表画面实际呈现帧率。多数稳定场景的 P95 约为 16.7–17.3 ms。模拟器没有复现用户真机上持续严重卡顿的程度。
- 原生 offset 驱动不是手指拖动：没有完整复现触摸命中、手势竞争、减速、侧栏动画、真实服务的后台事件以及整套应用外层界面。
- 启动阶段捕捉到 `AnyTextLayoutCollection` 和 `OnScrollGeometryChange` 的同帧重复更新警告；这些警告不能直接等同于稳定滚动阶段的每帧问题。
- 两份 5 秒的 `sample` 调用栈单独采集，采样期间的计时结果不混入下面的性能比较。
- 共保存 25 次完整运行、50 个测量阶段。大多数运行开启相同的诊断计数器；最后另做两次关闭计数器的对照，CPU 差值仍然存在，见下表。
- 最初一次校准误覆盖了 Swift package 的编译条件，未启用选择功能。通过挂载的选择视图计数发现后已修正，那组数据已排除。
- 后期实验结束时，通过原生 UITextInput 检查当前可见覆盖视图能否返回完整文字范围、最近文字位置和有效光标矩形。这只是接口冒烟检查，没有验证实际长按、拖动选择和复制交互。正常选择层和可见性实验没有检查失败；关闭布局读取后，6–7 个可见覆盖视图全部失败，这是预期的功能损失，进一步说明该诊断开关不可作为修复。

这次区分视图 body 更新与系统几何、文本布局工作，参考了 [Apple 的 SwiftUI 性能分析文档](https://developer.apple.com/documentation/xcode/understanding-and-improving-swiftui-performance)。

## 对照结果

每项均为约 12 秒滚动，以下为实测进程 CPU 秒数。

| 内容和开关 | CPU 秒数 | 解释 |
| --- | ---: | --- |
| 4,347 字符，原生纯 Text | 0.446 | 校准基线 |
| 同内容，当前 ChatMarkdownView | 1.882 | 30 个选择覆盖视图 |
| 同内容，完全关闭选择层 | 0.906 | 正文仍完整保留 |
| 6,072 字符与代码，当前 ChatMarkdownView | 2.258 | 代码高亮已完成 |
| 同内容，完全关闭选择层 | 0.905 | 高亮内容仍保留 |
| 真实时间线，代码与折叠工具 | 2.389–2.524 | 多次控制运行 |
| 同时间线，完全关闭选择层 | 1.196 | 诊断对照，不是产品方案 |
| 带文件修改的折叠工具组 | 2.456 | 统计仅挂载时计算 3 次 |
| 用解析后的坐标判断布局相等 | 2.375–2.476 | 设置次数减少，CPU 没有改善 |
| 只给可见段落创建布局集合 | 2.388–2.466 | 仍常驻订阅 Text.LayoutKey |
| 只移除原生 UIKit 选择覆盖视图 | 2.408 | 布局读取仍保留 |
| 布局集合与原生覆盖均按可见性处理 | 2.425 | 订阅仍在，未形成有效改善 |
| 保留全部原生覆盖视图，只移除布局读取订阅 | 1.182–1.211 | 两次重复，选择功能失效；用于定位 |
| 当前时间线，关闭诊断计数器 | 2.537 | 复核计数器自身开销 |
| 只移除布局读取订阅，同时关闭诊断计数器 | 1.272 | 差值仍约为一半 |

完整逐次结果见同目录 `summary.csv` 和 `results/`。变量隔离实验只是定位工具。关闭选择层或布局读取会损失选择功能，不能作为正式修复直接使用。

## 证据链：停止解析之后，仍有文本布局查询

4,347 字符场景在约 720 次更新中记录了：

- `LiveTextLayoutCollection` 创建 21,600 次，即 30 个段落每次滚动都参与，包括离屏段落。
- 布局比较 86,400 次，`setLayoutCollection` 调用 21,600 次。
- `markdown.parse`、`markdown.body`、`fragment.body` 在稳定滚动阶段均为零。

代码与工具时间线中同样出现约 19,000 次布局集合创建。应用自己的 Markdown 和高亮计数没有增加，但采样主线程出现以下链条：

```text
GraphHost.flushTransactions
  AG::Graph::UpdateStack::update
    TextLayoutQuery.value.getter
      ResolvedStyledText.TextLayoutManager.layoutValue
        prepareLayoutManager / computeMetrics
          NSTextLayoutManager.ensureLayoutForRange
```

开启选择层的 5 秒采样中，这一条主线程分支出现 211 个 `TextLayoutQuery` 样本，包含 56 个 `ensureLayoutForRange` 样本；关闭选择层的独立采样中未出现这两个符号。这里是包含子调用的样本数量，不是调用次数或精确耗时。

入口位于 `Packages/Textual/Sources/Textual/Internal/TextInteraction/Shared/TextLayout/View+TextLayoutCollection.swift`：`overlayPreferenceValue(Text.LayoutKey.self)` 外面常驻，内部通过 GeometryReader 构造布局集合。上层 `TextSelectionInteraction.swift` 将其与选择模型绑定。段落和代码通过 `View+Textual.swift` 的 `textSelectionScope()` 接入；普通工具文字通过 `ChatSelectableText` 的 InlineText 接入。

相等判断改用真实布局与局部坐标后，时间线的 `setLayoutCollection` 从约 19,000 次降至约 150 次，CPU 没有下降。这说明重计算发生在业务回调之前，仅在回调末尾去重无法消除成本。

可见性实验把布局集合创建降至约 3,450 次，甚至减少了原生覆盖视图数量，CPU 仍约 2.4 秒。该实验只是把条件放进 `overlayPreferenceValue` 的内容闭包，仍然保留整个文本布局偏好的订阅。因此不能声称它已经实现了有效的离屏工作隔离。

最后的变量隔离保留全部 27 个 UIKit 选择覆盖视图，在外层绕过 `overlayPreferenceValue(Text.LayoutKey.self)`。内容高度保持 5,035 点，CPU 时间两次分别为 1.182 与 1.211 秒，接近完全关闭选择层的 1.196 秒。反过来，只移除 UIKit 覆盖视图、保留读取订阅时为 2.408 秒。两组相反的隔离结果与采样调用栈一致，把额外工作定位到系统文本布局查询路径。禁用读取后选择模型没有文字布局，因此不能据此宣称保留了选择功能。

为排除诊断计数器影响，再将计数器关闭：当前路径消耗 2.537 CPU 秒，只移除读取订阅后为 1.272 CPU 秒，约减少 50%。因此这个差值不是大量计数操作造成的。上述实验没有提供统计置信区间，数值用于判断显著的相对差异，不用于承诺真机帧率或精确耗电改善。

## 证据链：running 但没有新文字

完全结束的时间线，静止 3 秒消耗约 0.015–0.022 CPU 秒，绘制与 Markdown 测量入口没有活动。

最后一条消息仍为 running、接收过一次追加后不再更新：同样静止 3 秒消耗 0.426 CPU 秒，记录到 `glyph.draw = 180` 与 `block.sizeThatFits = 180`。滚动 12 秒约 2.973 CPU 秒，记录到 717 次字形绘制和测量入口调用。

`block.sizeThatFits` 是测量函数入口计数，其中仍可能命中现有缓存；不能把这个数字描述成 180 次完整文本重排。

原因位于 `Models/Chat/SessionTimelinePresentation.swift` 的 `flush` / `settle`：超过 `settlesAt` 之后，仍要求 `!value.isStreamingText` 才关闭 `isRevealing`。`StreamingGlyphReveal.swift` 则以这个状态决定 `TimelineView(.animation)` 是否暂停。运行状态与当前是否还有新字形需要动画被绑定在一起。

这一场景与已完成会话必须分别处理。本探针没有启动完整 repository 的 presentation 循环，因此没有把真实应用每秒 30 次的额外扫描成本计入这里。

## 修复应针对的边界

优先处理选择布局获取机制：避免在普通滚动过程中让每个段落常驻订阅 `Text.LayoutKey` 并触发系统布局查询。保留完整内容、选择和复制；若采用按需获取或缓存，必须验证真实文字变化、宽度变化、附件、代码横向滚动及选择拖动时的坐标正确性。

另行解除运行状态与字形动画寿命的绑定：最后一批字形完成后应停止绘制时钟；有新追加时再恢复。验证长时间等待工具、尾部代码、离屏活动消息及重新开始输出，保持文字位置和显示内容稳定。

验收需要在真机的 Release / TestFlight 上，使用停止输出、全部工具折叠的几千字会话验证连续滚动和侧栏交互。当前实测足以确定需修复的额外工作路径，但不足以认定真机严重卡顿的所有贡献项，尤其真实后台事件和触摸过程尚未采集。

## 复现诊断

本诊断分支的 Xcode app target 单独启用 `STATIC_SCROLL_PROBE`。不要用全局 `SWIFT_ACTIVE_COMPILATION_CONDITIONS` 覆盖依赖包定义。

```sh
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
xcodebuild -project 'ios/Agents Anywhere/Agents Anywhere.xcodeproj' \
  -scheme 'Agents Anywhere' -configuration Release -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/aa-scroll-build \
  CODE_SIGNING_ALLOWED=NO PRODUCT_BUNDLE_IDENTIFIER=com.agentsanywhere.scrollprobe \
  ONLY_ACTIVE_ARCH=YES ARCHS=arm64 build
xcrun simctl install booted '/tmp/aa-scroll-build/Build/Products/Release-iphonesimulator/Agents Anywhere.app'
python3 ios/scripts/probe-static-scroll.py
```

`AA_PERF_DEVICE` 可指定已启动的模拟器，`AA_PERF_OUTPUT` 指定结果目录。`AA_MATRIX_CASES` 可覆盖串行运行的对照列表，格式是 `[[mode, scenario, selection, equality, label, extraEnvironment]]`；后三项可省略。所有额外环境变量使用 `SIMCTL_CHILD_AA_PERF_*` 形式传入 simctl。

`cases.json` 保存本报告各次运行的环境开关。重跑整组时可使用 `AA_MATRIX_CASES="$(cat ios/Tests/StaticScrollAudit/cases.json)" python3 ios/scripts/probe-static-scroll.py`，并设置新的 `AA_PERF_OUTPUT` 目录保留原始测量。

诊断探针与开关位于 `App/StaticScrollProbe.swift` 和 Textual 包内的 `TextualPerfProbe.swift`。采样、构建日志和截图保留在本机独立证据目录，没有提交包含设备路径的原始调用栈。
