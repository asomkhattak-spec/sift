//! Conservative URL privacy cleaning and canonicalization.

use url::Url;

/// Parameters that are used to stitch a visit to an advertising or analytics
/// identity. This list is deliberately limited to clear tracking keys; removing
/// arbitrary parameters breaks pagination, sessions and deep links.
const TRACKING_PARAMS: &[&str] = &[
    "gclid",
    "dclid",
    "fbclid",
    "msclkid",
    "yclid",
    "twclid",
    "igshid",
    "mc_cid",
    "mc_eid",
    "mkt_tok",
    "vero_id",
    "oly_anon_id",
    "oly_enc_id",
    "rb_clickid",
    "s_cid",
    "wickedid",
    "ref_src",
    "ref_url",
    "spm",
    "_hsenc",
    "_hsmi",
    "hsctatracking",
    "ml_subscriber",
    "ml_subscriber_hash",
    "pk_campaign",
    "pk_kwd",
    "pk_source",
    "pk_medium",
    "mtm_campaign",
    "mtm_source",
    "mtm_medium",
    "mtm_content",
    "mtm_cid",
    "mtm_group",
    "mtm_placement",
    "matomo_campaign",
    "at_medium",
    "at_campaign",
    "s_kwcid",
    "ef_id",
    "sscid",
    "trkcampaign",
    "sc_campaign",
    "sc_channel",
    "sc_content",
    "sc_medium",
    "sc_outcome",
    "sc_geo",
    "sc_country",
];

fn is_tracking_param(key: &str) -> bool {
    let lower = key.to_ascii_lowercase();
    lower.starts_with("utm_")
        || TRACKING_PARAMS
            .iter()
            .any(|candidate| lower == *candidate)
}

/// Returns true when the string looks like a public web address. A bare host
/// such as `example.com` is accepted; free text and unsupported schemes are not.
pub fn is_web_url(raw: &str) -> bool {
    let value = raw.trim();
    if value.is_empty() || value.chars().any(char::is_whitespace) {
        return false;
    }
    let parsed = if value.contains("://") {
        Url::parse(value)
    } else {
        Url::parse(&format!("https://{value}"))
    };
    let Ok(url) = parsed else {
        return false;
    };
    if !matches!(url.scheme(), "http" | "https") {
        return false;
    }
    let Some(host) = url.host_str() else {
        return false;
    };
    if host == "localhost" {
        return true;
    }
    host.contains('.') && !host.starts_with('.') && !host.ends_with('.')
}

/// Removes campaign and click-identifier parameters without otherwise touching
/// the URL. Returns `None` for anything that is not an http(s) URL.
pub fn clean_url(raw: &str) -> Option<String> {
    let mut url = Url::parse(raw.trim()).ok()?;
    if !matches!(url.scheme(), "http" | "https") || url.host_str().is_none() {
        return None;
    }
    if url.query().is_none() {
        return Some(url.into());
    }

    let pairs: Vec<(String, String)> = url
        .query_pairs()
        .filter(|(key, _)| !is_tracking_param(key))
        .map(|(key, value)| (key.into_owned(), value.into_owned()))
        .collect();
    if pairs.len() == url.query_pairs().count() {
        return Some(url.into());
    }

    {
        let mut query = url.query_pairs_mut();
        query.clear();
        for (key, value) in &pairs {
            query.append_pair(key, value);
        }
    }
    Some(url.into())
}

/// A scheme-independent key used to merge the same page arriving from several
/// providers. Tracking parameters and fragments never participate.
pub fn canonical_key(raw: &str) -> Option<String> {
    let cleaned = clean_url(raw)?;
    let url = Url::parse(&cleaned).ok()?;
    let host = url
        .host_str()?
        .to_ascii_lowercase()
        .trim_start_matches("www.")
        .to_string();
    let mut path = url.path().to_string();
    while path.len() > 1 && path.ends_with('/') {
        path.pop();
    }
    if path.is_empty() {
        path.push('/');
    }

    let mut pairs: Vec<(String, String)> = url
        .query_pairs()
        .map(|(key, value)| (key.into_owned(), value.into_owned()))
        .collect();
    pairs.sort_by(|a, b| a.0.cmp(&b.0).then_with(|| a.1.cmp(&b.1)));

    let mut key = host;
    if let Some(port) = url.port() {
        if Some(port) != url.port_or_known_default() {
            key.push(':');
            key.push_str(&port.to_string());
        }
    }
    key.push_str(&path);
    if !pairs.is_empty() {
        key.push('?');
        for (index, (name, value)) in pairs.iter().enumerate() {
            if index > 0 {
                key.push('&');
            }
            key.push_str(name);
            key.push('=');
            key.push_str(value);
        }
    }
    Some(key)
}

/// Host as people should see it: no `www.`, no port. Falls back to a trimmed
/// raw value when parsing fails.
pub fn display_host(raw: &str) -> String {
    let parsed = if raw.contains("://") {
        Url::parse(raw)
    } else {
        Url::parse(&format!("https://{raw}"))
    };
    if let Ok(url) = parsed {
        if let Some(host) = url.host_str() {
            return host.trim_start_matches("www.").to_string();
        }
    }
    raw.trim().trim_start_matches("www.").to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn strips_campaign_parameters_only() {
        let url = "https://example.com/read?utm_source=mail&id=42&fbclid=abc#notes";
        assert_eq!(
            clean_url(url).unwrap(),
            "https://example.com/read?id=42#notes"
        );
    }

    #[test]
    fn keeps_meaningful_parameters() {
        let url = "https://example.com/search?q=rust&page=2";
        assert_eq!(clean_url(url).unwrap(), url);
    }

    #[test]
    fn canonicalizes_scheme_www_trailing_slash_and_order() {
        let a = canonical_key("http://www.Example.com/path/?b=2&a=1#top").unwrap();
        let b = canonical_key("https://example.com/path?a=1&b=2").unwrap();
        assert_eq!(a, b);
        assert_eq!(a, "example.com/path?a=1&b=2");
    }

    #[test]
    fn rejects_non_web_schemes() {
        assert!(clean_url("javascript:alert(1)").is_none());
        assert!(!is_web_url("javascript:alert(1)"));
        assert!(is_web_url("example.com"));
        assert!(is_web_url("https://example.com/a"));
    }

    #[test]
    fn display_host_removes_noise() {
        assert_eq!(display_host("https://www.example.com:8443/a"), "example.com");
    }
}
