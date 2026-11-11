(() => {
  "use strict";
  function create({
    host,
    panel,
    request,
    user,
    helpers,
    onRoute,
    onCart,
    toast,
    onBalance,
  }) {
    const { escape: esc, image, money, icons } = helpers;
    const events = new AbortController();
    const listen = { signal: events.signal };
    const storageKey = `dc-launcher-topup:${user.id}`;
    const copy =
      '<svg viewBox="0 0 24 24" aria-hidden="true"><rect x="8" y="8" width="12" height="13"/><path d="M16 8V3H3v13h5"/></svg>';
    let disposed = false,
      busy = false,
      route = null,
      sequence = 0,
      historySequence = 0;
    let wallet = null,
      detail = null,
      topUpId = null,
      timer = null,
      tick = null,
      dialog = null;
    let tab = "topups",
      rows = [],
      nextOffset = null,
      amount = "100000",
      pending = null;
    try {
      pending = JSON.parse(localStorage.getItem(storageKey));
    } catch {
      /* Memory fallback. */
    }
    if (
      !pending ||
      typeof pending.idempotencyKey !== "string" ||
      pending.idempotencyKey.length < 16 ||
      !Number.isSafeInteger(pending.amount) ||
      pending.amount <= 0 ||
      !["live", "test"].includes(pending.environment)
    )
      pending = null;
    function savePending(value) {
      pending = value;
      try {
        if (value) localStorage.setItem(storageKey, JSON.stringify(value));
        else localStorage.removeItem(storageKey);
      } catch {
        /* The same request key remains available in memory. */
      }
    }
    const date = (value) => new Date(value).toLocaleString("vi-VN");
    const body = () => panel.querySelector("[data-wallet-body]");
    function status(message, error = false) {
      const target = panel.querySelector("[data-wallet-status]");
      if (!target) return;
      target.textContent = message;
      target.hidden = !message;
      target.classList.toggle("is-error", error);
    }
    function heading(title, description) {
      const titleMarkup = route === "wallet"
        ? `<h2 class="sr-only" tabindex="-1">${esc(title)}</h2>`
        : `<div class="commerce-heading"><div><p class="eyebrow">DC Gaming / Ví DC</p><h2 tabindex="-1">${esc(title)}</h2><p>${esc(description)}</p></div><button class="store-text-button" type="button" data-wallet-cart>${icons.arrow}Quay lại giỏ hàng</button></div>`;
      panel.innerHTML = `${titleMarkup}<div class="commerce-notice" data-wallet-status role="status" hidden></div><div data-wallet-body></div>`;
    }
    function loading(title) {
      heading(
        title,
        "Số dư và giao dịch được đồng bộ với tài khoản DC Gaming.",
      );
      body().innerHTML =
        '<div class="commerce-loading" role="status"><span class="spinner"></span>Đang tải…</div>';
    }
    function failure(error) {
      body().innerHTML = `<div class="store-empty" role="alert">${icons.refresh}<h3>Chưa tải được ví</h3><p>${esc(error.message)}</p><button class="store-button" type="button" data-wallet-refresh>Thử lại ${icons.refresh}</button></div>`;
    }
    function lock(value) {
      busy = value;
      panel.setAttribute("aria-busy", String(value));
      for (const root of [panel, dialog].filter(Boolean))
        root.querySelectorAll("button,input").forEach((el) => {
          if (value) {
            if (el.dataset.walletDisabled === undefined)
              el.dataset.walletDisabled = String(el.disabled);
            el.disabled = true;
          } else if (el.dataset.walletDisabled !== undefined) {
            el.disabled = el.dataset.walletDisabled === "true";
            delete el.dataset.walletDisabled;
          }
        });
    }
    function closeDialog() {
      dialog?.close();
      dialog?.remove();
      dialog = null;
    }
    function stop() {
      clearTimeout(timer);
      clearInterval(tick);
    }
    function close() {
      sequence++;
      historySequence++;
      route = null;
      stop();
      closeDialog();
    }
    async function open(view = "wallet", id = null) {
      if (busy || disposed) return;
      close();
      route = view;
      topUpId = id;
      detail = null;
      onRoute(view);
      if (view === "topup") await loadDetail();
      else await loadWallet();
      if (!disposed && route === view)
        panel.querySelector("h2")?.focus({ preventScroll: true });
    }
    function walletMarkup() {
      heading("Ví DC", "Nạp tiền và dùng số dư để thanh toán game nhanh hơn.");
      const presets = [50000, 100000, 200000, 500000, 1000000].filter(
        (x) => x >= wallet.minimumTopUp && x <= wallet.maximumTopUp,
      );
      body().innerHTML = `${wallet.environment === "test" ? '<p class="order-message">Chế độ thử nghiệm: không chuyển tiền thật. Giao dịch thử không cộng vào số dư ví.</p>' : ""}
        ${pending ? `<div class="commerce-notice is-error wallet-recovery"><span>Yêu cầu nạp ${money(pending.amount)} chưa xác định được kết quả.</span><button class="store-button" type="button" data-wallet-recover>Kiểm tra yêu cầu ${icons.refresh}</button></div>` : ""}
        <div class="wallet-layout"><section class="wallet-balance-card"><div class="wallet-balance-label">${icons.wallet}<span>Số dư khả dụng</span></div><strong data-wallet-balance>${money(wallet.balance)}</strong><p>Sử dụng số dư để mua game trên website và launcher.</p><button class="store-button" type="button" data-wallet-cart>Đến giỏ hàng ${icons.arrow}</button></section>
        <form class="wallet-topup-form" data-wallet-form novalidate><div class="wallet-section-heading"><h3>Nạp tiền vào ví</h3><span>Chuyển khoản ngân hàng</span></div>
        ${wallet.message ? `<p class="order-message" role="status">${esc(wallet.message)}</p>` : ""}<label for="wallet-amount">Số tiền muốn nạp</label><div class="wallet-amount-field"><input id="wallet-amount" type="text" inputmode="numeric" autocomplete="off" maxlength="10" aria-describedby="wallet-amount-help wallet-amount-error" value="${esc(amount)}" ${!wallet.canTopUp || pending ? "disabled" : ""}><span>VND</span></div>
        <p id="wallet-amount-help" class="wallet-help">Từ ${money(wallet.minimumTopUp)} đến ${money(wallet.maximumTopUp)}.</p><p id="wallet-amount-error" class="wallet-field-error" role="alert" hidden></p>
        <div class="wallet-presets" aria-label="Chọn nhanh số tiền">${presets.map((x) => `<button class="store-button" type="button" data-wallet-amount="${x}" aria-pressed="${Number(amount) === x}" ${!wallet.canTopUp || pending ? "disabled" : ""}>${money(x)}</button>`).join("")}</div>
        <button class="store-button store-primary wallet-submit" type="submit" ${!wallet.canTopUp || pending ? "disabled" : ""}>Tạo mã QR nạp tiền ${icons.arrow}</button><p class="wallet-help">Số dư tự cập nhật khi ngân hàng xác nhận chuyển khoản.</p></form></div>
        <section class="wallet-history"><div class="wallet-history-heading"><h3>Lịch sử ví</h3><button class="store-text-button" type="button" data-wallet-refresh>${icons.refresh}Làm mới</button></div><div class="wallet-tabs" role="tablist" aria-label="Lịch sử ví"><button type="button" id="wallet-tab-topups" role="tab" aria-controls="wallet-history-panel" data-wallet-tab="topups" aria-selected="${tab === "topups"}" tabindex="${tab === "topups" ? 0 : -1}">Yêu cầu nạp</button><button type="button" id="wallet-tab-transactions" role="tab" aria-controls="wallet-history-panel" data-wallet-tab="transactions" aria-selected="${tab === "transactions"}" tabindex="${tab === "transactions" ? 0 : -1}">Biến động số dư</button></div><div id="wallet-history-panel" role="tabpanel" tabindex="0" aria-labelledby="wallet-tab-${tab}" data-wallet-history></div></section>`;
    }
    async function loadWallet(message = "") {
      const id = ++sequence;
      historySequence++;
      stop();
      loading("Ví DC");
      try {
        const result = await request("wallet");
        if (disposed || route !== "wallet" || id !== sequence) return;
        wallet = result;
        onBalance?.(wallet.balance);
        walletMarkup();
        if (message) status(message, true);
        await loadHistory();
      } catch (error) {
        if (!disposed && route === "wallet" && id === sequence) failure(error);
      }
    }
    function historyMarkup() {
      const target = panel.querySelector("[data-wallet-history]");
      if (!target) return;
      target.setAttribute("aria-labelledby", `wallet-tab-${tab}`);
      target.innerHTML = rows.length
        ? `<div class="wallet-history-list">${rows
            .map((row) =>
              tab === "topups"
                ? `<button class="wallet-history-row" type="button" data-wallet-topup="${esc(row.topUpId)}"><span class="wallet-row-icon">${icons.wallet}</span><span class="wallet-row-title"><strong>${esc(row.code)}</strong><small>${date(row.createdAt)}${row.environment === "test" ? " · Thử nghiệm" : ""}</small></span><span class="order-status ${row.status === "completed" ? "is-paid" : ""}">${esc(row.statusLabel)}</span><strong>${money(row.amount)}</strong>${icons.chevron}</button>`
                : `<div class="wallet-history-row wallet-ledger-row"><span class="wallet-row-icon">${icons.wallet}</span><span class="wallet-row-title"><strong>${esc(row.label)}</strong><small>${esc(row.description || date(row.createdAt))}</small><small>${date(row.createdAt)}</small></span><span class="wallet-ledger-balance">Số dư sau<br><strong>${money(row.balanceAfter)}</strong></span><strong class="${row.direction === "credit" ? "wallet-credit" : ""}">${row.direction === "credit" ? "+" : "−"}${money(row.amount)}</strong></div>`,
            )
            .join(
              "",
            )}</div>${nextOffset !== null ? '<button class="store-button orders-more" type="button" data-wallet-more>Tải thêm</button>' : ""}`
        : `<div class="wallet-history-empty">${icons.order}<p>${tab === "topups" ? "Chưa có yêu cầu nạp tiền." : "Chưa có giao dịch thay đổi số dư."}</p></div>`;
    }
    async function loadHistory(append = false) {
      const id = ++historySequence,
        current = tab;
      const target = panel.querySelector("[data-wallet-history]");
      if (!target) return;
      if (!append) {
        rows = [];
        target.innerHTML =
          '<div class="commerce-loading" role="status"><span class="spinner"></span>Đang tải lịch sử…</div>';
      } else
        target
          .querySelector("[data-wallet-more]")
          ?.setAttribute("disabled", "");
      try {
        const result = await request(`wallet-${current}`, {
          offset: append ? nextOffset : 0,
        });
        if (disposed || route !== "wallet" || id !== historySequence) return;
        rows = append
          ? [
              ...new Map(
                [...rows, ...result.items].map((x) => [
                  x.topUpId || x.walletTransactionId,
                  x,
                ]),
              ).values(),
            ]
          : result.items;
        nextOffset = result.nextOffset;
        historyMarkup();
      } catch (error) {
        if (disposed || route !== "wallet" || id !== historySequence) return;
        if (append) {
          historyMarkup();
          status(error.message, true);
        } else
          target.innerHTML = `<div class="wallet-history-empty" role="alert"><p>${esc(error.message)}</p><button class="store-button" type="button" data-wallet-history-retry>Thử lại</button></div>`;
      }
    }
    function selectTab(value) {
      tab = value;
      panel.querySelectorAll("[data-wallet-tab]").forEach((el) => {
        el.setAttribute("aria-selected", String(el.dataset.walletTab === tab));
        el.tabIndex = el.dataset.walletTab === tab ? 0 : -1;
      });
      void loadHistory();
    }
    async function submit(recover = false) {
      if (busy || disposed) return;
      if (!recover && !pending) {
        if (!wallet?.canTopUp) return;
        const input = panel.querySelector("#wallet-amount");
        amount = input.value.trim();
        const value = Number(amount);
        if (
          !/^\d+$/.test(amount) ||
          !Number.isSafeInteger(value) ||
          value < wallet.minimumTopUp ||
          value > wallet.maximumTopUp
        ) {
          const error = panel.querySelector("#wallet-amount-error");
          error.textContent = `Nhập số tiền nguyên từ ${money(wallet.minimumTopUp)} đến ${money(wallet.maximumTopUp)}.`;
          error.hidden = false;
          input.setAttribute("aria-invalid", "true");
          input.focus();
          return;
        }
        savePending({
          amount: value,
          idempotencyKey: crypto.randomUUID(),
          environment: wallet.environment,
        });
      }
      if (!pending) return;
      lock(true);
      status("Đang kiểm tra yêu cầu nạp tiền…");
      try {
        let result = recover
          ? await request("wallet-find", { key: pending.idempotencyKey })
          : null;
        if (disposed) return;
        if (!result?.topUpId) result = await request("wallet-create", pending);
        if (!result?.topUpId)
          throw new Error("Chưa xác định được yêu cầu nạp tiền.");
        savePending(null);
        if (disposed) return;
        lock(false);
        await open("topup", result.topUpId);
      } catch (error) {
        if (disposed) return;
        if (
          ["wallet_error", "invalid_input", "request_failed"].includes(
            error.code,
          )
        ) {
          savePending(null);
          await loadWallet(error.message);
        } else {
          walletMarkup();
          void loadHistory();
          status(
            `${error.message} Hãy kiểm tra yêu cầu trước khi tạo lần nạp khác.`,
            true,
          );
        }
      } finally {
        if (!disposed) lock(false);
      }
    }
    const remaining = () =>
      Math.max(
        0,
        Math.ceil((Date.parse(detail?.topUp.expiresAt) - Date.now()) / 1000),
      );
    function detailMarkup() {
      const topup = detail.topUp,
        complete = topup.status === "completed";
      const payable =
        topup.status === "pending" && topup.qrUrl && remaining() > 0;
      heading("Nạp ví DC", topup.code);
      const field = (label, value, copyValue) =>
        `<div><dt>${label}</dt><dd><span>${esc(value)}</span>${copyValue ? `<button class="store-icon-button" type="button" data-wallet-copy="${esc(copyValue)}" aria-label="Sao chép ${label.toLowerCase()}">${copy}</button>` : ""}</dd></div>`;
      body().innerHTML = `<div class="order-overview ${complete ? "is-paid" : ""}">${icons.wallet}<div><h3>${esc(topup.statusLabel)}</h3><p>${complete ? "Tiền đã được cộng vào ví DC của bạn." : "Yêu cầu nạp " + esc(topup.code)}</p></div><strong>${money(topup.amount)}</strong></div>
        ${topup.message ? `<p class="order-message" role="status">${esc(topup.message)}</p>` : ""}
        ${payable ? `<section class="order-payment wallet-payment"><div class="order-qr"><div class="qr-image">${image(topup.qrUrl, "", false)}<span>Không tải được QR? Dùng thông tin chuyển khoản bên cạnh.</span></div><p>Thời gian còn lại <strong data-wallet-countdown></strong></p></div><div><h3>Thông tin chuyển khoản</h3><dl class="bank-details">${field("Ngân hàng", topup.bankCode)}${field("Chủ tài khoản", topup.accountName)}${field("Số tài khoản", topup.accountNumber, topup.accountNumber)}${field("Số tiền", money(topup.amount), String(topup.amount))}${field("Nội dung", topup.code, topup.code)}</dl><p class="cart-footnote">Chuyển đúng số tiền và giữ nguyên nội dung. Trạng thái tự cập nhật sau khi ngân hàng xác nhận.</p></div></section>` : ""}
        <div class="wallet-current-balance"><span>Số dư ví hiện tại</span><strong data-wallet-balance>${money(detail.balance)}</strong></div><div class="order-actions"><button class="store-button" type="button" data-wallet-home>${icons.wallet}Về ví DC</button><button class="store-button" type="button" data-wallet-refresh>${icons.refresh}Cập nhật trạng thái</button>${topup.status === "pending" && remaining() > 0 && topup.qrUrl ? '<button class="store-text-button order-cancel" type="button" data-wallet-cancel>Hủy yêu cầu</button>' : ""}${complete ? `<button class="store-button store-primary" type="button" data-wallet-cart>Tiếp tục thanh toán ${icons.arrow}</button>` : ""}</div>`;
      countdown();
    }
    function countdown() {
      const target = panel.querySelector("[data-wallet-countdown]");
      if (!target) return;
      const left = remaining();
      target.textContent = `${String(Math.floor(left / 60)).padStart(2, "0")}:${String(left % 60).padStart(2, "0")}`;
      if (left === 0) {
        panel.querySelector(".wallet-payment")?.setAttribute("hidden", "");
        panel.querySelector("[data-wallet-cancel]")?.setAttribute("hidden", "");
        status(
          "Yêu cầu đã hết hạn. Không chuyển tiền vào mã này. Nếu đã chuyển, liên hệ hỗ trợ kèm mã nạp.",
          true,
        );
      }
    }
    function schedule() {
      clearTimeout(timer);
      if (
        !disposed &&
        route === "topup" &&
        (!detail || detail.topUp.status === "pending")
      )
        timer = setTimeout(() => {
          if (busy || document.hidden || dialog?.open) schedule();
          else void loadDetail(true);
        }, 7000);
    }
    async function loadDetail(quiet = false) {
      const id = ++sequence;
      clearTimeout(timer);
      if (!quiet) loading("Nạp ví DC");
      try {
        const result = await request("wallet-topup", { topUpId });
        if (disposed || route !== "topup" || id !== sequence) return;
        const changed = JSON.stringify(detail) !== JSON.stringify(result);
        const wasPending = detail?.topUp.status === "pending";
        detail = result;
        if (Number.isFinite(detail.balance)) onBalance?.(detail.balance);
        if (changed || !quiet) detailMarkup();
        else status("");
        if (wasPending && detail.topUp.status === "completed")
          toast("Nạp tiền thành công. Số dư ví DC đã được cập nhật.");
        clearInterval(tick);
        if (detail.topUp.status === "pending") {
          countdown();
          tick = setInterval(countdown, 1000);
        }
      } catch (error) {
        if (!disposed && route === "topup" && id === sequence) {
          if (quiet)
            status(`Chưa cập nhật được trạng thái: ${error.message}`, true);
          else failure(error);
        }
      } finally {
        if (id === sequence) schedule();
      }
    }
    function confirmCancel() {
      closeDialog();
      dialog = document.createElement("dialog");
      dialog.className = "commerce-dialog";
      dialog.setAttribute("aria-labelledby", "wallet-dialog-title");
      dialog.innerHTML =
        '<h2 id="wallet-dialog-title">Hủy yêu cầu nạp tiền?</h2><p>Chỉ hủy khi bạn chưa chuyển khoản. Nếu đã chuyển, hãy chờ xác nhận hoặc liên hệ hỗ trợ kèm mã nạp.</p><div class="commerce-dialog-actions"><button class="store-button" type="button" data-wallet-dialog-close>Giữ yêu cầu</button><button class="store-button store-primary" type="button" data-wallet-confirm-cancel>Hủy yêu cầu</button></div>';
      host.append(dialog);
      dialog.showModal();
      dialog.addEventListener("cancel", (event) => {
        if (busy) event.preventDefault();
      });
    }
    async function cancel() {
      if (busy) return;
      lock(true);
      clearTimeout(timer);
      sequence++;
      try {
        await request("wallet-cancel", { topUpId });
        if (disposed) return;
        closeDialog();
        await loadDetail();
      } catch (error) {
        if (disposed) return;
        closeDialog();
        await loadDetail();
        status(error.message, true);
      } finally {
        if (!disposed) lock(false);
      }
    }
    host.addEventListener(
      "click",
      (event) => {
        const button = event.target.closest("button");
        if (!button || button.disabled || busy || disposed || !route) return;
        if (button.hasAttribute("data-wallet-cart")) onCart();
        else if (button.hasAttribute("data-wallet-home")) void open();
        else if (button.dataset.walletTopup)
          void open("topup", button.dataset.walletTopup);
        else if (button.dataset.walletTab) selectTab(button.dataset.walletTab);
        else if (button.dataset.walletAmount) {
          amount = button.dataset.walletAmount;
          const input = panel.querySelector("#wallet-amount");
          input.value = amount;
          input.dispatchEvent(new Event("input", { bubbles: true }));
          input.focus();
        } else if (button.hasAttribute("data-wallet-refresh")) {
          if (route === "topup") void loadDetail();
          else void loadWallet();
        } else if (button.hasAttribute("data-wallet-more"))
          void loadHistory(true);
        else if (button.hasAttribute("data-wallet-history-retry"))
          void loadHistory();
        else if (button.hasAttribute("data-wallet-recover")) void submit(true);
        else if (button.hasAttribute("data-wallet-cancel")) confirmCancel();
        else if (button.hasAttribute("data-wallet-dialog-close")) closeDialog();
        else if (button.hasAttribute("data-wallet-confirm-cancel"))
          void cancel();
        else if (button.dataset.walletCopy)
          void request("copy-text", { text: button.dataset.walletCopy })
            .then(() => {
              if (!disposed) toast("Đã sao chép.");
            })
            .catch((error) => {
              if (!disposed) toast(error.message, true);
            });
      },
      listen,
    );
    host.addEventListener(
      "submit",
      (event) => {
        if (!event.target.matches("[data-wallet-form]")) return;
        event.preventDefault();
        event.stopPropagation();
        void submit();
      },
      listen,
    );
    host.addEventListener(
      "input",
      (event) => {
        if (event.target.id !== "wallet-amount") return;
        amount = event.target.value;
        event.target.removeAttribute("aria-invalid");
        panel.querySelector("#wallet-amount-error").hidden = true;
        panel
          .querySelectorAll("[data-wallet-amount]")
          .forEach((el) =>
            el.setAttribute(
              "aria-pressed",
              String(Number(amount) === Number(el.dataset.walletAmount)),
            ),
          );
      },
      listen,
    );
    host.addEventListener(
      "keydown",
      (event) => {
        if (
          !event.target.matches("[data-wallet-tab]") ||
          !["ArrowLeft", "ArrowRight", "Home", "End"].includes(event.key) ||
          busy
        )
          return;
        event.preventDefault();
        selectTab(
          event.key === "Home"
            ? "topups"
            : event.key === "End"
              ? "transactions"
              : tab === "topups"
                ? "transactions"
                : "topups",
        );
        panel.querySelector(`[data-wallet-tab="${tab}"]`).focus();
      },
      listen,
    );
    return {
      open,
      close,
      get busy() {
        return busy;
      },
      dispose() {
        disposed = true;
        close();
        events.abort();
      },
    };
  }
  window.LauncherWallet = { create };
})();
