// hermes-station dashboard — Polling & DOM updates

(function () {
  'use strict';

  var POLL_INTERVAL = 10000;
  var SERVICES = ['gbrain', 'honcho', 'hermes', 'hermes-webui', 'postgres', 'ollama'];

  // --- Helpers ---

  function formatNumber(n) {
    if (n == null || typeof n !== 'number') return 'N/A';
    return n.toLocaleString();
  }

  function formatLatency(ms) {
    if (ms == null || typeof ms !== 'number') return '--';
    return ms + 'ms';
  }

  function formatTime(date) {
    return date.toLocaleTimeString();
  }

  // --- DOM updates ---

  function updateHealth(data) {
    var services = (data && data.services) || {};

    SERVICES.forEach(function (name) {
      var info = services[name] || {};
      var status = info.status || 'unknown';

      var card = document.querySelector('.health-card[data-service="' + name + '"]');
      if (!card) return;

      // Update card class
      card.className = 'health-card ' + status;

      // Update status dot
      var dot = card.querySelector('.status-dot');
      if (dot) dot.className = 'status-dot ' + status;

      // Update latency
      var latencyEl = card.querySelector('.latency');
      if (latencyEl) latencyEl.textContent = formatLatency(info.latencyMs);
    });
  }

  function updateMetrics(data) {
    if (!data) return;

    var gbrainFields = ['page_count', 'chunk_count', 'entity_count', 'link_count'];
    var honchoFields = ['peer_count', 'session_count', 'representation_count'];

    var gbrain = data.gbrain || {};
    var honcho = data.honcho || {};

    gbrainFields.forEach(function (key) {
      var el = document.getElementById('gbrain-' + key);
      if (el) el.textContent = formatNumber(gbrain[key]);
    });

    honchoFields.forEach(function (key) {
      var el = document.getElementById('honcho-' + key);
      if (el) el.textContent = formatNumber(honcho[key]);
    });
  }

  function updateTokens(data) {
    var panel = document.getElementById('tokensPanel');
    if (!panel) return;

    if (!data || Object.keys(data).length === 0) {
      panel.innerHTML = '<p class="tokens-unavailable">Data unavailable</p>';
      return;
    }

    var html = '<div class="tokens-grid">';
    Object.keys(data).forEach(function (key) {
      var label = key.replace(/_/g, ' ');
      html += '<div class="token-item">';
      html += '<span class="token-value">' + formatNumber(data[key]) + '</span>';
      html += '<span class="token-label">' + label + '</span>';
      html += '</div>';
    });
    html += '</div>';
    panel.innerHTML = html;
  }

  function updateTimestamp() {
    var el = document.getElementById('lastUpdated');
    if (el) el.textContent = 'Last updated: ' + formatTime(new Date());
  }

  // --- Fetching ---

  function fetchJSON(url) {
    return fetch(url).then(function (res) {
      if (!res.ok) throw new Error('HTTP ' + res.status);
      return res.json();
    });
  }

  function poll() {
    var healthReq = fetchJSON('/api/health')
      .then(updateHealth)
      .catch(function () {
        // Mark all services as unknown on error
        updateHealth({});
      });

    var metricsReq = fetchJSON('/api/metrics')
      .then(updateMetrics)
      .catch(function () {
        updateMetrics({});
      });

    var tokensReq = fetchJSON('/api/tokens')
      .then(updateTokens)
      .catch(function () {
        updateTokens(null);
      });

    Promise.all([healthReq, metricsReq, tokensReq]).then(updateTimestamp);
  }

  // --- Init ---

  poll();
  setInterval(poll, POLL_INTERVAL);
})();
