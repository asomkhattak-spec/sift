//! Small JSON-over-C ABI for Dart/FFI.
//!
//! Every call returns an owned UTF-8 JSON string. The host must release it with
//! `sift_core_free_string`. The engine handle owns the on-device index; it is
//! created once by the Flutter process and freed at shutdown.

use std::ffi::{c_char, CStr, CString};
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::sync::Mutex;

use serde_json::{json, Value};

use crate::bm25::{Document, LocalIndex, LocalSearchOptions};
use crate::fusion::{rank_results, RankOptions};
use crate::text::plan_query;
use crate::url::clean_url;

pub struct EngineHandle {
    index: Mutex<LocalIndex>,
}

impl EngineHandle {
    fn new() -> Self {
        Self {
            index: Mutex::new(LocalIndex::new()),
        }
    }
}

/// Creates an engine handle. Returns null only on allocation failure.
#[no_mangle]
pub extern "C" fn sift_engine_new() -> *mut EngineHandle {
    Box::into_raw(Box::new(EngineHandle::new()))
}

/// Releases an engine handle. Passing null is safe.
#[no_mangle]
pub unsafe extern "C" fn sift_engine_free(handle: *mut EngineHandle) {
    if !handle.is_null() {
        drop(Box::from_raw(handle));
    }
}

/// Releases a string returned by `sift_core_call` or `sift_core_version`.
#[no_mangle]
pub unsafe extern "C" fn sift_core_free_string(value: *mut c_char) {
    if !value.is_null() {
        drop(CString::from_raw(value));
    }
}

/// Returns the crate version as a JSON envelope.
#[no_mangle]
pub extern "C" fn sift_core_version() -> *mut c_char {
    let response = json!({
        "ok": true,
        "data": {
            "version": env!("CARGO_PKG_VERSION"),
            "abi": 1
        }
    });
    into_c_string(response.to_string())
}

/// Executes one JSON request against the supplied engine.
///
/// Requests:
/// - `{"op":"ping"}`
/// - `{"op":"query/plan","query":"..."}`
/// - `{"op":"url/clean","url":"..."}`
/// - `{"op":"rank","query":"...","results":[...],"limit":30,...}`
/// - `{"op":"index/replace","documents":[...]}`
/// - `{"op":"index/search","query":"...","limit":24,"includeStarter":true}`
/// - `{"op":"index/stats"}`
/// - `{"op":"index/clear"}`
///
/// The response is always `{"ok":true,"data":...}` or
/// `{"ok":false,"error":"..."}`.
#[no_mangle]
pub unsafe extern "C" fn sift_core_call(
    handle: *mut EngineHandle,
    request: *const c_char,
) -> *mut c_char {
    if handle.is_null() || request.is_null() {
        return into_c_string(error_response("null handle or request"));
    }
    let request_text = match CStr::from_ptr(request).to_str() {
        Ok(text) => text,
        Err(_) => return into_c_string(error_response("request is not valid UTF-8")),
    };

    let handle = &*handle;
    let response = catch_unwind(AssertUnwindSafe(|| dispatch(handle, request_text)))
        .unwrap_or_else(|_| Err("internal panic in Sift core".to_string()));

    into_c_string(match response {
        Ok(value) => json!({ "ok": true, "data": value }).to_string(),
        Err(message) => error_response(&message),
    })
}

fn dispatch(handle: &EngineHandle, request_text: &str) -> Result<Value, String> {
    let request: Value = serde_json::from_str(request_text)
        .map_err(|error| format!("invalid request JSON: {error}"))?;
    let op = request
        .get("op")
        .and_then(Value::as_str)
        .ok_or_else(|| "missing op".to_string())?;

    match op {
        "ping" => Ok(json!({ "pong": true })),
        "query/plan" => {
            let query = required_str(&request, "query")?;
            serde_json::to_value(plan_query(query))
                .map_err(|error| format!("could not serialize query plan: {error}"))
        }
        "url/clean" => {
            let url = required_str(&request, "url")?;
            let cleaned = clean_url(url);
            Ok(json!({
                "url": cleaned,
                "changed": cleaned.as_deref() != Some(url)
            }))
        }
        "rank" => {
            let query = required_str(&request, "query")?;
            let results = request
                .get("results")
                .and_then(Value::as_array)
                .cloned()
                .ok_or_else(|| "results must be an array".to_string())?;
            let options = rank_options(&request);
            let ranked = rank_results(query, results, &options);
            Ok(Value::Array(ranked))
        }
        "index/replace" => {
            let documents: Vec<Document> = serde_json::from_value(
                request
                    .get("documents")
                    .cloned()
                    .ok_or_else(|| "documents must be an array".to_string())?,
            )
            .map_err(|error| format!("invalid documents: {error}"))?;
            let mut index = lock_index(handle)?;
            index.replace(documents);
            serde_json::to_value(index.stats())
                .map_err(|error| format!("could not serialize index stats: {error}"))
        }
        "index/search" => {
            let query = required_str(&request, "query")?;
            let options = LocalSearchOptions {
                limit: request
                    .get("limit")
                    .and_then(Value::as_u64)
                    .map(|value| value as usize)
                    .unwrap_or(24),
                include_starter: request
                    .get("includeStarter")
                    .and_then(Value::as_bool)
                    .unwrap_or(true),
            };
            let index = lock_index(handle)?;
            serde_json::to_value(index.search(query, &options))
                .map_err(|error| format!("could not serialize search response: {error}"))
        }
        "index/stats" => {
            let index = lock_index(handle)?;
            serde_json::to_value(index.stats())
                .map_err(|error| format!("could not serialize index stats: {error}"))
        }
        "index/clear" => {
            let mut index = lock_index(handle)?;
            index.replace(Vec::new());
            serde_json::to_value(index.stats())
                .map_err(|error| format!("could not serialize index stats: {error}"))
        }
        other => Err(format!("unknown op: {other}")),
    }
}

