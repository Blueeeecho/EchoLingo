# Windows 取词现场：原生焦点校验调研（2026-10-28）

机主确认手动 Ctrl+C 正常；Ctrl+Shift+D 恢复浏览器，但 WPS 在严格识别和复制兼容均为空。Copy attempt29 明确在第一阶段退出：nativeContextValid0、guardReason1、dispatchInserted0、selectionQueryCount0、helper445ms。这证明是本程序复制前原生上下文拒绝，不证明 WPS 禁止复制；也尚不能细分为焦点为空、跨进程、root不匹配或前台变化。

[Microsoft GetGUIThreadInfo](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-getguithreadinfo) 可读其他进程GUI线程；thread=0表示当前前台线程，激活过渡时可能没有有效窗口句柄。单改为0不是普遍修复。

[Microsoft SetParent](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-setparent) 明确列出跨进程父子窗口及DPI限制。当前 NativeSelectionContext 在验证 same GA_ROOT 之前就要求焦点PID等于前台PID，因此能误挡合法嵌入；这是代码缺口，不能直接认定是本次 WPS 的完整根因。修正需仍绑定前台/root、焦点HWND/thread/PID、前后稳定性，并只接纳已核对的焦点进程作为剪贴板来源，不允许任意broker。

[selection-hook issue18](https://github.com/0xfullex/selection-hook/issues/18) 维护者确认网页可视选区与可访问焦点不一致，曾使读取间歇失败，已通过祖先选区查询修复。它是同类兼容问题的公开证据，与本次Copy phase1不同，不能当成本次原因或直接复用Electron依赖。该项目为MIT；本项目继续独立原生实现。

验证顺序：新增Copy-only有界数值分支 → 真实跨进程子Edit在同一root且手动复制成功 → 原逻辑phase1拒绝的反例 → 最小FocusProcess绑定修正 → 同一反例通过及异root/变更/密码/剪贴板回归。未成功执行的阶段不得标通过。Alt菜单掩蔽仍是独立未集成实验；不为WPS安装扩展、不调用其COM改文档、不改变源焦点。

Windows基线现已执行：[62a81b7/run40681500777](https://github.com/Blueeeecho/EchoLingo/actions/runs/40681500777)的同线程宿主/跨线程编辑框对照与跨进程子编辑框均完成手动单次Ctrl+C；前者helper成功，后者旧helper因invalidReason10在phase1/dispatch0拒绝。完整富剪贴板与源焦点保持，2/2反例断言通过；不是WPS现场或安装版通过声明。先前18d/ddf两轮在手动复制基线失败，原始failure保留；读数否定mouse-up折回假设，把夹具剪贴板操作改到有消息循环的UI线程后相同预算和一次输入成功。

最小Copy-only修正已写：接纳合法同root焦点，另存非零FocusProcess并前后比较，只把已验证焦点PID加入剪贴板来源集合。Strict Auto原PID门禁保持。177纯策略断言通过；同运行夹具加ExpectCrossProcessSuccess与全套Windows回归待执行。
