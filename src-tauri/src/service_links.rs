//! Opens only the bundled, reviewed public service guides in the OS browser.
//! The frontend cannot navigate the app WebView or pass arbitrary shell input.

const RELEASES_PAGE: &str = "https://github.com/Blueeeecho/EchoLingo/releases";

const ALLOWED: &[&str] = &[
    "https://cloud.google.com/products/translate/pricing",
    "https://docs.caiyunapp.com/lingocloud-api/index.html",
    "https://docs.cloud.google.com/docs/authentication/api-keys-use",
    "https://docs.cloud.google.com/translate/docs/reference/rest/v2/translate",
    "https://niutrans.com/documents/contents/trans_detection",
    "https://niutrans.com/text_trans",
    "https://platform.caiyunapp.com/",

    "https://ai.baidu.com/ai-doc/OCR/fk3h7xu7h",
    "https://ai.youdao.com/",
    "https://ai.youdao.com/DOCSIRMA/html/ocr/api/tyocr/index.html",
    "https://ai.youdao.com/DOCSIRMA/html/trans/api/wbfy/index.html",
    "https://ai.youdao.com/console/",
    "https://ai.youdao.com/new/newuser-promotion.s",
    "https://api-docs.deepseek.com/",
    "https://api-docs.deepseek.com/zh-cn/quick_start/pricing/",
    "https://azure.microsoft.com/en-us/pricing/details/translator/",
    "https://azure.microsoft.com/products/ai-services/ai-translator",
    "https://bailian.console.aliyun.com/",
    "https://cloud.baidu.com/doc/OCR/s/zk3h7xz52",
    "https://cloud.baidu.com/product/ocr",
    "https://cloud.google.com/docs/authentication/api-keys-use",
    "https://cloud.google.com/vision",
    "https://cloud.google.com/vision/docs/ocr",
    "https://cloud.google.com/vision/pricing",
    "https://cloud.siliconflow.cn/",
    "https://cloud.tencent.com/document/product/866/33526",
    "https://cloud.tencent.com/document/product/866/35945",
    "https://cloud.tencent.com/product/ocr",
    "https://console.bce.baidu.com/ai/#/ai/ocr/overview/index",
    "https://console.cloud.google.com/apis/credentials",
    "https://console.cloud.tencent.com/cam/capi",
    "https://console.cloud.tencent.com/ocr/overview",
    "https://developer.apple.com/documentation/translation/translationsession/init(installedsource:target:)",
    "https://developers.deepl.com/api-reference/translate/request-translation",
    "https://developers.openai.com/api/reference/overview",
    "https://developers.openai.com/api/docs/pricing",
    "https://developers.openai.com/api/docs/guides/chatgpt-api-credits",
    "https://docs.bigmodel.cn/cn/guide/develop/openai/introduction",
    "https://docs.bigmodel.cn/cn/guide/start/model-overview",
    "https://docs.libretranslate.com/",
    "https://docs.libretranslate.com/guides/api_usage/",
    "https://docs.siliconflow.cn/docs/api/chat-completions-post",
    "https://fanyi-api.baidu.com/access/0/1",
    "https://fanyi-api.baidu.com/doc/21",
    "https://fanyi-api.baidu.com/manage/developer",
    "https://github.com/mozilla/translations",
    "https://help.aliyun.com/zh/model-studio/compatibility-of-openai-with-dashscope",
    "https://help.aliyun.com/zh/model-studio/get-api-key",
    "https://help.aliyun.com/zh/model-studio/new-free-quota/",
    "https://learn.microsoft.com/azure/ai-services/translator/text-translation/reference/authentication",
    "https://learn.microsoft.com/azure/ai-services/translator/text-translation/reference/v3/translate",
    "https://libretranslate.com/",
    "https://open.bigmodel.cn/",
    "https://platform.deepseek.com/",
    "https://platform.deepseek.com/api_keys",
    "https://platform.minimax.cn/",
    "https://platform.minimax.cn/docs/api-reference/text-openai-api",
    "https://platform.minimax.cn/subscribe/coding-plan",
    "https://platform.openai.com/",
    "https://platform.openai.com/api-keys",
    "https://portal.azure.com/",
    "https://www.deepl.com/pro-api",
    "https://www.deepl.com/your-account/keys",
    "https://support.deepl.com/hc/en-us/articles/360021200939-DeepL-API-plans",
    "https://www.siliconflow.cn/pricing",
    "https://www.rfc-editor.org/rfc/rfc6901",
    "https://ai.google.dev/gemini-api/docs/openai",
    "https://ai.google.dev/gemini-api/docs/pricing",
    "https://aistudio.google.com/apikey",
    "https://azure.microsoft.com/en-us/pricing/details/cognitive-services/computer-vision/",
    "https://azure.microsoft.com/en-us/pricing/details/computer-vision/",
    "https://console.volcengine.com/iam/keymanage/",
    "https://docs.bigmodel.cn/cn/guide/models/free/glm-4-flash-250414",
    "https://docs.bigmodel.cn/cn/guide/models/free/glm-4v-flash",
    "https://docs.volcengine.com/docs/machine-translation/product-billing",
    "https://docs.volcengine.com/docs/machine-translation/text-translation-api",
    "https://github.com/Blueeeecho/EchoLingo/blob/main/docs/free-setup.md",
    "https://github.com/Blueeeecho/EchoLingo/blob/main/docs/free-setup.zh-CN.md",
    "https://help.aliyun.com/zh/machine-translation/developer-reference/api-reference-machine-translation-universal-version-call-guide",
    "https://help.aliyun.com/zh/machine-translation/product-overview/billing-overview",
    "https://learn.microsoft.com/azure/ai-services/computer-vision/overview",
    "https://ocr.space/",
    "https://ocr.space/ocrapi",
    "https://ram.console.aliyun.com/manage/ak",
];

