'use strict';

const bundled = require('../ui.json');

const REPO = process.env.SIFT_REPO || 'asomkhattak-spec/sift';
const BRANCH = process.env.SIFT_BRANCH || 'main';
const MAX_BYTES = 16 * 1024;
const DEFAULT_TAGLINE = 'No ads. No account. No profile.';
const DEFAULT_STARTERS = [
  'Rust ownership',
  'How does a heat pump work?',
  'Open source maps',
  'Best time to visit Japan',
];

function cleanLine(raw, max) {
  if (typeof raw !== 'string') return null;
  const clean = raw
    .replace(/[\u0000-\u001F\u007F]+/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
  if (!clean) return null;
  if (clean.length <= max) return clean;
  const cut = clean.slice(0, max);
  const space = cut.lastIndexOf(' ');
  return (space > max * 0.6 ? cut.slice(0, space) : cut).trimEnd();
}

function cleanStarters(raw) {
  if (!Array.isArray(raw)) return DEFAULT_STARTERS.slice();
  const seen = new Set();
  const result = [];
  for (const item of raw) {
    const value = cleanLine(item, 48);
    if (!value) continue;
    const key = value.toLowerCase();
    if (seen.has(key)) continue;
    seen.add(key);
    result.push(value);
    if (result.length === 4) break;
  }
  // An explicit empty list means "hide the row"; a malformed non-empty list
  // falls back to the shipped suggestions instead of producing a blank home.
  return result.length === 0 && raw.length > 0
    ? DEFAULT_STARTERS.slice()
    : result;
}

function cleanBoolean(raw, fallback) {
  return typeof raw === 'boolean' ? raw : fallback;
}

function sanitize(input) {
  if (!input || typeof input !== 'object' || Array.isArray(input)) return null;
  const version = Number(input.version);
  if (!Number.isInteger(version) || version < 1 || version > 1_000_000) {
    return null;
  }
  const output = {
    version,
    tagline: cleanLine(input.tagline, 90) || DEFAULT_TAGLINE,
    starters: cleanStarters(input.starters),
    show_shortcuts: cleanBoolean(input.show_shortcuts, true),
    show_privacy_card: cleanBoolean(input.show_privacy_card, true),
    compact_home: cleanBoolean(input.compact_home, false),
  };
  if (typeof input.accent === 'string' && /^#[0-9a-fA-F]{6}$/.test(input.accent)) {
    output.accent = input.accent.toLowerCase();
  }
  if (Buffer.byteLength(JSON.stringify(output), 'utf8') > MAX_BYTES) {
    return null;
  }
  return output;
}

function prefer(current, candidate) {
  if (!candidate) return current;
  if (!current) return candidate;
  return candidate.version > current.version ? candidate : current;
}

async function fetchPublishedBundle() {
  const url = `https://raw.githubusercontent.com/${REPO}/${BRANCH}/ota/ui.json`;
  const response = await fetch(url, {
    headers: {
      Accept: 'application/json',
      'User-Agent': 'Sift-OTA/1.0',
    },
    signal: AbortSignal.timeout(3500),
  });
  if (!response.ok) return null;
  const declared = Number(response.headers.get('content-length') || 0);
  if (declared > MAX_BYTES) return null;
  const text = await response.text();
  if (Buffer.byteLength(text, 'utf8') > MAX_BYTES) return null;
  return sanitize(JSON.parse(text));
}

module.exports = async function ui(req, res) {
  res.setHeader('Content-Type', 'application/json; charset=utf-8');
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.setHeader('Referrer-Policy', 'no-referrer');
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, OPTIONS');

  if (req.method === 'OPTIONS') {
    res.status(204).end();
    return;
  }
  if (req.method !== 'GET') {
    res.setHeader('Allow', 'GET, OPTIONS');
    res.status(405).json({ error: 'method_not_allowed' });
    return;
  }

  let selected = sanitize(bundled);
  try {
    selected = prefer(selected, await fetchPublishedBundle());
  } catch (_) {
    // GitHub is the source of the bundle, but the deployed copy is complete.
    // A network failure must never blank the app's interface.
  }

  if (!selected) {
    res.setHeader('Cache-Control', 'no-store');
    res.status(503).json({ error: 'bundle_unavailable' });
    return;
  }

  res.setHeader(
    'Cache-Control',
    'public, max-age=60, s-maxage=300, stale-while-revalidate=86400',
  );
  res.status(200).json(selected);
};