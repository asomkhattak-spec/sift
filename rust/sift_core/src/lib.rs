//! Sift's native search core.
//!
//! The Flutter layer owns presentation and networking. This crate owns the
//! parts where correctness and speed matter most:
//!
//! * Unicode-aware normalization, stemming, synonyms and typo tolerance.
//! * BM25 scoring over the on-device "My Search" shelf.
//! * Cross-provider result fusion, deduplication and diversity.
//! * Conservative URL privacy cleaning.
//!
//! The public surface is a small, synchronous C ABI that speaks JSON. It can be
//! used from Dart/FFI, tests, or another host without exposing Rust types.

pub mod bm25;
pub mod ffi;
pub mod fusion;
pub mod text;
pub mod url;

pub use bm25::{
    Document, IndexStats, LocalHit, LocalIndex, LocalSearchOptions, LocalSearchResponse,
};
pub use fusion::{RankOptions, rank_results};
pub use text::{QueryIntent, QueryPlan, QueryTerm, analyze, normalize_text, plan_query, tokenize};
pub use url::{canonical_key, clean_url, display_host, is_web_url};
