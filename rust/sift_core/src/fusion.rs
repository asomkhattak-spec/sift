//! Cross-provider result fusion.
//!
//! Network providers do not share a ranking model. This module gives every
//! candidate one query-aware score, merges copies of the same page, removes
//! near-duplicate titles and keeps the first screen from being a single host.
//! It receives and returns ordinary JSON objects so the original result fields
//! survive untouched apart from an updated `score`.

use std::collections::{HashMap, HashSet};
use std::time::{SystemTime, UNIX_EPOCH};

use chrono::DateTime;
use serde::Deserialize;
use serde_json::Value;

use crate::text::{analyze, expand_terms, normalize_text, plan_query, QueryIntent};
use crate::url::{canonical_key, display_host, is_web_url};

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct RankOptions {
    pub limit: usize,
    pub diversify: bool,
    pub max_per_host: usize,
}

impl Default for RankOptions {
    fn default() -> Self {
        Self {
            limit: 30,
            diversify: true,
            max_per_host: 2,
        }
    }
}

struct Candidate {
    index: usize,
    value: Value,
    score: f64,
    host: String,
    canonical_url: Option<String>,
    title_key: Option<String>,
    provider_rank: usize,
}

/// Scores, de-duplicates and orders a mixed provider result set.
pub fn rank_results(query: &str, results: Vec<Value>, options: &RankOptions) -> Vec<Value> {
    if results.is_empty() {
        return results;
    }

    let plan = plan_query(query);
    let base_terms = &plan.terms;
    let base_count = base_terms.len() as f64;
    let expanded = expand_terms(base_terms, None, None);
    let expanded_total = expanded.iter().map(|term| term.weight).sum::<f64>();
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_secs() as i64)
        .unwrap_or(0);
    let mut source_counts: HashMap<String, usize> = HashMap::new();
    let mut candidates: Vec<Candidate> = Vec::with_capacity(results.len());

    for (index, value) in results.into_iter().enumerate() {
        let title = value
            .get("title")
            .and_then(Value::as_str)
            .unwrap_or_default()
            .trim()
            .to_string();
        let url = value
            .get("url")
            .and_then(Value::as_str)
            .unwrap_or_default()
            .trim()
            .to_string();
        let snippet = value
            .get("snippet")
            .and_then(Value::as_str)
            .unwrap_or_default()
            .to_string();
        if title.is_empty() || !is_web_url(&url) {
            continue;
        }

        let source_id = value
            .get("sourceId")
            .and_then(Value::as_str)
            .unwrap_or("web")
            .to_ascii_lowercase();
        let kind = value
            .get("kind")
            .and_then(Value::as_str)
            .unwrap_or("web")
            .to_ascii_lowercase();

        let rank = value
            .get("providerRank")
            .and_then(Value::as_u64)
            .map(|rank| rank as usize)
            .unwrap_or_else(|| {
                let count = source_counts.entry(source_id.clone()).or_insert(0);
                let rank = *count;
                *count += 1;
                rank
            });

        let title_terms: HashSet<String> = analyze(&title).into_iter().collect();
        let snippet_terms: HashSet<String> = analyze(&snippet).into_iter().collect();
        let all_terms: HashSet<String> = title_terms.union(&snippet_terms).cloned().collect();
        let normalized_title = normalize_text(&title);

        let title_coverage = coverage(base_terms, &title_terms, base_count);
        let snippet_coverage = coverage(base_terms, &snippet_terms, base_count);
        let all_coverage = coverage(base_terms, &all_terms, base_count);
        let expanded_title = weighted_coverage(&expanded, &title_terms, expanded_total);

        let mut score = 0.0;
        score += 18.0 * title_coverage;
        score += 8.0 * snippet_coverage;
        score += 6.0 * all_coverage;
        score += 4.0 * expanded_title;
        score += source_prior(&source_id);
        score += kind_prior(&kind, plan.intent);
        score += if plan.intent == QueryIntent::Discussion && kind == "discussion" {
            2.0
        } else {
            0.0
        };

        // A contiguous phrase is a much stronger signal than scattered words.
        if base_terms.len() >= 2 && !plan.phrase.is_empty() {
            if normalized_title == plan.phrase {
                score += 38.0;
            } else if contains_phrase(&normalized_title, &plan.phrase) {
                score += 30.0;
            } else if normalized_title.starts_with(&plan.phrase) {
                score += 36.0;
            } else if normalize_text(&snippet).contains(&plan.phrase) {
                score += 7.0;
            }
        }

        // A provider's own ordering is weak evidence, but useful when lexical
        // signals are otherwise equal.
        score += 1.8 / (4.0 + rank as f64);
        score += freshness_bonus(
            value.get("publishedAt").and_then(Value::as_str),
            now,
            &kind,
        );

        if all_coverage < 0.5 && base_count >= 2.0 {
            score *= 0.72;
        }
        if title_terms.len() < 4 {
            score -= 0.7;
        }
        if snippet.trim().is_empty() {
            score -= 0.5;
        }

        let host = value
            .get("domain")
            .and_then(Value::as_str)
            .filter(|domain| !domain.trim().is_empty())
            .map(|domain| domain.trim_start_matches("www.").to_ascii_lowercase())
            .unwrap_or_else(|| display_host(&url));
        let title_key = title_dedupe_key(&title, &kind);

        candidates.push(Candidate {
            index,
            value,
            score: round(score),
            host,
            canonical_url: canonical_key(&url),
            title_key,
            provider_rank: rank,
        });
    }

    candidates.sort_by(|a, b| {
        b.score
            .total_cmp(&a.score)
            .then_with(|| a.provider_rank.cmp(&b.provider_rank))
            .then_with(|| a.index.cmp(&b.index))
    });

    let mut seen_urls = HashSet::new();
    let mut seen_titles = HashSet::new();
    let mut unique: Vec<Candidate> = Vec::with_capacity(candidates.len());
    for candidate in candidates {
        if let Some(key) = &candidate.canonical_url {
            if !seen_urls.insert(key.clone()) {
                continue;
            }
        }
        if let Some(key) = &candidate.title_key {
            if !seen_titles.insert(key.clone()) {
                continue;
            }
        }
        unique.push(candidate);
    }

    let target_limit = if options.limit == 0 {
        usize::MAX
    } else {
        options.limit
    };
    let max_per_host = options.max_per_host.max(1);
    let mut selected: Vec<Candidate> = Vec::new();
    let mut overflow: Vec<Candidate> = Vec::new();
    let mut per_host: HashMap<String, usize> = HashMap::new();

    for candidate in unique {
        let host_count = per_host.entry(candidate.host.clone()).or_insert(0);
        if options.diversify && *host_count >= max_per_host {
            overflow.push(candidate);
            continue;
        }
        *host_count += 1;
        selected.push(candidate);
        if selected.len() >= target_limit {
            break;
        }
    }

    if selected.len() < target_limit {
        for candidate in overflow {
            selected.push(candidate);
            if selected.len() >= target_limit {
                break;
            }
        }
    }

    selected
        .into_iter()
        .map(|mut candidate| {
            if let Some(object) = candidate.value.as_object_mut() {
                object.insert("score".to_string(), Value::from(candidate.score));
            }
            candidate.value
        })
        .collect()
}

