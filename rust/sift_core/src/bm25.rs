//! On-device BM25 index used by the My Search shelf.
//!
//! The index is intentionally small and synchronous. It holds the curated
//! starter shelf plus pages the reader explicitly indexes. Documents are
//! replaced as a complete snapshot, which keeps persistence and UI updates
//! deterministic.

use std::collections::{HashMap, HashSet};
use std::time::Instant;

use serde::{Deserialize, Serialize};

use crate::text::{analyze, expand_terms, normalize_text, plan_query};
use crate::url::canonical_key;

const K1: f64 = 1.2;
const B: f64 = 0.72;

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct Document {
    pub id: String,
    pub title: String,
    #[serde(default)]
    pub url: String,
    #[serde(default)]
    pub snippet: String,
    #[serde(default)]
    pub body: String,
    #[serde(default)]
    pub section: String,
    #[serde(default)]
    pub tags: Vec<String>,
    #[serde(default)]
    pub is_custom: bool,
    #[serde(default)]
    pub added_at: Option<String>,
}

#[derive(Debug, Clone)]
struct IndexedDocument {
    doc: Document,
    term_frequencies: HashMap<String, u32>,
    title_terms: HashSet<String>,
    unique_terms: HashSet<String>,
    normalized_title: String,
    normalized_body: String,
    length: u32,
}

#[derive(Debug, Clone, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct IndexStats {
    pub documents: usize,
    pub custom_documents: usize,
    pub starter_documents: usize,
    pub vocabulary_terms: usize,
    pub average_length: f64,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct LocalSearchOptions {
    pub limit: usize,
    /// `false` restricts results to pages the reader indexed themselves.
    pub include_starter: bool,
}

impl Default for LocalSearchOptions {
    fn default() -> Self {
        Self {
            limit: 24,
            include_starter: true,
        }
    }
}

#[derive(Debug, Clone, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct LocalHit {
    pub id: String,
    pub score: f64,
    pub matched_terms: Vec<String>,
    pub title_match: bool,
}

#[derive(Debug, Clone, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct LocalSearchResponse {
    pub query: String,
    pub hits: Vec<LocalHit>,
    /// Number of matching documents before the limit was applied.
    pub total: usize,
    pub documents: usize,
    pub elapsed_micros: u64,
}

#[derive(Debug, Default)]
pub struct LocalIndex {
    documents: Vec<IndexedDocument>,
    postings: HashMap<String, Vec<(u32, u32)>>,
    document_frequency: HashMap<String, u32>,
    vocabulary: HashSet<String>,
    average_length: f64,
    custom_documents: usize,
    starter_documents: usize,
}

impl LocalIndex {
    pub fn new() -> Self {
        Self::default()
    }