fn approved(url: &str) -> Result<&str, String> {
    if url == RELEASES_PAGE || ALLOWED.contains(&url) {
        Ok(url)
    } else {
        Err("只能打开应用内提供的官方链接".into())
    }
}

pub fn open(url: &str) -> Result<(), String> {
    let url = approved(url)?;
    #[cfg(target_os = "macos")]
    {
        let status = std::process::Command::new("/usr/bin/open")
            .arg(url)
            .status()
            .map_err(|_| "无法启动默认浏览器")?;
        if !status.success() {
            return Err("默认浏览器未能打开文档".into());
        }
        Ok(())
    }
    #[cfg(target_os = "windows")]
    {
        // ShellExecute receives a fixed URL as its file argument, never a shell
        // command. No credential, provider address or user text reaches it.
        #[link(name = "shell32")]
        extern "system" {
            fn ShellExecuteW(
                window: *mut std::ffi::c_void,
                operation: *const u16,
                file: *const u16,
                parameters: *const u16,
                directory: *const u16,
                show: i32,
            ) -> isize;
        }
        let operation: Vec<u16> = "open\0".encode_utf16().collect();
        let file: Vec<u16> = url.encode_utf16().chain(Some(0)).collect();
        let result = unsafe {
            ShellExecuteW(
                std::ptr::null_mut(),
                operation.as_ptr(),
                file.as_ptr(),
                std::ptr::null(),
                std::ptr::null(),
                1,
            )
        };
        if result <= 32 {
            return Err("默认浏览器未能打开文档".into());
        }
        Ok(())
    }
    #[cfg(not(any(target_os = "macos", target_os = "windows")))]
    {
        let _ = url;
        Err("当前平台暂不支持打开服务文档".into())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn all_bundled_guides_and_quotas_are_exactly_allowlisted() {
        let sources = [
            include_str!("../../src/service-guides.ts"),
            include_str!("../../src/service-quotas.ts"),
        ];
        let urls: std::collections::BTreeSet<_> = sources
            .iter()
            .flat_map(|source| source.split("'https://").skip(1))
            .map(|tail| format!("https://{}", tail.split('\'').next().unwrap()))
            .collect();
        let expected: std::collections::BTreeSet<_> =
            ALLOWED.iter().map(|url| (*url).to_owned()).collect();
        assert_eq!(urls, expected);
        for url in ALLOWED {
            assert_eq!(approved(url).unwrap(), *url);
        }
    }

    #[test]
    fn release_page_is_exactly_allowlisted_without_asset_or_tag_urls() {
        assert!(approved(RELEASES_PAGE).is_ok());
        for suffix in [
            "/latest",
            "/tag/0.2.0",
            "/download/0.2.0/setup.exe",
            "?redirect=evil",
            "#other",
            "/",
            "\n",
        ] {
            assert!(approved(&format!("{RELEASES_PAGE}{suffix}")).is_err());
        }
        assert!(approved("https://github.com.evil/Blueeeecho/EchoLingo/releases").is_err());
    }

    #[test]
    fn altered_urls_and_non_web_schemes_are_rejected() {
        for url in [
            "file:///tmp/test",
            "javascript:alert(1)",
            "https://platform.openai.com.evil/",
            "https://platform.openai.com/?key=secret",
            "https://platform.openai.com/#other",
            "https://user:secret@platform.openai.com/",
            "https://platform.openai.com/\n",
            "--help",
            "https://example.com/",
        ] {
            assert!(approved(url).is_err(), "accepted altered guide");
        }
    }
}
