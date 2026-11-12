//! Unicode text normalization, analysis and query planning.

use std::collections::{HashMap, HashSet};
use std::sync::LazyLock;

use rust_stemmers::{Algorithm, Stemmer};
use serde::Serialize;
use unicode_normalization::UnicodeNormalization;

/// A compact stop list. Search providers still receive the original query;
/// these words are only removed from local ranking and index terms.
const STOP_WORDS: &[&str] = &[
    "a", "an", "and", "are", "as", "at", "be", "but", "by", "can", "do", "does",
    "for", "from", "had", "has", "have", "he", "her", "his", "how", "i", "if",
    "in", "into", "is", "it", "its", "just", "me", "my", "no", "not", "of",
    "on", "or", "our", "she", "so", "than", "that", "the", "their", "them",
    "then", "there", "these", "they", "this", "to", "was", "we", "were", "what",
    "when", "where", "which", "who", "why", "will", "with", "would", "you",
    "your", "about",
];

static STOP_SET: LazyLock<HashSet<&'static str>> =
    LazyLock::new(|| STOP_WORDS.iter().copied().collect());

static STEMMER: LazyLock<Stemmer> =
    LazyLock::new(|| Stemmer::create(Algorithm::English));

fn is_ideograph(c: char) -> bool {
    matches!(
        c as u32,
        0x3040..=0x30ff      // kana
            | 0x3400..=0x4dbf // CJK extension A
            | 0x4e00..=0x9fff // CJK unified ideographs
            | 0xac00..=0xd7af // Hangul syllables
            | 0xf900..=0xfaff // compatibility ideographs
    )
}

/// Lowercases, removes diacritic marks and normalizes typographic punctuation.
///
/// Removing marks is intentional: people type "cafe" for "café" and searches
/// should behave the same either way. The original text is never rewritten for
/// display, only for matching.
pub fn fold(raw: &str) -> String {
    let replaced = raw
        .replace(['\u{2018}', '\u{2019}', '\u{02bc}'], "'")
        .replace(['\u{201c}', '\u{201d}'], "\"")
        .replace(['\u{2013}', '\u{2014}'], "-");
    replaced
        .nfd()
        .filter(|c| !unicode_normalization::char::is_combining_mark(*c))
        .flat_map(char::to_lowercase)
        .collect()
}

/// Splits text into normalized punctuation-free tokens.
///
/// Han, kana and Hangul characters are emitted individually. That is not full
/// language segmentation, but it makes short CJK queries useful without
/// pulling a multi-megabyte dictionary into the APK.
pub fn tokenize(raw: &str) -> Vec<String> {
    let folded = fold(raw);
    let mut out = Vec::new();
    let mut current = String::new();

    for c in folded.chars() {
        if is_ideograph(c) {
            if !current.is_empty() {
                push_token(&mut out, std::mem::take(&mut current));
            }
            push_token(&mut out, c.to_string());
        } else if c.is_alphanumeric() {
            current.push(c);
        } else if !current.is_empty() {
            push_token(&mut out, std::mem::take(&mut current));
        }
    }
    if !current.is_empty() {
        push_token(&mut out, current);
    }
    out
}

fn push_token(out: &mut Vec<String>, token: String) {
    let meaningful = if token.chars().count() == 1 {
        token.chars().next().is_some_and(is_ideograph)
    } else {
        token.chars().count() >= 2
    };
    if meaningful {
        out.push(token);
    }
}

/// Lowercase token stream with whitespace collapsed. Used for phrase bonuses.
pub fn normalize_text(raw: &str) -> String {
    tokenize(raw).join(" ")
}

/// Stems one token using the Snowball English stemmer.
pub fn stem(token: &str) -> String {
    if token.chars().count() <= 2 || token.chars().all(is_ideograph) {
        return token.to_string();
    }
    STEMMER.stem(token).into_owned()
}

/// Index/query terms: stop words removed, tokens stemmed, duplicates removed.
pub fn analyze(raw: &str) -> Vec<String> {
    let mut seen = HashSet::new();
    let mut out = Vec::new();
    for token in tokenize(raw) {
        if STOP_SET.contains(token.as_str()) {
            continue;
        }
        let stemmed = stem(&token);
        if stemmed.is_empty() {
            continue;
        }
        if seen.insert(stemmed.clone()) {
            out.push(stemmed);
        }
    }
    out
}

