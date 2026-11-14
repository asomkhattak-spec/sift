'use strict';

const fallback = require('../latest.json');

const REPO = process.env.SIFT_REPO || 'asomkhattak-spec/sift';
const MAX_BYTES = 8 * 1024;
const MIN_APK_BYTES = 500 * 1024;
const MAX_APK_BYTES = 350 * 1024 * 1024;

function cleanText(raw, max) {
  if (typeof raw !== 'string') return '';
  return raw
    .replace(/\r\n/g, '\n')
    .replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]/g, '')
    .trim()
    .slice(0, max);
}

function versionName(raw) {
  if (typeof raw !== 'string') return null;
  const value = raw.trim();
  return /^[0-9]{1,3}(\.[0-9]{1,5}){1,3}([-+][A-Za-z0-9._-]{1,24})?$/.test(
    value,
  )
    ? value
    : null;
}

function trustedApkUrl(raw) {
  if (typeof raw !== 'string' || raw.length > 600) return false;
  let url;
  try {
    url = new URL(raw);
  } catch (_) {
    return false;
  }
  if (url.protocol !== 'https:') return false;
  if (url.username || url.password) return false;
  if (url.port && url.port !== '443') return false;
  if (url.hostname === 'github.com') {
    return url.pathname.startsWith(`/${REPO}/releases/download/`);
  }
  return url.hostname.endsWith('.githubusercontent.com');
}

function sanitize(raw) {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) {
    throw new Error('not_an_object');
  }
  if (raw.available === false) return { available: false };

  const versionCode = Number(raw.version_code);
  if (
    !Number.isInteger(versionCode) ||
    versionCode <= 0 ||
    versionCode > 2_000_000_000
  ) {
    throw new Error('bad_version_code');
  }
  const name = versionName(raw.version_name);
  if (!name) throw new Error('bad_version_name');
  if (!trustedApkUrl(raw.apk_url)) throw new Error('bad_apk_url');

  const digest = raw.sha256;
  if (typeof digest !== 'string' || !/^[0-9a-f]{64}$/.test(digest)) {
    throw new Error('bad_checksum');
  }

  const size = Number(raw.size_bytes);
  if (
    !Number.isInteger(size) ||
    size < MIN_APK_BYTES ||
    size > MAX_APK_BYTES
  ) {
    throw new Error('bad_size');
  }

  const output = {
    available: true,
    version_code: versionCode,
    version_name: name,
    tag: cleanText(raw.tag, 64) || `v${name}`,
    apk_url: raw.apk_url,
    sha256: digest,
    size_bytes: size,
    notes: cleanText(raw.notes, 3000),
  };

  if (typeof raw.published_at === 'string') {
    const parsed = Date.parse(raw.published_at);
    if (Number.isFinite(parsed)) {
      output.published_at = new Date(parsed).toISOString();
    }
  }

  if (Buffer.byteLength(JSON.stringify(output), 'utf8') > MAX_BYTES) {
    throw new Error('manifest_too_large');
  }
  return output;
}

function fallbackManifest() {
  try {
    return sanitize(fallback);
  } catch (_) {
    return { available: false };
  }
}

async function fetchReleaseManifest() {
  const headers = {
    Accept: 'application/vnd.github+json',
    'User-Agent': 'Sift-OTA/1.0',
    'X-GitHub-Api-Version': '2022-11-28',
  };
  if (process.env.GITHUB_TOKEN) {
    headers.Authorization = `Bearer ${process.env.GITHUB_TOKEN}`;
  }

  const releaseResponse = await fetch(
    `https://api.github.com/repos/${REPO}/releases/latest`,
    { headers, signal: AbortSignal.timeout(3500) },
  );
  if (!releaseResponse.ok) return null;

  const release = await releaseResponse.json();
  const assets = Array.isArray(release.assets) ? release.assets : [];
  const asset = assets.find(
    (item) => item && item.name === 'update.json',
  );
  if (!asset || typeof asset.browser_download_url !== 'string') return null;

  const manifestResponse = await fetch(asset.browser_download_url, {
    headers: {
      Accept: 'application/json',
      'User-Agent': 'Sift-OTA/1.0',
    },
    signal: AbortSignal.timeout(3500),
  });
  if (!manifestResponse.ok) return null;
  const declared = Number(manifestResponse.headers.get('content-length') || 0);
  if (declared > MAX_BYTES) return null;
  const text = await manifestResponse.text();
  if (Buffer.byteLength(text, 'utf8') > MAX_BYTES) return null;
  return sanitize(JSON.parse(text));
}

module.exports = async function update(req, res) {
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

  let manifest = null;
  try {
    manifest = await fetchReleaseManifest();
  } catch (_) {
    // A GitHub outage, rate limit, or malformed asset falls back to the
    // committed release state. It must never turn into an app update.
  }
  if (!manifest) manifest = fallbackManifest();

  res.setHeader(
    'Cache-Control',
    'public, max-age=60, s-maxage=300, stale-while-revalidate=3600',
  );
  res.status(200).json(manifest);
};