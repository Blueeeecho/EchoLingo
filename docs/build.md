# 源码构建与测试

EchoLingo 使用 Tauri 2、Rust 和 TypeScript，桌面界面复用系统 WebView。

## 环境

- Node.js 24、npm、Rust stable 和 Python 3。
- Windows：Visual Studio C++ 构建工具、Windows SDK、WebView2；本机 OCR 需要系统 OCR 语言包。
- macOS：Xcode Command Line Tools；取词和截图权限在应用设置中配置。

## 界面开发与检查

```sh
npm ci
npm run check
npm test
npm run build
cargo test --manifest-path src-tauri/Cargo.toml
cargo fmt --manifest-path src-tauri/Cargo.toml --check
python3 scripts/check-repository.py
python3 -m unittest discover -s tests -p 'test_repository_hygiene.py'
```

`npm run tauri dev` 启动桌面开发版。隔离界面回归先运行 `npm run dev`，再执行 `npm run test:ui`；需要 Playwright Chromium，可通过 `ECHOLINGO_TEST_CHROMIUM` 指定已有测试浏览器。隔离测试不代替目标应用中的真实快捷键、框选和多屏验收。

## Windows 安装包

在 Windows x64 的 Visual Studio 开发环境中准备离线翻译资源，再构建 NSIS：

```sh
python scripts/prepare-offline-models.py --cache .cache/offline-models
python scripts/offline-engine/build.py --work-dir .cache/offline-engine --output-dir resources/offline-translation/bin --jobs 4 --generator Ninja
npm run tauri build -- --bundles nsis
python scripts/package-offline-source.py --engine-work-dir .cache/offline-engine --output ../EchoLingo-offline-engine-source.zip
```

引擎构建需要 CMake 与 Ninja。准备脚本按固定来源下载并核验模型与依赖。分发包含离线引擎的安装包时，同时提供对应源码归档和原始许可证，详见[离线资源许可](offline-translation-licenses.zh-CN.md)及[引擎构建说明](../scripts/offline-engine/README.md)。

## macOS 安装包

```sh
npm run tauri build -- --bundles app,dmg
```

产物位于 `src-tauri/target/release/bundle/`。对外分发的签名和 Apple 公证由发布者配置；开发构建不能代替公证。更多原生检查见[原生功能测试](native-testing.md)。