fn coverage(terms: &[String], present: &HashSet<String>, count: f64) -> f64 {
    if terms.is_empty() || count == 0.0 {
        return 0.0;
    }
    terms
        .iter()
        .filter(|term| present.contains(*term))
        .count() as f64
        / count
}

fn weighted_coverage(
    terms: &[crate::text::QueryTerm],
    present: &HashSet<String>,
    total: f64,
) -> f64 {
    if terms.is_empty() || total == 0.0 {
        return 0.0;
    }
    terms
        .iter()
        .filter(|term| present.contains(&term.term))
        .map(|term| term.weight)
        .sum::<f64>()
        / total
}

fn contains_phrase(haystack: &str, phrase: &str) -> bool {
    haystack == phrase
        || haystack.starts_with(&format!("{phrase} "))
        || haystack.contains(&format!(" {phrase} "))
        || haystack.ends_with(&format!(" {phrase}"))
}

fn source_prior(source_id: &str) -> f64 {
    match source_id {
        "wikipedia" => 4.8,
        "local" => 3.2,
        "bing" => 2.7,
        "hackernews" => 2.4,
        "stackexchange" => 2.1,
        "gnews" => 1.9,
        "searxng" => 1.6,
        "dailymotion" => 0.9,
        "openverse" => 0.4,
        _ => 1.0,
    }
}

fn kind_prior(kind: &str, intent: QueryIntent) -> f64 {
    match (intent, kind) {
        (QueryIntent::News, "news") => 1.9,
        (QueryIntent::Images, "image") => 1.6,
        (QueryIntent::Videos, "video") => 1.6,
        (QueryIntent::Discussion, "discussion") => 2.0,
        (QueryIntent::Definition, "web") => 0.5,
        _ => 0.0,
    }
}

