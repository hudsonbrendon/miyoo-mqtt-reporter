// MQTT Reporter web UI — v3
// Tabs · category grouping · toasts · skeleton states · live status.
// No build tooling. Pure ES2017+ targeting a busybox-served static page.

const $  = (id) => document.getElementById(id);
const $$ = (sel, root = document) => Array.from(root.querySelectorAll(sel));

// ─── Tab routing ────────────────────────────────────────────────────────
const initTabs = () => {
  $$(".tab").forEach((btn) => {
    btn.addEventListener("click", () => {
      const id = btn.dataset.tab;
      $$(".tab").forEach((b) => {
        const active = b === btn;
        b.classList.toggle("active", active);
        b.setAttribute("aria-selected", active);
      });
      $$(".panel").forEach((p) => {
        const show = p.id === `panel-${id}`;
        p.hidden = !show;
        if (show) p.classList.add("active");
      });
    });
  });
};

// ─── Toast notifications ────────────────────────────────────────────────
const ICONS = {
  ok: '<svg viewBox="0 0 24 24" fill="none"><path d="M4 12.5 9 17l11-11" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>',
  info: '<svg viewBox="0 0 24 24" fill="none"><circle cx="12" cy="12" r="9" stroke="currentColor" stroke-width="1.8"/><path d="M12 8h.01M11 12h1v5h1" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/></svg>',
  bad: '<svg viewBox="0 0 24 24" fill="none"><circle cx="12" cy="12" r="9" stroke="currentColor" stroke-width="1.8"/><path d="M9 9l6 6m0-6-6 6" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/></svg>',
};

function toast(msg, kind = "info", { timeout = 3200 } = {}) {
  const root = $("toasts");
  const el = document.createElement("div");
  el.className = `toast is-${kind}`;
  el.innerHTML = `
    <span class="toast-icon">${ICONS[kind] || ICONS.info}</span>
    <div class="toast-content">${msg}</div>
  `;
  root.appendChild(el);
  setTimeout(() => {
    el.classList.add("toast-out");
    el.addEventListener("animationend", () => el.remove(), { once: true });
  }, timeout);
}

// ─── Live status (overview KPIs + topbar pill) ──────────────────────────
function fmtAge(epoch) {
  if (!epoch) return "—";
  const age = Math.max(0, Math.floor(Date.now() / 1000 - epoch));
  if (age < 60)    return `${age}s ago`;
  if (age < 3600)  return `${Math.floor(age / 60)}m ago`;
  return `${Math.floor(age / 3600)}h ago`;
}

let currentStatus = null;

async function refreshStatus() {
  try {
    const r = await fetch("/cgi-bin/status", { cache: "no-store" });
    const s = await r.json();
    currentStatus = s;
    renderStatus(s);
  } catch (e) {
    console.error(e);
  }
}

function renderStatus(s) {
  // Topbar pill
  const pill = $("hero-pill");
  const label = $("hero-label");
  pill.classList.toggle("is-on", !!s.running);
  pill.classList.toggle("is-off", !s.running);
  label.textContent = s.running ? "Daemon ON" : "Daemon OFF";

  // Overview big pill
  const op = $("overview-pill");
  const ol = $("overview-label");
  op.classList.toggle("is-on", !!s.running);
  op.classList.toggle("is-off", !s.running);
  ol.textContent = s.running ? "Running" : "Stopped";

  // KPI: broker
  const brokerDot = $("kpi-broker-dot");
  brokerDot.classList.toggle("ok",  s.broker_ok === true);
  brokerDot.classList.toggle("bad", s.broker_ok === false);
  $("kpi-broker").textContent = s.broker_ok === true ? "Connected"
                              : s.broker_ok === false ? "Disconnected"
                              : "—";
  $("kpi-broker-sub").textContent = s.last_error || (s.broker_ok ? "publishing fine" : "waiting…");

  $("kpi-last").textContent     = fmtAge(s.last_publish_epoch);
  $("kpi-entities").textContent = s.entity_count ?? "—";
  $("kpi-devid").textContent    = s.device_id || "—";
  $("kpi-ip").textContent       = s.ip || "—";
}