fn synonyms(term: &str) -> &'static [&'static str] {
    // Terms arrive stemmed. Both the readable word and its common Snowball
    // stem are accepted so the table remains easy to audit.
    match term {
        "privacy" | "privaci" | "private" | "privat" => &["anonym", "untrack", "incognito"],
        "anonymous" | "anonym" => &["privaci", "untrack", "ident"],
        "password" | "passwords" | "passphrase" | "passphras" => {
            &["credential", "login", "secret"]
        }
        "security" | "secur" | "secure" => &["protect", "safeti", "privaci"],
        "encryption" | "encrypt" | "encrypted" => &["cipher", "cryptographi", "secur"],
        "browser" => &["web", "webpag", "site"],
        "tracker" | "tracking" | "track" => &["analyt", "advertis", "privaci"],
        "phone" | "smartphone" | "smartphon" => &["mobil", "android", "device"],
        "climate" | "climat" => &["warm", "carbon", "weather"],
        "money" | "finance" | "financ" => &["save", "invest", "budget"],
        "investing" | "invest" => &["index", "fund", "compound"],
        "backup" => &["restor", "recoveri", "archiv"],
        "health" => &["well", "medic", "sleep"],
        "sleep" => &["rest", "circadian", "health"],
        "space" | "astronomy" | "astronomi" => &["planet", "nasa", "cosmo"],
        "code" | "coding" => &["program", "software", "develop"],
        "search" => &["find", "queri", "discov"],
        "weather" => &["forecast", "temperatur", "rain"],
        "currency" | "currenc" => &["exchang", "rate", "dollar"],
        "define" | "defin" => &["mean", "definit", "dictionari"],
        "math" => &["calcul", "equat", "number"],
        "rust" => &["program", "compil", "languag"],
        "flutter" => &["dart", "mobil", "android"],
        _ => &[],
    }
}

/// One term and the share of confidence it carries in the query.
#[derive(Debug, Clone, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct QueryTerm {
    pub term: String,
    pub weight: f64,
    /// "base", "synonym" or "typo"
    pub reason: String,
}

impl QueryTerm {
    fn new(term: impl Into<String>, weight: f64, reason: &str) -> Self {
        Self {
            term: term.into(),
            weight,
            reason: reason.to_string(),
        }
    }
}