    /// Replaces the complete index with a snapshot. Duplicate IDs and duplicate
    /// canonical URLs collapse to one document; a reader-indexed copy wins over
    /// a shipped starter entry for the same page.
    pub fn replace(&mut self, documents: Vec<Document>) {
        let mut selected: Vec<Document> = Vec::new();
        let mut by_id: HashMap<String, usize> = HashMap::new();
        let mut by_url: HashMap<String, usize> = HashMap::new();

        for doc in documents {
            if doc.id.trim().is_empty() || doc.title.trim().is_empty() {
                continue;
            }
            let url_key = canonical_key(&doc.url);

            if let Some(existing) = by_id.get(&doc.id).copied() {
                let replace = doc.is_custom && !selected[existing].is_custom;
                if replace {
                    selected[existing] = doc;
                }
                continue;
            }

            if let Some(existing) = url_key
                .as_deref()
                .and_then(|key| by_url.get(key).copied())
            {
                let replace = doc.is_custom && !selected[existing].is_custom;
                if replace {
                    by_id.remove(&selected[existing].id);
                    by_id.insert(doc.id.clone(), existing);
                    selected[existing] = doc;
                }
                continue;
            }

            let index = selected.len();
            by_id.insert(doc.id.clone(), index);
            if let Some(key) = url_key {
                by_url.insert(key, index);
            }
            selected.push(doc);
        }

        self.documents.clear();
        self.postings.clear();
        self.document_frequency.clear();
        self.vocabulary.clear();
        self.custom_documents = 0;
        self.starter_documents = 0;

        let mut total_length: u64 = 0;
        for (index, doc) in selected.into_iter().enumerate() {
            if doc.is_custom {
                self.custom_documents += 1;
            } else {
                self.starter_documents += 1;
            }

            let title_terms: HashSet<String> = analyze(&doc.title).into_iter().collect();
            let mut body_text = String::new();
            body_text.push_str(&doc.snippet);
            body_text.push(' ');
            body_text.push_str(&doc.body);
            body_text.push(' ');
            body_text.push_str(&doc.section);
            for tag in &doc.tags {
                body_text.push(' ');
                body_text.push_str(tag);
            }

            let mut term_frequencies: HashMap<String, u32> = HashMap::new();
            for term in analyze(&doc.title) {
                *term_frequencies.entry(term).or_insert(0) += 3;
            }
            for term in analyze(&body_text) {
                *term_frequencies.entry(term).or_insert(0) += 1;
            }

            let length = term_frequencies.values().copied().sum::<u32>();
            total_length += u64::from(length);
            let unique_terms: HashSet<String> = term_frequencies.keys().cloned().collect();
            let normalized_title = normalize_text(&doc.title);
            let normalized_body = normalize_text(&body_text);

            for (term, frequency) in &term_frequencies {
                self.postings
                    .entry(term.clone())
                    .or_default()
                    .push((index as u32, *frequency));
                *self.document_frequency.entry(term.clone()).or_insert(0) += 1;
                self.vocabulary.insert(term.clone());
            }

            self.documents.push(IndexedDocument {
                doc,
                term_frequencies,
                title_terms,
                unique_terms,
                normalized_title,
                normalized_body,
                length,
            });
        }

        self.average_length = if self.documents.is_empty() {
            0.0
        } else {
            total_length as f64 / self.documents.len() as f64
        };
    }

    pub fn stats(&self) -> IndexStats {
        IndexStats {
            documents: self.documents.len(),
            custom_documents: self.custom_documents,
            starter_documents: self.starter_documents,
            vocabulary_terms: self.vocabulary.len(),
            average_length: self.average_length,
        }
    }

    pub fn is_empty(&self) -> bool {
        self.documents.is_empty()
    }

    pub fn documents(&self) -> impl Iterator<Item = &Document> {
        self.documents.iter().map(|indexed| &indexed.doc)
    }