// ─── Settings: load current config into the form ────────────────────────
async function loadConfig() {
  try {
    const r = await fetch("/cgi-bin/config?format=json", { cache: "no-store" });
    const c = await r.json();
    if (c.MQTT_HOST) $("f-host").value = c.MQTT_HOST;
    if (c.MQTT_PORT) $("f-port").value = c.MQTT_PORT;
    if (c.MQTT_USER) $("f-user").value = c.MQTT_USER;
    if (c.MQTT_PASS) {
      $("f-pass").placeholder = "(set — leave empty to keep)";
      $("f-pass").value = c.MQTT_PASS === "********" ? "********" : "";
    }
    if (c.INTERVAL)  { $("f-interval").value  = c.INTERVAL; $("kpi-interval").textContent = c.INTERVAL; }
    if (c.DEVICE_ID) $("f-devid").value = c.DEVICE_ID;
    if (c.KEEPALIVE) $("f-keepalive").value = c.KEEPALIVE;
  } catch (e) {
    console.error(e);
    toast("Failed to load configuration", "bad");
  }
}

// ─── Entities: load, group, render, save ────────────────────────────────
const CATEGORY_RULES = [
  { id: "power",   title: "Battery & Power",  icon: "⚡", match: ["battery", "charging", "vbat", "ibat", "charging_source", "battery_warning"] },
  { id: "perf",    title: "Performance",      icon: "📈", match: ["cpu", "ram", "swap", "mem_", "process_count", "temperature", "temp_throttle", "uptime"] },
  { id: "audio",   title: "Audio",            icon: "🔊", match: ["volume", "mute", "bgm_", "audiofix"] },
  { id: "display", title: "Display",          icon: "🖥️", match: ["brightness", "hue", "saturation", "contrast", "lumination", "blue_light", "theme", "language"] },
  { id: "network", title: "Network & WiFi",   icon: "📶", match: ["wifi_", "ip", "dns_", "ntp_synced"] },
  { id: "storage", title: "Storage",          icon: "💾", match: ["sd_", "disk_", "saves_size"] },
  { id: "gaming",  title: "Gaming & Onion",   icon: "🎮", match: ["game", "core", "mode", "playtime", "session", "save_state", "last_played", "most_played", "game_count", "autostart", "hibernate", "cpuclock", "apps_count", "emulators_count", "themes_count", "saves_count", "onion_version"] },
  { id: "system",  title: "System info",      icon: "🧠", match: ["kernel", "cpu_cores", "cpu_governor"] },
];
const ICONS_SVG = {
  power:   '<svg viewBox="0 0 24 24" fill="none"><path d="M13 2 4 14h7l-1 8 9-12h-7l1-8z" stroke="currentColor" stroke-width="1.6"/></svg>',
  perf:    '<svg viewBox="0 0 24 24" fill="none"><path d="M3 17l5-5 4 4 8-8" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/><path d="M14 8h6v6" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/></svg>',
  audio:   '<svg viewBox="0 0 24 24" fill="none"><path d="M3 10v4h4l5 4V6L7 10H3z" stroke="currentColor" stroke-width="1.6" stroke-linejoin="round"/><path d="M16 9a4 4 0 0 1 0 6" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"/></svg>',
  display: '<svg viewBox="0 0 24 24" fill="none"><rect x="3" y="4" width="18" height="13" rx="2" stroke="currentColor" stroke-width="1.6"/><path d="M9 21h6M12 17v4" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"/></svg>',
  network: '<svg viewBox="0 0 24 24" fill="none"><path d="M5 13a10 10 0 0 1 14 0M8 16.5a5 5 0 0 1 8 0M12 20h.01" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"/></svg>',
  storage: '<svg viewBox="0 0 24 24" fill="none"><rect x="4" y="4" width="16" height="16" rx="2" stroke="currentColor" stroke-width="1.6"/><path d="M8 4v6h8V4" stroke="currentColor" stroke-width="1.6"/></svg>',
  gaming:  '<svg viewBox="0 0 24 24" fill="none"><rect x="3" y="8" width="18" height="10" rx="3" stroke="currentColor" stroke-width="1.6"/><path d="M8 13h-3M6.5 11.5v3M16 13h3" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"/><circle cx="14" cy="12" r="0.8" fill="currentColor"/><circle cx="17" cy="14" r="0.8" fill="currentColor"/></svg>',
  system:  '<svg viewBox="0 0 24 24" fill="none"><rect x="4" y="4" width="16" height="16" rx="2" stroke="currentColor" stroke-width="1.6"/><rect x="8" y="8" width="8" height="8" rx="1" stroke="currentColor" stroke-width="1.6"/><path d="M1 9h3M1 15h3M20 9h3M20 15h3M9 1v3M15 1v3M9 20v3M15 20v3" stroke="currentColor" stroke-width="1.4"/></svg>',
  other:   '<svg viewBox="0 0 24 24" fill="none"><circle cx="12" cy="12" r="9" stroke="currentColor" stroke-width="1.6"/></svg>',
};

