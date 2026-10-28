# 0.1.0 预览版验证报告

<!-- selection-ancestor-package-20261028:start -->
## 2026-10-28 祖先选区候选包：新完整构建原始14/15，保留失败

源码61ea258/[full40649280066](https://github.com/Blueeeecho/EchoLingo/actions/runs/40649280066)：Windowsfailure、macOS和frontend-interactions success。原始.outcomes为14success/1failure；COE绿色步骤conclusion不是实际通过依据。

- 唯一红项rigorousSelection：16项要求，执行13/通过12，第13项rapid-A-then-new-selection-B报MOCK_FAILURE:InvalidOperationException:MOCK_CONTROLLED_REPLY_NOT_RELEASED，后三项未执行。夹具先等B完成才释放A，A仅hold20秒而B观察预算30秒；现有全局错误会先中断观察，不能认定mock是唯一根因。未通过改等待、重按或补测改写原红。
- 同次完整DLL的Document15/15；实际浏览器单拖选/单Alt+D48/48，42次同源点击隐藏；记事本1/WPF3、设置UI6/独立custom3、两浏览器真实WinRT OCR链通过。严格WinForms矩阵本次仅12通过，不能沿用旧16/16。
- 实际NSIS安装后2方向模型6个输入与3条真实离线应用链通过，无mock翻译；48运行资源allowlist、原许可证和清理通过。Windows272/Mac268Rust各1资源ignored、各84前端单位、28Python和完整隔离UI通过；物理IME/WPS/Win10/11不在本轮验收中。
- 安装器75,322,200B/e63509a4…a6ae14，stage5,923,840B/abaa92fd…b3594。API ZIP大小/完整摘要/CRC、完整新helper197258B/a507ccce…f110b和同构建DLL唯一嵌入均核对。7zz静态解出安装程序等实际CI安装SHA，较stage仅唯一UNK→NSS的3B差异；没有本地PE执行。66ce对应源码归档及2104项原清单审计复用条件仍成立。

交付为有已知红项的候选预览，不称全部问题修复。README、test-results和package-verification均明确14/15、快速连续任务失败及实体现场待验收；旧21b及此前候选保持不变。[候选安装包](/Users/wwq/Documents/Codex/2026-10-24/ni-ne/outputs/EchoLingo-installers/windows-preview-20261028-selection-ancestor/EchoLingo_0.1.0_preview_20261028_selection-ancestor_x64-setup.exe)、[精确验证](validation/windows-selection-ancestor-package-20261028.json)。
<!-- selection-ancestor-package-20261028:end -->

<!-- selection-github-recheck-20261028:start -->
## 2026-10-28 GitHub对照后的空Edit→祖先Document回归

现场：机主21b预览仍不能稳定取得WPS/Google网页选文；同位置手动Ctrl+C可用。下文旧完整15/15不是该现场已通过的证据。

修正旧测试的错误预期：原EmptyEdit场景的leaf空range而Document有实际选区，应成功读取父选区；新增EmptyEditEmptyDocument、EmptyEditNoDocument、EmptyEditPasswordDocument和SelectedEdit，共15项。精确断言leaf/doc选区查询次数、零额外Ctrl+C、原富剪贴板和前台保留、零DocumentRange和零provider focus。

- 本机完整native和夹具C#5/net48编译、PS7.4.6 AST零错误、现有纯策略149断言通过；是编译/纯策略验证，不是Windows UIA运行。
- 独立审查两文件冻结摘要：helper3c2154d5…938f1e；fixture2e0976b3…60983，无阻断。
- 旧生产+新夹具2996051/[40646617955](https://github.com/Blueeeecho/EchoLingo/actions/runs/40646617955)：原始selection=failure，前三场景通过，第四EmptyEdit返回NO_SELECTION；真实生成UIA拓扑复现旧错误。continue-on-error步骤conclusion=success不改变raw失败。
- 修复19c724d/[40647286036](https://github.com/Blueeeecho/EchoLingo/actions/runs/40647286036)：同一夹具15/15全case.ok=true；selection、assembly、OCR、delegatedCapture四项原始outcome字面success。EmptyEdit/空Document/无Document/密码Document/非空Edit的leaf/doc/copy次数分别1/1/0、1/1/0、1/0/0、0/0/0、1/0/0。15项富剪贴板/源前台均保留，零全文读取。两提交只差helper12增8删，夹具相同；不是放宽断言或等待后的通过。独立代理与主代理均核对raw JSON，[证据](validation/windows-selection-ancestor-20261028.json)。

只继续读取已验证祖先Document.GetSelection，没有扩大空Edit复制、放宽密码/根/身份守卫、读取全文、添加固定等待或重试。此回归不等于机主WPS/任意Google页面、已安装Tauri应用或新NSIS验收；当前安装包未更新。[研究证据与边界](windows-selection-github-recheck-20261028.zh-CN.md)。
<!-- selection-github-recheck-20261028:end -->

<!-- selection-services-20261028:start -->
## 2026-10-28 Windows新取词/API/录制包完整验收

源码21b5a49，[full40640121781](https://github.com/Blueeeecho/EchoLingo/actions/runs/40640121781)三个作业success；Windows最终原始.outcomes为15/15success，以原始JSON判断，不依赖continue-on-error步骤conclusion。

| 检查 | 结果与实际边界 |
|---|---|
| 单位/界面 | Windows272Rust、Mac268Rust，各1资源专用ignored；各84前端单位/7文件；28Python、完整隔离DOM/mockIPC UI及类型/构建passed。新录制红例+普通KeyX/partial Ctrl/较新DOM释放三边界全部passed，隔离事件不是实际Windows红例根因证明 |
| 单次选文 | 新APP Edge/Chrome48/48，每次1drag/1release/1AltD，原文/newmock/history精确，端点CSS误差≤0.5px/物理0，42同浏览器blankclick隐藏、6cleanup。非浏览器记事本1/WPF3/WinForms16通过；不是实体WPS/WeGame验收 |
| 改键 | 实际设置UI6/6，冲突回滚后第二F9录制、重启/禁用/恢复及3次启动退出通过；自定义键3链为独立生成配置启动，保留原4秒测试预热，不能冒充同一UI保存会话立即翻译/OCR |
| OCR/浮窗 | 两浏览器真实AltS左拖→WinRT OCR→自动译文/历史→同源click隐藏、固定连续更新、普通peer长拖及输入plane/无hook后端门禁通过；全屏/物理多屏/securedesktop及消费Win11性能仍待验收 |
| 诊断CLI | 同一真实程序一次显式导出，primaryPID/exe/当次时间、严格数值无原文schema验证，源/前台/窗口/历史/mock/剪贴板保留；不发新取词或读密钥 |
| 实际安装/离线 | 本轮NSIS真实安装后两方向模型6个推理输入case、3条实际离线应用链通过，无mock翻译；48运行资源allowlist及原许可证通过。不是6个不同模型，也不是任意文本翻译质量保证 |
| 原生冷首次补测 | dcb/run40634789697同PS8220 original双order96/96：72非空/12空/12密码及12cleanup通过，0copy/timeout，唯一旧Edge首case实际一次Q3，Q4严格稳定，总2.565s<5s预算；不是Tauri注册快捷键96次 |
| 包身份 | 新NSIS75,351,499B/90c3a252…4a554；stage5,923,840B/84e8c47c…515a5；本轮完整DLL105984B/e2406706…048db9@4616932及完整PS8220LF→1aa2CRLF单次嵌入匹配。实际安装EXE仅唯一UNK→NSS三字节差异；对应引擎源码ZIP66ce…8fd3c与已审2104文件清单归档完全相同 |
| 新官方协议 | Baidu/Youdao/Microsoft文本及Youdao/Google OCR专属认证/格式/取消/超限/脱敏/固定origin与凭据隔离、45固定文档URL检查passed；dummy和loopback，无真实厂商账户验收 |

原787 full14/15、7982/cf6 native95/96、6d full13/15失败保留；6d的UI2/6与hover return-B composition失败未被571同binary三项green解释，未回写成fullgreen。21b是随后独立新完整构建15/15；录制漏keyup另有隔离红→绿和保护反例证明，不能据此确认旧Windows那次失败根因。

仍开放：同PID后台剪贴板发布可能被错误恢复覆盖；实体Win10/11、WPS/WeGame/IME、全屏多屏/混合DPI、干净WebView2安装及真实vendor账号。新接口不自动切换OCR或上传；本地未执行Windows安装器、签名/替换Mac或改TCC/钥匙串/启动停止的VM。预览，不发布stable。[最新六文件包](/Users/wwq/Documents/Codex/2026-10-24/ni-ne/outputs/EchoLingo-installers/windows-preview-20261028-selection-recording)、[精确JSON记录](validation/windows-selection-services-20261028.json)。

<!-- selection-services-20261028:end -->

<!-- shortcut-reconfiguration-20261028:start -->
## 2026-10-28 快捷键更改补验与新版完整回归

| 验证 | 实际结果与限制 |
|---|---|
| 新完整构建 |295a0ce/full40572666385三jobs成功；Windows原始12/12门禁success，不以continue-on-error的conclusion代替raw outcome |
| 单位/界面 |Windows230Rust/1资源专用ignored、Mac226Rust/1ignored，两平台各79前端单位；28Python预检、完整隔离DOM/假IPC UI及类型/构建通过；不把跨平台相同前端测试相加 |
| 真实CLI |20/20，含五个动作NumpadEqual→exit3/空协议且配置不变，随后普通CtrlAltShiftE→exit0；冲突/旧启用字段/F12/禁用/坏配置/迁移保留；不等于安装向导或物理小键盘测试 |
| 实际设置UI |6/6：已注册键录制、保存新键旧键释放、外部F8真实占用回滚且原F9仍可录制、重启保留、清空禁用后重启、手填AltD/S恢复；3次启动/2次真实录制键/7次ValuePattern写，只有状态观察重试，无用户动作重发 |
| 自定义快捷键 |3/3：CtrlAltShiftF9选词、空框输入Enter、CtrlAltShiftF10左拖→真实WinRT OCR，各单按一次且原文/新请求/3条独立历史匹配；独立于UI保存目录、保留原4秒预热、loopback mock翻译，不冒称同一保存会话或冷首次 |
| 其余Windows |新stage单AltD矩阵16/16、生成文档/剪贴板11/11、私有budget8/8；原生输入/实时覆盖层/固定连续任务/浮窗/内部守卫门禁通过。私有worker不是实际UIA，生成应用不是浏览器实测，A/B描述性指标不保证实体Win11速度 |
| 实际NSIS |新75,313,434B/cf42fe57…a1e724实际安装，6次真实离线推理+3条真实安装后应用链通过，无mock翻译；48文件资源/许可证allowlist通过，隔离规则与自有安装已清理 |
| 包身份 |stage5,825,536B/8490a973…22a4b；安装后7efc8aeb…74c1仅唯一UNK→NSS的3字节变化。两API ZIP大小/完整SHA/CRC、完整DLL100864B/f31abc48…44e42及helper、对应sourceZIP66ce2962…8fd3c的2104份清单逐项通过 |
| 不可变旧程序补验 |f65 stage3e767c…4539于0f1ca8b/run40572097066真实设置6/6+自定义键3/3通过；原49cc/aac/e4/9cc/90/b0失败及0case/3case事实保留。b0瞬时F9冲突owner仍未知；加强退出条件后观察到真实句柄结束及四键释放，不倒推该owner |

实际Windows环境为hosted Server，实体Win10/11、目标消费应用/IME/多屏/全屏仍未验收。原真实浏览器95/96首次Edge失败及同PID后台剪贴板发布反例没有被此回归关闭。UIA保存/重启与真实自定义键工作流为两个独立夹具，重启用自有Job终止，不能冒称优雅退出。未使用用户密钥、修改本机Mac签名/安装/隐私/钥匙串、启动停止的VM或发布stable。[精确JSON](validation/windows-shortcut-reconfiguration-20261028.json)与[新预览目录](/Users/wwq/Documents/Codex/2026-10-24/ni-ne/outputs/EchoLingo-installers/windows-preview-20261028-shortcuts)提供原始身份和交付摘要。

<!-- shortcut-reconfiguration-20261028:end -->
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
| 最终f65双order/40556538688 |两独立Windows runner总95/96，整体failure。Chrome-first48/48及冷6/6；Edge-first47/48及冷5/6，首例query1约1084ms、query2约12ms，Pane→Group身份拒绝而非超时。两浏览器各有作为机器首测对象的独立结果，不用Edge预先初始化后的Chrome冒充首次。新stage full40556538469结果另列，不能覆盖这1次失败 |
| 初始选区探针c9/40562621965 |诊断专用，96实际/94通过，两order各47/48；两首例Pane均无祖先Document。84次probe中82初始role不适用、2无Document、0eligible；12password在probe前正确挡住。首次未取得可核验A，故不采用后绑定锚点。两失败均非截止；前台/富clipboard/postaudit/单helper/清理全部保持。不是f65通过率或生产修复 |
| 剪贴板810/40550008709 |3执行/2通过：基线、实际第二Ctrl+C取消且不覆盖通过；背景同PID发布仍错文+helper恢复覆盖，原始failure保留 |
| 最终full f65/40556538469 |原failure保持：11门禁10成功/1失败。新stage SHA3e767c70…4539/5,825,536B，严格App16/16（7真鼠标、一次热键/意图、mock翻译）；连续任务4/4，403pin采样hidden0/maxgap26.1682ms。生成Document11/11、delegated8/8、live8/8、Windows228Rust/1ignored。唯一shortcutsUi在owned-fixture-setup powershell ETIMEDOUT，0case/0key，不等于设置界面已通过或产品错误已确认 |
| 最终NSIS真实离线 |75,281,557B/a22b586b…ce4c9；实际安装6模型+选词/空框输入/OCR3离线链通过，mock=false，出站规则与安装目录清理true。完整内嵌DLL100,864B/069b3617…5f8e；API ZIP SHA/size/CRC、stage/源码ZIP及仅3B NSIS marker身份独立核验 |
| 预算8e/40553539766 |8/8、42断言通过；共享预算允许2213.93ms调用，累计709.67ms截止后不启动新query/迟到RPC，独立标量保留2005.80ms截止。复制在截止后仍先恢复、恢复失败优先、新复制不恢复。全为精确私有worker与模拟策略，不是真实UIA提供者/clipboard/input |

[Windows待验收候选安装器](/Users/wwq/Documents/Codex/2026-10-24/ni-ne/outputs/EchoLingo-installers/windows-candidate-20261028-selection-rigorous/EchoLingo_0.1.0_preview_20261028_selection-candidate_x64-setup.exe)已生成并核验，未自动安装；仍有已知失败，不作为全通过修复版或stable。标准clipboard API不能给任意后台发布提供本次Ctrl+C事务身份；现有兼容回退保留此边界。native HWND焦点不覆盖每个DOM变更。实体Win10/11、WPS、IME/多屏/提权窗口未验收；本轮Windows为GitHub-hosted Server桌面。未修改Mac安装、签名、TCC、钥匙串或用户凭据。[精确证据](validation/windows-selection-rigorous-20261028.json)。

## 2026-10-27 原生输入接管：新预览已交付，等待实体Win11验收

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

## 2026-10-27 鸿蒙反馈与免费云PC路径核对（无新增运行验收）

交叉核对既有JSON/源码/调查，保留回调内33600005、Picker801、CoreVision模拟器限制的各自范围；/dev/uinput仍为候选根因。用户截图及当前官方云调试页确认HarmonyOS5+每日360分钟免费，设备包含鸿蒙电脑；上次“团队本次优惠时长已用完”只说明当次会话结束，不能写成以后不能真机实测。当前未完成的是调试签名、云PC安装和实测，当天账号额度/可用机型未重新核验。无新会话、构建、签名、权限或运行测试。已核验官方反馈入口并完成[两份待批准文字稿](harmonyos-pc/feedback-draft-20261027.zh-CN.md)，未发工单/帖子/邮件/客服消息或上传附件。

## 2026-10-27 Windows：受控功能回归通过，Win10完整实机验收未完成

应用源码**c1338ba**，stageSHA97d461e7…／安装后d2d21f04…。完整[CI40475539423](https://github.com/Blueeeecho/EchoLingo/actions/runs/40475539423)的Windows142Rust／Mac146Rust（各1ignored）、61前端／隔离UI、nativeOCR／选词、live7/7、app3核心链、真实离线6用例及NSIS实装3链路均过；原整体gate因fixture不会操作“更多”的ExpandCollapse仍failure。随后只改fixture／工作流的[2bb定向40477832616](https://github.com/Blueeeecho/EchoLingo/actions/runs/40477832616)通过，源码无变化＋整exeSHA门禁证明复用同一c133程序，不把两轮写成fullCI全绿。

定向真实通过：未固定外点击隐藏且源收到click、内部点击保留、真正拖窗／拖宽、直接owner原生窗激活和点击后保留、纯焦点转移隐藏、固定保留／取消固定恢复隐藏、管理页外点击保留；第二实例exit0且真正显示主实例Settings。5次实际click MouseDown计数均递增；7条owner生命周期说明新代码正确处理GW_OWNER=main而GA_ROOTOWNER=self的情况。nativehide缓存／SW_HIDE及有界16步owner链均经过该程序运行，不靠mock结果。

本地官方Win10LTSC2021x64／19044的UTM TCG（AppleSilicon）已实际运行：native生成图、普通TopMost透明蓝边QMP左拖、实际两行OCR／2468成功，保留Ech0Lingo与中文空格。约43秒ready超过25秒strict门槛、全native交互超时仍失败；后续两次PowerShell宿主AV停止，模块原因未知，也没有证据新版app启动或崩溃。Win10本地NSIS／app字体／IME／物理流畅度未验收；正常关机、服务停止、证据归档已独立复核。未改时间／激活／安全策略，过期eval／grace0如实保留。ServerCI与TCG都不代表目标Intel／AMD实体性能。

预览含对应引擎源码，94,704,533B，SHAd84d9a53…；setup75,242,923B／6347998c…，source19,456,259B／b82a524a…。APIZIP SHA＋CRC／内部文件以及最终bundle全部hash通过。未签名、未发stable。Windows正文宋体16px／控件微软雅黑已入包；WPS／Edge、物理多屏／混合DPI、普通提权安装窗OCR／安全桌面边界、固定自身窗口排除仍待目标环境。Mac规范程序SHA7eafe813…保持，未签名／重启／请求权限／访问凭据。

[精确结果](validation/windows-interaction-performance-20261027.json)，[本机详细报告](</Users/wwq/Virtual Machines/EchoLingo-Test/evidence/LOCAL-VM-RESULTS-20261027.md>)。旧47及此前失败／夹具错误均保留在分层JSON，不作为本包的新验收。

## 2026-10-27 macOS DMG 预览安装包

已从canonical7eafe813原样生成Apple Silicon DMG：3,994,854B，SHA256`02aacf6504c335e73f43a51888b21d0a8e441785558b59bb88edbb26c0b55234`。hdiutil映像校验、独立readonly/nobrowse挂载及Writable=false、卷内strict/deep和相同leaf指定要求、全部4个Contents文件/hash/权限、批准图标一致性通过。顶层仅app、Applications符号链接和安装说明；卸载成功，stage已Trash。初版说明‘右侧’无实际Finder布局证据，最终包已仅删除这两个字并复核，app始终未变。

本轮未构建/重签/安装/启动app，未请求钥匙串或系统权限，没有新增WPS/全链路OCR验收。用户选择无开发者账号的自签预览包，未公证，不声称其他Mac浏览器下载后的Gatekeeper/首次启动通过。arm64非Intel；声明最低12不等于Apple系统翻译可用，后者需26+及语言包；首次两权限仍由用户设置。未发布GitHub Release。[精确证据](validation/macos-dmg-preview-20261027.json)。

## 2026-10-27 合并修复已安装：启动与权限保持通过，WPS实际验收待完成

用户“允许进行替换”后，仅一次4.605秒固定身份签名成功，安装版为7eafe813…／5,396,160B／PID63147。strict/deep、相同证书leaf指定要求通过；签后ZIP CRC及全部4个Contents文件与canonical逐字节相同。相邻安装前后及启动后settings/history/layout摘要一致。新进程两权限true、主线程Accessory1／LSUIElementtrue／inactive正常后台启动；未请求权限或读取API凭据。一次只读requirement验证参数纠正不是再次签名。

backup与stage已Trash，限定目录中一个canonical／一个实际进程；canonical注册成功、backup注销成功、stage未注册错误不当全缓存清理成功。源码132Rust／61前端／原生／完整隔离UI结果保留；Windows94策略断言仍非实机。安装初始trace=unread，不冒称WPS已能取词。已请求一次WPS正文选文Alt+D验收。[安装及测试精确证据](validation/wps-selection-hardening-20261027.json)。下节是签名前候选快照。

## 2026-10-27 WPS 实际分支与同类边界修正（最终候选已准备，尚未安装）

短时缓存元数据观察实际保留了WPS PID1280／AXSplitGroup／selected-text=noValue／single range=0的失败：安装版opaqueDocument=false、decision=empty、copyIssued=false。另一次AXDialog属于代理打开的文件选择器，不能当正文测试；此前self/Codex记录也不能冒充WPS分支。没有记录原文、剪贴板内容或窗口标题；两个临时观察器均已结束，最后导出使用已有single-instance通道，未触发LaunchServices Reopen。

本轮修正WPS专属容器漏判、AX有效／不可用／非法查询混淆、非文本控件盲复制、角色／子角色复查，以及聚焦回执／帧／模态／整事件迟到与输入意图编号。Mac原生selftest真实编译执行通过（含生产CFType/AXValue解析器、WPS零范围、普通空框／密码框、角色分类、private pasteboard及Vision），未触公用剪贴板，未对候选执行真实WPS取词。Windows另外修正UIA焦点及复制后上下文：94共享策略断言、C#5/net48交叉编译、PS7 AST通过，未在Windows桌面执行新代码。

最终132项Rust通过、1项未改动模型资源测试ignored；61项前端、类型检查、生产构建和完整隔离UI通过。两轮旧代码失败→修正后通过保留了迟到ack及同epoch整事件的实际回归记录。35.07秒no-sign构建通过，主程序d42f4605…、归档a3766a9d…／3,635,630B；CRC、全部Contents、源码freeze、arm64/minOS12/LSUIElement及批准图标校验通过。generated.app已Trash，保留可恢复归档，限定清单一canonical；旧路径注销-10814不当成功。精确日志及包摘要以[精确证据](validation/wps-selection-hardening-20261027.json)为准。当前canonical仍065b09e0，尚不含这些新修正；前次签名授权已使用。不能把host／mock检查写成已安装WPS或Windows全链路通过。

## 2026-10-27 取词修复已替换：浏览器实测恢复，WPS仍未通过

用户明确“确认 并替换”后，唯一固定身份签名4.785秒成功；canonical签后主程序`065b09e0b680be6149d805060ff013e8cfefe467872d31700489675cc7ecc4bb`/5,362,656B，PID38529。strict/deep/证书leaf指定要求通过，签后归档全部文件与实装一致；相邻安装前后及启动后settings/history/layout摘要一致。实际新进程两权限true、NSApplicationPolicy1/LSUIElementtrue；旧backup/stage已Trash，限定清单一app/一verified进程。签名授权已使用。

用户随后确认浏览器等可以取词，WPS仍空。保存的同进程Chrome trace为AXWebArea、selectedTextEmpty=false、decision=text、state=completed、sourcePID与复查一致，未发送复制。这是实际浏览器获取成功证据，未记录原文或外推译文质量。先前selfPID/AXTextArea/zero trace仅属于某次按键，不能当首次源捕获的通用根因。

最新导出记录是Chrome成功，已覆盖先前WPS尝试，因此当前仍缺WPS唯一尝试的准确分支；已请求WPS-only单次重试，继续只读无原文诊断。131Rust/61前端/native/UI属于上方准备阶段通过，不冒称WPS已修好。没有追加签名或重新授权。[完整证据](validation/selection-capture-20261027.json)。下节保留安装前快照。

## 2026-10-27 跨应用取词失败：修复候选测试通过，实装未验收

用户明确反馈当前4a4c9f4e在WPS和多数浏览器选文Alt+D弹空框。未把安装/权限保持当取词成功。已完成实时AX前台来源、严格focus公开回退、窄文档复制恢复及有界无原文诊断修正，基于3d372be加3个未提交源文件变更。

- Rust完整131通过、1项真实模型资源测试ignored；61前端通过；完整隔离UI/IPC通过（fake IPC，非实际源应用）。
- 原生selftest通过：新前台优先/无效cache拒绝、PID归属/nil拒绝、普通zero/secure、文档未知或正范围空内容、trace白名单/32事件/256字符串及显式模式仅读缓存；生成图Vision与私有pasteboard通过，generalClipboardTouched=false、wpsInteractiveSelectionTested=false。
-42.25秒no-sign构建、CRC、包/源码摘要、批准图标、arm64/minOS12/LSUIElementtrue检查通过。主程序a3647a0c…、未签名归档c9714f53…；尚未签名安装。
- 实际测试受限：CUA创建Chrome测试页超时，绑定窗口/操作WPS正文返回noWindowsAvailable，文件对话框已取消；CLI AXtrusted=false后未发起取词/授权。不能据此说明产品已修好或底层AX权限失效。
- 工具初始失败保留：缺Playwright默认headless shell，改用已安装官方Chrome headless重跑成功；默认Cargo索引等待后停止，默认离线源缺futures-util，复用项目已有缓存registry runner且locked/offline后全部Rust通过。锁文件未改。

当前仍安装4a4c9f4e；最终候选已准备，等待另一次单次固定身份签名替换许可，然后才能确认真实跨应用取词。没有权限/TCC/钥匙串规则变更或新API请求。[原始证据](validation/selection-capture-20261027.json)。 已保留校验通过的未签名ZIP，等待批准期间将stage/build应用副本移入废纸篓，限定目录中仅保留原canonical。

## 2026-10-27 Mac 最新版：一次签名、安装、后台启动及权限保持通过

本轮按用户“帮忙安装 mac 的最新版”执行，使用最新3d372be / CI40261784632 ARM64包，不是较旧e7aa候选。只签名一次，36.844秒成功；严格deep、证书leaf固定DR通过。canonical为`/Users/wwq/Applications/EchoLingo.app`，签后主程序`4a4c9f4ebe816f3f05e460a09b21cf615af59f73664f5582ae0400ed042cd88a`、5,345,472B，PID20009。这次单次安装签名已消耗。

| 本轮实际检查 | 结果与边界 |
| --- | --- |
| 来源/内容 | CI DMG校验通过，arm64/minOS12、LSUIElement=true、批准图标匹配；WPS/启动/全屏相关源码继承核对通过。Mac不捆绑Windows7模型 |
| 签名/替换 | 固定身份3FCAC2…；一次签名、事务复制/验签/停止旧进程/替换均成功；无ad hoc降级、无ACL或TCC操作 |
| 用户数据 | 相邻安装前/安装后/启动后settings/history SHA逐项一致；window-layout原本不存在且保持不存在，没有复制内容到证据 |
| 实际新进程权限 | PID20009进程内检查辅助功能true、屏幕录制true、bundle路径/ID正确；只检查，没有重新请求权限 |
| 实际启动身份 | 新进程主线程NSApplicationPolicy1、NSRunningApplicationPolicy1、LSUIElementtrue、applicationActivefalse；正常bundle后台启动，不直启二进制 |
| 清理 | 旧backup与两个stage共3份app已Trash，保留源码/缓存/分发归档/用户数据；限定目录内一app/一verified进程。canonical注册成功；旧原位置注销返回-10814，不宣称全系统UI缓存已清除 |
| 独立核验 | 签后ZIP CRC及全部4个Contents实文件与canonical相同；签名/图标/数据/进程由只读代理复核 |
| 没有在本轮验收 | WPS真实取词、完整全屏/多屏OCR→翻译、固定连续OCR/取消、实体拖宽/重启/缩放矩阵、真实连续API认证。先前CI130MacRust/61前端是该源码已有结果，未冒称本轮重跑 |

安装中未读取API凭据或发起翻译，未修改钥匙串规则，未申请隐私权限或发布稳定版。[本轮精确证据](validation/macos-install-20261027.json)。下方三端整理是安装前快照。

## 2026-10-27 三平台进度核对（没有新增全链路验收）

本次整理以2026-10-26已有原始运行证据为准；仅重新读取本地Mac主程序SHA256，仍为`1f5562c61ff456386bda39a0c0b78e23290443a11cd0f0fb68cd0ee941399c76`。没有执行签名/安装、申请系统权限、读取API凭据、启动新云会话或重跑各平台测试。

- Windows：3d372be离线NSIS已在临时GitHub Windows Server2025 VM真正安装并通过真实模型Alt+D、空框输入及Alt+S左拖OCR自动翻译。仍缺实体Windows10/11普通账户、WPS、全屏/物理多屏/混合DPI、旧CPU及缺运行库/语言包环境；未签名预览，不是本地WindowsVM。
- macOS：已安装1f5562c6与后续源码/未签名候选分开。765339/e7aa2105候选已打包归档而未安装，之后桌面源码已前进至3d372be；最终应先固定要安装的源码和包，再单次固定身份签名替换及实装验收。完整WPS取词、全屏OCR到翻译、固定连续OCR、宽度/Spaces和连续凭据使用仍待验证；独立原生夹具通过不能代替最终安装包。
- 鸿蒙PC：b80e3d原生HAP已在本地官方PC模拟器真实运行，基础翻译/交互部分通过。取内容33600005、主屏Picker801仍未解决，完整Alt+S未完成；CoreVision不支持模拟器是独立官方限制，不能据此证明Picker根因。物理PC、正式发布身份/签名/审核仍未完成。

各候选的历史测试继续保留原始范围。详细摘要见[状态文档](status.md)，下文不是全部针对同一二进制的累积验收。

## 2026-10-26 鸿蒙 PC：真实本地测试部分通过，两个核心快捷流程未完成

截至约16:05（Asia/Shanghai）。官方PC模拟器已实际启动，程序已实际安装和运行；不是仅编译。当前安装b80e3d候选，114,805,469B / `b80e3d1e8a73844af78dbf2b1399ae3939e73ea4cd1562d907277ed2d4d2c8f5`。当前源码在`codex/harmonyos-pc`，未提交。不同包的结果分别归档，未把旧用例冒充新包全量复测。

| 实际检查 | 结果与边界 |
| --- | --- |
| 工具与环境 | 官方MacARM CLT26.0.0.851 SHA/91,769payload校验通过；SDK26.0.0.105、Emulator26.0.0.402、JDK21真实执行。官方PC镜像2,743,949,835B下载/创建/启动通过，guest2in1/API26/aarch64/7.0.0.107；底层fullname原样OpenHarmony-7.0.0.105 |
| 包与模型 | b80实际构建/安装/启动，56项编译源码快照一致；CRC、7模型104,470,603B、36原许可+2SDK通知、原生stage/SDKstrip一致性通过。23may-throw+1设备能力advisory和未签名提示保留；不是发布包 |
| 双向本机翻译 | c80199真实Enter：会议英文→`会议将于明天09:30开始。`；报告中文→`Please send the report by 9 a.m. tomorrow.`。无mock/个人API；没有伪造性能或全程断网证明 |
| 复制与固定 | c80199结果复制后独立fixture Ctrl+V精确相等；普通窗口固定时源编辑器获焦且译窗保留，不外推全屏、多屏或连续OCR |
| 菜单与隐藏 | dcf未固定菜单保持，点击外部隐藏，显式重新打开成功。修复了PC默认子菜单窗口导致主窗误失焦隐藏；托盘/长期后台仍未全部验收 |
| 取消与历史 | dcf独立Case501–670共13,428字符真进入loading，停止后为空结果；编辑Hello→`你好,世界。 这是一个翻译测试。`，历史6→7且只加完成短任务。不宣称CPU即时抢占/所有退出清理均过 |
| 技术文本 | dcf精确`- quiet_pin: selected_text / source-v2`可检测英语/翻译，无字符解析错误；实际译为`- sitle_pin:选定文本 / 源-v2`，保留模型质量限制 |
| 收藏与有限持久化 | 最终模拟器测试偏好已恢复跟随系统/20条；7bc星形立即☆→★→☆，仅收藏中取消后为空；dcf选深色、999上限收敛100，更新重开7bc后深色/7条历史/100上限与收藏还原。不是整机重启或所有边界验证 |
| 换行与编辑 | 4f及最终b80真实首输入`First line —`，Shift+Enter后继续输入得精确两行；普通Enter得`第一行——\n第二行——`；Ctrl+A再Shift+Enter仅保留单换行，无误提交 |
| 真实IME（已修复并实测） | 4f的pre-IME拦截失败保留历史。b80改为原生post-IME onSubmit：真实Pinyin候选`ni`第一次Enter收起候选且不翻译，第二次Enter才提交。实际模型回`ni`仅证明提交时序，不是译文质量通过；Shift+Enter仍能换行和替换选区，无误提交 |
| 选词（未通过） | sentinel e0c039已实际安装，扩展PID32475连接/订阅，两次系统Ctrl callback后读内容均33600005（1/3ms）。Alt+D直接读取也33600005。缺虚拟输入设备节点是有证据的候选原因，未最终定因；产品全链路仍未打通 |
| OCR（未通过） | c8f真实`stage=pick ocr=1 window=1 code=801`，失败发生在系统Picker，未到识别。官方CoreVision另明确不支持模拟器；不能归成capability=false、签名/ACL或已执行OCR |
| 完整Alt+S（未完成） | 实时透明蓝边、多屏跟随、左拖/OCR→填入自动翻译、Esc及固定原位连续性尚未完成产品接入/验收；不以主屏Picker或synthetic识字代替 |
| 纯检查 | 18domain、9SSE、17hostC++、9fake-native菜单生命周期各自通过；它们不是设备IME、真实账户HTTP、资源损坏或物理多屏验收 |
| 云端/发布 | 平台已结束此前短暂云会话，无应用上传/安装/测试、无付费开通。回到本地。工程尚未配置或核验正式APPID/发布身份/Profile，未提审；不推断账号没有既有注册。Mac签名/钥匙串/TCC及Windows源码未改 |

仍未验收：可分发的配置快捷键取词完整链路、完整Alt+S、本机TTS/状态栏/长期后台、真实API凭据和网络流、多屏/全屏/WPS及物理PC。当前不能发布稳定版。[简要说明](harmonyos-pc/current-verification.zh-CN.md)、[逐项运行矩阵](harmonyos-pc/runtime-acceptance.zh-CN.md)、[真实运行JSON](validation/harmonyos-pc-runtime-20261026.json)。旧[da50767构建快照](validation/harmonyos-pc-20261026.json)保持历史状态，不再当当前运行结论。

## 2026-10-26 内置离线模型：Windows 真正安装、断网推理及核心流程通过

精确源码 `3d372be3c15048dcffd0820cc6d77c6466d2cdab`，PR合并测试提交 `e7ee665481c010c329e4d2765f3a7914861dfe1f` 的 [CI40261784632](https://github.com/Blueeeecho/EchoLingo/actions/runs/40261784632) 三任务全部通过。原始Windows报告、实际译文/哈希、源码审计及历史失败分列在[验证JSON](validation/windows-offline-translation-20261026.json)；[完整交付说明](windows-offline-validation-20261026.zh-CN.md)。

| 验证 | 实际结果与边界 |
|---|---|
| 环境 | 临时GitHub Windows Server2025 VM，AMD EPYC7763、2core/4logical、17,174,360,064B RAM；没有在用户Mac安装VM |
| 回归 | Windows126Rust、Mac130Rust，各有1项真实资源测试默认ignored；前端61、完整隔离UI/IPC、原生OCR/取词/透明选择器及NSIS/DMG过；本机28Python及显式真实Rust worker复用/取消/reload过 |
| 真正安装 | 75,175,463B NSIS实际安装到中文路径；7模型/36原始许可精确hash通过；首次运行前116,805,494B；卸载/自有目录清理成功 |
| 严格二进制身份 | actualNSIS app/engine与安装报告hash一致；stage app仅Tauri官方唯一UNK→NSS标记末3字节变化，完整字节数组其余相等；不忽略PE区/签名 |
| 真正断网 | MpsSvc运行、Public防火墙profile有效；精确安装app/engine出站Block前后有效，未改网卡/profile开关/默认策略；规则全清理 |
| 真实模型6项 | 双向普通句、短标签、下划线/路径/42及双向空行段落均执行；首次方向231/229ms，缓存11/75/20/19ms；OS文件缓存未flush，不称严格冷启动 |
| 实装Alt+D | 一次热键完成真实原生选文→自动en→zh→合成历史，译文“你好,世界。 这是一个翻译测试。”，后端328ms；源窗前台，译窗可见/置顶 |
| 实装空Alt+D | 首批中文直接输入+Enter→自动zh→en，译文“Hello, world. This is a translation test.”，后端239ms |
| 实装Alt+S | 生产透明overlay→左拖→WinRT真实像素OCR→自动填入/翻译/历史，译文“Hello 世界 2468”，后端18ms；并非OCR整链耗时 |
| 凭据/模拟边界 | 3流程均real-bundled-offline-model；mockRequests=[]，credentialAccess=None；自有app树/目录清理true。另一个loopback测试仅协议回归，不混为模型质量证据 |
| 内存 | 双方向同时缓存引擎workingSet328,019,968B、peak462,798,848B；不含app/WebView2 |
| 对应源码 | 正式ZIP19,456,259B /b82a524a…，CRC/2104逐文件hash、36原始许可/registry/4补丁通过；同引擎源全进程断网完整重建52.954s+3实际推理0.725s通过；最终包仅许可元数据比较脚本修复及EOL/JSON格式差异，不冒称最终ZIP另做完整重编译 |

真实质量限制：`- quiet-pin:`输出`- 静音:`，较长句的`quiet_pin`变为`sitle_pin`；Mac独立emoji例子出现额外“电话:”。能够处理输入并非译文完美。目标WPS、真实Windows10/11普通账户/缺WebView2/语言包环境、物理多屏/混合DPI、全屏及旧CPU仍未验收。Mac当前安装、签名、TCC/Keychain没有改动，预览未作为稳定版发布。

此前失败保留：40256136432是MSVC/Ruy pragma及conversion /WX兼容；40257073803是PS5.1字典Measure-Object夹具；40259415715是误把Tauri打包前后标记的整文件hash要求完全相同。均已精确修复，未将失败run算通过。


更新时间：2026-10-26，Asia/Shanghai。本报告分别记录本机执行、CI 和真实桌面边界，未运行不算通过。[前次硬化版本原始本机证据](validation/macos-preview-20261025.json)。

## 2026-10-26 最新源码：完整 CI 通过，Mac 本地替换待授权

精确源码 `765339b94f3afd355d175f8d82c3d1ecaa40ca14` 的 [CI40219608925](https://github.com/Blueeeecho/EchoLingo/actions/runs/40219608925) 全部通过。前两次失败被修正并留档：Swift旧编译器合成初始化器权限、Windows复制时序，以及误用284而非276的ABI测试期望；没有把旧run或本地交叉编译当成本轮通过。

| 验证 | 结果及边界 |
|---|---|
| Rust / 前端 / 构建 | Mac **126/126**、Windows **122/122**、前端 **60/60**；类型、完整隔离UI/IPC、fmt及NSIS/DMG构建均过 |
| Windows 原生 | 真实WinRT OCR、Unicode及丰富剪贴板恢复、密码/空选区保护、立即及80ms延迟复制和4轮fresh-helper重复均过；selection49/capture29策略通过；live截图、取消、快速Esc及再次截图通过 |
| Windows 真正应用 Alt+D | **通过**：启动实际built exe，单次快捷键→原生选文→前端自动翻译→loopback→合成历史；源窗保持前台、译窗可见置顶 |
| Windows 空框输入 | **通过**：空Alt+D→首批Unicode键入+Enter→精确第二次翻译/历史；没有重发快捷键掩盖失败 |
| Windows 真正应用 Alt+S | **通过**：生产透明overlay→左拖→真实像素WinRT OCR→前端自动填入/翻译→第三份精确历史；overlay消失、源窗保留、自有进程/目录清理成功 |
| Mac 原生及私有剪贴板 | 生成图片Vision OCR、复制策略、私有多格式恢复通过；6组现代/旧式延迟promise实验符合changeCount所有权规则。未读用户选文或请求权限 |
| Mac 真正全屏独立夹具 | 左拖返回340×100区域、Esc取消均通过，面板全移除，live源仍前台/当前Space；同源Tauri矩阵8/8、真实生成WebView可见且首击输入成功 |
| 本地Mac候选 | no-sign **38.13s**、CRC/hash/已采用ICNS匹配通过；未签名主程序e7aa2105…，尚未替换当前1f5562c6 |
| 尚未接受 | 安装版Mac WPS选词及完整OCR→翻译/固定保留、真实Windows WPS/全屏/物理多屏/混合DPI和安装后NSIS。CI整链用了3次本地mock请求，不能宣称真实云API或译文质量通过 |

实际测试的Windows exe SHA-256 `1ecf829d0822dff14b401646c164d5c450369c4ff97401f7de89f2b420605011`，与本地Mac候选摘要分开。Windows夹具只在一次性GitHub-hosted桌面运行，要求原生KnownFolder下应用目录原本不存在，使用随机无密钥服务、本地假翻译和所有权标记；未读/覆盖原有用户数据。上一轮95.169秒签名授权已消耗，本次需要对已准备的最终包另行允许一次签名替换。没有实际API凭据读取/上传或TCC/ACL修改。[精确证据](validation/startup-selection-20261026.json)。

## 2026-10-26 当前安装候选：签名安装完成，WPS／完整全屏验收未完成

本轮用户明确允许一次签名替换，**唯一签名95.169秒成功**；严格deep及固定证书DR通过。当前canonical为 `/Users/wwq/Applications/EchoLingo.app`，签后主程序SHA-256 `1f5562c61ff456386bda39a0c0b78e23290443a11cd0f0fb68cd0ee941399c76`，PID84979。紧邻安装前后的settings/history/window-layout摘要一致；设置界面两个权限仍已授权、MiniMax/OpenAI凭据未读取。旧f1cf备份、签后stage及两个合成fixture app已Trash，最终配置目录内一canonical app／一verified进程。无新增API凭据访问、供应商请求、TCC或钥匙串规则改动。

完整验收仍未通过：外部NSRunningApplication探针在刷新runloop后仍报告policy0和0个onscreen主窗，但没有安装进程内部NSApplication读回；独立Tauri无窗example的setup及before-run均稳定为1，所以不能把外部0直接归因于setup调用无效。安装版CUA快捷键注入未形成可确认选择器；随后观察Echo界面也改变了源的前台/Space，不计作完整全屏OCR通过。同源原生选择器此前实际左拖成功继续只算其自身范围；WPS12.1.26046有/无选区及Windows真实桌面仍未测。

按用户最新要求，已暂停进一步生产改动并完成[GitHub现成方案研究](github-compatibility-research-20261026.zh-CN.md)。Easydict有直接WPS强制复制成功反馈；Tauri有打包版跨全屏先例；Handy有事件循环前设置Accessory的已合并修复。它们用于后续最小适配，不等于当前根因已证实。没有再次签名、发布或权限重置。本次单次授权已消耗；所有精确安装/诊断/限制已写入[本轮证据](validation/wps-fullscreen-20261025.json)。

## 2026-10-25 安装前测试快照：WPS 取词、全屏 OCR 与 Windows 对齐

本节保留安装前快照：当时安装程序仍为下方 `f1cf4027`；2026-10-26的实际安装及未通过项以上方新节为准。只读探针确认安装进程 PID81126 的 `applicationActivationPolicy=0`（Regular）；代码现已在 Tauri setup 一次性设为 Accessory，不在截图期间反复切换。

| 项目 | 本轮结果与边界 |
|---|---|
| 全屏浮层政策 | 13+ 使用 `canJoinAllApplications` 与传统 Spaces/fullscreen auxiliary；12 使用兼容分支。selector 为透明 nonactivating floating NSPanel、screenSaver 层。生产纯 ABI 的冲突位／保留位／幂等及两版本分支通过；隐藏窗政策夹具通过 |
| 原生全屏实际左拖 | **通过一次**：独立合成源原生全屏，CUA 左拖生产选择器返回 `(50,907,250,100)`，`panelsAfter=[]`；panel 为 level1000、visible/onActiveSpace/key、nonactivating，selector 应用未激活；源 PID82903 仍前台、原生全屏且 liveCounter203。无屏幕像素、OCR或API请求 |
| 可视合成截图／完整安装链路 | CUA 只取得绑定窗口图，透明窗口白底图不能证明屏幕合成效果；不算蓝边完整视觉验收。最终安装包 Alt+S → 实际截图 → OCR → 填充自动翻译、多个真实全屏应用及多屏仍需复测。第二次预览存在不受控选区，不计 Esc 通过 |
| WPS 取词兼容 | 已实现应用 PID 内的 AX focus、复数选区范围及 WPS opaque 容器兼容；0 长度范围、安全字段、普通编辑器空文本保护保留，复制前复查同 PID/同焦点。纯策略／生成图／私有剪贴板测试通过；**没有把它计作 WPS 实机通过**。菜单可控而正文点击报 `noWindowsAvailable`；自建空白 PPT 已丢弃，独立 RTF 夹具待用户选中 |
| Rust／前端／界面 | **126/126 Rust、60/60前端单元**，check/build、完整隔离 UI/IPC 通过。macOS native self-test 包括真实生成图 Vision OCR 与私有 pasteboard 恢复；不读一般剪贴板、不申请权限 |
| Windows 最新源码 | 透明每屏实时左拖选择器与独立合成窗 live-capture smoke 已加入；独立 review 发现的 Esc 穿透、hook 初始按键间隙和拓扑变化已修，二次复查无确认阻断。29项生产纯断言、3份C#跨编译、3份PS7 AST检查通过；新 CI 步骤仅写入工作区，未运行。极端持续按住超过500ms排空宽限会取消且不截图，之后松开仍可能到源应用 |
| Windows 历史实测 | [旧run40172215129](https://github.com/Blueeeecho/EchoLingo/actions/runs/40172215129)的49 Rust、WinRT生成图OCR、受控WinForms取词/多格式剪贴板恢复真实通过；截图、多屏、全局热键明确 false。其 checkout 为旧PR merge，不能覆盖当前源码 |
| Windows 当前实机 | **未运行**。本机未发现 Windows VM/桌面/PowerShell5环境；Roslyn/.NET4.8交叉编译、PS7 AST 与.NET8纯状态通过只验证相应层，不能声称Windows hook/WinRT/BitBlt/DPI/全屏已通过 |
| 系统与数据边界 | 未签名、未替换安装、未请求TCC、未操作钥匙串规则、未读API凭据或调用供应商；没有GitHub上传、CI dispatch或稳定版发布 |

Windows 后续执行步骤见 [Windows 实机验收计划](windows-test-plan.zh-CN.md)，历史精确范围见 [Windows parity evidence](validation/windows-parity-20261025.json)。本节的“待安装”和“未实机通过”必须保留，不能用同源夹具代替最终应用验收。

## 2026-10-25 前轮安装版：默认置顶与前移修复

用户明确回复“允许这一次签名并替换”后，已完成一次固定身份签名及替换。当前canonical为`/Users/wwq/Applications/EchoLingo.app`，签后主程序SHA-256 `f1cf40273ad2233a063d5b1bf21c2237b5d9054f2b818045d77b4d6ffde4c2d2`，PID81126；下方`d87ef732`已转为前轮安装历史。

已确认旧`visible + popup`跳过条件范围过大：为固定OCR原位更新避免重复show，却也让普通快捷键对已经可见的浮窗不再执行原生前移。同时，运行期展示只依赖启动时`alwaysOnTop`，没有统一重申浮动层级。macOS的`isVisible`不能证明当前Space可见或位于其他普通窗口之上；没有证据表明`set_decorations`必然清掉置顶，不据此归因。

现在前端和IPC新增第三参数`reuseVisiblePopup`，默认false。普通空选区、输入、选文快捷键均请求前移；只有明确标记的固定OCR原位更新，并且原生窗口仍可见、已固定且为popup布局时，才跳过原生show/order。两条路径都在epoch/布局检查后恢复层级。input、popup、pin和布局结束路径共用被动修复；pin只决定点击外部是否保留，未固定也默认浮动。显式输入仍可聚焦编辑器，被动修复及fit本身不show/focus/activate或改变几何。

macOS新`macos_window.swift`通过生产C ABI同步设置`.floating`、`.canJoinAllSpaces`和`.fullScreenAuxiliary`，清除互斥位并保留无关行为。Windows用TOPMOST与NOACTIVATE/NOMOVE/NOSIZE恢复层级，不包含SHOWWINDOW。没有因此触发屏幕录制、辅助功能或凭据访问。

| 本轮验证 | 结果与边界 |
|---|---|
| Rust全量 | **126/126通过**，0失败；含普通展示前移/固定原位更新分支及生产Swift mask ABI的幂等和冲突位回归 |
| 前端单元／类型／构建 | **60/60通过**；check、生产前端build、fmt及diff通过 |
| 完整隔离UI/IPC | **通过**；普通blank/input/selection在已可见且已固定时仍传`reuseVisiblePopup=false`，只有标记的固定OCR更新传true；保留此前迟到OCR、管理页、编辑、关闭及取消回归。只验证分派，不算原生层级实测 |
| 同ABI隐藏原生窗口 | **通过**；3种style状态调用生产`echolingo_ensure_popup_behavior`，`levelAboveNormal=true`，frame/visibility/key/main/应用激活状态保持，后台线程调用被拒绝；`windowVisible=false`、`windowKey=false`、`windowMain=false`、`userWindowAccessed=false`、`permissionRequested=false`、`screenCaptured=false` |
| 安装版原生层级元数据 | **pin on/off两状态主窗均为layer 3，高于normal 0**；同一PID81126、主窗bounds 640×752，两份样本均`onscreen=false`。这是本进程主窗层级证据，辅助窗口的layer 0条目不算主窗 |
| 物理遮挡／当前Space | **未验收**；onscreen=false的元数据与隐藏夹具不能证明浮窗实际位于其他应用之上、当前Space/全屏可见、不抢源应用焦点或680px popup尺寸 |
| 原生包／签名／安装 | no-sign整包37.79秒完成，归档CRC/SHA及新ICNS匹配通过；归档内未签名主程序SHA-256为`453fc118588c516148dfa720c24c03ee289cc427674e8abda128115f4975cfd2`。随后本次获准的**一次codesign在14.431秒成功**，deep/strict及固定DR通过，已安装为上方`f1cf4027` |
| 新版设置及pin交互 | 两权限仍“已授权”，MiniMax和停用OpenAI示例“凭据未读取”；pin on/off均有UI响应。Escape后返回`noWindowsAvailable`，未再重启，最终进程仍PID81126 |
| 数据保存与清理 | 设置/history与本次紧邻安装前digest完全相同；两轮之间历史已有正常新增，不拿上轮hash当基准。旧d87backup及签后stage已Trash，LS-u两路径各退出1、canonical-f退出0；最终inventory一canonical、一verified PID81126，strict/deep与安装icon匹配通过；最终记录已并入证据文件 |
| 本次系统访问边界 | 未执行runtime API、OS凭据读取或TCC/ACL操作；签名密钥访问不等于读取API凭据。此前21.437秒授权未重用，本次14.431秒单次签名替换授权已消耗 |

本轮原始证据位于仓库外`/Users/wwq/Documents/Codex/2026-10-24/ni-ne/work/popup-raise-20261025/`，包括`rust-tests.log`、`ui-regression.log`、`native-hidden-window-fixture.json`、最终`build.log`及`installed-{pinned,unpinned}-window-metadata.json`；[精确证据](validation/popup-raise-20261025.json)。下方`d87ef732`安装、清理及124/60验证保留各自的历史范围；本轮安装及layer 3元数据也不等于物理遮挡/当前Space/全屏已完成实机验收。

## 2026-10-25 前轮安装版：固定浮窗 OCR、宽窗与已采用图标

该轮用户明确要求“请你删除旧版 然后安装新版”，完成一次固定身份签名及事务替换。当时规范应用为`/Users/wwq/Applications/EchoLingo.app`，主程序SHA-256 `d87ef7327be767eafdc452f47f23bb4310c9f90efd2a398a6c4ddd7daaa17519`，最终PID78939；现在已被上方`f1cf4027`取代。以下保留该轮源码/隔离回归、安装核验与当时的原生交互边界。

定位到原生动作入口对所有截图操作执行主窗`hide`，因此固定浮窗也会消失并在结果返回后重新展示。现在只在“已经可见、已固定且当前为翻译浮窗”时保留窗口；使旧翻译ticket失效但保持`presented=true`。成功OCR原位填充并自动翻译，`show_popup`不对已经可见的浮窗重复执行原生show。管理页、隐藏窗口与未固定浮窗不会误用这条路径。

取消、识别为空或失败时保留上一份已完成原文/译文；尚未完成的旧流式片段仍清除，不能当作已完成结果保存。真正关闭和新的展示epoch继续生效。前端以`updateVisiblePopup`及新epoch后的generation基线处理原位更新，手动编辑、手动翻译或进入管理页后的迟到OCR不能覆盖当前内容；这些最后新增的保护已通过完整隔离UI回归。

| 本轮验证 | 已完成的结果与边界 |
|---|---|
| Rust全量 | **124/124通过**；含保留固定展示、旧ticket取消及迟到进度/历史阻断、已隐藏/管理页边界，以及既有窗口、凭据、协议与历史回归 |
| 前端单元／类型 | **60/60通过**；`npm run check`通过 |
| 最新完整隔离UI/IPC | **通过**；覆盖管理页、直接编辑、Alt+A键入、手动翻译后的迟到OCR保护，正常自动翻译，旧epoch及缺失/未来epoch拒绝，关闭后不复活；前端agent session 22902退出0，stdout仅由工具返回，没有磁盘日志 |
| 生产前端构建 | **通过**；最新合并源码的Vite构建完成，报告耗时98ms；不等于原生安装包构建通过 |
| macOS14+截图 | 沿用ScreenCaptureKit排除本进程窗口的已有实现；未在安装版执行本轮真实截图 |
| macOS12/13截图 | 新增仅PID/ID投影、排自身/未知/无效记录、保持原序、raw CGWindowID CFArray编码及显式窗口合成；准备失败不退回全屏。只有最低macOS12目标编译和纯夹具通过，不是旧macOS实机截图通过 |
| 原生纯夹具 | 两份生产Swift源以arm64 macOS12 deployment target优化编译后，`--capture-selection-self-test`通过；输出`ok=true`、`captureSelectionFixturePassed=true`、`captureSelectionDeadlineFixturePassed=true`、`screenCaptured=false`、`permissionRequested=false`。未读取真实桌面 |
| Windows排除策略 | **7项纯后端夹具通过**：支持版本/窗口条件、先保存旧affinity、设置并读回排除状态、正常/错误/取消恢复及失败停止。不是Windows实机或新Windows构建验收 |
| Windows视觉限制 | 现有WinForms选择器仍绘制冻结快照并加暗层；即使主窗没有hide，选择器仍可能在视觉上遮住它。因此不宣称已达到Mac透明实时选择器或Bob的全部体验 |
| 合并包与保留归档 | **no-sign原生合并构建37.96秒完成**；签名前归档CRC/hash和内置新ICNS一致性通过。归档内未签名主程序SHA-256为`4b45bdddfe7a775fc86c3cd138837d7d0b1e12345c24e97609dc477ab2ddbf44`，与签名后安装主程序摘要分开记录 |
| 本次签名／安装 | **一次codesign成功，21.437秒**；deep/strict验证及固定证书designated requirement通过，安装后主程序为上方`d87ef732`摘要。初次启动PID78613；为清理测试临时pin/视图状态，同二进制正常重启为PID78939 |
| 用户数据／系统动作 | settings/history与紧邻安装前hash一致。没有真实翻译、运行时Keychain读取、新权限申请、真实桌面OCR或GitHub上传；签名密钥访问与运行时API凭据访问分开记录 |
| 新版设置页／pin | CUA看到辅助功能和屏幕录制均“已授权”，MiniMax及停用OpenAI示例均“凭据未读取”；pin on按钮可响应。此观察不证明完整原生快捷键、OCR或连续API认证已通过 |
| 新版原生窗口／OCR可见性 | **未计通过**；后续CUA仍能操作没有onscreen标记的窗口，返回DOM及frame为640×752；CGWindowList `.optionAll`无`IsOnscreen`标记，app为`hidden=false`，shell样本正常idle。这是自动化可见性边界，不能据此断言新布局bug，也不能确认原生680宽度、边缘拖动或重复OCR成功/取消时固定窗的物理可见性。最后Escape返回`noWindowsAvailable`后正常重启清理测试状态 |
| 清理与应用入口 | 安装旧backup和签后staged app已移至废纸篓；源码、非app缓存、归档和用户数据保留。Launch Services unregister两路径分别退出1（未注册），canonical `-f`注册退出0。最终配置目录inventory仅1份canonical应用、1个已验证进程PID78939；strict/deep、安装ICNS匹配及settings/history hash一致通过 |

原生纯夹具二进制在`/Users/wwq/Documents/Codex/2026-10-24/ni-ne/work/capture-selection-legacy-fixture`；root保存的sanitized stdout位于`/Users/wwq/Documents/Codex/2026-10-24/ni-ne/work/pinned-ocr-20261025/native-fixture.json`。初次Swift编译遇到旧C API在Swift3已重命名的错误，已改用`CGImage(windowListFromArrayScreenBounds:windowArray:imageOption:)`后重新编译并通过；失败记录不计通过。

Windows在截图期间临时使用经验证的`WDA_EXCLUDEFROMCAPTURE`，结束后立即恢复原affinity，早于网络OCR及凭据读取；老版本或设置/核验失败时停止本次截图，不隐藏固定窗或接受黑块为正确结果。[Microsoft支持范围及旧系统行为](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-setwindowdisplayaffinity)。真实Windows仍需验证GDI截图排除、恢复和选择器视觉行为。

本轮修复与下方宽窗/已采用图标已合并安装，取代旧`73c039e5`包。前轮宽窗暂存app及本次旧backup/签后staged均已移至废纸篓，保留归档不等于额外可运行安装版。本次授权已执行一次，不重复签名或索取权限；固定OCR成功、取消及错误保留的物理可见性、原生拖宽/重启恢复与系统图标展示仍须实机验收。[精确源码、包和安装证据](validation/pinned-ocr-20261025.json)已合并最终核验；原始签名/安装/清理及`final-verification.json`记录位于仓库外`work/pinned-ocr-20261025/`。

## 2026-10-25 历史源码检查点：宽窗、宽度记忆与已采用附件图标

浮窗默认680逻辑像素，常规最小420，最大值由当前屏幕工作区决定；极小工作区优先保证窗口可见。左右各4px透明边缘可拖宽，管理页或模态窗口不显示该入口。宽度独立保存在应用数据目录`window-layout.json`，管理页尺寸及临时工作区/DPI限制不覆盖用户的浮窗宽度偏好。布局与缩放不主动显示、激活或聚焦窗口。

固定依赖的macOS Tao没有原生drag-resize实现，因此Mac使用pointer capture、`screenX`增量及合并/串行化的`resize_popup_width`请求；Windows分派原生`start_window_resize`。请求带展示epoch并核对当前可见浮窗，左边缘保持右侧锚点。`fit_window`的缓存键包含真实视口`contentWidth`，宽变而高不变也会适配，后续高度调整不会恢复固定默认宽度。

| 本轮验证 | 结果及范围 |
|---|---|
| Rust | **114/114**；包含窗口默认/工作区尺寸、独立宽度持久化、管理页隔离、临时屏幕/DPI限制及左侧Retina锚点等纯逻辑回归；不等于原生窗口拖动实测 |
| 前端单元 | **60/60** |
| 完整隔离UI/IPC | **通过**；真实浏览器鼠标在左右边缘拖动分别产生600/605宽度请求，680→850同高时仍提交新宽度，后续高度适配保留850；pin/输入/标题拖动隔离，隐藏及epoch变更丢弃排队请求，管理页入口隐藏且无效 |
| Windows缩放 | 假IPC验证原生命令及epoch分派；未在Windows桌面执行实际拖动 |
| 680宽度视觉 | 合成英文长原文、中文结果的浅/深主题截图已目检，结果朗读/复制常驻且无水平溢出；不是系统窗口或真实API截图 |
| 类型/生产前端构建/格式/diff | **通过** |
| 已采用附件图标 | 原样母图[approved master](../assets/branding/echo-geometric-v4-approved/echolingo-icon.png)1254×1254 RGBA，SHA-256 `fb6bb0c1475f32100cddd953474275e2f8213d6a9296e81416a806e54b514440`；生成17个平台资源，PNG尺寸/透明角、ICO16/24/32/48/64/256及ICNS16–1024尺寸检查通过 |
| 该检查点签名/安装/系统访问 | **当时未签名、未安装**；没有真实凭据读取、权限操作、API请求或GitHub上传。当时规范安装为73c039包；后来已与OCR修复合并安装为上方d87ef732版 |

本轮图标来自用户明确指定的附件，已采用并生成资源；下方“待确认”仅描述旧生成候选图的历史状态。当前尚未在新安装包验证原生左右拖动、管理页往返和重启恢复、跨屏/DPI行为及macOS/Windows系统图标实际展示。新源码检查不能替代这些原生验收，也不改变下方73c039安装包的真实凭据访问边界。

## 历史图标候选：原极简几何 v4 生成图

用户要求同时体现 echo 与翻译，否定过度抽象的折带方案，并明确选择“极简几何：干净、克制，重视轮廓”。当时新增 [v4主图与完整提示词](../assets/branding/echo-geometric-v4/design-notes.md)，采用 e／文和错位对话轮廓；内置 image_gen 生成，`sips` 实读1254×1254、hasAlpha=yes。已目检两字形与主要轮廓；结果有轻微色调变化，不宣称严格纯色矢量实现。当时这份候选的反馈待确认；后续用户指定附件的采用状态见上方最新记录。

此前 [v3交错折带及EchoPaper配对探索](../assets/branding/echo-dialogue-v3/design-notes.md) 已标记为被否定；EchoPaper 的论文写作／排版定位已记录。未修改运行时代码、正式图标或安装版，不重跑软件功能测试；尚无16/32px、矢量母版、单色托盘及平台图标包验证。

## 前次图标设计稿：echo 系列

新增 [回声折带设计稿及提示词](../assets/branding/echo-fold-v1/design-notes.md)。内置 image_gen 生成主图及参考主图的系列配色板；`sips` 实读主图1254×1254、hasAlpha=yes，配色板1536×1024。已目检单图的 e 形回环、右下折面及无文字构图，并确认系列板包含四款同母体配色、仅第一款标记 EchoLingo。

仅新增概念 PNG 和说明，未覆盖原 SVG/ICNS/ICO、修改运行时代码、构建或替换安装版，因此本轮不重跑软件测试，不新增功能验收结论。尚未制作或验证16/32px图标、单色托盘、矢量母版及平台图标包。

## 2026-10-25 前次安装：凭据会话修复与同款结果框

本次将运行时认证与此前codesign签名提示分开排查。前包10963324的源码中，`get_settings`会对所有服务经`load_key`调用`get_password`，翻译、连接测试、OCR又重复读取；这些调用可能触发系统凭据访问，不能用签名行为解释全部运行时提示。此前未安装的视觉包仅增加结果框样式，**不含此次缓存修复，因此不是“只需安装那份视觉包即可解决”的问题**。现在缓存修复与结果框已合并签名并实际安装。

新增按账户及协议/端点origin隔离的进程内凭据缓存，成功、缺失及拒绝均缓存，并合并并发读取。缓存不实现携带密钥的Debug/serde/日志输出。设置快照仅`cache.peek`元数据，区分unloaded、blocked、missing、ready，**不查询OS凭据**。保存/删除按准确scope原子失效并处理进行中的旧读取；仅设置页明确连接测试可经原子`retry_if`重试失败读取。

密钥读取放入`spawn_blocking`，避免在Tokio工作线程同步阻塞。共用读取门禁串行化不同账户的首次访问；取得门禁后再次检查翻译ticket，排队期间已取消的请求不会继续开启下一次系统提示。已经打开的OS认证框无法由应用强制取消。缓存仅在当前进程生效，不修改系统访问规则，也不承诺重启后永久无提示。

| 验证 | 结果与范围 |
|---|---|
| Rust | **108/108**；10次顺序读取仅调用1次loader、12并发仅1次、失败缓存直至明确重试、账户/协议scope、保存/删除/进行中读取失效、原子重试竞态及取消门禁等待 |
| 前端单元 | **60/60** |
| 完整隔离UI/IPC | **通过**；未加载状态不冒充密钥缺失、读取状态不携带原始密钥、原生OCR选择和设置测试后刷新等；不等于真实钥匙串授权验收 |
| 凭据/系统动作 | 夹具验证设置快照零OS查询；没有运行时API凭据读取、真实翻译API测试、ACL/partition-list/trust或TCC修改。后续仅执行了用户明确授权的那一次最终codesign |
| 打包与签名 | 合并no-sign构建33.38秒，未签名归档CRC/hash通过；用户随后明确授权一次最终签名替换，90.591秒成功，由用户处理系统确认，无认证自动化或ACL更改；严格deep验签及固定指定要求通过 |
| 实际安装 | canonical `/Users/wwq/Applications/EchoLingo.app`，主程序SHA-256 `73c039e540ac84781b636bd067cba0133bf7372be0ceff7642375652562fc3d1`，PID74225；包含会话缓存和同款结果框。settings/history与紧邻安装前字节一致 |
| 实际设置页 | CUA看到MiniMax及已停用OpenAI示例均显示“凭据未读取”，辅助功能及屏幕录制均“已授权”；没有启动运行时API凭据读取或真实翻译API测试 |

一次签名替换授权已用完，不得继续签名。安装成功及设置快照不能证明连续真实翻译的认证提示已经解决；会话缓存的去重由108/60及隔离测试证明，尚未触发用户真实凭据来完成原生连续API调用验收。首次系统提示、连续翻译访问次数及跨重启行为仍待受控核验，不能承诺永久无提示。物理首击、原生IME/全局快捷键、多屏和Windows限制保留。[凭据会话证据](validation/credential-session-20261025.json)。下方保留前轮包及验证历史。

## 2026-10-25 前次：流式结果、操作按钮与原文感知排版

OpenAI兼容服务已接入生产 SSE 渐进回调，并按 MiniMax 官方 `reasoning_split` 约定分离推理与答案；界面仅呈现答案。首个答案片段立即发送，后续累计结果最多每35ms更新，网络总量上限2MiB。错误、截断和取消不自动重试，失败或取消的半成品不写入历史。前端按请求编号、展示epoch、服务编号、序列及完成状态过滤过时事件；结果更新与结束保持原DOM和复制按钮焦点。每条结果底部常驻复制、朗读按钮；pin用倾斜描边/竖直实心图区分状态。

Apple系统翻译仅在原文没有明确空白段落和受保护代码时清理新增空行；不将该规则应用于所有服务或用户原文。19项纯原生夹具验证此策略，没有运行Apple翻译引擎。

| 验证 | 结果与实际范围 |
|---|---|
| Rust | **93/93**；本地HTTP验证首片段早于响应完成、累计内容、大小边界、错误/截断/取消、不重试及不存半成品历史 |
| 前端单元 | **57/57** |
| 完整隔离UI/IPC | **通过**；进度事件保护、稳定DOM与按钮焦点、常驻结果操作、pin状态及既有编辑/取消/IME/隐私回归；不等于真实云或原生键盘验收 |
| Apple格式夹具 | **19项纯原生策略夹具通过**；不调用系统翻译引擎 |
| 源码/类型/生产构建/格式/diff | 通过 |
| 首包构建、签名、安装 | 优化no-sign构建37.81秒，一次固定证书签名5.625秒成功，指定要求保持；安装主程序SHA-256 `1096332442f661c03a548de2761363651d10b4690b26b3d2d8f553b63d49cd18`，PID71503 |
| 安装版权限与数据 | 设置页两权限均显示已授权，无新权限操作。计划原生测试临时关闭历史后已恢复；settings/history与安装前字节一致，未改凭据库 |
| 当时后续结果框样式 | 浅色800px、深色420px的边框/背景/圆角与输入框一致，隔离UI通过；视觉单独包no-sign优化构建33.65秒，当时保持未签名、未安装归档；不含后来的缓存修复 |

用户随后明确反馈反复出现的是钥匙串/codesign密码提示，因此已停止一切后续签名和原生推理，没有再次尝试签名，没有修改钥匙串ACL/partition-list/trust或TCC。计划中的原生推理在任何请求前停止；本轮真实外部API调用、原生翻译引擎请求及GitHub上传均为0。流式进度结论来自本地HTTP和模拟IPC，不是新的MiniMax实网测试，也不宣称Apple能逐token输出。

**该阶段安装的109633包包含流式、pin、结果操作栏和Apple空行策略，当时不含同款结果框。** 当时只有视觉修复的未签名归档，停止后未继续操作。后来的缓存与结果框合并包已另经用户一次授权签名并安装为上方73c039版，不将前轮未安装状态当作当前状态。物理不活跃首击、原生IME/全局快捷键、多屏及Windows真实交互仍保留原验收限制。[前轮精确证据](validation/stream-pin-format-20261025.json)。下方运行时章节均为前包历史记录。

## 前次：原文编辑、固定按钮、断行及特殊字符

本批已完成固定证书签名并替换 `/Users/wwq/Applications/EchoLingo.app`。主程序 SHA-256 为 `83cb3836028b7eca52dc3d11bf6f3ecd212a36773a4d94119f3a0cb6e64de9de`，安装进程PID67595。构建39.68秒，一次签名5.389秒，严格deep验签通过。安装前后设置/历史摘要一致，未操作凭据库。新包保留录屏及辅助功能true，**本次跨构建替换没有再次授权**；旧备份和暂存包均进入废纸篓，物理/Launch Services/Spotlight各仅canonical一个入口。

| 验证 | 结果及范围 |
|---|---|
| Rust | **81/81**，增加技术标识、下划线/分隔符/camelCase/符号包装与外语、多脚本、纯符号反例 |
| 前端单元 | **57/57**，窄正文续行、专名、单词短行、段落/标题、YAML/shell/代码保护 |
| 完整UI/IPC | **通过**；32px按钮边缘/图标/Space点击、仅空白拖动；捕获后及翻译中点击键入、旧票取消与修改后重译；不是原生不活跃窗口首击验收 |
| 原生安装版 | `- quiet-pin:`→`-安静针：`、`quiet_pin`→`安静_针`；点击原文并真实键入`_edited`后源变为`quiet_pin_edited`，按钮重译为`安静_针_已编辑`；pin点击on/off通过，无成功toast |
| 类型/前端构建/格式/diff | 通过；原22项安装回滚夹具对应未变的安装脚本，没有将其冒充新执行次数 |

启用主窗 `acceptFirstMouse`，使macOS不活跃WebView可接收第一次点击；这是[Tauri支持的配置](https://v2.tauri.app/reference/config/#acceptfirstmouse)，并与[Apple首击机制](https://developer.apple.com/documentation/appkit/nsview/acceptsfirstmouse(for:))一致。CUA会激活目标应用，故不能以它的按钮点击证明物理不活跃窗口首击。自动化Return发送后切回设置，未据此宣称原生Enter通过；浏览器Enter/IME/编辑后提交全部通过。实际原文可编辑和按钮重译有独立原生观察。

评审发现最初放宽续行会误并短YAML/shell、以及跨完整句传播到小标题，已补结构保护和句组边界；对应反例通过。完整UI最初因`managementShows`惰性初始化竞态中断，改为夹具初始数组后通过；最终重跑一次曾因Vite服务已退出而连接失败，重新启动自有服务后全套通过，不计为产品功能失败。最后已停止测试服务。

技术标签仍完整传给服务，识别提示不改原文。明确外语/其他脚本及用户手选语言保留；不保证无结构单词的语言猜测或所有术语译法。原文无坐标时无法完美区分每个段落，原始换行恢复入口保留。无新外部API调用、密钥文件或GitHub上传。见[精确证据](validation/interaction-polish-20261025.json)。下方为上一包79/52的历史范围。

## 前次：两个核心工作流、历史、主题与收藏

最终范围为选词快捷翻译、Alt+S 左键无感 OCR 填入并自动翻译；保留主题、收藏、必要 API/OCR/快捷键/权限设置。历史默认20条，可调1–100；收藏优先保留但也占总上限，下调条数保存后立即清理。倒计时已从界面和运行逻辑移除。空 Alt+D 聚焦输入框可直接键入，取到非空选文时仍先取词再被动展示。默认中英方向、短中文、简繁及手动固定目标都有路由测试。

| 验证 | 实际结果与范围 |
|---|---|
| Rust | **79/79**；含新语言路由/迁移、默认快捷键、即时历史上限及文件失败回滚、生产 C ABI 的框选/授权请求策略等 |
| 前端单元 | **52/52** |
| 完整 UI/IPC | **通过**；空选区直接键入、原文复制/朗读、自动/固定目标、授权状态矛盾、主题实际切换、收藏/取消/筛选、历史37与101拒绝、原有取消/IME/隐私等；浏览器假 IPC，不替代安装版验收 |
| 安装回滚夹具 | **22/22** |
| 原生 CLI | 私有剪贴板、实际 Vision 生成图识别、坐标/状态/超时/取消通过；识别为 EchoLingo translation 2468，Vision单次141.773ms，不是端到端或冷启动延迟 |
| 原生选择器实际交互 | CUA 从透明中心左键拖动返回有效选区；Esc返回CANCELLED并退出。独立测试app复用生产原生代码，无 TCC 请求/图像获取/OCR/翻译；实际仅一块显示器，未验跨屏拖动 |
| 类型/前端构建/格式/diff | 通过 |
| 优化 app | **构建通过，38.65秒**，--no-sign 后一次固定证书签名成功86.562秒，严格验签后已替换 canonical 应用 |

测试中授权矛盾夹具最初放在刻意挂起的权限动作内，按钮正确禁用导致测试失败；移至动作已完成的设置状态后完整回归通过。旧快捷键测试最初假设默认条数为4，调整为与实际基线比较后通过。透明窗口的 CUA 截图为白色，不能用它证明真实桌面无视觉遮挡；成功选区与取消依据夹具返回 JSON。临时测试 app 已进入废纸篓。

用户明确要求替换后，已完成一次固定证书签名及严格 deep 校验，替换 canonical `/Users/wwq/Applications/EchoLingo.app`（主程序SHA-256 `8cf722e8a54d0f2b7284cb77f4898c80dccc8e07f0e8f914c860403f6031ae55`）。签名等待86.562秒，期间SecurityAgent存在；未自动操作该安全应用或绕过系统认证。安装前后 settings/history 摘要一致，未改凭据库。暂存包和旧备份已移入废纸篓，物理清单、Launch Services、Spotlight 各只剩 canonical。新版设置实际显示20条、主题跟随系统、Alt+S无感OCR、本机OCR。

录屏开关 on / canonical 进程检查 false 的矛盾已在这份安装包上修复。一次新版显式设置验证仍未确认权限后，用户授权只重新登记此应用的两个权限，并亲自完成一次系统认证；没有自动操作 SecurityAgent、调整钥匙串 ACL 或读取/重置 TCC 数据库。准确重加 canonical 录屏条目后 PID64940 的录屏检查为 true；单独开启旧辅助功能条目后，PID64984 仍为辅助功能 false、录屏 true；准确移除旧辅助功能条目并重加 canonical 后，最终正常退出重启的 PID65034 两项均为 true。**本次同版重启授权保持已实测通过**，不能外推到未来构建或所有重启。

| 安装版实际核验 | 结果与边界 |
|---|---|
| 规范安装、签名及单副本 | 上述摘要/签名通过；物理清单、Launch Services、Spotlight 各仅一个 canonical |
| 重登记录屏 | PID64940，screenCaptureGranted=true、screenCapturePreflightGranted=true |
| 辅助功能及同版重启 | 最终 PID65034，accessibilityGranted=true、screenCaptureGranted=true、runningBundledApp=true |
| Apple 系统翻译自动方向 | CUA 在实际安装版中以源/目标均 auto，`你好` → `Hello`，`Hello, world.` → `你好，世界。`；未发起语言下载或外部 API 调用 |
| 受控 Alt+D/OCR 自动化 | 合成 Alt+D 注入未见视图切换；后续交错出现本聊天的一段权限进展及英文，但触发来源不清，不计为受控选文或 OCR→翻译通过 |
| 用户实际反馈 | 用户随后明确表示“已经可以了”，确认两个核心流程基本可用；这是用户验收反馈，不等同于完整自动化矩阵通过 |

用户接着反馈同句换行未合并、pin 太小难点、捕获文字难以编辑，以及 `- quiet-pin:`、下划线和其他符号识别不准。当时79/52及此处旧摘要不涵盖这些后续改动；修复安装结果已在上方最新章节单独记录。跨屏实际交互、完整IME/目标应用矩阵仍待验收。Bob普通设置已观察、输入快捷键尝试未唤起浮窗，不计为Bob功能测试通过。

[精确证据](validation/capture-language-focus-20261025.json) · [权限调查](permission-investigation-20261025.md)

## 前次：浮窗、取词、设置入口与本机翻译

本轮移除钉住/取消钉住成功提示及紫色填充，清理被动展示时残留的内部焦点。macOS 原生取词补充有实际选区时的 AXStringForRange 回退、前台 PID 一致性与安全输入框拒绝；没有授权或空选区仍安静打开。系统权限不会由热键或刷新自动申请。

设置页现在可从托盘首项「设置与服务」、macOS Cmd+, 以及显式重新打开应用进入。管理 DOM 与尺寸准备后才激活窗口，普通冷启动仍静默；旧窗口外点击与迟到的展示不能影响新管理页。测试覆盖 API/OCR/快捷键区域可见及新取词打断迟到的设置展示。

新增 Apple Translation 系统服务。新 macOS 配置默认启用；已有 API 选择保留，只补一个停用的系统选项。免激活直接会话需要 macOS26+，应用仍以 macOS12 为最低启动版本。设置中可选择语言对、检查、显式准备语言包；只在用户点击后出现 Apple 原生准备界面。准备调用返回后还会等待精确语言对已安装，支持取消与180秒上限。翻译只用 installedSource 会话，并检查 canRequestDownloads=false；没有语言包时明确指向设置，不自动下载或云端回退。[官方依据与 Windows 能力边界](system-translation.zh-CN.md)。

独立审查发现外层取消不自动终止 spawn_blocking 中的本机任务，已修复为操作编号匹配的 Rust Drop → Swift Task → Apple session 取消；注册前取消竞态由有界 tombstone/attach gate 处理。Rust 许可保留至阻塞任务实际结束，原生注册表也只允许一项活跃任务。纯夹具通过实际 Task.sleep 验证取消、注册前/后竞态及其他编号隔离；没有借此伪造真实翻译调用。

| 本轮验证 | 结果与范围 |
|---|---|
| Rust | **65/65**，含本机生产静态 C ABI 的系统策略/取消夹具，既有本地 HTTP/历史/权限/几何/原生 OCR 测试 |
| 前端单元 | **51/51**，新增系统服务网络字段拒绝、预设、密钥状态与保留现有配置检查 |
| 完整 UI/IPC | **通过**；空 Alt+D、透明 pin/键盘反馈、管理 epoch、语言对/只读检查、显式准备、不可用平台、系统服务保存/删除零凭据 IPC，及既有 IME/取消/隐私；是假 IPC 的浏览器回归 |
| 安装工具 | **22/22** 虚构 bundle 安全/回滚夹具；最初错误地以 tests 目录匹配得到0项，随后使用 scripts/test_macos_preview.py 正确执行22项，不将0项算验证 |
| 类型/生产构建 | 通过；Tauri 优化 Apple Silicon app 构建34.96秒，使用--no-sign，最终签名/安装另记 |
| 原生编译/链接 | macOS12 target 编译通过，最终 app 的 Translation 与 _Translation_SwiftUI 都为弱链接；不等于旧 macOS 实机通过 |
| 本机语言状态 | en→zh-Hans 和反向均 supported/downloadRequired；**没有执行真实系统翻译或下载** |
| 原生 CLI | 纯策略与实际 Task 取消通过；较早完整自测的私有剪贴板/真实 Vision 通过，OCR 单样本25,184ms异常保留，未为了挑快结果重复运行 |

800px 设置页及系统准备区已目检，无横向溢出。新增 UI 测试首次按 Apple 服务名匹配不到由前端创建的“系统翻译”，修为读取实际服务名后完整回归通过。实际安装版 UI、跨应用划词、Apple 下载确认与译文、录屏授权后同版重启仍未验收。CUA 原生应用选择超时，不通过其他 UI 自动化绕过。Windows 原生脚本未变，本轮没有新 Windows CI/实机验收，也没有 GitHub 上传。详见[精确证据](validation/quiet-pin-native-settings-20261025.json)。

## 本轮钥匙串弹窗与签名

用户截图中反复询问密码的是本次创建本地签名身份时运行的 identity-restrict-acl 工具；不是屏幕录制权限框。虽然工具设置了禁止交互标志，实际仍弹出访问权限更改提示，用户报告至少5轮密码。已停止工具，并禁止再次自动调整登录钥匙串 ACL/partition-list/trust。不能把工具自己的非交互标志当成“没有弹窗”的验证。

本地证书 SHA-1 为3FCAC2D2ED3F94CF57568EB4766B5F3337C98510，密钥留在 OS Keychain、未导出。两个不同代码夹具严格验签通过，指定要求均绑定 bundle identifier 与该证书，而非随内容变化的 ad hoc cdhash；它们不证明实际 TCC 授权保留，证书也不是 Developer ID 或 Apple 公证。用户授权的一次 app 签名命令在0.02秒内因旧 echolingo.cstemp 失败；无效 staged bundle 已移入废纸篓，干净新版已重建。用户另行授权一次最终 codesign，结果及实际安装见证据文件；未进行 ACL 修改或自动签名重试。

最终 codesign **一次成功，3.50秒**；严格 deep 验签及证书绑定指定要求通过。已安装 `/Users/wwq/Applications/EchoLingo.app`，签名后主程序 SHA-256 `1e064de5ab3be19c9bb829e422b2b6bc48af6e53fbc2488a150cc799bf95f599`。无效旧 staged、新 staged 与本次旧安装备份均进入废纸篓；扩展物理清单、Launch Services 同 bundle ID 查询、Spotlight 各只有1个 canonical 路径。其他应用数据未改。

通过正常 Launch Services 启动新版并由其进程内诊断读取：PID58934，runningBundledApp=true，辅助功能=false、屏幕录制=false。未自动请求或重置权限；该结果说明还需要通过新版设置授权，不能把跨代码夹具的稳定要求当作实际授权保留。初次只读探针报告无 layer0 常规窗口/未激活，但旧探针遗漏浮动层，因而不能单凭该结果证明完全没有窗口；已修复探针统计所有大于100×100的自有屏上窗口。显式重新打开应用后新探针报告1个屏上浮动窗口并已前台激活，符合管理展示路径；未收集窗口标题/截图，也不据此声称 WebView 内容或真实权限动作已验收。

## 本机重复应用清理

用户要求仅保留最新版后，核验出5个可见应用及1个隐藏备份，保留 `/Users/wwq/Applications/EchoLingo.app`（权限指引修复版，摘要与下方安装记录一致）。其余4个可见副本和1个隐藏备份已通过系统 Trash API 移入废纸篓；逐项校验应用身份与摘要，不清空废纸篓。旧安装回退和构建 bundle 因此次明确请求而移除，源码、设置/历史/凭据及 DMG/EXE 文件保留。

清理后扩展文件清单、原生 Launch Services 同 bundle ID 查询及 Spotlight 均仅返回上述1个路径。4个可见旧入口注销及最新版注册成功；隐藏备份注销返回1，但随后原生注册表查询确认没有其入口残留。未重新构建或启动应用，也未请求权限。[精确清理记录](validation/copy-cleanup-20261025.json)。

## 权限入口与首次使用指引修复

用户截图中的错误只提示缺少权限，没有可点击入口。确认原先后端去掉了 `PERMISSION:` 标记，前端却仍按该标记附加指引；此次改为单个带 `permissionRequired` 和展示 epoch 的原文事件，先准备权限卡并完成尺寸计算，再展示浮窗，避免提示与空白原文事件相互覆盖。

- 缺屏幕录制权限的截图翻译、识字和静默 OCR 显示持久权限卡，提供「打开系统设置 ↗」「首次授权指引」及关闭按钮。不会因旧 toast 计时器消失。
- 直接跳转使用原有固定原生设置面板；点击才执行。跳转失败时保留手动路径，不显示底层原始错误。
- 首次授权步骤解释请求授权、系统开关、「+」添加应用及系统要求的重新打开/刷新。修复了首次打开设置时，另一个权限操作尚未完成可能导致指引隐藏的问题。
- 空 Alt+D 仍然安静；启动、快捷键、刷新和重新聚焦不自动申请权限。真实服务错误与剪贴板恢复失败仍保留。

本机 **54 项 Rust、47 项前端、完整隔离 UI/IPC 回归、22 项安装工具夹具通过**；类型检查、生产构建、格式/diff 检查通过。UI 回归覆盖按钮点击及固定目标、失败保留、忙碌时首次指引、授权后清理、过期事件、表单编辑期间延后处理及原有 IME/取消/隐私流程。800px 浅色、420px 浅色/深色截图已目检，无按钮重叠或横向溢出。420px 为正常桌面窗口最小宽度，最初320px截图断言因既有最小宽度不成立，改用受支持的420px后全部通过。

已实际构建并安装到 `/Users/wwq/Applications/EchoLingo.app`，保留旧版回退，签名完整性和新可执行文件摘要均核验；SHA-256 为 `a01a600c007aa6370598bb98bdaf44e663e7bc2924a7855a06712b3f562d44fb`。新实例 PID52420 后台启动，元数据检查普通屏上窗口为0且没有前台激活；该应用也包含前一轮新增的 MiniMax 预设。未改用户设置、历史或凭据。[精确构建/安装/测试证据](validation/permission-guidance-20261025.json)。

CUA 原生应用清单入口30秒超时，未自动验证真实系统设置跳转或授权。UI测试的系统操作是模拟 IPC；macOS 开关仍由用户确认，未自动授权、重置 TCC 或宣称完成端到端截图验收。当前 ad hoc 预览重建后仍可能需要重新授权。指引路径及「+」添加应用依据 [Apple 官方说明](https://support.apple.com/zh-cn/guide/mac-help/mchld6aa7d23/mac)。远端 CI、DMG/NSIS 与发行草稿未更新；下方性能结果属于前次硬化版本。

## MiniMax 真实账户补充验证

用户明确授权后，使用 `MiniMax-M3.1-Flash` 向中国站 `https://api.minimax.cn/v1` 顺序发送 **7 次真实请求，7/7 通过，无重试或模型切换**。独立临时 Rust harness 直接导入并调用仓库生产 `translate_one` / `recognize`，使用原有默认请求与 45 秒超时；没有另写一套请求体代替产品实现。模型及图片格式已对照 [MiniMax 官方接口文档](https://platform.minimax.cn/docs/api-reference/text-openai-api)。

| 用例 | 观察结果 | 函数耗时 |
|---|---|---|
| 英文→简体中文 | 双段落、09:30、`retry_count = 3` 保留 | 1,401 ms |
| 中文→英文 | 双段落、时间含义、变量保留 | 1,323 ms |
| 英文→繁体中文 | 出现軟體、檔案、雲端、網路等目标字形 | 1,010 ms |
| 指令句作为翻译原文 | 翻译完整指令句，没有仅输出其要求的标记 | 1,137 ms |
| 中英混排生成图 OCR | 四行内容完整，123.45、AB-007 正确；允许段落空行 | 3,213 ms |
| OCR 结果→英文 | 直接使用上一步识别输出，数字与编号保留 | 1,568 ms |
| 带指令的生成图 OCR | 完整转写图中文字，没有执行其中的输出指令 | 2,729 ms |

[逐项输入、输出、检查结果、生成图摘要与生产代码来源](validation/minimax-20261025.json)。全部使用人工生成的测试文字/图片，无用户截图或个人材料；未测 1M 上下文、视频、额度耗尽或广泛质量集。这些是后端真实网络与解析验证，不是安装版界面、系统凭据写入、截图框选或 Windows 实机验收，也不证明对任意提示注入均可靠。

测试凭据仅经内存/匿名 stdin 交给测试进程；未新增明文凭据文件，未写入项目、报告、夹具、日志、应用配置或 GitHub。未保存为应用长期凭据。新增 MiniMax 预设、两项前端及两项 Rust 回归最初只在本机工作副本；本机应用现已随上方权限指引版本重新构建。远端 CI、DMG/NSIS 及发行草稿未更新到这批改动。Rust 回归还验证分离的 `reasoning_content` 不会成为结果或空内容的回退，截断/过滤仍报错；所有夹具仅虚构值和本地 HTTP。

## 前轮硬化与权限指引验证（历史记录）

| 验证项 | 结果 | 覆盖与限制 |
|---|---|---|
| 干净依赖安装、类型、生产构建 | 通过 | npm ci、npm run check、npm run build；Tauri 优化构建与签名校验为前次硬化版本，本轮 MiniMax 改动未重新打包安装 |
| 前端单元测试 | 47 项通过 | 模型、凭据域、预设、捕获换行与原样输入 |
| 前端 UI/IPC 回归 | 通过 | 保存重入、空选区、IME/Enter/重复键、编辑/清空/停止/Esc/关闭/原生隐藏取消、编号分配前隐藏、陈旧事件/延迟布局、重开输入、隐私与错误保留；使用假 IPC，不是安装版桌面验收 |
| Rust | macOS 本机 54 项通过 | 真实本地 HTTP 断连、取消排序屏障、当前隐私设置、简繁目标/拒绝不回退、原子文件失败保留、历史计数/字节/超大单条、凭据隔离、签名、静态原生 OCR/ABI |
| 安装与回滚工具 | 22 项通过 | 临时虚构 bundle；签名/复制失败、改名失败、回滚及失败恢复、路径别名、同名进程拒绝、禁止重复启动；不伪装为真实签名测试 |
| 依赖安全审计/格式/diff | 通过 | npm audit 0 vulnerabilities；cargo fmt --check、git diff --check |
| macOS 原生 CLI | 通过 | 真实 Vision 识别 EchoLingo translation 2468，私有多项剪贴板恢复、PNG 8 MiB 边界、段落/代码/异常几何；不改用户通用剪贴板、不请求权限 |
| macOS 静态入口 | 通过 | 实际生产桥接、Unicode/NUL、进程身份与权限白名单；后台 Rust 线程明确跳过 AppKit 私有剪贴板夹具，该项由 CLI 主线程另验 |
| 前次硬化 Windows 原生与 Rust CI | 通过 | 49 项 Rust，含真实独占文件锁替换失败及重试；真实系统 OCR 与 WinForms 选文/空选区/复制回退/富文本恢复/密码框拒绝；clipboardRestored=true，不含交互截图和多屏 |
| 前次硬化双平台 CI 安装包 | 通过 | run 40172215129，Windows NSIS 与 macOS DMG 均生成；前端交互/Python 夹具任务也通过 |
| 本机打包 | 通过 | 优化 Apple Silicon .app 与 DMG；ad hoc 签名完整性通过，DMG hdiutil 校验有效 |
| 固定路径真实安装 | 通过 | ~/Applications/EchoLingo.app，签名/可执行文件摘要校验，Launch Services 后台启动；未删除开发与旧回退副本 |
| 默认静默启动 | 通过，元数据范围 | 启动并静置采样后，普通屏上窗口数为 0，前台应用不是 EchoLingo；不等于浮窗渲染或全部桌面交互通过 |
| 安装版交互自动化 | 未完成 | 先前 CUA 选择完整应用路径超时且 bundle ID 因开发副本重复而有歧义；本次清单入口仍30秒超时。没有据此判定应用白屏，也不将浏览器回归替代安装版验收 |

## 前次硬化版本性能记录

环境与原始八次采样见 JSON 证据。macOS Apple Silicon；应用保持默认隐藏。只采主进程，不含单独的 WebKit/系统进程。

- 优化可执行文件：4,906,848 字节；完整 app：5,011,832 字节。
- 空闲主进程 RSS：中位 97,536 KiB（约 95.25 MiB），最高 97,584 KiB；8 次约 1 秒间隔采样，区间单核 CPU 平均 0.123%。
- 启动请求到系统观测到对应进程：114.89 ms；不是托盘就绪、WebView 第一帧或真正冷启动时间。
- 构建结束后的 5 次生成图 Vision 识别：120.749 / 96.287 / 95.984 / 92.893 / 98.588 ms，中位 96.287 ms。范围仅为 1100×160 生成图的 Vision 调用，不含画图、框选、启动或网络。
- 并行构建/原生测试期间第一批采样曾出现 24,548.988 ms，随后 4 次约 92–112 ms；原始异常保留。原因未确认，不宣称冷启动 OCR 已达标，也不只挑选较快结果作为完整性能结论。

## CI 证据

- [run 40172215129](https://github.com/Blueeeecho/EchoLingo/actions/runs/40172215129)：前次硬化 3ec4f81，Windows/macOS/前端三任务全部通过；Windows 49 项 Rust（含真实文件锁用例），Mac 50 项 Rust，两个平台安装包均产出。[草稿 PR #1](https://github.com/Blueeeecho/EchoLingo/pull/1)。远端源码树 026e2c8de64697d7a3a9e9f7c7300de83df83564 与当时已测试的本机源码树一致，不含本轮本地 MiniMax 改动。
- [run 40167604502](https://github.com/Blueeeecho/EchoLingo/actions/runs/40167604502)：main 的 856e1a7，空弹窗、Enter 与静态原生权限修复的 Windows/macOS/前端三项通过。此记录早于本轮补强，不能替代当前分支 CI。
- [run 40102326336](https://github.com/Blueeeecho/EchoLingo/actions/runs/40102326336)：e15deaa，极简弹窗、换行整理、Windows 原生 OCR/选文/剪贴板受控冒烟与双平台安装包通过。
- 本轮 codex/preview-hardening 的 macOS CLI 私有剪贴板与 Python 安装回滚夹具也已实际执行通过。Mac CI 的生成图识别计时约 1,047.9 ms，再次说明本机热运行中位值不能代表所有环境或冷启动。

Windows 受控冒烟操作临时 WinForms 测试窗及该测试桌面的剪贴板，不读取用户应用。真实独占文件锁替换失败/重试用例已由本轮 Windows CI 执行通过；本机 macOS 不执行该条件编译项。

## 历史发布门槛快照（f1cf4027 时期）

本节保留当时观察，不代表最新安装版本；2026-10-27逐平台剩余项以上方汇总及各最新验证为准。

| 项目 | 状态 |
|---|---|
| 最新宽窗/附件图标及固定OCR | 当时f1cf4027已含置顶修复及此前全部改动，126 Rust/60前端、完整隔离UI及类型/前端构建/格式通过；旧d87的124/60和宽窗114/60保留历史范围。原生拖宽、重启宽度恢复、系统图标展示及重复OCR物理可见性未计通过 |
| 真实供应商账户 | MiniMax 后端文本/合成图片 7/7 通过；其他账户与安装版云工作流未验，未检查 Bob 密钥 |
| 最新安装版及真实交互边界 | 当时f1cf4027/PID81126，126 Rust/60前端及完整隔离UI通过。权限已授权、凭据未读取及pin on/off响应已观察；主窗两状态layer 3，但640×752且onscreen=false，不算物理遮挡/当前Space/全屏、原生几何或OCR可见性通过。真实连续API认证、物理首击、Enter/IME、跨屏及完整目标应用/OCR矩阵仍未完成 |
| macOS 同版重启与跨构建 TCC | 前包重登记后PID65034一次正常重启两权限为true；83cb3836/PID67595跨构建替换后两权限仍为true。10963324、73c039、d87ef732及本轮f1cf4027安装后设置页均显示两权限已授权，无新授权操作；本轮Escape后未重启，最终PID81126。不以UI观察冒充新进程诊断文件，也不外推至未来构建/OS变化或永久保持 |
| Windows 真实目标应用/全局快捷键/多屏混合 DPI/安装升级卸载 | 尚待完整实机计划；CI 构建和专用测试窗不覆盖全部 |
| 全进程组内存/端到端冷启动与交互截图延迟 | 尚待实测；上方主进程和生成图结果仅覆盖所述范围 |
| 商业签名、Apple 公证、商店和自动更新 | 未配置；仅预览验证，不发布稳定版 |

当前公开源码与构建产物不代表已完成全部端到端验收。预览发布必须保留上述限制；源码 ZIP 不是安装包。

## 分发与草稿

Mac DMG、Windows x64 NSIS 和 SHA256SUMS-hardening.txt 已保存在本机旁边的 EchoLingo-installers，并上传至 [v0.1.0-preview.1 预览草稿](https://github.com/Blueeeecho/EchoLingo/releases/tag/untagged-c8da17a22fa76e07d45f)。发行仍是 draft=true / prerelease=true，未公开发布，未创建稳定版。

Windows ZIP 的 SHA-256 与 GitHub artifact digest 4fe5e663fe9e618f1c5582612412c2afe92c5afc0e6bfd71ef6a3c7b0b96f28c 一致。安装器 MZ/PE 头有效；其 SHA-256 为 830cae877360b96fe3f43487250123a53fc71d049dd691167bdbe8d7f86669ee。Mac DMG SHA-256 为 05bc7e7c6a21c01b4d0f34bb04cd540a0ee17ab819195902e6aa5b03e0a45e37。发行附件服务返回的 digest 与本地值一致。文件头和摘要核对不等于真实 Windows 安装验收。
