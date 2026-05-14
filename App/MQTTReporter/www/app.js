// Tiny status/config UI for the on-device httpd. All fetch targets are CGI
// scripts under /cgi-bin/.

const $ = (id) => document.getElementById(id);

const fmtAge = (epoch) => {
  if (!epoch) return "never";
  const ageSec = Math.max(0, Math.floor(Date.now() / 1000 - epoch));
  if (ageSec < 60) return `${ageSec}s ago`;
  if (ageSec < 3600) return `${Math.floor(ageSec / 60)}m ago`;
  return `${Math.floor(ageSec / 3600)}h ago`;
};

async function refreshStatus() {
  try {
    const r = await fetch("/cgi-bin/status", { cache: "no-store" });
    const s = await r.json();
    $("s-running").textContent = s.running ? "ON" : "OFF";
    $("s-running").className = s.running ? "ok" : "bad";
    $("s-broker").textContent = s.broker_ok ? "connected" : (s.broker_ok === false ? "disconnected" : "—");
    $("s-broker").className = s.broker_ok ? "ok" : (s.broker_ok === false ? "bad" : "muted");
    $("s-last").textContent = fmtAge(s.last_publish_epoch);
    $("s-entities").textContent = s.entity_count ?? "—";
    $("s-devid").textContent = s.device_id || "—";
    $("s-ip").textContent = s.ip || "—";
  } catch (e) {
    console.error(e);
  }
}

async function loadConfig() {
  try {
    const r = await fetch("/cgi-bin/config?format=json", { cache: "no-store" });
    const c = await r.json();
    if (c.MQTT_HOST) $("f-host").value = c.MQTT_HOST;
    if (c.MQTT_PORT) $("f-port").value = c.MQTT_PORT;
    if (c.MQTT_USER) $("f-user").value = c.MQTT_USER;
    if (c.MQTT_PASS) $("f-pass").placeholder = "(set — leave empty to keep)";
    if (c.INTERVAL) $("f-interval").value = c.INTERVAL;
    if (c.DEVICE_ID) $("f-devid").value = c.DEVICE_ID;
    if (c.KEEPALIVE) $("f-keepalive").value = c.KEEPALIVE;
  } catch (e) {
    console.error(e);
  }
}

$("btn-toggle").addEventListener("click", async () => {
  const fb = $("toggle-feedback");
  fb.textContent = "Toggling…";
  try {
    const r = await fetch("/cgi-bin/toggle", { method: "POST" });
    const j = await r.json();
    fb.textContent = j.running ? "Now ON" : "Now OFF";
  } catch (e) {
    fb.textContent = "Error";
  }
  refreshStatus();
});

loadConfig();
refreshStatus();
setInterval(refreshStatus, 5000);
