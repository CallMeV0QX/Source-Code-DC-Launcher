(() => {
  "use strict";
  const gameName = window.DCGameNames.display;
  function create({ host, request, user, helpers, onOpen, onClose, onCount, onBalance, onWalletRefresh }) {
    const { escape: esc, image, imageUrl, money, icons } = helpers;
    const panel = host.querySelector("[data-commerce]");
    const events = new AbortController();
    const listen = { signal: events.signal };
    const trash =
      '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M3 6h18M9 6V3h6v3M5 6l1 15h12l1-15M10 10v7m4-7v7"/></svg>';
    const check =
      '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="m5 12 4 4L19 6"/></svg>';
    const closeIcon =
      '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="m6 6 12 12M6 18 18 6"/></svg>';
    const copyIcon =
      '<svg viewBox="0 0 24 24" aria-hidden="true"><rect x="8" y="8" width="12" height="13"/><path d="M16 8V3H3v13h5"/></svg>';
    let disposed = false,
      busy = false,
      route = null,
      sequence = 0,
      data = null,
      voucher = "",
      method = "sepay";
    let orderId = null,
      paymentOrderId = null,
      order = null,
      timer = null,
      tick = null,
      toastTimer = null,
      countGeneration = 0;
    let orderRows = [],
      nextOffset = null,
      dialog = null,
      pending = null;
    const paymentGuidesShown = new Set();
    const storageKey = `dc-launcher-checkout:${user.id}`;
    try {
      pending = JSON.parse(localStorage.getItem(storageKey));
    } catch {
      /* Storage may be disabled. */
    }
    if (!pending?.payload?.idempotencyKey || !pending.payload.quoteSignature)
      pending = null;
    const labels = {
      pending_payment: "Chờ thanh toán",
      paid: "Đã thanh toán",
      cancelled: "Đã hủy",
      refunded: "Đã hoàn tiền",
      failed: "Không thành công",
      processing: "Đang xử lý",
    };
    const status = (message, error = false) => {
      const target = panel.querySelector("[data-commerce-status]");
      if (target) {
        target.textContent = message;
        target.hidden = !message;
        target.classList.toggle("is-error", error);
      }
    };
    function savePending(value) {
      pending = value;
      try {
        if (value) localStorage.setItem(storageKey, JSON.stringify(value));
        else localStorage.removeItem(storageKey);
      } catch {
        /* In-memory retry still uses the same key. */
      }
    }
    function setCount(cart) {
      countGeneration++;
      onCount(cart.itemCount);
    }
    async function refreshCount() {
      const id = ++countGeneration;
      try {
        const result = await request("cart-count");
        if (!disposed && id === countGeneration) onCount(result.itemCount);
      } catch {
        /* Cart page provides the retry UI. */
      }
    }
    function toast(message, error = false, cartAction = false) {
      if (disposed) return;
      clearTimeout(toastTimer);
      const target = host.querySelector("[data-commerce-toast]");
      target.innerHTML = `<span>${error ? icons.bell : check}</span><p>${esc(message)}</p>${cartAction ? '<button class="store-text-button" type="button" data-toast-cart>Xem giỏ</button>' : ""}<button class="store-icon-button" type="button" data-toast-close aria-label="Đóng thông báo">${closeIcon}</button>`;
      target.classList.toggle("is-error", error);
      target.hidden = false;
      toastTimer = setTimeout(
        () => {
          target.hidden = true;
        },
        error ? 12000 : 6500,
      );
    }
    function closeDialog() {
      dialog?.close();
      dialog?.remove();
      dialog = null;
    }
    function showDialog(title, content, className = "") {
      closeDialog();
      dialog = document.createElement("dialog");
      dialog.className = `commerce-dialog ${className}`.trim();
      dialog.setAttribute("aria-labelledby", "commerce-dialog-title");
      dialog.innerHTML = `<div class="commerce-dialog-heading"><h2 id="commerce-dialog-title">${esc(title)}</h2><button class="store-icon-button" type="button" data-modal-close aria-label="Đóng">${closeIcon}</button></div>${content}`;
      host.append(dialog);
      dialog.showModal();
      dialog.addEventListener("cancel", (event) => {
        if (busy) event.preventDefault();
      });
      return dialog;
    }
    function showPaymentGuide() {
      if (paymentGuidesShown.has(order.orderId) || order.total <= 0) return;
      const steps = [
        ["Mở Thư viện", "Xem các game bạn đã mua."],
        ["Chọn game", "Mở trang chi tiết game cần kích hoạt."],
        ["Nhấn ACTIVE", "Làm theo hướng dẫn để hoàn tất."],
      ];
      const modal = showDialog(
        "Thanh toán thành công!",
        `<p class="payment-success-description" id="payment-success-description">Vào Thư viện để quản lý và kích hoạt game.</p>
        <ol class="payment-success-steps">${steps.map(([title, description], index) => `<li><span class="payment-success-number" aria-hidden="true">${index + 1}</span><div><h3>${esc(title)}</h3><p>${esc(description)}</p></div></li>`).join("")}</ol>
        <p class="payment-success-note">Hãy thoát game trước khi ACTIVE.</p>
        <button class="store-button store-primary payment-success-primary" type="button" data-library-web data-payment-library>${icons.order}<span>Vào Thư viện</span>${icons.arrow}</button>
        <button class="store-text-button payment-success-later" type="button" data-modal-close>Để sau</button>`,
        "payment-success-dialog",
      );
      modal.setAttribute("aria-describedby", "payment-success-description");
      modal.querySelector(".commerce-dialog-heading").insertAdjacentHTML(
        "afterbegin",
        `<div class="payment-success-icon" aria-hidden="true">${check}</div>`,
      );
      paymentGuidesShown.add(order.orderId);
      modal.addEventListener("keydown", (event) => {
        if (event.key !== "Tab") return;
        const buttons = [...modal.querySelectorAll("button:not(:disabled)")];
        const first = buttons[0], last = buttons.at(-1);
        if (event.shiftKey && document.activeElement === first) {
          event.preventDefault();
          last.focus();
        } else if (!event.shiftKey && document.activeElement === last) {
          event.preventDefault();
          first.focus();
        }
      });
      modal.querySelector("[data-payment-library]").focus();
    }
    function stopPolling() {
      clearTimeout(timer);
      clearInterval(tick);
    }
    function heading(title, description = "") {
      const titleMarkup = route === "orders" || route === "cart"
        ? `<h2 class="sr-only" tabindex="-1">${esc(title)}</h2>`
        : `<div class="commerce-heading"><div><p class="eyebrow">DC Gaming / Cửa hàng</p><h2 tabindex="-1">${esc(title)}</h2>${description ? `<p>${esc(description)}</p>` : ""}</div><button class="store-text-button" type="button" data-commerce-back>${icons.arrow}Tiếp tục mua sắm</button></div>`;
      panel.innerHTML = `${titleMarkup}<div class="commerce-notice" data-commerce-status role="status" hidden></div><div data-commerce-body></div>`;
    }
    const body = () => panel.querySelector("[data-commerce-body]");
    function loading(title) {
      heading(title);
      body().innerHTML =
        '<div class="commerce-loading" role="status"><span class="spinner"></span>Đang tải…</div>';
    }
    function errorPage(title, message) {
      heading(title);
      body().innerHTML = `<div class="store-empty" role="alert">${icons.refresh}<h3>Chưa tải được dữ liệu</h3><p>${esc(message)}</p><button class="store-button" type="button" data-commerce-retry>Thử lại ${icons.refresh}</button></div>`;
    }
    function focusHeading() {
      if (dialog?.open) return;
      panel.querySelector("h2")?.focus({ preventScroll: true });
    }
    function lock(value) {
      busy = value;
      panel.setAttribute("aria-busy", String(value));
      panel.querySelectorAll("button,input").forEach((el) => {
        if (value) {
          el.dataset.beforeDisabled = String(el.disabled);
          el.disabled = true;
        } else if (el.dataset.beforeDisabled !== undefined) {
          el.disabled = el.dataset.beforeDisabled === "true";
          delete el.dataset.beforeDisabled;
        }
      });
      if (dialog)
        dialog.querySelectorAll("button,select").forEach((el) => {
          el.disabled = value;
        });
    }
    async function open(view = "cart", id = null, { fromCheckout = false } = {}) {
      if (busy || wallet.busy || disposed) return;
      stopPolling();
      closeDialog();
      wallet.close();
      library.close();
      route = view;
      orderId = id;
      paymentOrderId = fromCheckout ? id : null;
      sequence++;
      onOpen(view);
      panel.hidden = false;
      if (view === "library" || view === "library-detail")
        await library.open(view, id);
      else if (view === "wallet" || view === "topup")
        await wallet.open(view, id);
      else if (view === "cart") await loadCart();
      else if (view === "orders") await loadOrders();
      else await loadOrder();
      if (!disposed) focusHeading();
    }
    function close() {
      sequence++;
      stopPolling();
      closeDialog();
      wallet.close();
      library.close();
      route = null;
      paymentOrderId = null;
      panel.hidden = true;
    }
    function cartMarkup() {
      const cart = data.cart;
      if (
        method === "wallet" &&
        (!data.walletAvailable || data.walletBalance < cart.total)
      )
        method = "sepay";
      heading(
        "Giỏ hàng",
        cart.items.length
          ? `${cart.items.length} game · Giỏ hàng được đồng bộ với tài khoản của bạn.`
          : "",
      );
      if (!cart.items.length) {
        body().innerHTML = `<div class="store-empty cart-empty">${icons.cart}<h3>Giỏ hàng của bạn đang trống</h3><p>Khám phá cửa hàng và chọn tựa game tiếp theo.</p><button class="store-button store-primary" type="button" data-commerce-back>Khám phá game ${icons.arrow}</button></div>`;
        if (pending) recoveryBanner();
        return;
      }
      const hasIssues =
        Object.keys(data.itemIssues || {}).length > 0 || cart.items.length > 50;
      const walletEnough =
        data.walletAvailable && data.walletBalance >= cart.total;
      const canPay =
        !hasIssues &&
        (cart.total === 0 ||
          (method === "wallet" ? walletEnough : data.bankAvailable));
      const lines = cart.items
        .map((item) => {
          const issue = data.itemIssues?.[item.cartItemId];
          return `<article class="cart-row ${issue ? "cart-row-unavailable" : ""}" data-cart-row="${esc(item.cartItemId)}"><div class="cart-cover"><span class="art-fallback">${icons.game}</span>${image(item.photoUrl)}</div><div class="cart-item-info"><h3>${esc(gameName(item.gameName))}</h3><button class="cart-version" type="button" data-cart-version="${esc(item.cartItemId)}" aria-label="Đổi phiên bản ${esc(gameName(item.gameName))}">${esc(item.versionName)}${icons.chevron}</button><p>${issue ? esc(issue) : "PC · 1 quyền sử dụng"}</p></div><div class="cart-item-price">${item.discountPercent > 0 ? `<del>${money(item.originalLineTotal)}</del>` : ""}<strong>${item.lineTotal === 0 ? "Miễn phí" : money(item.lineTotal)}</strong></div><button class="store-icon-button cart-remove" type="button" data-cart-remove="${esc(item.cartItemId)}" aria-label="Xóa ${esc(gameName(item.gameName))} khỏi giỏ">${trash}</button></article>`;
        })
        .join("");
      body().innerHTML = `<div class="cart-layout"><section class="cart-items" aria-label="Game trong giỏ"><div class="cart-list-heading"><strong>Sản phẩm <span>${cart.items.length}</span></strong><button class="store-text-button" type="button" data-cart-clear>${trash}Xóa tất cả</button></div>${lines}<p class="cart-footnote">Mỗi game giữ một phiên bản trong giỏ. Chọn phiên bản khác ở trang sản phẩm để thay thế.</p></section><aside class="cart-summary" aria-labelledby="cart-summary-title"><h3 id="cart-summary-title">Thông tin thanh toán</h3><form class="cart-coupon" data-coupon-form><label for="launcher-voucher">Mã giảm giá</label><div><input id="launcher-voucher" maxlength="50" autocomplete="off" placeholder="Nhập mã ưu đãi" value="${esc(voucher)}"><button class="store-button" type="submit">Áp dụng</button></div></form>${data.voucherCode ? `<div class="applied-coupon">${check}<span>${esc(data.voucherCode)}</span><button class="store-text-button" type="button" data-coupon-remove aria-label="Bỏ mã giảm giá">${closeIcon}</button></div>` : ""}<dl class="cart-totals"><div><dt>Tạm tính</dt><dd>${money(cart.originalTotal)}</dd></div>${data.gameDiscount > 0 ? `<div class="saving"><dt>Giảm giá sản phẩm</dt><dd>−${money(data.gameDiscount)}</dd></div>` : ""}${data.voucherDiscount > 0 ? `<div class="saving"><dt>Mã giảm giá</dt><dd>−${money(data.voucherDiscount)}</dd></div>` : ""}<div class="cart-total"><dt>Tổng thanh toán</dt><dd>${money(cart.total)}</dd></div></dl>${cart.total > 0 ? `<fieldset class="payment-methods"><legend>Phương thức thanh toán</legend><label class="payment-choice"><input type="radio" name="launcher-payment" value="sepay" ${method === "sepay" ? "checked" : ""}><span><strong>Chuyển khoản QR</strong><small>${data.bankAvailable ? "Quét mã bằng ứng dụng ngân hàng" : "Tạm dừng nhận đơn chuyển khoản mới"}</small></span></label><label class="payment-choice"><input type="radio" name="launcher-payment" value="wallet" ${method === "wallet" ? "checked" : ""} ${!walletEnough ? "disabled" : ""}><span><strong>Ví DC <b>${money(data.walletBalance)}</b></strong><small>${!data.walletAvailable ? "Ví hiện chưa khả dụng" : !walletEnough ? "Số dư chưa đủ để thanh toán đơn này" : "Thanh toán ngay bằng số dư hiện có"}</small></span></label>${data.walletAvailable && !walletEnough ? '<button class="store-text-button" type="button" data-wallet-web>Nạp ví DC</button>' : ""}</fieldset>` : ""}${hasIssues ? '<p class="cart-blocker">Xóa sản phẩm không khả dụng để tiếp tục. Mỗi đơn hỗ trợ tối đa 50 game.</p>' : ""}<button class="store-button store-primary cart-checkout" type="button" data-checkout ${!canPay ? "disabled" : ""}>${cart.total === 0 ? "Nhận miễn phí" : method === "wallet" ? "Thanh toán bằng ví DC" : "Tiếp tục thanh toán"}${icons.arrow}</button><p class="cart-payment-hint">${cart.total === 0 ? "Thêm vào thư viện DC Gaming sau khi xác nhận." : method === "wallet" ? "Bạn sẽ xác nhận tổng tiền trước khi trừ số dư." : "Mã QR và thông tin chuyển khoản ở bước tiếp theo."}</p><button class="store-text-button cart-refresh" type="button" data-commerce-retry>${icons.refresh}Cập nhật giỏ hàng</button></aside></div>`;
      if (pending) recoveryBanner();
    }
    function recoveryBanner() {
      const notice = document.createElement("div");
      notice.className = "commerce-notice";
      notice.innerHTML =
        '<span>Có yêu cầu thanh toán cần kiểm tra kết quả.</span><button class="store-text-button" type="button" data-checkout-recover>Kiểm tra đơn hàng</button>';
      body().prepend(notice);
    }
    async function loadCart(message = "") {
      const id = ++sequence;
      loading("Giỏ hàng");
      try {
        let result;
        try {
          result = await request("cart", { voucher });
        } catch (error) {
          if (!voucher || error.code !== "commerce_error") throw error;
          voucher = "";
          message = `${error.message} Mã đã được bỏ; hãy kiểm tra tổng tiền mới.`;
          result = await request("cart", { voucher });
        }
        if (disposed || id !== sequence) return;
        data = result;
        if (Number.isFinite(data.walletBalance)) onBalance?.(data.walletBalance);
        voucher = data.voucherCode || "";
        setCount(data.cart);
        if (
          method === "wallet" &&
          (!data.walletAvailable || data.walletBalance < data.cart.total)
        )
          method = "sepay";
        cartMarkup();
        if (message) status(message, true);
      } catch (error) {
        if (!disposed && id === sequence) errorPage("Giỏ hàng", error.message);
      }
    }
    async function add(versionId, buyNow = false) {
      if (busy || disposed) return false;
      lock(true);
      try {
        const result = await request("cart-add", { versionId });
        if (disposed) return false;
        setCount(result.cart);
        closeDialog();
        toast(result.message, false, !buyNow);
        lock(false);
        if (buyNow) await open("cart");
        else if (route === "cart") await loadCart();
        return true;
      } catch (error) {
        toast(error.message, true);
        return false;
      } finally {
        if (!disposed) lock(false);
      }
    }
    async function choose(slug, selectedVersion = null) {
      if (busy || disposed) return;
      const modal = showDialog(
        "Chọn phiên bản",
        '<p class="commerce-loading"><span class="spinner"></span>Đang tải phiên bản…</p>',
      );
      try {
        const game = await request("store-detail", { slug });
        if (disposed || dialog !== modal || !modal.open) return;
        const ownership = await request("library-ownership", {
          gameId: game.gameId,
        });
        if (disposed || dialog !== modal || !modal.open) return;
        const versions = game.versions || [];
        const owned = new Set(ownership.ownedVersionIds);
        const pendingVersions = new Set(ownership.pendingVersionIds);
        const available = versions.filter(
          (v) => !owned.has(v.versionId) && !pendingVersions.has(v.versionId),
        );
        if (versions.length === 1 && available.length && !selectedVersion) {
          await add(versions[0].versionId);
          return;
        }
        modal.querySelector(".commerce-loading").outerHTML = versions.length
          ? `<p class="commerce-dialog-copy">${esc(gameName(game.name))}</p><label class="sr-only" for="cart-variant">Phiên bản</label><select id="cart-variant">${versions.map((v) => `<option value="${esc(v.versionId)}" ${owned.has(v.versionId) || pendingVersions.has(v.versionId) ? "disabled" : ""} ${v.versionId === (available.some((x) => x.versionId === selectedVersion) ? selectedVersion : available[0]?.versionId) ? "selected" : ""}>${esc(v.name)} · ${owned.has(v.versionId) ? "Đã sở hữu" : pendingVersions.has(v.versionId) ? "Đã mua · Đang giao" : money(v.currentPrice)}</option>`).join("")}</select><div class="commerce-dialog-actions"><button class="store-button" type="button" data-modal-close>Để sau</button><button class="store-button store-primary" type="button" data-modal-add ${available.length ? "" : "disabled"}>${icons.cart}${selectedVersion ? "Lưu phiên bản" : "Thêm vào giỏ"}</button>${!available.length ? '<button class="store-text-button" type="button" data-library-web>Vào thư viện</button>' : ""}</div>`
          : "<p>Sản phẩm chưa có phiên bản mở bán.</p>";
      } catch (error) {
        if (dialog === modal) {
          closeDialog();
          toast(error.message, true);
        }
      }
    }
    async function mutate(command, payload = {}) {
      if (busy) return;
      lock(true);
      try {
        const result = await request(command, payload);
        if (disposed) return;
        setCount(result.cart);
        closeDialog();
        toast(result.message);
        await loadCart();
      } catch (error) {
        if (!disposed) {
          closeDialog();
          status(error.message, true);
        }
      } finally {
        if (!disposed) lock(false);
      }
    }
    async function applyCoupon(code) {
      if (busy) return;
      lock(true);
      try {
        const result = await request("cart", { voucher: code });
        if (disposed) return;
        data = result;
        voucher = data.voucherCode || "";
        setCount(data.cart);
        cartMarkup();
        toast(voucher ? `Đã áp dụng mã ${voucher}.` : "Đã bỏ mã giảm giá.");
      } catch (error) {
        if (!disposed) status(error.message, true);
      } finally {
        if (!disposed) lock(false);
      }
    }
    function startCheckout() {
      if (busy || !data) return;
      const draft = panel
        .querySelector("#launcher-voucher")
        ?.value.trim()
        .toUpperCase();
      if (draft !== voucher) {
        status("Hãy áp dụng hoặc bỏ mã đang nhập trước khi thanh toán.", true);
        panel.querySelector("#launcher-voucher")?.focus();
        return;
      }
      if (pending) {
        void checkout(true);
        return;
      }
      if (method === "wallet" && data.cart.total > 0) {
        showDialog(
          "Xác nhận thanh toán",
          `<p class="commerce-dialog-copy">Thanh toán ${data.cart.items.length} game bằng ví DC.</p><div class="wallet-confirm-total">${money(data.cart.total)}</div><p>Số dư còn lại: <strong>${money(data.walletBalance - data.cart.total)}</strong></p><div class="commerce-dialog-actions"><button class="store-button" type="button" data-modal-close>Quay lại</button><button class="store-button store-primary" type="button" data-confirm-checkout>Xác nhận thanh toán ${icons.arrow}</button></div>`,
        );
      } else void checkout();
    }
    async function checkout(recoverOnly = false) {
      if (busy) return;
      lock(true);
      status("Đang kiểm tra yêu cầu thanh toán…");
      try {
        if (pending) {
          const previous = await request("checkout-find", {
            key: pending.payload.idempotencyKey,
          });
          if (disposed) return;
          if (previous.orderId) {
            savePending(null);
            lock(false);
            closeDialog();
            await open("order", previous.orderId, { fromCheckout: true });
            void refreshCount();
            return;
          }
          if (recoverOnly) {
            closeDialog();
            showDialog(
              "Kiểm tra yêu cầu thanh toán",
              `<p>Chưa tìm thấy đơn từ yêu cầu trước. Bạn có thể gửi lại đúng yêu cầu với tổng tiền <strong>${money(pending.payload.expectedTotal)}</strong>. Hệ thống sẽ kiểm tra để tránh tạo trùng.</p><div class="commerce-dialog-actions"><button class="store-button" type="button" data-modal-close>Để sau</button><button class="store-button store-primary" type="button" data-confirm-checkout>Kiểm tra & gửi lại ${icons.arrow}</button></div>`,
            );
            return;
          }
        } else {
          if (!data) return;
          savePending({
            payload: {
              idempotencyKey: crypto.randomUUID(),
              paymentMethod: method,
              expectedTotal: data.cart.total,
              voucherCode: voucher || null,
              quoteSignature: data.quoteSignature,
              environment: data.environment,
            },
          });
        }
        const result = await request("checkout", pending.payload);
        if (!result.orderId)
          throw new Error(
            "Chưa xác định được đơn hàng. Hãy kiểm tra lại yêu cầu.",
          );
        savePending(null);
        if (disposed) return;
        lock(false);
        closeDialog();
        await open("order", result.orderId, { fromCheckout: true });
        void refreshCount();
      } catch (error) {
        if (disposed) return;
        closeDialog();
        if (
          ["commerce_error", "request_failed", "invalid_input"].includes(
            error.code,
          )
        ) {
          savePending(null);
          await loadCart(error.message);
        } else {
          status(
            `${error.message} Dùng “Kiểm tra đơn hàng” để xác định kết quả trước khi thanh toán lại.`,
            true,
          );
          if (pending)
            toast(
              "Chưa xác định được kết quả. Yêu cầu đã được giữ để kiểm tra lại.",
              true,
            );
          if (route === "cart") {
            cartMarkup();
            status(error.message, true);
            const button = panel.querySelector("[data-checkout]");
            if (button) button.textContent = "Kiểm tra đơn hàng";
          }
        }
      } finally {
        if (!disposed) lock(false);
      }
    }
    async function loadOrders(append = false) {
      const id = ++sequence;
      if (!append) {
        orderRows = [];
        loading("Đơn hàng");
      } else
        panel.querySelector("[data-orders-more]")?.setAttribute("disabled", "");
      try {
        const result = await request("orders", {
          offset: append ? nextOffset : 0,
        });
        if (disposed || id !== sequence) return;
        orderRows = append
          ? [
              ...new Map(
                [...orderRows, ...result.orders].map((row) => [
                  row.orderId,
                  row,
                ]),
              ).values(),
            ]
          : result.orders;
        nextOffset = result.nextOffset;
        heading("Đơn hàng");
        body().innerHTML = orderRows.length
          ? `<div class="order-list">${orderRows.map((row) => `<button class="order-list-row" type="button" data-open-order="${esc(row.orderId)}"><span class="order-list-icon">${icons.order}</span><span><strong>${esc(row.orderCode)}</strong><small>${new Date(row.createdAt + (/[Z+]\d*/.test(row.createdAt) ? "" : "Z")).toLocaleString("vi-VN")}</small></span><span class="order-status ${row.status === "paid" ? "is-paid" : ""}">${esc(labels[row.status] || row.status)}</span><strong>${money(row.total)}</strong>${icons.chevron}</button>`).join("")}</div>${nextOffset !== null ? '<button class="store-button orders-more" type="button" data-orders-more>Tải thêm đơn hàng</button>' : ""}`
          : `<div class="store-empty">${icons.order}<h3>Chưa có đơn hàng</h3><p>Đơn mua game của bạn sẽ hiển thị tại đây.</p><button class="store-button" type="button" data-commerce-back>Khám phá game ${icons.arrow}</button></div>`;
      } catch (error) {
        if (!disposed && id === sequence) {
          if (!append) errorPage("Đơn hàng", error.message);
          else {
            status(error.message, true);
            panel
              .querySelector("[data-orders-more]")
              ?.removeAttribute("disabled");
          }
        }
      }
    }
    function remaining() {
      return Math.max(
        0,
        Math.ceil((Date.parse(order?.expiresAt) - Date.now()) / 1000),
      );
    }
    function orderMarkup() {
      const paid = order.status === "paid";
      const payable = order.status === "pending_payment" && remaining() > 0;
      heading(order.orderCode, "Chi tiết đơn hàng");
      const field = (label, value, canCopy = false) =>
        `<div><dt>${label}</dt><dd><span>${esc(value)}</span>${canCopy ? `<button class="store-icon-button" type="button" data-copy="${esc(value)}" aria-label="Sao chép ${label.toLowerCase()}">${copyIcon}</button>` : ""}</dd></div>`;
      body().innerHTML = `<div class="order-overview ${paid ? "is-paid" : ""}">${paid ? check : icons.order}<div><h3>${esc(order.statusLabel)}</h3><p>${esc(paid ? order.fulfillmentLabel : payable ? "Quét mã QR hoặc chuyển khoản đúng thông tin bên dưới." : order.message || "Bạn có thể quay lại giỏ hàng để tạo đơn mới.")}</p></div><strong>${money(order.total)}</strong></div>${order.message ? `<p class="order-message">${esc(order.message)}</p>` : ""}${payable && order.accountNumber ? `<section class="order-payment"><div class="order-qr"><div class="qr-image">${image(order.qrUrl, "", false)}<span>Không tải được QR? Dùng thông tin chuyển khoản bên cạnh.</span></div><p>Thời gian còn lại <strong data-order-countdown></strong></p></div><div><h3>Thông tin chuyển khoản</h3><dl class="bank-details">${field("Ngân hàng", order.bankCode)}${field("Chủ tài khoản", order.accountName)}${field("Số tài khoản", order.accountNumber, true)}${field("Số tiền", money(order.total))}${field("Nội dung", order.transferContent, true)}</dl><p class="cart-footnote">Giữ nguyên nội dung và số tiền. Trạng thái sẽ tự cập nhật sau khi ngân hàng xác nhận.</p></div></section>` : ""}<section class="order-products"><h3>Sản phẩm trong đơn</h3>${order.items.map((item) => `<div class="order-product"><div><strong>${esc(gameName(item.gameName))}</strong><span>${esc(item.versionName)} · ${item.quantity} quyền sử dụng</span></div><strong>${money(item.lineTotal)}</strong></div>${item.instructions ? `<div class="delivery-instructions">${esc(item.instructions)}</div>` : ""}`).join("")}${order.discount > 0 ? `<p class="order-discount">Tổng giảm giá: <strong>−${money(order.discount)}</strong>${order.voucherCode ? ` · Mã ${esc(order.voucherCode)}` : ""}</p>` : ""}${order.deliveryNote ? `<p class="delivery-instructions">${esc(order.deliveryNote)}</p>` : ""}</section><div class="order-actions"><button class="store-button" type="button" data-order-list>${icons.order}Tất cả đơn hàng</button><button class="store-button" type="button" data-commerce-retry>${icons.refresh}Cập nhật trạng thái</button>${order.status === "pending_payment" ? '<button class="store-text-button order-cancel" type="button" data-order-cancel>Hủy đơn hàng</button>' : ""}${paid ? `<button class="store-text-button" type="button" data-library-web>Vào thư viện ${icons.arrow}</button>` : ""}</div>`;
      if (paid && order.fulfillmentStatus === "manual_pending") {
        body().querySelector(".order-overview p")?.remove();
        body().querySelector(".order-message")?.remove();
      }
      countdown();
    }
    function countdown() {
      const target = panel.querySelector("[data-order-countdown]");
      if (!target) return;
      const left = remaining();
      target.textContent = `${Math.floor(left / 60)
        .toString()
        .padStart(2, "0")}:${(left % 60).toString().padStart(2, "0")}`;
      if (left === 0) {
        panel.querySelector(".order-payment")?.setAttribute("hidden", "");
        status(
          "Đơn đã hết hạn. Không chuyển thêm tiền; nếu đã chuyển, hãy liên hệ hỗ trợ kèm mã đơn.",
          true,
        );
      }
    }
    async function loadOrder(quiet = false) {
      const id = ++sequence;
      const target = orderId;
      clearTimeout(timer);
      if (!quiet) loading("Đơn hàng");
      try {
        const result = await request("order", { orderId: target });
        if (disposed || id !== sequence || route !== "order") return;
        const changed = JSON.stringify(order) !== JSON.stringify(result);
        const wasPending = order?.orderId === target && order.status === "pending_payment";
        order = result;
        if (!quiet || changed) orderMarkup();
        else status("");
        if (order.status === "paid") {
          if (wasPending || paymentOrderId === target) onWalletRefresh?.();
          if (wasPending) void refreshCount();
          if (wasPending || paymentOrderId === target) showPaymentGuide();
          paymentOrderId = null;
        }
        clearInterval(tick);
        tick = setInterval(countdown, 1000);
      } catch (error) {
        if (!disposed && id === sequence) {
          if (!quiet) errorPage("Đơn hàng", error.message);
          else status(`Chưa cập nhật được trạng thái: ${error.message}`, true);
        }
      } finally {
        if (
          !disposed &&
          id === sequence &&
          route === "order" &&
          (!order ||
            order.status === "pending_payment" ||
            (order.status === "paid" &&
              !["completed", "failed", "cancelled"].includes(
                order.fulfillmentStatus,
              )))
        )
          timer = setTimeout(() => {
            if (!busy && !document.hidden) void loadOrder(true);
            else scheduleOrder();
          }, 7000);
      }
    }
    function scheduleOrder() {
      clearTimeout(timer);
      timer = setTimeout(() => {
        if (!disposed && route === "order" && !busy && !document.hidden)
          void loadOrder(true);
        else if (!disposed && route === "order") scheduleOrder();
      }, 7000);
    }
    async function cancelOrder() {
      if (busy) return;
      lock(true);
      clearTimeout(timer);
      try {
        await request("order-cancel", { orderId });
        if (!disposed) {
          closeDialog();
          toast("Đã hủy đơn hàng.");
          await loadOrder();
        }
      } catch (error) {
        if (!disposed) {
          closeDialog();
          status(error.message, true);
          scheduleOrder();
        }
      } finally {
        if (!disposed) lock(false);
      }
    }
    const library = window.LauncherLibrary.create({
      host,
      panel,
      request,
      helpers,
      toast,
      onRoute: (view) => {
        route = view;
        onOpen(view);
      },
      onOrder: (id) => void open("order", id),
    });
    const wallet = window.LauncherWallet.create({
      host,
      panel,
      request,
      user,
      helpers,
      toast,
      onBalance,
      onRoute: (view) => {
        route = view;
        onOpen(view);
      },
      onCart: () => {
        method = "wallet";
        void open("cart");
      },
    });
    host.addEventListener(
      "click",
      (event) => {
        const button = event.target.closest("button");
        if (!button || button.disabled || disposed) return;
        if (button.hasAttribute("data-toast-close"))
          host.querySelector("[data-commerce-toast]").hidden = true;
        else if (busy || wallet.busy) return;
        else if (button.hasAttribute("data-modal-close")) closeDialog();
        else if (button.hasAttribute("data-toast-cart")) {
          host.querySelector("[data-commerce-toast]").hidden = true;
          void open("cart");
        } else if (button.hasAttribute("data-commerce-back")) {
          close();
          onClose();
        } else if (button.hasAttribute("data-modal-add"))
          void add(dialog.querySelector("select").value);
        else if (button.dataset.cartVersion) {
          const item = data?.cart.items.find(
            (item) => item.cartItemId === button.dataset.cartVersion,
          );
          if (item) void choose(item.slug, item.versionId);
        } else if (button.dataset.cartRemove)
          void mutate("cart-remove", { itemId: button.dataset.cartRemove });
        else if (button.hasAttribute("data-cart-clear"))
          showDialog(
            "Xóa toàn bộ giỏ hàng?",
            '<p>Các game trong giỏ sẽ được xóa khỏi giỏ hàng trên cả web và launcher.</p><div class="commerce-dialog-actions"><button class="store-button" type="button" data-modal-close>Giữ lại</button><button class="store-button store-primary" type="button" data-confirm-clear>Xóa giỏ hàng</button></div>',
          );
        else if (button.hasAttribute("data-confirm-clear"))
          void mutate("cart-clear");
        else if (button.hasAttribute("data-coupon-remove"))
          void applyCoupon("");
        else if (button.hasAttribute("data-checkout")) startCheckout();
        else if (button.hasAttribute("data-checkout-recover"))
          void checkout(true);
        else if (button.hasAttribute("data-confirm-checkout")) void checkout();
        else if (button.dataset.openOrder)
          void open("order", button.dataset.openOrder);
        else if (button.hasAttribute("data-order-list")) void open("orders");
        else if (button.hasAttribute("data-orders-more")) void loadOrders(true);
        else if (button.hasAttribute("data-commerce-retry")) {
          if (route === "cart") void loadCart();
          else if (route === "orders") void loadOrders();
          else void loadOrder();
        } else if (button.hasAttribute("data-order-cancel"))
          showDialog(
            "Hủy đơn hàng?",
            '<p>Chỉ hủy khi bạn chưa chuyển khoản. Nếu đã chuyển, hãy chờ cập nhật trạng thái hoặc liên hệ hỗ trợ.</p><div class="commerce-dialog-actions"><button class="store-button" type="button" data-modal-close>Giữ đơn</button><button class="store-button store-primary" type="button" data-confirm-cancel>Hủy đơn hàng</button></div>',
          );
        else if (button.hasAttribute("data-confirm-cancel")) void cancelOrder();
        else if (button.dataset.copy)
          void request("copy-text", { text: button.dataset.copy })
            .then(() => toast("Đã sao chép."))
            .catch((error) => toast(error.message, true));
        else if (button.hasAttribute("data-wallet-web")) void open("wallet");
        else if (button.hasAttribute("data-library-web")) void open("library");
      },
      listen,
    );
    host.addEventListener(
      "submit",
      (event) => {
        if (!event.target.matches("[data-coupon-form]")) return;
        event.preventDefault();
        event.stopPropagation();
        void applyCoupon(
          panel.querySelector("#launcher-voucher").value.trim().toUpperCase(),
        );
      },
      listen,
    );
    host.addEventListener(
      "change",
      (event) => {
        if (event.target.name === "launcher-payment" && !busy) {
          const draft = panel.querySelector("#launcher-voucher").value;
          method = event.target.value;
          cartMarkup();
          panel.querySelector("#launcher-voucher").value = draft;
          panel.querySelector(`[value="${method}"]`)?.focus();
        }
      },
      listen,
    );
    return {
      open,
      close,
      add,
      toast,
      choose,
      refreshCount,
      get busy() {
        return busy || wallet.busy;
      },
      dispose() {
        disposed = true;
        close();
        wallet.dispose();
        library.dispose();
        events.abort();
        clearTimeout(toastTimer);
      },
    };
  }
  window.LauncherCommerce = { create };
})();
