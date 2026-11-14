'use strict';

(function () {
  const uiState = document.getElementById('ui-state');
  const uiStateText = document.getElementById('ui-state-text');
  const uiVersion = document.getElementById('ui-version');
  const uiBody = document.getElementById('ui-body');
  const uiTagline = document.getElementById('ui-tagline');
  const uiSwatch = document.getElementById('ui-swatch');

  const updateState = document.getElementById('update-state');
  const updateStateText = document.getElementById('update-state-text');
  const updateHeadline = document.getElementById('update-headline');
  const updateBody = document.getElementById('update-body');
  const updateActions = document.getElementById('update-actions');
  const updateNotes = document.getElementById('update-notes');
  const stamp = document.getElementById('stamp');

  const accentPattern = /^#[0-9a-fA-F]{6}$/;

  function setState(node, textNode, text, live) {
    node.classList.toggle('live', live === true);
    node.classList.toggle('off', live === false);
    textNode.textContent = text;
  }

  function formatBytes(bytes) {
    if (!Number.isFinite(bytes) || bytes <= 0) return '';
    const mb = bytes / (1024 * 1024);
    return `${mb.toFixed(1)} MB`;
  }

  function trustedDownload(raw) {
    if (typeof raw !== 'string') return null;
    let url;
    try {
      url = new URL(raw);
    } catch (_) {
      return null;
    }
    if (url.protocol !== 'https:') return null;
    if (url.username || url.password) return null;
    if (url.port && url.port !== '443') return null;
    const host = url.hostname;
    const allowed =
      host === 'github.com' || host.endsWith('.githubusercontent.com');
    return allowed ? url.toString() : null;
  }

  function addLink(label, href) {
    const link = document.createElement('a');
    link.className = 'quiet-link';
    link.href = href;
    link.rel = 'noopener noreferrer';
    link.textContent = label;
    updateActions.appendChild(link);
  }

  function renderUi(bundle) {
    const version = Number(bundle && bundle.version);
    if (!Number.isInteger(version) || version < 1) {
      throw new Error('invalid bundle');
    }
    setState(uiState, uiStateText, 'Published', true);
    uiVersion.textContent = `Bundle ${version}`;
    if (typeof bundle.accent === 'string' && accentPattern.test(bundle.accent)) {
      uiSwatch.style.background = bundle.accent;
      uiSwatch.hidden = false;
    } else {
      uiSwatch.hidden = true;
    }
    const starters = Array.isArray(bundle.starters) ? bundle.starters : [];
    uiBody.textContent =
      starters.length > 0
        ? `${starters.length} home-screen ${starters.length === 1 ? 'starter' : 'starters'}, validated before they reach the app.`
        : 'The home-screen starter row is hidden in this bundle.';
    if (typeof bundle.tagline === 'string' && bundle.tagline.trim()) {
      uiTagline.textContent = bundle.tagline.trim();
      uiTagline.hidden = false;
    } else {
      uiTagline.hidden = true;
    }
  }

  function renderUiFallback() {
    setState(uiState, uiStateText, 'Unavailable', false);
    uiVersion.textContent = 'Built-in interface';
    uiBody.textContent =
      'This service did not answer. Sift keeps using the interface shipped inside the app.';
    uiTagline.hidden = true;
    uiSwatch.hidden = true;
  }

  function renderUpdate(manifest) {
    if (manifest && manifest.available === true) {
      const version =
        typeof manifest.version_name === 'string'
          ? manifest.version_name
          : 'new version';
      const code = Number(manifest.version_code);
      setState(updateState, updateStateText, 'Published', true);
      updateHeadline.textContent = `Sift ${version}`;
      updateBody.textContent = [
        Number.isInteger(code) ? `Build ${code}` : '',
        formatBytes(Number(manifest.size_bytes)),
      ]
        .filter(Boolean)
        .join(' · ');
      const href = trustedDownload(manifest.apk_url);
      if (href) addLink('Download APK', href);
      if (typeof manifest.notes === 'string' && manifest.notes.trim()) {
        updateNotes.textContent = manifest.notes.trim();
        updateNotes.hidden = false;
      } else {
        updateNotes.hidden = true;
      }
      return;
    }

    setState(updateState, updateStateText, 'Published', true);
    updateHeadline.textContent = 'No app update is published';
    updateBody.textContent =
      'Sift still checks this endpoint, but nothing is offered. Android would ask before any install.';
  }

  function renderUpdateFallback() {
    setState(updateState, updateStateText, 'Unavailable', false);
    updateHeadline.textContent = 'Release channel unavailable';
    updateBody.textContent =
      'The release manifest could not be read. Sift will offer its built-in version and wait for the next check.';
  }

  async function getJson(path) {
    const response = await fetch(path, {
      headers: { Accept: 'application/json' },
      cache: 'no-store',
      credentials: 'omit',
    });
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    return response.json();
  }

  async function load() {
    const checkedAt = new Date();

    try {
      renderUi(await getJson('/api/ui'));
    } catch (_) {
      renderUiFallback();
    }

    try {
      renderUpdate(await getJson('/api/update'));
    } catch (_) {
      renderUpdateFallback();
    }

    stamp.textContent = `Checked in your browser at ${checkedAt.toLocaleTimeString(
      [],
      { hour: '2-digit', minute: '2-digit' },
    )}.`;
  }

  load();
})();