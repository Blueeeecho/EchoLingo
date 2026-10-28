# EchoLingo · 回声译官网

## 目标与内容计划

用户于 2026-10-28 授权制定计划并创建公开产品官网，沿用前面确认的 GitHub Pages 免费网址路线。官网面向电脑使用者，不宣传手机应用。

品牌主标题为「让陌生的语言，有熟悉的回声。」；核心价值为「让理解跟上思路。」。三个首要卖点是无感翻译、轻量、自定义服务。补充展示区域 OCR、固定与编辑浮窗、本机处理与清楚的数据去向。

页面顺序：品牌与可播放的操作示意 → 选词/OCR 两个工作流 → 轻量设计 → 翻译与 OCR 自定义服务 → 隐私 → 桌面平台状态 → 入门步骤及常见问题。

## 实现与预览

源文件位于项目的 `website/` 目录，采用无需构建的 HTML、CSS、JavaScript 和系统字体，无外部脚本、字体、账户或统计服务。图标使用机主已确认的原始品牌图所生成的桌面资源。交互示意只播放固定样例，不读取真实屏幕/选区/剪贴板，不连接翻译或 OCR 服务，也不收集密钥。

本地预览：

```sh
python3 -m http.server 4173 --bind 127.0.0.1 --directory website
```

打开 `http://127.0.0.1:4173/`。桌面布局需要检查常见电脑窗口及浏览器缩放后的可读性；窄 CSS 视口堆叠内容用于桌面窗口/缩放，不表示推出手机产品。

## 发布路线

已上线地址：`https://blueeeecho.github.io/EchoLingo/`。实际是否部署成功，以 Pages API、构建结果与公开 HTTPS 内容核验为准，不能仅凭目标地址宣称上线。

使用现有公开仓库独立 `gh-pages` 分支，仅保存 `website/` 中的静态站点文件（部署时位于分支根目录）。Pages 从该分支 `/` 发布，`.nojekyll` 避免 Jekyll 处理。此方案不更改默认 `main`、桌面开发分支或应用发布流程，也不混入本地未提交的桌面代码。

更新时应先核对远端分支头，创建只包含官网文件的新提交，再以非强制方式推进；发现远端已变动须重新核对，不能覆盖其他工作。部署后核对首页、脚本、样式、图片和隐私页的实际返回内容。

## 宣传与下载边界

- 以实际工作流表达优势，不虚构用户、性能数字、包体积或全应用兼容。
- Windows、macOS 仍为预览验证阶段；macOS 系统翻译要求与应用本体要求分开说明。鸿蒙 PC 为研发中，不标稳定或可下载。
- 2026-10-28机主确认当前Windows包可用并授权发布首个内测版，公开入口为[https://github.com/Blueeeecho/EchoLingo/releases/tag/0.1.0-beta.1](https://github.com/Blueeeecho/EchoLingo/releases/tag/0.1.0-beta.1)。首页Windows按钮直达对应EXE，另保留Mac发布页及鸿蒙项目入口。发布与下载说明按机主要求保持简洁。
- 翻译和 OCR 都支持用户选择服务，但通用接口不能冒充对所有供应商鉴权协议的支持。新服务以对应预览包说明为准。
- 默认本机 OCR 不等于整条流程离线：选择云翻译时识别文字会发送给所选服务；选择云 OCR 时图片也会发送。隐私页清楚区分应用行为、第三方服务和 GitHub Pages 安全访问日志。

## 后续维护

有公开安装包后，同步更新平台卡片、下载入口、版本日期、FAQ 及隐私说明，并核验外部用户可访问。网站可后续绑定机主注册的独立域名，无需重做页面。

本轮精确发布与浏览器核验记录保存在 `docs/validation/official-website-20261028.json`。

首次发布于2026-10-28：gh-pages提交a3e923fc539de675cf94e9fbbefc25bb2c7363cf，Pages构建40657109025成功。公开HTML/JS/CSS/隐私页/PNG与本地精确匹配；内置浏览器自动切换线上URL超时，不计作线上UI验收。

2026-10-28: Beta1 published; gh-pages209861d863f1b3303678c10da39f5aea34b6ad26 built; six anonymous public file bodies verified byte-for-byte. See docs/validation/beta1-release-20261028.json.

2026-10-28: Added a natural Star invitation and current licensing link. gh-pages d1aa59ad37b30f3d68e1e0bc023dd64626564a04 built; six public file bodies verified exact. See validation/project-presentation-license-20261028.json.