    pub fn search(&self, query: &str, options: &LocalSearchOptions) -> LocalSearchResponse {
        let started = Instant::now();
        let plan = plan_query(query);
        if plan.terms.is_empty() || self.documents.is_empty() {
            return LocalSearchResponse {
                query: query.to_string(),
                hits: Vec::new(),
                total: 0,
                documents: self.documents.len(),
                elapsed_micros: started.elapsed().as_micros() as u64,
            };
        }

        let terms = expand_terms(
            &plan.terms,
            Some(&self.vocabulary),
            Some(&self.document_frequency),
        );
        let base_terms = &plan.terms;
        let base_count = base_terms.len() as f64;
        let document_count = self.documents.len() as f64;
        let phrase = plan.phrase.clone();
        let phrase_eligible = base_terms.len() >= 2;

        let mut preliminary: Vec<(usize, f64, Vec<String>, bool)> = Vec::new();

        for (index, doc) in self.documents.iter().enumerate() {
            if !options.include_starter && !doc.doc.is_custom {
                continue;
            }

            let mut score = 0.0;
            let mut matched_terms: Vec<String> = Vec::new();

            for query_term in &terms {
                let Some(frequency) = doc.term_frequencies.get(&query_term.term).copied() else {
                    continue;
                };
                let document_frequency = self
                    .document_frequency
                    .get(&query_term.term)
                    .copied()
                    .unwrap_or(0) as f64;
                let idf =
                    (1.0 + (document_count - document_frequency + 0.5) / (document_frequency + 0.5))
                        .ln();
                let length_norm = 1.0 - B
                    + B * (doc.length as f64 / self.average_length.max(1.0));
                let denominator = frequency as f64 + K1 * length_norm;
                let term_score =
                    idf * (frequency as f64 * (K1 + 1.0)) / denominator.max(f64::EPSILON);
                score += query_term.weight * term_score;
                matched_terms.push(query_term.term.clone());
            }

            if score <= 0.0 {
                continue;
            }

            let title_coverage = if base_count == 0.0 {
                0.0
            } else {
                base_terms
                    .iter()
                    .filter(|term| doc.title_terms.contains(*term))
                    .count() as f64
                    / base_count
            };
            let all_coverage = if base_count == 0.0 {
                0.0
            } else {
                base_terms
                    .iter()
                    .filter(|term| doc.unique_terms.contains(*term))
                    .count() as f64
                    / base_count
            };

            score += 5.5 * all_coverage;
            if title_coverage >= 0.999 {
                score += 3.2;
            }
            if all_coverage < 0.45 {
                score *= 0.62;
            }

            if phrase_eligible && !phrase.is_empty() {
                if contains_phrase(&doc.normalized_title, &phrase) {
                    score += 9.0;
                } else if contains_phrase(&doc.normalized_body, &phrase) {
                    score += 2.2;
                }
            }

            if doc.doc.is_custom {
                score += 0.35;
            }
            if doc.title_terms.len() < 4 {
                score -= 0.65;
            }

            let title_match = title_coverage > 0.0;
            preliminary.push((index, score, matched_terms, title_match));
        }

        preliminary.sort_by(|a, b| {
            b.1.total_cmp(&a.1)
                .then_with(|| self.documents[a.0].doc.id.cmp(&self.documents[b.0].doc.id))
        });

        let total = preliminary.len();
        let mut seen_urls = HashSet::new();
        let mut hits = Vec::with_capacity(preliminary.len().min(options.limit.max(1)));

        for (index, score, mut matched_terms, title_match) in preliminary {
            let doc = &self.documents[index].doc;
            if let Some(key) = canonical_key(&doc.url) {
                if !seen_urls.insert(key) {
                    continue;
                }
            }
            matched_terms.sort();
            matched_terms.dedup();
            hits.push(LocalHit {
                id: doc.id.clone(),
                score: round(score),
                matched_terms,
                title_match,
            });
            if options.limit > 0 && hits.len() >= options.limit {
                break;
            }
        }

        LocalSearchResponse {
            query: query.to_string(),
            hits,
            total,
            documents: self.documents.len(),
            elapsed_micros: started.elapsed().as_micros() as u64,
        }
    }
}

fn contains_phrase(haystack: &str, phrase: &str) -> bool {
    haystack == phrase
        || haystack.starts_with(&format!("{phrase} "))
        || haystack.contains(&format!(" {phrase} "))
        || haystack.ends_with(&format!(" {phrase}"))
}

fn round(value: f64) -> f64 {
    (value * 10_000.0).round() / 10_000.0
}

#[cfg(test)]
mod tests {
    use super::*;

