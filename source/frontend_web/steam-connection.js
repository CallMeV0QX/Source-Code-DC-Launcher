(() => {
  "use strict";
  const wifi = '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M2 8.5a16 16 0 0 1 20 0M5 12a11 11 0 0 1 14 0M8.5 15.5a5.5 5.5 0 0 1 7 0"/><circle cx="12" cy="19" r="1"/></svg>';
  const kinds = new Set(["Off", "Starting", "Checking", "Connected", "Failed", "Stopping", "Unknown", "Unavailable"]);
  const markup = () => `<button class="nav-item steam-connection-toggle" type="button" data-steam-connection role="switch" aria-label="1.1.1.1 — hỗ trợ kết nối Steam" aria-checked="false" aria-describedby="steam-connection-feedback" disabled>${wifi}<span class="steam-connection-label">1.1.1.1</span><i class="steam-connection-track" aria-hidden="true"></i></button><span id="steam-connection-feedback" class="sr-only" role="status"></span>`;

  function create({ host, request, toast }) {
    const button = host.querySelector("[data-steam-connection]");
    const feedback = host.querySelector("#steam-connection-feedback");
    const events = new AbortController();
    let disposed = false, supported = false, pending = false, statusFlight = null, latestRevision = -1, state = null, lastFailure = "";
    const hasOwnership = () => !!(state?.enabled || state?.cleanupPending);
    const cancelling = () => hasOwnership() || (state?.busy && ["Starting", "Checking"].includes(state.kind));
    function render() {
      if (disposed) return;
      const on = hasOwnership();
      const busy = !!state?.busy;
      button.dataset.enabled = String(on);
      button.dataset.busy = String(busy);
      button.dataset.issue = String(!!state?.cleanupPending || (on && state?.kind === "Failed"));
      button.setAttribute("aria-checked", String(on));
      button.setAttribute("aria-busy", String(pending || busy));
      button.disabled = !supported || pending || !state?.canToggle || state?.kind === "Stopping";
      const description = !supported ? "Cần cập nhật launcher để dùng hỗ trợ kết nối."
        : !state ? "Đang đọc trạng thái 1.1.1.1."
        : [state.label, state.detail].filter(Boolean).join(". ");
      const action = state?.cleanupPending ? "Bấm để thử tắt lại." : cancelling() ? "Bấm để tắt hoặc hủy." : "Bấm để bật cho phiên launcher này.";
      button.title = `1.1.1.1 — ${description}${supported && state ? ` ${action}` : ""}`;
      feedback.textContent = description;
    }
    function apply(snapshot) {
      if (disposed || !snapshot || typeof snapshot.enabled !== "boolean" || typeof snapshot.canToggle !== "boolean"
        || !Number.isSafeInteger(snapshot.revision) || snapshot.revision < latestRevision || !kinds.has(snapshot.kind)) return;
      const finishedFailure = snapshot.kind === "Failed" && !snapshot.busy && (pending || state?.busy);
      state = snapshot; latestRevision = snapshot.revision;
      render();
      const failure = `${snapshot.operationId}:${snapshot.errorCode}:${snapshot.label}`;
      if (finishedFailure && failure !== lastFailure) {
        lastFailure = failure;
        toast(snapshot.detail || snapshot.label, true);
      }
    }
    function readStatus() {
      if (disposed || !supported) return Promise.resolve();
      if (statusFlight) return statusFlight;
      statusFlight = request("steam-connection-status").then(apply).catch(error => {
        if (!disposed) {
          button.title = `1.1.1.1 — ${error.message}`;
          feedback.textContent = error.message;
        }
      }).finally(() => { statusFlight = null; });
      return statusFlight;
    }
    function initialize() {
      if (disposed || window.dcLauncherInfo?.capabilities?.steamConnection !== true) return;
      supported = true;
      apply(window.dcSteamConnection);
      render();
      void readStatus();
    }
    button.addEventListener("click", async () => {
      if (button.disabled || disposed) return;
      const enabled = !cancelling();
      pending = true; render();
      try {
        apply(await request("steam-connection-set", { enabled }));
      } catch (error) {
        if (!disposed) {
          toast(error.message || "Chưa xử lý được 1.1.1.1.", true);
          void readStatus();
        }
      } finally { pending = false; render(); }
    }, { signal: events.signal });
    window.addEventListener("dc-steam-connection", event => apply(event.detail), { signal: events.signal });
    window.addEventListener("dc-launcher-info", initialize, { signal: events.signal });
    // Reconcile after WebView navigation/return without probing, enabling or requesting UAC.
    document.addEventListener("visibilitychange", () => { if (!document.hidden) void readStatus(); }, { signal: events.signal });
    render(); initialize();
    return { dispose() { disposed = true; events.abort(); } };
  }
  window.LauncherSteamConnection = { markup, create };
})();