fn freshness_bonus(published_at: Option<&str>, now: i64, kind: &str) -> f64 {
    let Some(published_at) = published_at else {
        return 0.0;
    };
    let Ok(parsed) = DateTime::parse_from_rfc3339(published_at) else {
        return 0.0;
    };
    let age_seconds = now - parsed.timestamp();
    if age_seconds < 0 {
        return 0.0;
    }
    let days = age_seconds as f64 / 86_400.0;
    if kind == "news" {
        if days <= 1.0 {
            5.2
        } else if days <= 7.0 {
            3.4
        } else if days <= 30.0 {
            1.3
        } else {
            0.0
        }
    } else if days <= 7.0 {
        1.1
    } else if days <= 30.0 {
        0.4
    } else {
        0.0
    }
}

fn title_dedupe_key(title: &str, kind: &str) -> Option<String> {
    let tokens = analyze(title);
    if tokens.len() < 3 {
        return None;
    }
    Some(format!("{kind}:{}", tokens.into_iter().take(9).collect::<Vec<_>>().join(" ")))
}

fn round(value: f64) -> f64 {
    (value * 10_000.0).round() / 10_000.0
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn options() -> RankOptions {
        RankOptions {
            limit: 20,
            diversify: true,
            max_per_host: 2,
        }
    }

    #[test]
    fn exact_title_phrase_ranks_first() {
        let results = vec![
            json!({
                "id": "other",
                "kind": "web",
                "title": "A general article about browsers",
                "url": "https://a.example/page",
                "snippet": "privacy and browsers",
                "sourceId": "bing"
            }),
            json!({
                "id": "exact",
                "kind": "web",
                "title": "Browser privacy",
                "url": "https://b.example/page",
                "snippet": "A guide",
                "sourceId": "wikipedia"
            }),
        ];
        let ranked = rank_results("browser privacy", results, &options());
        assert_eq!(ranked[0]["id"], "exact");
        assert!(ranked[0]["score"].as_f64().unwrap() > 0.0);
    }

    #[test]
    fn deduplicates_tracking_variants_of_one_url() {
        let results = vec![
            json!({
                "id": "one",
                "kind": "web",
                "title": "The same page",
                "url": "https://example.com/page?utm_source=one",
                "sourceId": "bing"
            }),
            json!({
                "id": "two",
                "kind": "web",
                "title": "The same page again",
                "url": "https://www.example.com/page?fbclid=two",
                "sourceId": "hackernews"
            }),
        ];
        let ranked = rank_results("same page", results, &options());
        assert_eq!(ranked.len(), 1);
    }

    #[test]
    fn keeps_hosts_diverse_but_fills_the_result_set() {
        let results: Vec<Value> = (0..8)
            .map(|index| {
                json!({
                    "id": format!("r{index}"),
                    "kind": "web",
                    "title": format!("Example result {index}"),
                    "url": format!("https://example.com/{index}"),
                    "snippet": "example",
                    "sourceId": "bing"
                })
            })
            .collect();
        let ranked = rank_results(
            "example",
            results,
            &RankOptions {
                limit: 6,
                diversify: true,
                max_per_host: 2,
            },
        );
        assert_eq!(ranked.len(), 6);
        assert_eq!(
            ranked
                .iter()
                .filter(|value| value["url"].as_str().unwrap().contains("example.com"))
                .count(),
            6
        );
    }

    #[test]
    fn rejects_non_web_urls() {
        let results = vec![json!({
            "id": "bad",
            "kind": "web",
            "title": "Bad",
            "url": "javascript:alert(1)",
            "sourceId": "bing"
        })];
        assert!(rank_results("bad", results, &options()).is_empty());
    }

    #[test]
    fn intent_boosts_news_results() {
        let results = vec![
            json!({
                "id": "web",
                "kind": "web",
                "title": "Climate policy background",
                "url": "https://example.com/background",
                "snippet": "climate news",
                "sourceId": "bing"
            }),
            json!({
                "id": "news",
                "kind": "news",
                "title": "Climate policy background",
                "url": "https://news.example.com/story",
                "snippet": "climate news",
                "sourceId": "gnews",
                "publishedAt": "2026-11-13T08:00:00Z"
            }),
        ];
        let ranked = rank_results("climate news", results, &options());
        assert_eq!(ranked[0]["id"], "news");
    }
}