fn lock_index(handle: &EngineHandle) -> Result<std::sync::MutexGuard<'_, LocalIndex>, String> {
    handle
        .index
        .lock()
        .map_err(|_| "index lock was poisoned".to_string())
}

fn required_str<'a>(request: &'a Value, key: &str) -> Result<&'a str, String> {
    request
        .get(key)
        .and_then(Value::as_str)
        .ok_or_else(|| format!("{key} must be a string"))
}

fn rank_options(request: &Value) -> RankOptions {
    RankOptions {
        limit: request
            .get("limit")
            .and_then(Value::as_u64)
            .map(|value| value as usize)
            .unwrap_or(30),
        diversify: request
            .get("diversify")
            .and_then(Value::as_bool)
            .unwrap_or(true),
        max_per_host: request
            .get("maxPerHost")
            .and_then(Value::as_u64)
            .map(|value| value as usize)
            .unwrap_or(2),
    }
}

fn error_response(message: &str) -> String {
    json!({ "ok": false, "error": message }).to_string()
}

fn into_c_string(value: String) -> *mut c_char {
    let sanitized = value.replace('\0', "");
    CString::new(sanitized)
        .unwrap_or_else(|_| {
            CString::new("{\"ok\":false,\"error\":\"could not encode response\"}")
                .expect("static response is valid")
        })
        .into_raw()
}

#[cfg(test)]
mod tests {
    use super::*;

    unsafe fn call(handle: *mut EngineHandle, request: &str) -> Value {
        let request = CString::new(request).unwrap();
        let response = sift_core_call(handle, request.as_ptr());
        assert!(!response.is_null());
        let text = CStr::from_ptr(response).to_str().unwrap().to_string();
        sift_core_free_string(response);
        serde_json::from_str(&text).unwrap()
    }

    #[test]
    fn ffi_round_trip_indexes_and_searches() {
        unsafe {
            let handle = sift_engine_new();
            assert!(!handle.is_null());
            let replace = call(
                handle,
                r#"{"op":"index/replace","documents":[{"id":"a","title":"Rust ownership","url":"https://example.com/rust","snippet":"borrowing"},{"id":"b","title":"Weather models","url":"https://example.com/weather","snippet":"forecast"}]}"#,
            );
            assert_eq!(replace["ok"], true);
            assert_eq!(replace["data"]["documents"], 2);

            let search = call(
                handle,
                r#"{"op":"index/search","query":"rust borrow","limit":5}"#,
            );
            assert_eq!(search["ok"], true);
            assert_eq!(search["data"]["hits"][0]["id"], "a");
            sift_engine_free(handle);
        }
    }

    #[test]
    fn ffi_returns_structured_errors() {
        unsafe {
            let handle = sift_engine_new();
            let response = call(handle, r#"{"op":"nope"}"#);
            assert_eq!(response["ok"], false);
            assert!(response["error"].as_str().unwrap().contains("unknown op"));
            sift_engine_free(handle);
        }
    }

    #[test]
    fn ffi_rank_envelope_keeps_result_fields() {
        unsafe {
            let handle = sift_engine_new();
            let response = call(
                handle,
                r#"{"op":"rank","query":"privacy","results":[{"id":"x","kind":"web","title":"Privacy guide","url":"https://example.com/p","snippet":"privacy","sourceId":"bing"}]}"#,
            );
            assert_eq!(response["ok"], true);
            assert_eq!(response["data"][0]["id"], "x");
            assert!(response["data"][0]["score"].as_f64().unwrap() > 0.0);
            sift_engine_free(handle);
        }
    }
}
