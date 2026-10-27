# 0.1.0 预览版验证报告

更新时间：2026-10-28，Asia/Shanghai。本报告分别记录本机执行、CI 和真实桌面边界，未运行不算通过。[本轮原始本机证据](validation/macos-preview-20261025.json)。

## 2026-10-28 Alt+D 严格冷启动、精确内容和竞态复核

| 执行 | 原始结果及解释 |
|---|---|
| 浏览器653/40541154743 |48required；30rows含6准备失败，实际helper24次/23通过，18项未执行。Edge首次真实鼠标选区DOM精确却UIA超时；未预热/强制AX/重试。contenteditable准备修正另测，原红保留 |
| 剪贴板653/40541158106 |3执行/1通过；背景同PID发布及真实第二Ctrl+C均被误当原选文，helper恢复旧clipboard；后续源实际原copy发布的时序确认覆盖 |
| 实际App0e0/40542535831 |15/16执行，raw8pass含负向误判，至多7有效pass。同窗口A请求晚读B已产生1请求+1历史；固定empty保留旧文且不聚焦，5鼠标准备失败0hotkey |
| Notepad830/40542927823、08/40543536555 |均0hotkey，未验收；第二次保留NOTEPAD_CLASSIC_EDITOR_NOT_UNIQUE和独立清理错误，不附着不同PID/替换生成应用冒充 |
| 候选4385本机 |224Rust/1引擎专用ignored、76前端/类型/构建/完整假IPC UI通过；C#5/net48、PS AST0；不等于真实Windows或物理取词 |
| full4385/40544606324 |failure保持。11门禁9success/2failure（旧快捷键UI准备0case；当时严格App11/16）。Windows228Rust/1ignored、NSIS安装、6实际模型及3安装后链通过 |
| 4385严格App补测6300/40549765310 |同一不可变stage SHA6684d75f…bd6/5,809,152B，无重建，16/16通过；7次真实鼠标拖选，单Alt+D精确文本+请求+历史，固定连续更新、空框直接输入、编辑取消、原生焦点变更取消、管理页保留。不是810完整程序验收 |
| 浏览器4385/40544606772、11b/40545865325 |各48实际/42通过、0setup失败；6fresh首次全失败。11b明确其余快速失败是Document→Group的RuntimeId不等，非异常取ID；6冷启动不算通过 |
| 浏览器cac/40546585120 |改普通FocusedElement→同元素GetUpdatedCache，48实际/47通过，冷5/6；首例2秒截止，其他35正例和12空/password负例通过，所有FG/富clipboard保持 |
| c74诊断/40548339120 |保留2秒失败后，受控诊断只观察已废弃同一worker：调用2185.9692ms返回，未启动新RPC/未复用结果。不把迟到返回当完整选文成功 |
| 浏览器810/40550008786 |共享5秒预算，48实际/47通过，冷5/6，0setup失败。首次query1约2297ms成功返回Pane，query2约17ms返回Group，严格身份拒绝；没有超时，不能靠延时宣称修复。剩余预算单调递减，FG/clipboard全保持 |
| 来源根初始化8e/40553539117 |48/47、冷5/6、0setup失败；新增两次root UIA调用未解决Pane→Group，所有前台/富剪贴板/0copy仍成立。29行无效对照撤回，原红保留 |
| 获焦MSAA初始化93b/40555594514 |48实际/42通过、冷0/6；6次nativefocus实为root，MSAA均S_OK/nonnull但Pane→Group身份失配，未超时。该初始化回归后精确撤回，未称有效激活/修复 |
| 剪贴板810/40550008709 |3执行/2通过：基线、实际第二Ctrl+C取消且不覆盖通过；背景同PID发布仍错文+helper恢复覆盖，原始failure保留 |
| 预算8e/40553539766 |8/8、42断言通过；共享预算允许2213.93ms调用，累计709.67ms截止后不启动新query/迟到RPC，独立标量保留2005.80ms截止。复制在截止后仍先恢复、恢复失败优先、新复制不恢复。全为精确私有worker与模拟策略，不是真实UIA提供者/clipboard/input |

