# Windows 划词取词：GitHub 对照与已确认缺口（2026-10-28）

## 用户现场结论

机主报告最新21b预览在WPS和Google等网页仍出现“鼠标已选中→Alt+D→空原文”，并确认同一位置手动Ctrl+C后能正确粘贴到记事本。因此不能把这些失败归结为原文不可复制。旧包的Windows Server受控浏览器48/48及15/15门禁保留，但未通过机主实际WPS/网页验收。

窗口上的高亮由源应用绘制；跨应用取词依赖源应用提供的可访问性选区或复制操作，不能把高亮颜色当成统一的文本缓冲区。焦点所在控件和真正管理选区的文档可能不同。

## 找到的可借鉴方案

- [selection-hook #18](https://github.com/0xfullex/selection-hook/issues/18)：Chrome/Edge的tabindex容器接收焦点，选区却由祖先Document管理，旧实现还受光标/控件启发式影响而间歇失败。维护者在[fac4ef0](https://github.com/0xfullex/selection-hook/commit/fac4ef0ba26cdfecf4636c12cd148e1e834e8f0a)加入祖先选区查询。其[当前固定源码](https://github.com/0xfullex/selection-hook/blob/d8ac605db1b0a87f816f6fdfd880e054033737e5/src/windows/core/engine.cc#L456)遇到空的焦点选区仍继续祖先GetSelection。
- [selection-hook #25](https://github.com/0xfullex/selection-hook/issues/25)：旧版全文DocumentRange探测会阻塞复杂Chromium页面；v2.1.2已移除。不能把全文、控件名称或控件全部Value伪装为选中文字。参考版本声明[MIT许可](https://github.com/0xfullex/selection-hook/blob/d8ac605db1b0a87f816f6fdfd880e054033737e5/LICENSE)；本次独立修改现有代码，没有复制上游源码或加入其Node/Electron运行时。
- [Pot #679](https://github.com/pot-app/pot-desktop/issues/679)同样报告Windows网页快捷键后空框，评论还记录第二次成功及剪贴板已变化的现象。这证明症状并非本项目独有，不能据此认定根因相同。其实际依赖[Selection库](https://github.com/pot-app/Selection/blob/622e8f32c851daabe45c88481a1c59d11bc7256e/src/windows.rs)的固定等待和较弱剪贴板保存，不适合直接替换。
- [get-selected-text实现](https://github.com/yetone/get-selected-text/blob/0ddeb5d67de04660c067f8378970bc486f305032/src/utils.rs)也有清剪贴板、强制释放按键、固定等待及仅恢复文字/图片的取舍。本项目已有修饰键释放等待和复制流程，重复增加等待不是新修复。

## 本项目已确认的错误

旧windows.ps1把有TextPattern但选区为空的Edit控件当作终点，立即NO_SELECTION。既有WindowsSelectionDocumentFixture.EmptyEdit恰好模拟“焦点Edit为空、父Document有实际选区”，却把拒绝它列为通过；旧绿灯包含了这个错误预期。

本次修正：空Edit只阻止复制兜底，不阻止读取已完成密码/根窗口核验的祖先Document.GetSelection。祖先有真实非空选区便返回；祖先也空或不存在仍NO_SELECTION、零复制；原本非空Edit照常直接返回。密码祖先在任何选区读取之前拒绝。没有读取DocumentRange、调用SetFocus、加入准备延时或重按快捷键。

夹具增加真正空Edit+空Document、空Edit无Document、空Edit+密码Document、已选中的Edit；连同修正后的EmptyEdit共15个场景，核对精确leaf/document选区查询次数、原剪贴板格式、前台、零全文查询和零provider焦点修改。

## 验证与仍待确认

同一份新夹具的真实Windows前后对照已经完成：旧生产2996051/[40646617955](https://github.com/Blueeeecho/EchoLingo/actions/runs/40646617955)前三项通过，第四EmptyEdit因NO_SELECTION失败；修复19c724d/[40647286036](https://github.com/Blueeeecho/EchoLingo/actions/runs/40647286036)15/15通过，selection/assembly/OCR/delegatedCapture原始四门禁均success。只差20行helper代码，未改夹具或增加等待后重跑。同一个版本的重复基线40646848200来自推送网络失败后的误调度，不算修复证据。Git Data API补传后严格核对19c724d的完整提交身份才运行新代码。

EmptyEdit有选文父Document、空Document、无Document、密码Document以及非空Edit的leaf/document/copy次数分别是1/1/0、1/1/0、1/0/0、0/0/0、1/0/0。15项都保留原富剪贴板和源前台，未读取全文。独立代理和主代理均从raw JSON核对结果；没有以continue-on-error步骤的绿色conclusion代替原始outcome。[精确验证记录](validation/windows-selection-ancestor-20261028.json)。

这是生成UIA提供者的原生helper验证，不是注册Alt+D、实际浏览器、实体WPS或安装器测试。本次没有把这个已确认分支提前认定为机主全部WPS/Google失败的根因，也未构建包含它的新安装包。

本项目还有重复身份核验、来源校验、旧剪贴板格式物化、输入完成和复制结果来源等拒绝点；普通取词错误按产品约定显示安静空输入，因此外观相同并不表示内部原因相同。当前已交付21b的显式--selection-diagnostics可导出上一轮有限数值元数据，不含原文、剪贴板、标题或密钥；进一步兼容改动应依据实际失败分支。

MSAA/LegacyIAccessible是上游额外路径，但[微软文档](https://learn.microsoft.com/en-us/windows/win32/api/oleacc/nf-oleacc-iaccessible-get_accselection)定义accSelection主要返回选中对象，不能盲读accName/accValue当文本。此次不扩大这条路径。[SendInput](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-sendinput)还受完整性级别与按键状态影响；当前手动复制成功本身不能证明模拟输入必然成功。

当前安装包未更换；未操作本机Mac签名、TCC、钥匙串、用户凭据或本地虚拟机。没有发布stable。
