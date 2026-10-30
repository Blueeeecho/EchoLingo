use crate::model::Provider;

/// A card retry must never fall back to every provider if its configuration was
/// removed or disabled while the result was visible.
pub fn request_providers(
    providers: &[Provider],
    provider_id: Option<&str>,
) -> Result<Vec<Provider>, String> {
    let selected: Vec<_> = providers
        .iter()
        .filter(|provider| provider.enabled && provider_id.is_none_or(|id| id == provider.id))
        .cloned()
        .collect();
    if selected.is_empty() {
        return Err(if provider_id.is_some() {
            "翻译服务已停用或删除，请检查设置"
        } else {
            "请在设置中添加并启用翻译服务"
        }
        .into());
    }
    Ok(selected)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::{offline_translation_provider, system_translation_provider};

    #[test]
    fn retry_selects_exactly_one_enabled_provider() {
        let providers = vec![
            offline_translation_provider(true),
            system_translation_provider(true),
        ];
        assert_eq!(request_providers(&providers, None).unwrap().len(), 2);
        let retry = request_providers(&providers, Some("system-translation")).unwrap();
        assert_eq!(retry.len(), 1);
        assert_eq!(retry[0].id, "system-translation");
    }

    #[test]
    fn disabled_missing_or_empty_retry_never_falls_back_to_all_providers() {
        let providers = vec![
            offline_translation_provider(true),
            system_translation_provider(false),
        ];
        for id in ["system-translation", "deleted", ""] {
            assert!(request_providers(&providers, Some(id)).is_err());
        }
        assert!(request_providers(&[], None).is_err());
    }
}