当前没有新版安装器交付。标准clipboard API不能给任意后台发布提供本次Ctrl+C事务身份；现有兼容回退保留此边界。native HWND焦点不覆盖每个DOM变更。实体Win10/11、WPS、IME/多屏/提权窗口未验收；本轮Windows为GitHub-hosted Server桌面。未修改Mac安装、签名、TCC、钥匙串或用户凭据。[精确证据](validation/windows-selection-rigorous-20261028.json)。

## 2026-10-28 latest-intent：同一程序的固定连续操作通过，浏览器范围部分待验收

| 检查 | 实际结果与边界 |
|---|---|
| 本机/构建 |224 Rust passed/1引擎专用ignored，76前端单位/类型/构建/完整假IPC UI passed；Windows228 Rust/1ignored，Mac与前端CI成功 |
| 原full40529706953 |原9gate保留6success/3failure；实际NSIS离线6模型+取词/空框输入/OCR3链通过。选词夹具引用漏项0/11、固定夹具空间不足0/4、旧shortcutUI启动PowerShell超时0实际case，均未算通过 |
| native补测40530892064 |产品未变，显式接口引用修正后11/11真实UIA/剪贴板与8/8精确生产输入桥通过 |
| exact4cf补测40535341400 |生产源diff为空、stageSHA86373b0c…cf03/5,784,064B硬核对；固定2次新选词、AltS→AltS、AltS→AltD无需Esc，4/4及7条不同历史通过，旧helper退出/0overlay/0底层OCR点击/源前台保持 |
| 固定持续性/延迟 |428采样hidden0，maxgap25.845ms；capture affinity实读17。OCR松手→history696ms，包含识别/界面/mock翻译；不是所有实机或原版对照。非重叠ROI不证明遮挡处像素排除 |
| 真实浏览器 |40533405895正文首次真实helper成功，次场景setup主窗判定失败；40535344819首场景pre-helper UIA查询2s超时，整体4场景未验收。该冷控件限界可能与产品同样2s上限有关，不能简单说产品无关，也未构成已执行helper失败 |
| 分发审核 |75,306,581B/eeb16b91…安装器已交付；API ZIP摘要/大小/CRC、唯一EXE、安装后仅3B NSIS marker、对应source2105成员CRC/2104清单文件hash独审通过。无新增依赖/模型/运行时 |

[精确JSON](validation/windows-latest-intent-20261027.json)保留原始失败与补测身份。预览不是stable；实体Win10/11/消费应用、IME/全屏/多屏仍需验收。未安装/签名Mac、改TCC/钥匙串或启动停止的VM。

## 2026-10-27 原生输入接管：新预览已交付，等待实体Win11验收

最新候选1820f4e已实现独立原生输入会话：复用Rust消息泵，每次捕获前刷新一次鼠标钩子；用随机会话编号、实际子进程PID和私有标量消息连接OCR窗口。应用路径停用托管鼠标钩子；保持源应用焦点，保护预持按钮和全部匹配释放，助手退出后继续吞掉已接管的迟到松开。Windows先启动原生消息队列再注册快捷键。独立源代码审查未发现剩余阻断；本机211项Rust通过/1项真实模型专用测试ignored，76项前端单位与完整隔离UI回归通过。Alt+D的设置锁丢弃首次快捷键和启动监听前丢选文两处已修正，仍待新安装版Windows验证。

真实Windows原生定向40516999432/1820f4e raw门禁OCR/DLL/delegatedCapture全部success，8/8实际输入场景通过：首次立即松开、普通窗口抢回置顶、外线程已捕获鼠标、900ms跨两个窗口拖动、源应用预持按钮释放、Esc配对释放、助手已退出后延迟1600ms才松开、同宿主下一次捕获。各场景底层新down/up/click均0，匹配像素/自由ROI/取消及清理断言保留。实际使用backend3，managedhook及plane按钮计数0，确认没有借旧路径冒充新机制。它是Server受控生成窗口和真实生产输入模块测试，不是Tauri安装版或实体Win11/WeGame全应用验收；完整构建40516999533现已结束：Windows215项Rust/1ignored、Mac211项Rust/1ignored、前端76项及完整隔离UI通过；Windows原始8门槛7项success，shortcutsUi在应用启动前测试工具PowerShell15s超时，故完整run仍为failure。新机制8项、实际取词/空框输入/OCR3链、浮窗核心和真实NSIS安装后的6模型+3离线链均通过。