    fn docs() -> Vec<Document> {
        vec![
            Document {
                id: "privacy".into(),
                title: "A practical guide to browser privacy".into(),
                url: "https://example.com/privacy".into(),
                snippet: "Trackers, fingerprints and the settings that limit them.".into(),
                body: "Private browsing does not make you anonymous. It clears local history and cookies. Use a trusted network or proxy when network anonymity matters.".into(),
                section: "Privacy".into(),
                tags: vec!["browser".into(), "tracking".into()],
                ..Default::default()
            },
            Document {
                id: "rust".into(),
                title: "Rust ownership explained".into(),
                url: "https://example.com/rust".into(),
                snippet: "Borrowing, lifetimes and moves without a garbage collector.".into(),
                body: "Ownership is Rust's central memory model.".into(),
                section: "Programming".into(),
                tags: vec!["rust".into(), "memory".into()],
                ..Default::default()
            },
            Document {
                id: "weather".into(),
                title: "How weather forecasts are made".into(),
                url: "https://example.com/weather".into(),
                snippet: "Numerical models and ensembles.".into(),
                body: "Forecasting starts with observations and a model of the atmosphere.".into(),
                section: "Science".into(),
                tags: vec!["weather".into()],
                ..Default::default()
            },
        ]
    }

    fn options() -> LocalSearchOptions {
        LocalSearchOptions {
            limit: 10,
            include_starter: true,
        }
    }

    #[test]
    fn indexes_and_returns_the_obvious_document_first() {
        let mut index = LocalIndex::new();
        index.replace(docs());
        let response = index.search("browser privacy", &options());
        assert!(!response.hits.is_empty());
        assert_eq!(response.hits[0].id, "privacy");
        assert_eq!(index.stats().documents, 3);
    }

    #[test]
    fn typo_tolerance_is_used_when_the_exact_term_is_absent() {
        let mut index = LocalIndex::new();
        index.replace(docs());
        let response = index.search("privicy", &options());
        assert_eq!(response.hits.first().map(|hit| hit.id.as_str()), Some("privacy"));
    }

    #[test]
    fn synonyms_bridge_vocabulary() {
        let mut index = LocalIndex::new();
        index.replace(docs());
        let response = index.search("anonymity settings", &options());
        assert_eq!(response.hits.first().map(|hit| hit.id.as_str()), Some("privacy"));
    }

    #[test]
    fn title_phrase_beats_a_body_mention() {
        let mut index = LocalIndex::new();
        index.replace(docs());
        let response = index.search("rust ownership", &options());
        assert_eq!(response.hits.first().map(|hit| hit.id.as_str()), Some("rust"));
    }

    #[test]
    fn custom_only_mode_excludes_the_starter_shelf() {
        let mut documents = docs();
        documents.push(Document {
            id: "custom".into(),
            title: "My private browser notes".into(),
            url: "https://notes.example.com/browser".into(),
            body: "browser privacy checks I ran".into(),
            is_custom: true,
            ..Default::default()
        });
        let mut index = LocalIndex::new();
        index.replace(documents);
        let response = index.search(
            "browser privacy",
            &LocalSearchOptions {
                limit: 10,
                include_starter: false,
            },
        );
        assert!(response.hits.iter().all(|hit| hit.id == "custom"));
    }

    #[test]
    fn replaces_a_starter_page_with_the_readers_copy() {
        let mut documents = docs();
        let mut copy = documents[0].clone();
        copy.id = "custom-privacy".into();
        copy.title = "My browser privacy checklist".into();
        copy.is_custom = true;
        documents.push(copy);
        let mut index = LocalIndex::new();
        index.replace(documents);
        let stats = index.stats();
        assert_eq!(stats.documents, 3);
        assert_eq!(stats.custom_documents, 1);
        assert!(
            index
                .search("browser privacy", &options())
                .hits
                .iter()
                .any(|hit| hit.id == "custom-privacy")
        );
    }

    #[test]
    fn empty_query_returns_no_hits() {
        let mut index = LocalIndex::new();
        index.replace(docs());
        assert!(index.search("the and of", &options()).hits.is_empty());
    }

    #[test]
    fn duplicate_urls_collapse() {
        let mut documents = docs();
        documents.push(Document {
            id: "duplicate".into(),
            title: "Browser privacy, another provider".into(),
            url: "https://www.example.com/privacy?utm_source=feed".into(),
            body: "duplicate page".into(),
            ..Default::default()
        });
        let mut index = LocalIndex::new();
        index.replace(documents);
        assert_eq!(index.stats().documents, 3);
    }
}
