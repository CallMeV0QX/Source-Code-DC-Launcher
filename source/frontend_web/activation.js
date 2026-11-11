(() => {
  "use strict";
  function create({ panel, host, request, helpers, toast }) {
    const { escape: esc, icons } = helpers;
    const svg = (body) =>
      '<svg viewBox="0 0 24 24" aria-hidden="true">' + body + "</svg>";
    const bolt = svg('<path d="m13 2-9 12h7l-1 8 10-13h-7Z"/>');
    const box = svg('<path d="m12 3 9 5v8l-9 5-9-5V8Zm-9 5 9 5 9-5M12 13v8"/>');
    const cloud = svg(
      '<path d="M6 18a4 4 0 0 1-1-7.9 6 6 0 0 1 11.7-1.6A4.8 4.8 0 0 1 18 18Z"/>',
    );
    const file = svg('<path d="M14 3H5v18h14V8Zm0 0v5h5M8 12h8M8 16h6"/>');
    let item = null,
      message = "",
      info = null,
      status = null,
      loading = false,
      checked = false,
      statusFlight = null,
      submitting = false,
      disposed = false,
      generation = 0,
      poll,
      renderTimer,
      lastRender = 0,
      startContext = null;
    const events = new AbortController(),
      listen = { signal: events.signal };
    const busy = () => submitting || status?.isBusy === true;
    const supersededOperations = new Set();
    function acceptStatus(next, { reconcile = false } = {}) {
      if (!next) return false;
      if (next?.operationId && supersededOperations.has(next.operationId)) return false;
      if (startContext && next.operationId === startContext.previousId && !reconcile) return false;
      if (startContext && next.operationId && next.operationId !== startContext.previousId) {
        if (startContext.previousId) supersededOperations.add(startContext.previousId);
        startContext.acceptedId = next.operationId;
      }
      if (next?.operationId && next.operationId === status?.operationId) {
        if ((next.sequence || 0) < (status.sequence || 0)) return false;
        if (["completed", "failed", "cancelled"].includes(status.state) && next.isBusy) return false;
      }
      status = { ...next, steamDirectory: next.steamDirectory ??
        (next.state !== "idle" && next.versionId === status?.versionId ? status.steamDirectory : null) };
      return true;
    }
    function lockAccount(value) {
      const logout = host.querySelector("[data-logout]");
      if (logout) logout.disabled = value;
    }
    function markup(current, detail) {
      const owned = current.status === "ready";
      const same = item?.versionId === current.versionId;
      const state = same ? status : null;
      const waiting = same ? loading : owned;
      const working = same && busy();
      const indeterminate = working && state?.isIndeterminate === true;
      const complete = state?.state === "completed";
      const failed = state?.state === "failed";
      const cancelled = state?.state === "cancelled";
      const betterOnly =
        state?.betterOnly === true && state?.state !== "busy_elsewhere";
      const retrying = false;
      const cloudSkipped = complete && betterOnly;
      const reason = !owned
        ? detail.message
        : same && message
          ? message
          : state?.isBusy
            ? state.message
            : waiting
              ? "Đang kiểm tra Steam và bộ ACTIVE…"
            : !info?.canActivate && same
              ? info?.unavailableReason || "Chưa kiểm tra được bộ ACTIVE. Hãy làm mới trạng thái."
              : state?.message || "Đang kiểm tra Steam và bộ ACTIVE…";
      const displayReason = working && !message && ["downloading_lua", "downloading_manifest", "lua_manifest"].includes(state?.stage)
        ? "Đang tải dữ liệu kích hoạt…"
        : working && !message && state?.stage === "extracting"
          ? "Đang chuẩn bị dữ liệu kích hoạt…"
          : reason;
      const canStart =
        owned &&
        same &&
        info?.canActivate &&
        state?.steamDirectory &&
        !waiting &&
        !working;
      const visibleReason = canStart && state?.state === "idle" && !message ? "" : displayReason;
      const title = !owned
        ? "Chờ nhận game"
        : working
          ? "Đang ACTIVE"
          : complete
            ? "Đã ACTIVE"
            : failed
              ? "ACTIVE chưa hoàn tất"
              : "";
      const label = !owned
        ? "Chưa thể ACTIVE"
        : working
          ? retrying
            ? "Đang xử lý"
            : "Đang xử lý"
          : complete
            ? cloudSkipped
              ? "Đã ACTIVE"
              : "Đã cài đặt"
            : failed
              ? "Cần thử lại"
              : "Chưa ACTIVE";
      const percentage = Math.max(0, Math.min(100, state?.percentage || 0));
      const components = [[bolt, "Thành phần hỗ trợ"]];
      return (
        '<aside class="library-activation" data-activation-pane aria-labelledby="' + (title ? 'library-activation-title' : 'library-activation-label') + '" aria-busy="' + (working || waiting) + '">' +
        '<div class="library-activation-heading"><p class="eyebrow" id="library-activation-label">Kích hoạt game</p><h3 id="library-activation-title"' + (title ? '' : ' hidden') + '>' +
        title +
        "</h3>" +
        '<span class="library-badge ' +
        (complete ? "is-ready" : failed ? "is-failed" : "is-pending") +
        '">' +
        label +
        "</span></div>" +
        '<div class="library-activation-actions"><button type="button" class="store-button store-primary library-active-button" data-library-active data-activation-start aria-describedby="library-active-reason" ' +
        (!canStart ? "disabled" : "") +
        ">" +
        bolt +
        (working
          ? "Đang ACTIVE…"
          : complete
            ? "ACTIVE lại"
            : failed
              ? "Thử ACTIVE lại"
              : "ACTIVE") +
        "</button>" +
        (working && state?.canCancel
          ? '<button type="button" class="store-button activation-secondary" data-activation-cancel>Hủy ACTIVE</button>'
          : "") +
        "</div>" +
        (owned &&
        (working || complete || failed || state?.state === "cancelled")
          ? '<div class="activation-progress ' +
            (failed ? "is-failed" : complete ? "is-complete" : "") +
            '"><div><span>' +
            (complete
              ? "Hoàn tất"
              : failed
                ? "Chưa hoàn tất"
                : state?.state === "cancelled"
                  ? "Đã dừng"
                  : retrying
                    ? "Tiến trình ACTIVE"
                    : "Tiến trình ACTIVE") +
            "</span><b>" +
            (indeterminate ? "Đang xử lý…" : percentage + "%") +
            '</b></div><progress max="100" ' +
            (indeterminate ? '' : 'value="' + percentage + '" ') +
            'aria-label="Tiến trình ACTIVE"></progress></div>'
          : "") +
        '<p id="library-active-reason" class="activation-message ' +
        (failed || message ? "is-error" : "") +
        '" data-activation-message role="status"' + (visibleReason ? '' : ' hidden') + '>' +
        esc(visibleReason) +
        "</p>" +
        (betterOnly
          ? '<div class="activation-warning" data-activation-warning role="status">' +
            cloud +
            "<div><strong>" +
            (cloudSkipped
              ? "Cloud Save chưa được bật"
              : cancelled
                ? "Đã dừng lượt thử lại"
                : failed
                  ? "ACTIVE chưa hoàn tất"
                  : "Đang chuẩn bị kích hoạt") +
            "</strong><p>" +
            (cloudSkipped
              ? "Đã cài thành phần kích hoạt. Cloud Save chưa được bật."
              : cancelled
                ? "Lượt thử lại đã dừng. Bạn có thể ACTIVE lại khi sẵn sàng."
                : failed
                  ? "Kiểm tra thông tin bên dưới rồi thử lại."
                  : "Launcher đang cài thành phần hỗ trợ cho game.") +
            "</p></div></div>"
          : "") +
        '<div class="library-activation-status">' +
        icons.game +
        "<div><strong>" +
        (owned ? "Game đã có trong thư viện" : "Đang chờ giao sản phẩm") +
        "</strong><p>" +
        (owned
          ? "Cài bộ hỗ trợ vào Steam trên máy này."
          : esc(detail.message)) +
        "</p></div></div>" +
        '<details class="library-package"><summary>' +
        box +
        "<span>Bộ kích hoạt</span>" +
        icons.chevron +
        "</summary><ul>" +
        components
          .map(
            ([icon, name]) =>
              '<li class="' +
              (name === "Cloud Save" && betterOnly
                ? "is-skipped"
                : complete
                  ? "is-verified"
                  : "") +
              '">' +
              icon +
              "<div><strong>" +
              name +
              "</strong><span>" +
              (name === "Cloud Save" && betterOnly
                ? complete
                  ? "Chưa được bật"
                  : "Không dùng trong lượt thử lại"
                : complete
                  ? "Đã cài đặt"
                  : name === "Cloud Save"
                    ? "Thử bật cùng bộ kích hoạt"
                    : name === "Lua"
                      ? "Kịch bản đúng game đã sở hữu"
                      : name === "Manifest"
                        ? "Thông tin phiên bản game"
                        : window.dcRuntimePrefetch?.state === "ready"
                          ? "Đã sẵn sàng trên máy"
                          : window.dcRuntimePrefetch?.state === "downloading"
                            ? "Đang tải nền • " + (window.dcRuntimePrefetch.percentage || 0) + "%"
                            : "Công cụ hỗ trợ Steam") +
              "</span></div></li>",
          )
          .join("") +
        "</ul></details>" +
        (owned && !working
          ? '<div class="activation-tools"><button type="button" class="store-text-button" data-activation-refresh>Làm mới trạng thái</button>' +
            '<button type="button" class="store-text-button" data-activation-steam>Chọn thư mục Steam</button></div>'
          : "") +
        '<p class="library-restart-note">Hãy lưu và thoát game trước khi bắt đầu. Nếu Steam chưa mở lại sau khi kích hoạt, hãy mở Steam thủ công.</p>' +
        (state?.backupDirectory
          ? '<p class="activation-backup">Bản sao lưu cấu hình được giữ trên máy.</p>'
          : "") +
        (failed
          ? '<div class="activation-tools"><button type="button" class="store-text-button activation-copy" data-activation-copy>Sao chép thông tin lỗi</button>' +
            (state?.operationId ? '<button type="button" class="store-text-button" data-activation-log>Tải file log</button>' : '') + '</div>'
          : "") +
        '<div class="library-cloud-note">' +
        cloud +
        "<span>Dữ liệu game và save hiện có được giữ lại trong quá trình kích hoạt.</span></div>" +
        '<button type="button" class="store-button library-guide-button" data-library-guide>' +
        icons.order +
        (owned ? "Xem hướng dẫn" : "Xem thông tin giao hàng") +
        "</button></aside>"
      );
    }
    // Keep the same DOM nodes: replacing the pane restarts progress/spinner animations and moves focus/scroll.
    function patchNode(current, next) {
      if (current.nodeType !== next.nodeType || current.nodeName !== next.nodeName) {
        current.replaceWith(next.cloneNode(true));
        return;
      }
      if (current.nodeType === Node.TEXT_NODE) {
        if (current.nodeValue !== next.nodeValue) current.nodeValue = next.nodeValue;
        return;
      }
      if (current.nodeType !== Node.ELEMENT_NODE) return;
      for (const attribute of [...current.attributes]) {
        if (current.tagName === "DETAILS" && attribute.name === "open") continue;
        if (!next.hasAttribute(attribute.name)) current.removeAttribute(attribute.name);
      }
      for (const attribute of next.attributes) {
        if (current.tagName === "DETAILS" && attribute.name === "open") continue;
        if (current.getAttribute(attribute.name) !== attribute.value) current.setAttribute(attribute.name, attribute.value);
      }
      const wanted = [...next.childNodes];
      for (let index = 0; index < wanted.length; index++) {
        const existing = current.childNodes[index];
        if (existing) patchNode(existing, wanted[index]);
        else current.append(wanted[index].cloneNode(true));
      }
      while (current.childNodes.length > wanted.length) current.lastChild.remove();
    }
    function render(immediate = false) {
      if (disposed || !item) return;
      const wait = 125 - (performance.now() - lastRender);
      if (!immediate && wait > 0) {
        if (!renderTimer) renderTimer = setTimeout(() => { renderTimer = null; render(true); }, wait);
        return;
      }
      clearTimeout(renderTimer); renderTimer = null; lastRender = performance.now();
      const pane = panel.querySelector("[data-activation-pane]");
      if (!pane) return;
      const open = pane.querySelector(".library-package")?.open;
      const focus = pane.contains(document.activeElement)
        ? [...document.activeElement.attributes].find((x) =>
            x.name.startsWith("data-activation-"),
          )?.name
        : null;
      const template = document.createElement("template");
      template.innerHTML = markup(item, {
        message: item.status === "ready" ? "" : message,
      });
      patchNode(pane, template.content.firstElementChild);
      if (open !== undefined)
        panel.querySelector(".library-package").open = open;
      if (focus)
        panel.querySelector("[" + focus + "]")?.focus({ preventScroll: true });
      lockAccount(busy());
    }
    function schedule() {
      clearTimeout(poll);
      if (!disposed && item && busy())
        poll = setTimeout(() => void refreshStatus(), 2000);
    }
    async function refreshStatus() {
      if (!item || disposed) return;
      const version = item.versionId,
        id = generation;
      if (statusFlight?.version === version && statusFlight.id === id) return;
      const flight = { version, id };
      statusFlight = flight;
      try {
        const result = await request("activation-status", {
          versionId: version,
        });
        if (disposed || version !== item?.versionId || id !== generation)
          return;
        if (!acceptStatus(result)) return;
        if (info || result.isBusy) message = "";
        render(!result.isBusy);
      } catch (error) {
        if (!disposed && version === item?.versionId && id === generation) {
          message = error.message;
          render();
        }
      } finally {
        if (statusFlight === flight) statusFlight = null;
        schedule();
      }
    }
    async function refresh() {
      if (!item || item.status !== "ready" || disposed || loading) return;
      if (busy()) return refreshStatus();
      const version = item.versionId,
        id = ++generation;
      loading = true;
      message = "";
      render();
      try {
        const [game, local] = await Promise.allSettled([
          request("activation-info", { versionId: version }),
          request("activation-status", { versionId: version }),
        ]);
        if (disposed || version !== item?.versionId || id !== generation)
          return;
        info = game.status === "fulfilled" ? game.value : null;
        if (local.status === "fulfilled") acceptStatus(local.value);
        else status = null;
        if (game.status === "rejected") message = game.reason.message;
        else if (local.status === "rejected") message = local.reason.message;
      } catch (error) {
        if (disposed || version !== item?.versionId || id !== generation)
          return;
        info = null;
        message = error.message;
      } finally {
        if (!disposed && version === item?.versionId && id === generation) {
          loading = false;
          checked = true;
          render();
          schedule();
        }
      }
    }
    function connect(current, detail) {
      const becameReady = item?.status !== "ready" && current.status === "ready";
      if (item?.versionId !== current.versionId) {
        generation++;
        clearTimeout(poll); clearTimeout(renderTimer); renderTimer = null;
        item = current;
        info = null;
        status = null;
        message = "";
        loading = false;
        checked = false;
        statusFlight = null;
        submitting = false;
        startContext = null;
      } else item = current;
      if (becameReady) checked = false;
      if (current.status !== "ready") {
        message = detail.message;
        return;
      }
      // Background library updates must not restart preflight or its loading state.
      if (!busy() && !loading && !checked) void refresh();
      else {
        render();
        if (!busy() && !loading && checked && info) void refreshStatus();
        else schedule();
      }
    }
    async function start() {
      if (
        !item ||
        busy() ||
        loading ||
        !info?.canActivate ||
        !status?.steamDirectory
      )
        return;
      const version = item.versionId;
      const attempt = ++generation;
      startContext = { previousId: status?.operationId ?? null, acceptedId: null };
      submitting = true;
      message = "";
      status = {
        ...status,
        operationId: null,
        sequence: 0,
        betterOnly: false,
        attemptCount: 1,
        warningCode: null,
        errorCode: null,
        state: "checking",
        stage: "checking",
        percentage: 0,
        message: "Đang bắt đầu ACTIVE…",
        isBusy: true,
        canCancel: false,
      };
      render(true);
      schedule();
      try {
        const result = await request("activation-start", {
          versionId: version,
        });
        if (disposed || item?.versionId !== version || generation !== attempt) return;
        if (!acceptStatus(result)) return;
        if (result.state === "completed")
          toast(
            result.betterOnly
              ? "ACTIVE thành công. Cloud Save chưa được bật."
              : "ACTIVE thành công.",
          );
      } catch (error) {
        if (disposed || item?.versionId !== version || generation !== attempt) return;
        message = error.message;
        // An uncertain response must never replay installation. Read the native operation first.
        try {
          const observed = await request("activation-status", { versionId: version });
          if (disposed || item?.versionId !== version || generation !== attempt) return;
          acceptStatus(observed, { reconcile: !startContext?.acceptedId });
        } catch {
          status = { ...status, isBusy: true, canCancel: false };
        }
      } finally {
        if (!disposed && item?.versionId === version && generation === attempt) {
          submitting = false; startContext = null;
          render(true);
          schedule();
        }
      }
    }
    panel.addEventListener(
      "click",
      (event) => {
        const button = event.target.closest("button");
        if (!button || button.disabled || !item) return;
        if (button.hasAttribute("data-activation-start")) void start();
        else if (button.hasAttribute("data-activation-refresh")) void refresh();
        else if (
          button.hasAttribute("data-activation-cancel") &&
          status?.operationId
        ) {
          button.disabled = true;
          void request("activation-cancel", { operationId: status.operationId })
            .then(() => refreshStatus())
            .catch((error) => toast(error.message, true));
        } else if (button.hasAttribute("data-activation-steam")) {
          void request("activation-select-steam")
            .then(() => refresh())
            .catch((error) => toast(error.message, true));
        } else if (button.hasAttribute("data-activation-log") && status?.operationId) {
          button.disabled = true;
          void request("activation-log", { versionId: item.versionId, operationId: status.operationId })
            .then((result) => { if (result.saved) toast("Đã lưu file log ACTIVE."); })
            .catch((error) => toast(error.message, true))
            .finally(() => { button.disabled = false; });
        } else if (button.hasAttribute("data-activation-copy")) {
          const text = [
            window.DCGameNames.display(item.gameName),
            item.versionName,
            status?.stage,
            status?.errorCode,
            status?.warningCode,
            status?.attemptCount ? "Lượt " + status.attemptCount + "/2" : null,
            status?.operationId,
            status?.message,
          ]
            .filter(Boolean)
            .join("\n")
            .slice(0, 2048);
          void request("copy-text", { text })
            .then(() => toast("Đã sao chép thông tin lỗi."))
            .catch((error) => toast(error.message, true));
        }
      },
      listen,
    );
    window.addEventListener("dc-runtime-prefetch", () => {
      if (!disposed && item && !busy()) render();
    }, listen);
    window.addEventListener(
      "dc-activation-progress",
      (event) => {
        const next = event.detail;
        if (!next || disposed) return;
        if (next.operationId && supersededOperations.has(next.operationId)) return;
        lockAccount(next.isBusy === true);
        if (!item) return;
        if (next.versionId === item.versionId) {
          if (!acceptStatus(next)) { lockAccount(busy()); return; }
          message = "";
          render(!next.isBusy);
          schedule();
        } else if (next.isBusy) {
          status = {
            ...next,
            versionId: item.versionId,
            state: "busy_elsewhere",
            canCancel: false,
            message: "Đang ACTIVE game khác. Hãy chờ hoàn tất.",
          };
          render();
          schedule();
        } else void refresh();
      },
      listen,
    );
    return {
      markup,
      connect,
      close() {
        generation++;
        item = null;
        submitting = false; startContext = null; loading = false;
        checked = false; statusFlight = null;
        clearTimeout(poll); clearTimeout(renderTimer); renderTimer = null;
      },
      dispose() {
        disposed = true;
        generation++;
        item = null;
        clearTimeout(poll); clearTimeout(renderTimer); renderTimer = null;
        events.abort();
        lockAccount(false);
      },
    };
  }
  window.LauncherActivation = { create };
})();