历史失败保留：真实Windows40513309819已编译新原生模块，但首条夹具控制命令协议失败，0项有效捕获。修正夹具UTF-8写入后，40515584043已完成8次助手启动；全部在约0.5秒内以NATIVE_ASSEMBLY退出，未创建选择窗口，故仍是0项有效框选。相同DLL的OCR/加载检查通过；正在核对harness canonicalize产生的Windows长路径前缀与PowerShell/.NET加载及路径归属校验的兼容性。不能据此称原生接管已修复实体Win11/WeGame，也不能把原先托管路径的通过结果算给新路径。

历史0a包快捷键真实UI诊断的中完整性实验40513309471在Node路径选择前失败；修正后40515583842已核验Node为MEDIUM8192，但在启动应用前的PowerShell命令15s超时。一次标准Windows环境修正后的40517000056仍在应用启动前PowerShell15s超时；真实设置录入UI仍未完成验收，保留failure并转后续手工验收，不继续放宽门槛。不改CDP/总超时、系统安全规则或产品开发者工具；原失败全部保留。[新版x64安装器](/Users/wwq/Documents/Codex/2026-10-24/ni-ne/outputs/EchoLingo-installers/windows-preview-20261027-native-input/EchoLingo_0.1.0_preview_20261027_native-input_x64-setup.exe)已下载并核对API ZIP完整SHA/size/CRC、包内唯一安装器及真实NSIS验收报告身份：75,285,569B/SHA256fafb95ebd831dcf5fa9348c72665f715915ff7381893a2ec9c53dc0b14570f65。引擎对应源码另附19,272,655B/SHA66ce29624429bfdcdb4f265815402e9bd2a8b324535bc1d9d13bcfa267d8fd3c，与本轮CI报告完全相同。已直接向机主提供安装器链接供实体Windows11/WeGame测试；旧5731bb78包仍保留机主确认的穿透/首次取词缺陷，不再当作本轮新版。未签名预览，未发布stable/公开Release。Mac规范应用未安装、签名或变更权限。

## 2026-10-27 owner-tested input-repair preview still fails on WeGame; Alt+D first attempt unreliable

The owner confirms installing the exact newly supplied input-repair package and fully exiting the old process. Alt+S still clicks through on WeGame. They also report Alt+D often needs two presses to obtain selected text. These are current physical acceptance failures, not a stale-version assumption or something controlled Server passes can override. The delivered5731bb78 installer remains an immutable preview with known remaining defects; do not call either workflow universally fixed.

New generic counterexamples are confirmed in actual Windows run40507078098/source30aca7e: hybrid2/2 passed, but forced-no-hook planeOnly2/2 failed. A generated ordinary topmost window re-raised immediately before input received1down/1up/1click; a generated source with existing capture received1down/1up even though the plane also received1down/1up and completed a region. Thus plane visibility/TOPMOST style/hit-test or observed plane events do not establish exclusive input ownership. The250ms Z-order repair cannot prevent these first-event races. This is a general failure, not a WeGame-specific patch requirement. WeGame elevation/anti-cheat/hook-loss is not proven; optional lastCaptureHealth metadata remains pending. Independent actual-foreground+SetCapture and same-user MEDIUM-helper/HIGH-source experiments are frozen and dispatched as separate raw gates in40508548973/source9acdf4a; neither is a production correction or universal acceptance.

Independent run40508548973/9acdf4a remains failure: original live/OCR/DLL raw success; ownership/activeExperiment/integrityBoundary raw failure. Active+SetCapture passed takeover of a pre-existing foreign capture, but failed against repeated topmost re-raising: source received1down/1up while picker had verified actual foreground/capture before the down;42raises, plane1down/1up but zero-size selection and capture loss. Thus simply activating the overlay is not the correction. Its Esc down0/up1 is separately unclassified fixture behavior; new-foreground cleanup passed. Synthetic same-user MEDIUM8192 helper/HIGH12288 source had1readiness failure+3zero-underlying-input/35×15ROI passes, with22–23s spent in initial Add-Type assembly loading; not proof elevation causes the owner failure. A new native Rust session hook on the existing message pump, refreshed once before capture and paired with a validated child mailbox, is being implemented to replace the managed mouse hook in the actual app path. Preserve passive source focus; no per-app branch or security-policy change. The previous fallback is not treated as exclusive input ownership.