/// Expands base query terms with synonyms and, when a vocabulary is available,
/// a small number of high-confidence typo corrections.
pub fn expand_terms(
    base: &[String],
    vocabulary: Option<&HashSet<String>>,
    document_frequency: Option<&HashMap<String, u32>>,
) -> Vec<QueryTerm> {
    let mut weights: HashMap<String, (f64, &'static str)> = HashMap::new();

    fn put(
        weights: &mut HashMap<String, (f64, &'static str)>,
        term: String,
        weight: f64,
        reason: &'static str,
    ) {
        if term.is_empty() {
            return;
        }
        match weights.get(&term) {
            Some((existing, _)) if *existing >= weight => {}
            _ => {
                weights.insert(term, (weight, reason));
            }
        }
    }

    for term in base {
        put(&mut weights, term.clone(), 1.0, "base");
        for synonym in synonyms(term) {
            put(&mut weights, stem(synonym), 0.55, "synonym");
        }
    }

    if let Some(vocabulary) = vocabulary {
        for term in base {
            if vocabulary.contains(term) || term.chars().count() < 4 {
                continue;
            }
            for (candidate, distance) in fuzzy_terms(term, vocabulary, 4, document_frequency) {
                let weight = if distance == 1 { 0.78 } else { 0.66 };
                put(&mut weights, candidate, weight, "typo");
            }
        }
    }

    let mut out: Vec<QueryTerm> = weights
        .into_iter()
        .map(|(term, (weight, reason))| QueryTerm::new(term, weight, reason))
        .collect();
    out.sort_by(|a, b| {
        b.weight
            .total_cmp(&a.weight)
            .then_with(|| a.term.cmp(&b.term))
    });
    out
}

/// Edit candidates restricted by length and bounded distance. Sorting prefers
/// closer matches, then terms that appear in more documents.
pub fn fuzzy_terms(
    term: &str,
    vocabulary: &HashSet<String>,
    limit: usize,
    document_frequency: Option<&HashMap<String, u32>>,
) -> Vec<(String, usize)> {
    let term_len = term.chars().count();
    let max_distance = if term_len >= 8 { 2 } else { 1 };
    let mut candidates: Vec<(String, usize, u32)> = Vec::new();

    for candidate in vocabulary {
        let candidate_len = candidate.chars().count();
        let delta = candidate_len.abs_diff(term_len);
        if delta > max_distance {
            continue;
        }
        if candidate.starts_with(term) || term.starts_with(candidate.as_str()) {
            // Prefix variants are handled by stemming or are a different word;
            // do not spend a typo slot on them here.
            continue;
        }
        let Some(distance) = edit_distance_bounded(term, candidate, max_distance) else {
            continue;
        };
        if distance == 0 {
            continue;
        }
        let df = document_frequency
            .and_then(|frequencies| frequencies.get(candidate).copied())
            .unwrap_or(0);
        candidates.push((candidate.clone(), distance, df));
    }

    candidates.sort_by(|a, b| {
        a.1.cmp(&b.1)
            .then_with(|| b.2.cmp(&a.2))
            .then_with(|| a.0.cmp(&b.0))
    });
    candidates.truncate(limit);
    candidates
        .into_iter()
        .map(|(term, distance, _)| (term, distance))
        .collect()
}

/// Optimal string alignment distance, with an early exit once the bound is
/// exceeded. This catches insertions, deletions, substitutions and adjacent
/// transpositions — the mistakes people actually make while typing.
pub fn edit_distance_bounded(a: &str, b: &str, max: usize) -> Option<usize> {
    let a: Vec<char> = a.chars().collect();
    let b: Vec<char> = b.chars().collect();
    if a.len().abs_diff(b.len()) > max {
        return None;
    }
    let width = b.len() + 1;
    let mut matrix = vec![0usize; (a.len() + 1) * width];
    for (i, row) in matrix.chunks_mut(width).enumerate() {
        row[0] = i;
    }
    for j in 0..=b.len() {
        matrix[j] = j;
    }
    for i in 1..=a.len() {
        let mut row_min = usize::MAX;
        for j in 1..=b.len() {
            let substitution = usize::from(a[i - 1] != b[j - 1]);
            let mut value = (matrix[(i - 1) * width + j] + 1)
                .min(matrix[i * width + j - 1] + 1)
                .min(matrix[(i - 1) * width + j - 1] + substitution);
            if i > 1 && j > 1 && a[i - 1] == b[j - 2] && a[i - 2] == b[j - 1] {
                value = value.min(matrix[(i - 2) * width + j - 2] + 1);
            }
            matrix[i * width + j] = value;
            row_min = row_min.min(value);
        }
        if row_min > max {
            return None;
        }
    }
    let distance = matrix[a.len() * width + b.len()];
    (distance <= max).then_some(distance)
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum QueryIntent {
    General,
    Navigational,
    Informational,
    News,
    Images,
    Videos,
    Discussion,
    Definition,
    Calculation,
}

#[derive(Debug, Clone, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct QueryPlan {
    pub normalized: String,
    /// Original query words after stemming (no synonyms).
    pub terms: Vec<String>,
    /// All terms used for scoring, with weights and the reason they exist.
    pub expanded: Vec<QueryTerm>,
    pub intent: QueryIntent,
    pub is_url: bool,
    pub is_question: bool,
    pub phrase: String,
}

/// Turns a raw query into a deterministic plan shared by local search and the
/// cross-provider ranker.
pub fn plan_query(raw: &str) -> QueryPlan {
    let normalized = normalize_text(raw);
    let terms = analyze(raw);
    let expanded = expand_terms(&terms, None, None);
    let folded = fold(raw);
    let trimmed = folded.trim();
    let is_url = crate::url::is_web_url(trimmed);
    let is_question = trimmed.ends_with('?')
        || trimmed.starts_with("who ")
        || trimmed.starts_with("what ")
        || trimmed.starts_with("when ")
        || trimmed.starts_with("where ")
        || trimmed.starts_with("why ")
        || trimmed.starts_with("how ");

    let intent = if is_url {
        QueryIntent::Navigational
    } else if starts_with_any(trimmed, &["define ", "definition of ", "meaning of ", "synonym for "])
    {
        QueryIntent::Definition
    } else if contains_any(trimmed, &[" news", "headline", "headlines"])
        || trimmed.starts_with("news ")
    {
        QueryIntent::News
    } else if contains_any(trimmed, &["image", "images", "photo", "photos", "wallpaper"])
    {
        QueryIntent::Images
    } else if contains_any(trimmed, &["video", "videos", "youtube", "watch "])
    {
        QueryIntent::Videos
    } else if contains_any(
        trimmed,
        &[" reddit", " forum", " discussion", "stack overflow", "hacker news"],
    ) {
        QueryIntent::Discussion
    } else if looks_like_calculation(trimmed) {
        QueryIntent::Calculation
    } else if is_question
        || trimmed.starts_with("best ")
        || trimmed.starts_with("compare ")
    {
        QueryIntent::Informational
    } else {
        QueryIntent::General
    };

    QueryPlan {
        normalized: normalized.clone(),
        terms,
        expanded,
        intent,
        is_url,
        is_question,
        phrase: normalized,
    }
}

fn starts_with_any(value: &str, prefixes: &[&str]) -> bool {
    prefixes.iter().any(|prefix| value.starts_with(prefix))
}

fn contains_any(value: &str, needles: &[&str]) -> bool {
    needles.iter().any(|needle| value.contains(needle))
}

fn looks_like_calculation(value: &str) -> bool {
    let has_operator = value
        .chars()
        .any(|c| matches!(c, '+' | '-' | '*' | '/' | '^' | '%' | '×' | '÷'));
    let has_digit = value.chars().any(|c| c.is_ascii_digit());
    if has_operator && has_digit {
        return true;
    }
    starts_with_any(
        value,
        &[
            "calculate ",
            "convert ",
            "how many ",
            "square root",
            "percent of ",
        ],
    )
}

/// Extracts a short excerpt around the earliest matching query token.
pub fn excerpt(text: &str, query: &str, max_chars: usize) -> String {
    let clean = text.split_whitespace().collect::<Vec<_>>().join(" ");
    if clean.chars().count() <= max_chars {
        return clean;
    }
    let folded = fold(&clean);
    let terms = analyze(query);
    let mut match_at: Option<usize> = None;
    for term in &terms {
        if let Some(byte_index) = folded.find(term) {
            let char_index = folded[..byte_index].chars().count();
            match_at = Some(match_at.map_or(char_index, |best| best.min(char_index)));
        }
    }
    let chars: Vec<char> = clean.chars().collect();
    let start = match_at
        .map(|index| index.saturating_sub(max_chars / 3))
        .unwrap_or(0)
        .min(chars.len());
    let mut end = (start + max_chars).min(chars.len());
    if end < chars.len() {
        let tail: String = chars[start..end].iter().collect();
        if let Some(space) = tail.rfind(' ') {
            if space > max_chars / 3 {
                end = start + tail[..space].chars().count();
            }
        }
    }
    let mut out = String::new();
    if start > 0 {
        out.push('…');
    }
    out.extend(chars[start..end].iter());
    if end < chars.len() {
        out.push('…');
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn folds_diacritics_and_smart_punctuation() {
        assert_eq!(fold("Café’s “Menu”"), "cafe's \"menu\"");
        assert_eq!(tokenize("Café’s “Menu”"), vec!["cafe", "menu"]);
    }

    #[test]
    fn removes_stop_words_and_stems() {
        assert_eq!(analyze("How are the running searches?"), vec!["run", "search"]);
    }

    #[test]
    fn handles_cjk_without_a_dictionary() {
        assert_eq!(tokenize("東京 検索"), vec!["東", "京", "検", "索"]);
    }

    #[test]
    fn expands_synonyms() {
        let terms = vec!["privaci".to_string()];
        let expanded = expand_terms(&terms, None, None);
        assert!(expanded.iter().any(|term| term.term == "anonym"));
        assert!(expanded
            .iter()
            .any(|term| term.term == "privaci" && term.reason == "base"));
    }

    #[test]
    fn catches_typos_within_one_edit() {
        let vocabulary: HashSet<String> =
            ["privacy", "browser", "private"].iter().map(|s| s.to_string()).collect();
        let candidates = fuzzy_terms("privicy", &vocabulary, 4, None);
        assert_eq!(candidates.first().unwrap().0, "privacy");
    }

    #[test]
    fn transposition_is_one_edit() {
        assert_eq!(edit_distance_bounded("fluter", "flutter", 2), Some(1));
        assert_eq!(edit_distance_bounded("fluter", "flutter", 0), None);
    }

    #[test]
    fn classifies_intents() {
        assert_eq!(plan_query("https://example.com").intent, QueryIntent::Navigational);
        assert_eq!(plan_query("define entropy").intent, QueryIntent::Definition);
        assert_eq!(plan_query("climate news").intent, QueryIntent::News);
        assert_eq!(plan_query("12 * 4").intent, QueryIntent::Calculation);
        assert_eq!(plan_query("why is the sky blue?").intent, QueryIntent::Informational);
    }

    #[test]
    fn excerpt_centres_the_match() {
        let text = "one two three four five six seven eight nine ten eleven twelve";
        let excerpt = excerpt(text, "eight", 20);
        assert!(excerpt.contains("eight"));
        assert!(excerpt.starts_with('…') || excerpt.ends_with('…'));
    }
}