function categorize(key) {
  for (const rule of CATEGORY_RULES) {
    if (rule.match.some((m) => key.startsWith(m) || key === m)) return rule.id;
  }
  return "other";
}

let allEntities = [];     // [{key, component, label, enabled, original}]
let groupsState = {};     // {categoryId: {open: bool}}

function shortLabel(label) {
  return label.replace(/^Miyoo\s+/, "");
}

async function loadEntities() {
  try {
    const r = await fetch("/cgi-bin/entities?format=json", { cache: "no-store" });
    const data = await r.json();
    allEntities = data.entities.map((e) => ({ ...e, original: !!e.enabled }));
    renderEntities();
    updateEntityBadge();
  } catch (e) {
    console.error(e);
    $("entities-groups").innerHTML = '<p class="muted center">Failed to load entity list.</p>';
    toast("Failed to load entity list", "bad");
  }
}

function renderEntities() {
  const root = $("entities-groups");
  root.innerHTML = "";

  const byCat = new Map();
  for (const e of allEntities) {
    const cat = categorize(e.key);
    if (!byCat.has(cat)) byCat.set(cat, []);
    byCat.get(cat).push(e);
  }

  const order = [...CATEGORY_RULES.map((r) => r.id), "other"];
  for (const id of order) {
    const items = byCat.get(id);
    if (!items || items.length === 0) continue;
    const rule = CATEGORY_RULES.find((r) => r.id === id) || { id, title: "Other" };
    root.appendChild(renderGroup(rule, items));
  }
}

function renderGroup(rule, items) {
  const wrap = document.createElement("section");
  wrap.className = "entity-group";
  wrap.dataset.category = rule.id;
  // Open by default; remember user toggles across re-renders
  const state = groupsState[rule.id] ??= { open: true };
  if (state.open) wrap.classList.add("is-open");

  const enabledCount = items.filter((e) => e.enabled).length;

  wrap.innerHTML = `
    <header>
      <div class="group-icon">${ICONS_SVG[rule.id] || ICONS_SVG.other}</div>
      <span class="group-title">${rule.title}</span>
      <span class="group-count">${enabledCount}/${items.length}</span>
      <svg class="group-chevron" viewBox="0 0 24 24" fill="none"><path d="m6 9 6 6 6-6" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/></svg>
    </header>
    <div class="group-body">
      <div class="group-controls">
        <button type="button" class="ghost-btn group-all">All</button>
        <button type="button" class="ghost-btn group-none">None</button>
      </div>
      <div class="group-grid"></div>
    </div>
  `;
  const grid = wrap.querySelector(".group-grid");
  for (const ent of items) grid.appendChild(renderEntity(ent));

  // header → toggle open
  wrap.querySelector("header").addEventListener("click", () => {
    state.open = !state.open;
    wrap.classList.toggle("is-open", state.open);
  });

  wrap.querySelector(".group-all").addEventListener("click", (e) => {
    e.stopPropagation();
    for (const ent of items) ent.enabled = true;
    renderEntities();
    updateEntityBadge();
  });
  wrap.querySelector(".group-none").addEventListener("click", (e) => {
    e.stopPropagation();
    for (const ent of items) ent.enabled = false;
    renderEntities();
    updateEntityBadge();
  });

  // Style the count chip based on filled-ness
  const chip = wrap.querySelector(".group-count");
  if (enabledCount === items.length) chip.classList.add("full");
  else if (enabledCount > 0) chip.classList.add("partial");

  return wrap;
}

