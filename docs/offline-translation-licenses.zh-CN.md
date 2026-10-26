# 内置离线翻译资源与分发许可

本次选择 Mozilla 官方 registry 中两个 `base-memory` 定向模型：英文→中文的 `llmaat_finetune10M_qe8_f2_ByQcSxGXQRqGi-UTxYE43g`，中文→英文的 `cjk_retrain_base-memory_cNY_yaJCStGwnTeXgW8A5w`。两者统一呈现为一个中英互译服务，不另装独立词典。它们分别为约 4354 万和 4357 万参数；没有把更大通用大模型算作轻量方案。

## 固定来源和实际体积

[Mozilla 官方源码](https://github.com/mozilla/translations/tree/69455acaecbe8650cdba988dbcf7c10ca20e7c48)的 README 明确说明，官方公开 GCS registry 的模型文件按 **MPL 2.0** 分发。固定源码为 `69455acaecbe8650cdba988dbcf7c10ca20e7c48`。仓库内保存 registry 原样快照及所选条目；快照生成时间为 `2026-10-26T00:44:07Z`，SHA-256 为 `45324510eb038cc84c7b964e81e75bc1855d09b6edcecaa6ffc35f9dd1fcd3d2`。

七个真实文件已从固定官方路径下载并解压，两个权重都匹配 registry 发布的解压后 SHA-256。全部文件的压缩及解压长度、SHA-256、固定来源保存在 [`resources/offline-translation/manifest.json`](../resources/offline-translation/manifest.json)。registry 未发布 shortlist/SPM 的单独 hash，因此这些文件的固定 hash 是本次从官方 HTTPS 下载后记录的审计值，不能表述成 Mozilla 单独签署的校验和。

- gzip 下载合计 **75,033,319 字节（75.03 MB / 71.56 MiB）**。
- 解压模型、shortlist 与 SPM 合计 **104,470,603 字节（104.47 MB / 99.63 MiB）**。
- 上述值不含引擎可执行文件、应用、许可和源码供应包；最终安装包的压缩体积另测。此前的“75 MB”指官方 gzip 下载量，不是安装占用或运行内存。

准备脚本仅使用 Python 标准库，按固定 manifest 下载，在压缩及解压两层验证长度与 SHA-256，并对现有损坏的输出或缓存报错，不静默覆盖。构建生成的模型和引擎目录被 Git 忽略；运行时完全本地，不下载模型，不读取 API 密钥，不自动切换到云翻译。首次启用的实际加载内存、速度及译文质量必须通过引擎和 Windows 安装版实测，不能用体积或 mock 测试替代。

## 分发要求

模型和 Mozilla 推理源按 MPL 2.0；底层 Marian 为 MIT。MPL 是文件范围的许可，不能据此把整个 EchoLingo 宣称为 MPL，也不能忽略被覆盖文件的源码供应。随安装资源附原样 MPL 文本、来源、归属、第三方许可与 `SOURCE-OFFER.md`。同次 preview 发行必须同时提供 `EchoLingo-offline-engine-source.zip`，含实际构建使用的 Mozilla 推理源、依赖、我们的 wrapper/CMake/准备脚本、构建说明、逐文件清单；不含模型或构建产物。未发布前不得宣称公开源码供应已完成。

原始模型权重随安装包提供，保留其来源和全部 SHA。源码包中的上游改动必须保留，不能只链接一个未包含本地补丁的上游 main 分支。实际依赖的原样许可另存 `resources/offline-translation/licenses/`，目标平台最终链接清单须与构建配置核对；禁止把未启用的服务器/GPU/MKL 等算进实际运行依赖。

ssplit-cpp 的 C++ 代码是 Apache 2.0，但 `nonbreaking_prefixes` 数据是 LGPL 2.1，不能混称为 Apache。我们的 wrapper 使用空 prefix-file 与其支持的正则分句，不分发、不加载该目录；源码供应包也排除这份未使用数据。PCRE2、分词器及其嵌入的第三方版权声明必须一并保留。

公开模型许可可以支持符合条件的部署和分发；它不能消除所有训练语料、商标或译文的第三方权利争议。这里确认的是可追溯的官方发布许可与具体履约材料，而非“绝对不会发生权利争议”的保证。

## 许可证核验入口

- [Mozilla 固定 README / 模型许可](https://github.com/mozilla/translations/blob/69455acaecbe8650cdba988dbcf7c10ca20e7c48/README.md)
- [Mozilla 固定 MPL 2.0 原文](https://github.com/mozilla/translations/blob/69455acaecbe8650cdba988dbcf7c10ca20e7c48/LICENSE)
- [MPL 2.0 官方 FAQ](https://www.mozilla.org/en-US/MPL/2.0/FAQ/)
- [已固定模型清单](../resources/offline-translation/manifest.json)
- [安装资源中的来源和源码供应说明](../resources/offline-translation/licenses/SOURCE-OFFER.md)
