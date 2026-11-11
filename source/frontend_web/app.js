(() => {
  "use strict";
  const screen = document.querySelector("#screen");
  const bridge = window.chrome?.webview;
  const pending = new Map();
  const cooldowns = new Map();
  const state = {
    view: "login",
    email: "",
    busy: false,
    user: null,
    restoreFailed: false,
  };
  const icons = {
    back: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="m12 5-7 7 7 7M5 12h14"/></svg>',
    arrow:
      '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M5 12h14m-7-7 7 7-7 7"/></svg>',
    external:
      '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M7 17 17 7M7 7h10v10"/></svg>',
    eye: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7S2 12 2 12Z"/><circle cx="12" cy="12" r="3"/></svg>',
  };
  const password = (id, label, autocomplete = "new-password") =>
    `<div class="field"><label for="${id}">${label}</label><div class="input-wrap"><input id="${id}" name="${id}" type="password" data-password required ${autocomplete === "new-password" ? 'minlength="8"' : ""} maxlength="100" autocomplete="${autocomplete}" placeholder="${autocomplete === "new-password" ? "Tối thiểu 8 ký tự" : "Nhập mật khẩu"}"><button class="eye" type="button" data-toggle="${id}" aria-label="Hiện ${label.toLowerCase()}" aria-pressed="false">${icons.eye}</button></div></div>`;
  const emailField =
    '<div class="field"><label for="email">Email</label><input id="email" name="email" type="email" required maxlength="255" autocomplete="email" spellcheck="false" placeholder="you@example.com"></div>';
  const codeField =
    '<div class="field"><label for="code">Mã xác minh</label><input class="otp-input" id="code" name="code" type="text" inputmode="numeric" autocomplete="one-time-code" pattern="[0-9]{6}" minlength="6" maxlength="6" required placeholder="000000" aria-describedby="otp-help"><p class="helper" id="otp-help">Mã gồm 6 số, có hiệu lực trong 10 phút.</p></div>';
  const notice = '<div class="notice" id="notice" role="alert" hidden></div>';
  const submit = (label) =>
    `<button class="primary" type="submit" data-submit><span>${label}</span>${icons.arrow}</button>`;
  const back =
    '<button type="button" class="back" data-view="login" aria-label="Quay lại đăng nhập" title="Quay lại đăng nhập">' +
    icons.back +
    "</button>";
  const heading = (title, showBack = false) =>
    `<header class="card-heading"><img class="brand-logo" src="images/dc-monogram-reference-v1.webp" width="52" height="44" alt="DC Gaming"><h1>${title}</h1>${showBack ? back : ""}</header>`;
  const resend =
    '<p class="resend">Chưa nhận được mã? <button type="button" class="link accent" data-resend>Gửi lại mã</button></p>';

  bridge?.addEventListener("message", (event) => {
    const message = event.data;
    if (message?.event === "launcher-info") {
      window.dcLauncherInfo = message.data;
      window.dispatchEvent(new CustomEvent("dc-launcher-info", { detail: message.data }));
      return;
    }
    if (message?.event === "runtime-prefetch") {
      window.dcRuntimePrefetch = message.data;
      window.dispatchEvent(new CustomEvent("dc-runtime-prefetch", { detail: message.data }));
      return;
    }
    if (message?.event === "steam-connection-state") {
      const snapshot = message.data;
      if (!Number.isSafeInteger(snapshot?.revision) || snapshot.revision < (window.dcSteamConnection?.revision ?? -1)) return;
      window.dcSteamConnection = snapshot;
      window.dispatchEvent(new CustomEvent("dc-steam-connection", { detail: snapshot }));
      return;
    }
    if (message?.event === "activation-progress") {
      window.dispatchEvent(
        new CustomEvent("dc-activation-progress", { detail: message.data }),
      );
      return;
    }
    const item = pending.get(message?.id);
    if (!item) return;
    clearTimeout(item.timer);
    pending.delete(message.id);
    if (message.ok) item.resolve(message.data);
    else {
      if (message.error?.code === "session_expired" && state.user) {
        state.user = null;
        render(
          "login",
          "Phiên đăng nhập đã hết hạn. Hãy đăng nhập lại để tiếp tục.",
          "error",
        );
      }
      item.reject(
        Object.assign(
          new Error(message.error?.message || "Yêu cầu chưa hoàn tất."),
          { code: message.error?.code },
        ),
      );
    }
  });
  function request(command, payload = {}) {
    return new Promise((resolve, reject) => {
      if (!bridge) {
        reject(new Error("Hãy mở giao diện bằng ứng dụng DC Gaming Launcher."));
        return;
      }
      const id = crypto.randomUUID();
      const timer = setTimeout(
        () => {
          pending.delete(id);
          reject(
            Object.assign(
              new Error(
                "Chưa nhận được phản hồi. Hãy kiểm tra kết nối trước khi thử lại.",
              ),
              { code: "timeout" },
            ),
          );
        },
        command === "activation-start" ? 12 * 60 * 1000 : 35000,
      );
      pending.set(id, { resolve, reject, timer });
      bridge.postMessage({ id, command, payload });
    });
  }
  function showNotice(message, kind = "error") {
    const element = document.querySelector("#notice");
    if (!element) {
      window.LauncherStore.notify?.(message, kind === "error");
      return;
    }
    element.className = "notice " + kind;
    element.textContent = message;
    element.hidden = !message;
    if (state.restoreFailed) {
      const retry = document.createElement("button");
      retry.type = "button";
      retry.className = "link retry";
      retry.dataset.restore = "";
      retry.textContent = "Thử khôi phục đăng nhập";
      element.append(retry);
    }
  }
  function render(view, message = "", kind = "info") {
    window.LauncherStore.unmount();
    state.view = view;
    document.body.dataset.layout = view === "home" ? "home" : "auth";
    screen.className = view === "home" ? "launcher-shell" : "card";
    document
      .querySelector("#main")
      .setAttribute(
        "aria-label",
        view === "home" ? "DC Gaming Launcher" : "Tài khoản DC Gaming",
      );
    if (view === "home") {
      screen.removeAttribute("aria-live");
      window.LauncherStore.mount(screen, {
        request, user: state.user,
        onPasswordChanged: async () => {
          const email = state.user?.email || state.email;
          try { await request("logout"); }
          finally {
            state.user = null;
            state.email = email;
            render("login", "Đổi mật khẩu thành công. Hãy đăng nhập lại.", "success");
          }
        },
      });
      return;
    }
    screen.setAttribute("aria-live", "polite");
    const layouts = {
      login: `${heading("Đăng nhập")}${notice}<form class="form" data-action="login">${emailField}${password("password", "Mật khẩu", "current-password")}<div class="form-row"><label class="check"><input name="rememberMe" type="checkbox" checked>Ghi nhớ đăng nhập</label><button class="link" type="button" data-view="forgot">Quên mật khẩu?</button></div>${submit("Đăng nhập")}</form><p class="switch">Chưa có tài khoản?<button class="link accent" type="button" data-view="register">Đăng ký</button></p>`,
      register: `${heading("Tạo tài khoản")}${notice}<form class="form" data-action="register">${emailField}${password("password", "Mật khẩu")}${password("confirmPassword", "Xác nhận mật khẩu")}<label class="check terms"><input name="acceptTerms" type="checkbox" required><span>Tôi đồng ý với điều khoản sử dụng của DC Gaming.</span></label>${submit("Tạo tài khoản")}</form><p class="switch">Đã có tài khoản?<button class="link accent" type="button" data-view="login">Đăng nhập</button></p>`,
      verify: `${heading("Xác minh email", true)}<p class="description">Nhập mã gửi tới <strong data-email></strong></p>${notice}<form class="form" data-action="verify-email">${codeField}${submit("Xác minh email")}</form>${resend}<p class="switch"><button class="link" type="button" data-view="register">Sử dụng email khác</button></p>`,
      forgot: `${heading("Quên mật khẩu?", true)}<p class="description">Nhập email để nhận mã đặt lại mật khẩu.</p>${notice}<form class="form" data-action="forgot-password">${emailField}${submit("Gửi mã xác minh")}</form>`,
      reset: `${heading("Đặt mật khẩu mới", true)}<p class="description"><strong data-email></strong></p>${notice}<form class="form" data-action="reset-password">${codeField}${password("password", "Mật khẩu mới")}${password("confirmPassword", "Xác nhận mật khẩu mới")}${submit("Lưu mật khẩu mới")}</form>${resend}`,
    };
    screen.innerHTML = layouts[view] || layouts.login;
    const input = screen.querySelector("#email");
    if (input) input.value = state.email;
    screen.querySelectorAll("[data-email]").forEach((e) => {
      e.textContent = state.email;
    });
    showNotice(message, kind);
    updateCooldown();
    screen.querySelector("input:not([type=checkbox])")?.focus();
  }
  function busy(value) {
    state.busy = value;
    document.body.dataset.busy = String(value);
    if (state.view === "home") {
      const logout = screen.querySelector("[data-logout]");
      if (logout) logout.disabled = value;
      return;
    }
    document.querySelectorAll("button,input").forEach((element) => {
      element.disabled = value;
    });
    const button = screen.querySelector("[data-submit]");
    if (button) {
      if (value) {
        button.dataset.previous = button.innerHTML;
        button.innerHTML =
          '<span class="spinner" aria-hidden="true"></span><span>Đang xử lý…</span>';
      } else if (button.dataset.previous) {
        button.innerHTML = button.dataset.previous;
        delete button.dataset.previous;
      }
    }
    screen.setAttribute("aria-busy", String(value));
    if (!value) updateCooldown();
  }
  function cooldownKey() {
    return `${state.view === "reset" ? "reset" : "verify"}:${state.email.toLowerCase()}`;
  }
  function beginCooldown(seconds = 45) {
    cooldowns.set(cooldownKey(), Date.now() + seconds * 1000);
    updateCooldown();
  }
  function updateCooldown() {
    const button = screen.querySelector("[data-resend]");
    if (!button) return;
    const seconds = Math.max(
      0,
      Math.ceil(((cooldowns.get(cooldownKey()) || 0) - Date.now()) / 1000),
    );
    button.disabled = state.busy || seconds > 0;
    button.textContent = seconds > 0 ? `Gửi lại sau ${seconds}s` : "Gửi lại mã";
  }
  setInterval(updateCooldown, 1000);

  document.addEventListener("input", (event) => {
    event.target.setCustomValidity?.("");
    if (event.target.id === "code")
      event.target.value = event.target.value
        .replace(/[^0-9]/g, "")
        .slice(0, 6);
    if (event.target.name === "email") state.email = event.target.value.trim();
    if (event.target.name === "password")
      screen.querySelector("#confirmPassword")?.setCustomValidity("");
  });
  document.addEventListener(
    "invalid",
    (event) => {
      const input = event.target;
      if (input.name === "email")
        input.setCustomValidity("Vui lòng nhập địa chỉ email hợp lệ.");
      else if (input.name === "code")
        input.setCustomValidity("Vui lòng nhập đủ 6 chữ số.");
      else if (input.name === "acceptTerms")
        input.setCustomValidity("Bạn cần đồng ý với điều khoản sử dụng.");
      else if (input.validity.tooShort)
        input.setCustomValidity("Mật khẩu cần tối thiểu 8 ký tự.");
      else if (input.validity.valueMissing)
        input.setCustomValidity("Vui lòng điền thông tin này.");
    },
    true,
  );

  document.addEventListener("submit", async (event) => {
    event.preventDefault();
    if (state.busy) return;
    const form = event.target;
    const action = form.dataset.action;
    const values = Object.fromEntries(new FormData(form));
    if (
      values.confirmPassword !== undefined &&
      values.confirmPassword !== values.password
    ) {
      const confirm = form.querySelector("#confirmPassword");
      confirm.setCustomValidity("Mật khẩu xác nhận chưa khớp.");
      confirm.reportValidity();
      return;
    }
    if (!form.reportValidity()) return;
    const payload = {
      ...values,
      email: (values.email || state.email).trim(),
      rememberMe: !!values.rememberMe,
      acceptTerms: !!values.acceptTerms,
    };
    state.email = payload.email;
    state.restoreFailed = false;
    showNotice("");
    busy(true);
    try {
      const data = await request(action, payload);
      if (action === "login") {
        state.user = data.user;
        render("home");
      }
      if (action === "register") {
        render("verify", data.message);
        beginCooldown(data.retryAfterSeconds);
      }
      if (action === "forgot-password") {
        render("reset", data.message);
        beginCooldown(data.retryAfterSeconds);
      }
      if (action === "verify-email" || action === "reset-password")
        render("login", data.message, "success");
    } catch (error) {
      if (error.code === "email_unverified")
        render(
          "verify",
          "Tài khoản chưa xác minh. Nhập mã trong email hoặc chọn Gửi lại mã.",
        );
      else {
        showNotice(error.message);
        if (error.code === "invalid_otp")
          screen.querySelector("#code")?.focus();
      }
    } finally {
      busy(false);
    }
  });

  document.addEventListener("click", async (event) => {
    const button = event.target.closest("button");
    if (!button || button.disabled || state.busy) return;
    if (button.dataset.view) {
      state.restoreFailed = false;
      render(button.dataset.view);
      return;
    }
    if (button.dataset.toggle) {
      const field = document.getElementById(button.dataset.toggle);
      const visible = field.type === "password";
      field.type = visible ? "text" : "password";
      button.setAttribute("aria-pressed", String(visible));
      button.setAttribute(
        "aria-label",
        (visible ? "Ẩn " : "Hiện ") +
          (field.id === "confirmPassword" ? "mật khẩu xác nhận" : "mật khẩu"),
      );
      return;
    }
    if (button.hasAttribute("data-restore")) {
      await restore();
      return;
    }
    const resending = button.hasAttribute("data-resend");
    const logout = button.hasAttribute("data-logout");
    const command = resending
      ? state.view === "reset"
        ? "forgot-password"
        : "resend-verification"
      : logout
        ? "logout"
        : button.dataset.command;
    if (!command) return;
    busy(true);
    try {
      const data = await request(command, { email: state.email });
      if (resending) {
        beginCooldown(data.retryAfterSeconds);
        showNotice(data.message, "info");
      }
      if (logout) {
        state.user = null;
        render("login", data.message, "success");
      }
    } catch (error) {
      showNotice(error.message);
    } finally {
      busy(false);
    }
  });

  async function restore() {
    busy(true);
    state.restoreFailed = false;
    try {
      const data = await request("restore");
      state.user = data.user;
      render(data.user ? "home" : "login");
    } catch (error) {
      state.restoreFailed = true;
      render("login", error.message, "error");
    } finally {
      busy(false);
    }
  }
  restore();
})();