Alt+D has a confirmed silent-discard code path: settings.try_lock() after accepting a shortcut could lose the first press during settings/history persistence. Commit a57b91b replaces dispatch settings access with registered-route snapshots; host61shortcut Rust tests pass, independent review and full Windows app validation remain pending. A second startup source-event/listener race is being repaired with memory-only epoch/delivery-ID retention. No new app replacement or package yet. Exact-binary UI diagnostic40505400539 also failed before any keyboard sends (CDP ECONNREFUSED with app and WebView child running), so actual shortcut-recorder UI acceptance remains unknown.

## 2026-10-27 Windows input repair: preview packaged for owner testing; full CI retains one failed gate

[Download x64 installer](/Users/wwq/Documents/Codex/2026-10-24/ni-ne/outputs/EchoLingo-installers/windows-preview-20261027-input-repair/EchoLingo_0.1.0_preview_20261027_input-repair_x64-setup.exe):75,249,159B/SHA2565731bb781591f4acd4eb6bb2eeeecae3ac335e2b9b8c53d87a47b3c07b2b8041. [Instructions and remaining tests](/Users/wwq/Documents/Codex/2026-10-24/ni-ne/outputs/EchoLingo-installers/windows-preview-20261027-input-repair/README.zh-CN.txt). Corresponding engine source is separate19,272,655B/SHA66ce29624429bfdcdb4f265815402e9bd2a8b324535bc1d9d13bcfa267d8fd3c; no source download is needed to install. Unsigned preview, no stable/public release. Owner explicitly requests the package first for physicalWin11 self-testing; the link has been supplied.