function renderEntity(ent) {
  const lbl = document.createElement("label");
  lbl.className = "entity";
  lbl.dataset.key = ent.key;
  lbl.dataset.search = `${ent.label} ${ent.key}`.toLowerCase();
  lbl.innerHTML = `
    <input type="checkbox" name="entity_${ent.key}" value="on"${ent.enabled ? " checked" : ""}>
    <span class="entity-name">
      <span>${shortLabel(ent.label)}</span>
      <span class="ent-key">${ent.key}</span>
    </span>
    ${ent.component === "binary_sensor" ? '<span class="entity-tag">bin</span>' : ""}
  `;
  lbl.querySelector("input").addEventListener("change", (e) => {
    ent.enabled = e.target.checked;
    refreshGroupCounts();
    updateEntityBadge();
  });
  return lbl;
}

function refreshGroupCounts() {
  for (const group of $$(".entity-group")) {
    const cat = group.dataset.category;
    const items = allEntities.filter((e) => categorize(e.key) === cat);
    const on = items.filter((e) => e.enabled).length;
    const chip = group.querySelector(".group-count");
    chip.textContent = `${on}/${items.length}`;
    chip.classList.toggle("full",    on === items.length);
    chip.classList.toggle("partial", on > 0 && on < items.length);
  }
}

function updateEntityBadge() {
  const on = allEntities.filter((e) => e.enabled).length;
  $("ent-badge").textContent = `${on}/${allEntities.length}`;
  $("ent-summary").textContent = `${on} of ${allEntities.length} enabled`;
}

// ─── Toolbar buttons ────────────────────────────────────────────────────
const wireEntitiesToolbar = () => {
  $("ent-all").addEventListener("click", () => {
    allEntities.forEach((e) => (e.enabled = true));
    renderEntities();
    updateEntityBadge();
  });
  $("ent-none").addEventListener("click", () => {
    allEntities.forEach((e) => (e.enabled = false));
    renderEntities();
    updateEntityBadge();
  });
  $("ent-reset").addEventListener("click", () => {
    allEntities.forEach((e) => (e.enabled = e.original));
    renderEntities();
    updateEntityBadge();
    toast("Reset to saved selection", "info", { timeout: 1800 });
  });
  $("ent-filter").addEventListener("input", (ev) => {
    const q = ev.target.value.toLowerCase().trim();
    let visiblePerGroup = new Map();
    for (const el of $$(".entity")) {
      const matches = !q || el.dataset.search.includes(q);
      el.classList.toggle("hidden", !matches);
    }
    // Hide groups with no visible items, force-open the rest.
    for (const grp of $$(".entity-group")) {
      const visible = $$(".entity:not(.hidden)", grp).length;
      grp.classList.toggle("is-empty", visible === 0);
      if (q && visible > 0) grp.classList.add("is-open");
    }
  });
};

// ─── Toggle wiring ──────────────────────────────────────────────────────
async function toggleDaemon() {
  try {
    const r = await fetch("/cgi-bin/toggle", { method: "POST" });
    const j = await r.json();
    toast(`Daemon ${j.running ? "started" : "stopped"}`, "ok", { timeout: 1800 });
    refreshStatus();
  } catch (e) {
    toast("Toggle failed", "bad");
  }
}

// ─── Saved-state toasts after redirect ──────────────────────────────────
function checkRedirectFlash() {
  const q = new URLSearchParams(location.search);
  if (q.has("saved"))           toast("Configuration saved · daemon restarted", "ok");
  if (q.has("entities_saved"))  toast("Entity selection saved · daemon restarted", "ok");
  if (q.size > 0) {
    history.replaceState(null, "", location.pathname);
  }
}

// ─── Boot ───────────────────────────────────────────────────────────────
initTabs();
wireEntitiesToolbar();
$("hero-toggle").addEventListener("click", toggleDaemon);
$("overview-toggle").addEventListener("click", toggleDaemon);

checkRedirectFlash();
loadConfig();
loadEntities();
refreshStatus();
setInterval(refreshStatus, 5000);
