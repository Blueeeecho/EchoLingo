# Findings

- Baseline HEAD 856e1a7; working tree clean. Latest GitHub run 40167604502 passed three jobs and created two platform artifacts; no Release existed at prior read.
- Durable documents mix 30 and 34 Rust counts and old installer links. README still mentions former helper identity and Ctrl/Cmd+Enter as the primary submit action.
- Review R6: frontend generation invalidates display but backend network/history tasks keep running.
- Review R10: DeepL/Libre currently collapse zh-Hans and zh-Hant; must respect provider capability or report unsupported goals.
- Native interactive permissions, IME, Windows target apps/multiple monitors and commercial signing remain distinct acceptance boundaries.
- First implementation: abortable HTTP tickets plus serialized ticket allocation, cancellation on edit/clear/stop/Escape/close/native hide, and commit under current privacy settings. Real pending HTTP body cancellation and history guards passed.
- Independent review found pending-ticket native-hide gap and stale result state in backend-only cancellation. Assigned repair with presentation barrier and dedicated regressions before final package.
- Native self-tests now include unique private pasteboard roundtrip, PNG limits and geometry. The general clipboard is never touched; private AppKit fixture only runs in standalone main thread.
- DeepL official current target codes ZH-HANS/ZH-HANT; LibreTranslate zh/zt. Rejections stay explicit without simplified fallback.
- Final local suite: 50 Rust,45 frontend unit,22 installer fixtures and UI/IPC regression passed. Windows-specific locked-file fixture is only compiled/run on Windows.
- Fixed installation now runs from ~/Applications/EchoLingo.app. Startup window probe found0regular onscreen windows and no foreground activation. Main RSS median95.25MiB; full WebKit process-group memory not measured.
- CUA installed-app full-path selection timed out; bundle-ID selection is ambiguous because old development bundles remain registered. Do not claim installed IME/floating UI acceptance from this automation.
- Native Vision timing initial concurrent-build batch retained a24.549s outlier; idle-after-build batch median96.287ms. End-to-end cold OCR remains unresolved.

- Current CI run40172215129 passed all3jobs: Windows49Rust including exclusive locked-target replacement, Mac50Rust, native OCR/private clipboard and UI/Python fixtures; NSIS/DMG artifacts exist. Windows artifact ZIP downloaded via HTTP1/resume and matched digest4fe5e663fe9e618f1c5582612412c2afe92c5afc0e6bfd71ef6a3c7b0b96f28c. Draft preview release423215017 created; no stable/public release.