Application0a08830f8286a2d54aa658c8876b013a8b1696b1 ([full40502410316](https://github.com/Blueeeecho/EchoLingo/actions/runs/40502410316)) has Windows200Rust/1resource-specific ignored,Mac204Rust/1ignored,71frontend units and complete isolatedUI pass. Actual Windows raw runtime outcomes: shortcut CLI/live/performance/app3chains/popup/installedoffline all success; **shortcutsUi=failure**, so the fullWindows job and run remain **failure**. Its first real packaged WebView/registered-key recorder fixture failed after32s; PowerShell Stop truncated the Node stderr before preserving the underlying error. Cause is unknown; do not label a product or fixture root cause, or count real recorder UI acceptance as passed. Only a separate unchanged-exe diagnosis may supplement this result. Installer conflict wizard itself is not interactively accepted.

Actual NSIS installed into a Chinese path under verified app/engine outbound blocking, passed6real offline model cases and3installed selected-text/empty-popup typing/Alt+S left-drag WinRT OCR→automatic offline translation→history chains. It classified the actual no-redirection input plane and exact blue screen/hover edges. Native [40499607585](https://github.com/Blueeeecho/EchoLingo/actions/runs/40499607585) hybrid9/9+forced-no-mousehook planeOnly9/9 passed, including900ms independent ordinary A→B drag,zero underlying events/button clicks,zero blue captured pixels,source foreground,cancellation and cleanup. Same-runner full A/B also passed all3variants. PhysicalWindows10/11/WPS/consumer browser,IME/multiscreen/mixedDPI/elevated-installer/secure-desktop and pinned capture-exclusion acceptance remain open; generated Server2025 fixtures do not override the owner's earlier realWin11 failure.

Implemented: per-display transparent Win32 NOREDIRECTIONBITMAP/NOACTIVATE/TOPMOST input plane to receive client mouse events without relying solely on the low-level hook; no bitmap/GPU framework or new runtime. Preserve live readability/freeleftdrag/thin guidance and capture cleanup. Remove the Windows180ms delay; embed/verify a build-time Framework DLL on every load, avoid operation-time C# compilation, coalesce move wakes and reduce duplicate edge changes. OCR-only Han spacing/softwrap/paragraph repair preserves code/Latin/raw restore and typed/history text. Two prominent shortcut recorders/manual editors use a bounded registered-key bridge, transactional registration/persistence and rollback. Installed-exe early probe checks all5enabled bindings with the same startup settings migration/validation, distinguishes unknown from conflicts and never starts Tauri/WebView or reads credentials. NSIS hook offers explicit settings on interactive conflict/unknown; the hook does not launch in silent/passive mode, though upstream /R explicitly can.

Measured same-runner helper readiness median654.4→559.3ms/P95817.6→569.6ms, excluding the separately removed180ms app delay. Burst visible-update median31.9→16.4ms, P9537.44→37.46ms; CPU46.875/1535ms→93.75/1503ms. No-hook candidate median560.4ms and dragP9531.84ms/CPU125ms. These are one controlled comparison, not guaranteed physicalWin11 speed-ups; CPU increased in this sample.

API ZIP size/digest/CRC, exact complete embedded native DLL and full frozen helper, stage046a33fd…/installedbf715dad… exact3-byte NSIS marker difference verified. Actual installed runtime allowlist48files includes7models/104,470,603B,38licensefiles/36notices;195,072B build metadata excluded. Installer increased38,255B over prior75,210,904B after new input/shortcut code; actual installed116,870,483B. Separating the19.27MB corresponding source reduces the required download, not installed model size. Source inventory/licensing and independent package audit are preserved.

Earlier full40495244597(geometry),fast40497120651(longdrag guard),40498805516(testpeer hiddenowner),full40499606943(build metadata cmdlet),full40500894203(stale Windows F12 test) remain failed;40500330683/40502259353 were canceled with explicit reasons. Corrections and actual later passes are attributed separately. No Mac sign/install/TCC/Keychain/API credentials or stoppedWin10VM action occurred; canonicalMac7eafe813 hash read unchanged. Original34source/test/config files were safely synced with previous-hash guards, preserving unrelatedMac/Harmony edits. [Exact validation](validation/windows-input-repair-20261027.json).

## 2026-10-27 Windows 悬停窗口蓝框：受控实测与预览包完成

Windows Alt+S保留当前屏幕蓝边，悬停时增加实际应用窗口蓝框；桌面/任务栏或不确定目标只保留屏幕框。左拖清除悬停提示，仍按实际任意区域OCR→填入原文→自动翻译。使用每屏12个薄边HWND、80ms元数据查询，不在hook线程枚举，不取标题/文本/截图、不抢焦点或增加授权。独立审阅发现的disabled遮挡歧义已在实测前修正。

| 实际检查 | 结果 | 范围 |
|---|---|---|
| 完整CI40481264703/live |8/8通过；A→B、419.7ms disabled B正确框、真实Shell_TrayWnd回退仅4边、回B、按住左拖隐藏hover、12distinct HWND、320×220自由ROI、7/7 RGB无蓝边入图 |WindowsServer2025受控生成窗口；单屏 |
| 原full其他desktop |popup全部核心行为/第二实例、真实NSIS安装、6模型和安装后选词/空框/左拖OCR自动离线翻译通过 |真实程序与模型；不等于Win10实体机 |
| 原full应用夹具 |前2链通过后，旧count==4 readiness超时，故原full正确保持failure；没有记录当时实际边数 |该错误未被COE结论掩盖 |
| 仅夹具ef27367定向40483707524 |源码未改+stageSHA199d3f29…硬校验；3实际链和源窗口/PID/physicalpointer/DWM稳定/唯一directchildhelper/screen4+hover4精确几何全部通过，清理true |同一原始程序，无重建；mock翻译，与原full真实离线模型检查分开 |
| 常规回归 |142WindowsRust/146MacRust，各1ignored；61frontend、完整隔离UI；实际nativeOCR/选词剪贴板、76策略(30hover)通过 |不外推消费应用/物理多屏/流畅度 |
| 分发完整性 |API ZIP SHA/size/CRC、完整冻结helper payload、stage与installed仅3bytes NSIS marker差异、对应source ZIP及最终5members逐字节检查通过 |未签名预览，未发布稳定或公开Release |

[新版完整下载包](/Users/wwq/Documents/Codex/2026-10-24/ni-ne/outputs/EchoLingo-installers/windows-preview-20261027-hover-window/EchoLingo_0.1.0_preview_20261027_hover-window_windows_x64_with-source.zip)：94,674,254B，SHA256a6c99dbdc1908b108731e481c87ff554b84371868c272cde3937bfaa9d06328b。内含75,210,904B NSIS(293a2648…)及19,456,259B引擎源码(b82a524a…)、说明/精确摘要/校验表。轻量离线模型对技术标识符/路径质量有限，不以非空输出当高质量翻译。

Mac对应功能未实现，canonical7eafe813只读hash不变，未签名/安装/重启或申请权限。已停止的本机Win10VM未重启、不作新版验收。Win10实机性能/字体/IME及消费环境、WPS/Edge、物理多屏/混合DPI、实际提权安装窗/安全桌面和固定自身窗口排除仍待验收。[完整证据](validation/windows-ocr-hover-20261027.json)。

## 本轮完成

| 验证项 | 结果 | 覆盖与限制 |
|---|---|---|
| 干净依赖安装、类型、生产构建 | 通过 | npm ci、npm run check、npm run build；实际 Tauri 优化构建与应用签名校验通过 |
| 前端单元测试 | 45 项通过 | 模型、凭据域、预设、捕获换行与原样输入 |
| 前端 UI/IPC 回归 | 通过 | 保存重入、空选区、IME/Enter/重复键、编辑/清空/停止/Esc/关闭/原生隐藏取消、编号分配前隐藏、陈旧事件/延迟布局、重开输入、隐私与错误保留；使用假 IPC，不是安装版桌面验收 |
| Rust | macOS 本机 50 项通过 | 真实本地 HTTP 断连、取消排序屏障、当前隐私设置、简繁目标/拒绝不回退、原子文件失败保留、历史计数/字节/超大单条、凭据隔离、签名、静态原生 OCR/ABI |
| 安装与回滚工具 | 22 项通过 | 临时虚构 bundle；签名/复制失败、改名失败、回滚及失败恢复、路径别名、同名进程拒绝、禁止重复启动；不伪装为真实签名测试 |
| 依赖安全审计/格式/diff | 通过 | npm audit 0 vulnerabilities；cargo fmt --check、git diff --check |
| macOS 原生 CLI | 通过 | 真实 Vision 识别 EchoLingo translation 2468，私有多项剪贴板恢复、PNG 8 MiB 边界、段落/代码/异常几何；不改用户通用剪贴板、不请求权限 |
| macOS 静态入口 | 通过 | 实际生产桥接、Unicode/NUL、进程身份与权限白名单；后台 Rust 线程明确跳过 AppKit 私有剪贴板夹具，该项由 CLI 主线程另验 |
| 最新 Windows 原生与 Rust CI | 通过 | 49 项 Rust，含真实独占文件锁替换失败及重试；真实系统 OCR 与 WinForms 选文/空选区/复制回退/富文本恢复/密码框拒绝；clipboardRestored=true，不含交互截图和多屏 |
| 最新双平台 CI 安装包 | 通过 | run 40172215129，Windows NSIS 与 macOS DMG 均生成；前端交互/Python 夹具任务也通过 |
| 本机打包 | 通过 | 优化 Apple Silicon .app 与 DMG；ad hoc 签名完整性通过，DMG hdiutil 校验有效 |
| 固定路径真实安装 | 通过 | ~/Applications/EchoLingo.app，签名/可执行文件摘要校验，Launch Services 后台启动；未删除开发与旧回退副本 |
| 默认静默启动 | 通过，元数据范围 | 启动并静置采样后，普通屏上窗口数为 0，前台应用不是 EchoLingo；不等于浮窗渲染或全部桌面交互通过 |
| 安装版交互自动化 | 未完成 | CUA 选择完整应用路径超时；bundle ID 因开发副本重复而有歧义。没有据此判定应用白屏，也不将浏览器回归替代安装版验收 |

## 本机性能记录

环境与原始八次采样见 JSON 证据。macOS Apple Silicon；应用保持默认隐藏。只采主进程，不含单独的 WebKit/系统进程。

- 优化可执行文件：4,906,848 字节；完整 app：5,011,832 字节。
- 空闲主进程 RSS：中位 97,536 KiB（约 95.25 MiB），最高 97,584 KiB；8 次约 1 秒间隔采样，区间单核 CPU 平均 0.123%。
- 启动请求到系统观测到对应进程：114.89 ms；不是托盘就绪、WebView 第一帧或真正冷启动时间。
- 构建结束后的 5 次生成图 Vision 识别：120.749 / 96.287 / 95.984 / 92.893 / 98.588 ms，中位 96.287 ms。范围仅为 1100×160 生成图的 Vision 调用，不含画图、框选、启动或网络。
- 并行构建/原生测试期间第一批采样曾出现 24,548.988 ms，随后 4 次约 92–112 ms；原始异常保留。原因未确认，不宣称冷启动 OCR 已达标，也不只挑选较快结果作为完整性能结论。

## CI 证据

- [run 40172215129](https://github.com/Blueeeecho/EchoLingo/actions/runs/40172215129)：本轮 3ec4f81，Windows/macOS/前端三任务全部通过；Windows 49 项 Rust（含真实文件锁用例），Mac 50 项 Rust，两个平台安装包均产出。[草稿 PR #1](https://github.com/Blueeeecho/EchoLingo/pull/1)。远端源码树 026e2c8de64697d7a3a9e9f7c7300de83df83564 与本机已测试树完全一致。
- [run 40167604502](https://github.com/Blueeeecho/EchoLingo/actions/runs/40167604502)：main 的 856e1a7，空弹窗、Enter 与静态原生权限修复的 Windows/macOS/前端三项通过。此记录早于本轮补强，不能替代当前分支 CI。
- [run 40102326336](https://github.com/Blueeeecho/EchoLingo/actions/runs/40102326336)：e15deaa，极简弹窗、换行整理、Windows 原生 OCR/选文/剪贴板受控冒烟与双平台安装包通过。
- 本轮 codex/preview-hardening 的 macOS CLI 私有剪贴板与 Python 安装回滚夹具也已实际执行通过。Mac CI 的生成图识别计时约 1,047.9 ms，再次说明本机热运行中位值不能代表所有环境或冷启动。

Windows 受控冒烟操作临时 WinForms 测试窗及该测试桌面的剪贴板，不读取用户应用。真实独占文件锁替换失败/重试用例已由本轮 Windows CI 执行通过；本机 macOS 不执行该条件编译项。

## 尚未通过的发布门槛

| 项目 | 状态 |
|---|---|
| 真实供应商账户 | 未运行；仅虚构凭据与本地 HTTP，未检查 Bob 密钥 |
| 最新安装版真实 IME、选文、截图框选/取消 | 尚待用户桌面验收；旧版简洁弹窗的用户确认不能套用于本轮 |
| macOS 同版重启与跨构建 TCC | 尚待验收；固定路径与进程内原生代码不能替代 Developer ID 身份 |
| Windows 真实目标应用/全局快捷键/多屏混合 DPI/安装升级卸载 | 尚待完整实机计划；CI 构建和专用测试窗不覆盖全部 |
| 全进程组内存/端到端冷启动与交互截图延迟 | 尚待实测；上方主进程和生成图结果仅覆盖所述范围 |
| 商业签名、Apple 公证、商店和自动更新 | 未配置；仅预览验证，不发布稳定版 |

当前公开源码与构建产物不代表已完成全部端到端验收。预览发布必须保留上述限制；源码 ZIP 不是安装包。

## 分发与草稿

Mac DMG、Windows x64 NSIS 和 SHA256SUMS-hardening.txt 已保存在本机旁边的 EchoLingo-installers，并上传至 [v0.1.0-preview.1 预览草稿](https://github.com/Blueeeecho/EchoLingo/releases/tag/untagged-c8da17a22fa76e07d45f)。发行仍是 draft=true / prerelease=true，未公开发布，未创建稳定版。

Windows ZIP 的 SHA-256 与 GitHub artifact digest 4fe5e663fe9e618f1c5582612412c2afe92c5afc0e6bfd71ef6a3c7b0b96f28c 一致。安装器 MZ/PE 头有效；其 SHA-256 为 830cae877360b96fe3f43487250123a53fc71d049dd691167bdbe8d7f86669ee。Mac DMG SHA-256 为 05bc7e7c6a21c01b4d0f34bb04cd540a0ee17ab819195902e6aa5b03e0a45e37。发行附件服务返回的 digest 与本地值一致。文件头和摘要核对不等于真实 Windows 安装验收。
