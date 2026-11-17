# EchoLingo 常驻资源基线（手动选择、只读采样）

目的：对同一个 Release 构建的冷启动、翻译、设置和截图阶段做可比较的采样。工具不会启动/关闭应用，不改设置，不清理内存，不读取剪贴板、原文、截图、进程参数或环境变量内容。默认运行行为保持不变，没有引入离线引擎或隐藏 WebView 自动销毁。

## 使用

需要 Python 3.9+，以及原生 macOS 或 Windows。Windows 使用系统 Windows PowerShell 和 CIM；无需 pip 包、管理员权限或第三方性能工具。权限不够时会标记未验证进程，不能把缺项当成零占用。

1. 在活动监视器/任务管理器中确认正在运行的**目标 Release 包**与主进程 PID，确认真实可执行文件路径。不要测 Vite、调试包或同时运行多个不明版本。
2. 记录提交 SHA、包版本、操作系统、机器 RAM、显示器/分辨率、测试图尺寸和服务类型。记录里不要写密钥、个人原文或私人路径。
3. 使用新输出文件运行；脚本拒绝覆盖已有记录。以下 PID 是占位示例，必须换成实际值。

macOS：

```sh
python3 scripts/process-memory-baseline.py --pid 12345 \
  --executable "$HOME/Applications/EchoLingo.app/Contents/MacOS/echolingo" \
  --phase cold-idle --samples 150 --interval 2 --output cold-idle.jsonl
```

Windows（PowerShell）：

```powershell
python scripts/process-memory-baseline.py --pid 12345 `
  --executable 'C:\verified-install\EchoLingo.exe' `
  --phase cold-idle --samples 150 --interval 2 --output cold-idle.jsonl
```

可执行文件名和安装目录以实际包为准，脚本严格核对 PID 对应路径。采样期间进程退出或 PID 身份变化会结束本阶段，并在输出里标记 incomplete。结束后重新采下一阶段。

## 归属范围与指标口径

- 自动跟踪已核对的主进程、采样时可见的后代进程，以及此前已观察到且身份不变的被重新托管后代。不会把其他应用的 WebView 算进来。
- macOS 的 WebKit/XPC 服务可能不在主进程树里。这种情况下**自动结果不是完整应用占用**。只有已通过本机原生进程工具确认归属，才能用 `--helper 'PID=/absolute/helper/executable'` 显式加入。Windows 同样可用此选项。不要仅凭 `WebKit`/`msedgewebview2` 进程名猜归属；无法确认就明确保留缺项。
- 输出每个选中进程的 basename、PID、启动时间、RSS、累计 CPU；Windows 额外包含 Private Bytes 和 handles。不输出全系统进程列表或完整本机路径。
- `summedRssBytesNotUnique` 只是所选进程 RSS 相加，包含共享页，**不是独占物理内存**。macOS physical footprint 没有测量，不得以此冒充。
- Windows `summedPrivateBytes` 是所选进程私有提交内存之和，不等于驻留 RAM；仍受归属完整性影响。
- CPU 是同一进程身份的累计 CPU 增量/实际采样间隔，100% 表示一个核。新出现进程的第一段没有可比较起点；采样之间已经退出的短命 helper 可能漏记。
- 主进程和每个显式 helper 都必须保持存活；主动测引擎退出时可只指定主进程，让后代自动跟踪。对不在进程树里的显式 helper，退出会正确结束该阶段。
- 工具自身和 OS 缓存会影响结果。不要用单次较高 RSS 证明泄漏，不要人为清 working set 制造好看的结果。

原有 `scripts/macos-preview.py benchmark` 仍可用于主进程纵向比较；`scripts/windows-offline-translation-test.ps1` 的引擎采样、`tests/windows-live-capture-smoke.ps1` 的截图 helper 指标也应保留。它们不能单独代表整个应用。

## 手动回归矩阵

使用合成文本和合成测试图，不采集用户当前工作屏幕。每一阶段保存单独 JSONL。建议各跑三次；记录中位数、峰值、进程数量，以及阶段前后是否回到稳定平台。

| 阶段 | 操作 | 观察 |
|---|---|---|
| 冷启动 | 托盘隐藏，静置 5 分钟，不使用离线翻译 | 主程序及已归属 helper 基线；离线引擎未启动 |
| 设置 | 打开/关闭设置 50 次，再静置 5 分钟 | 后半段是否持续按次数增长；不要把一次性缓存当泄漏 |
| 弹窗 | 翻译框打开/关闭 50 次 | 窗口/进程数、闲置 CPU 和内存平台 |
| 离线 | 中英各首次一次，再各重复 50 次 | 分离首译加载与热调用；两方向模型缓存后的平台 |
| 取消 | 合成输入翻译时关闭、重新打开、切换服务 | 无失控子进程；记录哪些退出属于预期 |
| 截图 | 1080p/4K/8K 合成图各复制/取消 50 次 | 峰值、关闭后平台、像素数与峰值关系 |
| 贴图 | 1→6→全部关闭，重复 10 轮 | 进程/窗口/handle 数回落；无持续增长 |
| 长空闲 | 使用离线与截图后静置 30 分钟 | 这是“用过后的常驻”，与冷启动分开报告 |

延迟需另外通过原生入口到可交互/结果显示的测量记录 p50/p95；本脚本不测首帧、OCR 或翻译响应时间。

## 后续优化的准入条件

先建立上述基线，再决定空闲卸载或大图复制优化。现版本有意复用成功的离线引擎和隐藏截图编辑器，升到稳定平台不等于泄漏。未来回收实验必须满足：活动请求不误杀、未保存截图不丢失、旧回调不唤醒已销毁窗口、恢复后第一笔 OCR/翻译正常，以及多屏/快捷键回归通过。没有原生实测前，不应默认打开回收策略或声称节省多少 MB。

## 测试工具本身

```sh
python3 -m unittest discover -s tests -p 'test_process_memory_baseline.py' -v
```

单元测试覆盖解析、归属筛选、重新托管、PID 复用、未知身份和 CPU 差值。Linux 上可运行这些测试，但不能据此宣称 macOS/Windows 原生采样已验收。
