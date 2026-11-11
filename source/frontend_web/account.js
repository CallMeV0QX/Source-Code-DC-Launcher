(() => {
  "use strict";
  const svg = body => `<svg viewBox="0 0 24 24" aria-hidden="true">${body}</svg>`;
  const icons = {
    profile: svg('<circle cx="12" cy="7" r="4"/><path d="M4 21a8 8 0 0 1 16 0"/>'),
    picture: svg('<rect x="3" y="3" width="18" height="18" rx="1"/><circle cx="8" cy="8" r="2"/><path d="m3 17 6-6 4 4 3-3 5 5"/>'),
    lock: svg('<rect x="4" y="10" width="16" height="11" rx="1"/><path d="M7 10V7a5 5 0 0 1 10 0v3M12 14v3"/>'),
    logout: svg('<path d="M9 4H4v16h5m5-12 4 4-4 4m-6-4h13"/>'),
    chevron: svg('<path d="m9 5 7 7-7 7"/>'),
  };
  const initial = user => Array.from(user.displayName || user.email || "D")[0].toUpperCase();
  function markup(user, { escape: esc }) {
    const name = user.displayName || "Tài khoản DC Gaming";
    const entries = [["profile", "Tài khoản của tôi", "profile"], ["avatar", "Đổi ảnh đại diện", "picture"], ["password", "Đổi mật khẩu", "lock"], ["logout", "Đăng xuất", "logout"]];
    return `<details class="launcher-account"><summary aria-label="Tài khoản ${esc(name)}" aria-controls="launcher-account-menu"><span class="avatar" data-avatar aria-hidden="true"><span class="avatar-content" data-avatar-content>${esc(initial(user))}</span></span><strong data-name title="${esc(name)}">${esc(name)}</strong>${icons.chevron}</summary><div class="account-popover" id="launcher-account-menu" role="group" aria-label="Tài khoản">${entries.map(([action, label, icon]) => `<button type="button" class="account-menu-item${action === "logout" ? " account-menu-logout" : ""}" data-account-action="${action}">${icons[icon]}<span>${label}</span></button>`).join("")}</div><span class="sr-only" data-email>${esc(user.email)}</span></details>`;
  }
  function create({ host, user, request, helpers, toast, isBlocked, onPasswordChanged }) {
    const { escape: esc } = helpers;
    const account = host.querySelector(".launcher-account");
    const summary = account.querySelector("summary");
    const logout = host.querySelector("[data-logout]");
    const events = new AbortController();
    const listen = { signal: events.signal };
    let disposed = false, busy = false, dialog = null, avatarBlob = null, avatarUrl = null,
      draft = null, draftUrl = null, draftChanged = false, identity = "", revision = 0, cooldownUntil = 0, cooldownTimer = null;
    const urls = new Set();
    const objectUrl = blob => { const url = URL.createObjectURL(blob); urls.add(url); return url; };
    const revoke = url => { if (url && urls.delete(url)) URL.revokeObjectURL(url); };
    const storageKey = () => `${window.dcLauncherInfo?.apiOrigin || location.origin}:${user.id || user.email}`;
    function storeAvatar(key, action = "get", value = null) {
      return new Promise((resolve, reject) => {
        const opening = indexedDB.open("dc-launcher-avatars", 1);
        opening.onupgradeneeded = () => opening.result.createObjectStore("avatars");
        opening.onerror = () => reject(new Error("Không mở được nơi lưu ảnh trên máy này."));
        opening.onsuccess = () => {
          const db = opening.result;
          const transaction = db.transaction("avatars", action === "get" ? "readonly" : "readwrite");
          const store = transaction.objectStore("avatars");
          const operation = action === "put" ? store.put(value, key) : action === "delete" ? store.delete(key) : store.get(key);
          transaction.oncomplete = () => { db.close(); resolve(operation.result); };
          transaction.onabort = transaction.onerror = () => { db.close(); reject(new Error("Không lưu được ảnh trên máy này. Hãy thử lại.")); };
        };
      });
    }
    function paintAvatar(face, url = avatarUrl) {
      face.replaceChildren(document.createTextNode(initial(user)));
      if (!url) return;
      const img = document.createElement("img");
      img.src = url;
      img.alt = "";
      img.addEventListener("error", () => img.remove(), { once: true });
      face.append(img);
    }
    function setAvatar(blob) {
      revoke(avatarUrl);
      avatarBlob = blob;
      avatarUrl = blob ? objectUrl(blob) : null;
      paintAvatar(account.querySelector("[data-avatar-content]"));
      if (!draftChanged) {
        draft = blob;
        dialog?.querySelectorAll("[data-account-avatar-face]").forEach(face => paintAvatar(face));
      }
    }
    async function loadAvatar() {
      const version = ++revision;
      identity = storageKey();
      const key = identity;
      setAvatar(null);
      try {
        const blob = await storeAvatar(key);
        if (!disposed && version === revision && key === identity && blob instanceof Blob
          && blob.type === "image/png" && blob.size <= 512 * 1024) setAvatar(blob);
      } catch { /* The initial avatar remains available when local storage is disabled. */ }
    }
    function message(text, error = true) {
      const target = dialog?.querySelector("[data-account-notice]");
      if (!target) return;
      target.textContent = text;
      target.hidden = !text;
      target.classList.toggle("is-error", error);
    }
    function lock(value) {
      busy = value;
      dialog?.setAttribute("aria-busy", String(value));
      dialog?.querySelectorAll("button,input").forEach(element => { element.disabled = value; });
      if (!value) {
        const save = dialog?.querySelector("[data-account-save-avatar]");
        if (save) save.disabled = !draftChanged;
        updateCooldown();
      }
    }
    function closeDialog() {
      clearInterval(cooldownTimer);
      cooldownTimer = null;
      dialog?.close();
      dialog?.remove();
      dialog = null;
      draft = null;
      draftChanged = false;
      revoke(draftUrl); draftUrl = null;
      if (!disposed) summary.focus({ preventScroll: true });
    }
    function showDialog(title, body) {
      closeDialog();
      account.open = false;
      dialog = document.createElement("dialog");
      dialog.className = "commerce-dialog account-dialog";
      dialog.setAttribute("aria-labelledby", "account-dialog-title");
      dialog.innerHTML = `<div class="commerce-dialog-heading"><h2 id="account-dialog-title">${title}</h2><button type="button" class="store-icon-button" data-account-close aria-label="Đóng">×</button></div><p class="commerce-notice" data-account-notice role="status" hidden></p>${body}`;
      host.append(dialog);
      dialog.addEventListener("cancel", event => { event.preventDefault(); if (!busy) closeDialog(); });
      dialog.showModal();
      return dialog;
    }
    const preview = () => `<span class="avatar account-avatar-preview" aria-hidden="true"><span class="avatar-content" data-account-avatar-face>${esc(initial(user))}</span></span>`;
    function showProfile() {
      showDialog("Tài khoản của tôi", `<div class="account-profile">${preview()}<div><strong>${esc(user.displayName || "Tài khoản DC Gaming")}</strong><span>${esc(user.email)}</span></div></div><div class="commerce-dialog-actions"><button type="button" class="store-button" data-account-close>Đóng</button></div>`);
      paintAvatar(dialog.querySelector("[data-account-avatar-face]"));
    }
    function showAvatar() {
      showDialog("Đổi ảnh đại diện", `${preview()}<p class="account-note">Ảnh đại diện lưu trên máy này.</p><label class="account-file-label" for="account-avatar-file">Chọn ảnh PNG, JPG hoặc WebP (tối đa 2 MB)</label><input id="account-avatar-file" type="file" accept="image/png,image/jpeg,image/webp" data-account-file><div class="commerce-dialog-actions"><button type="button" class="store-text-button" data-account-remove-avatar>Xóa ảnh</button><button type="button" class="store-button" data-account-close>Hủy</button><button type="button" class="store-button store-primary" data-account-save-avatar disabled>Lưu ảnh</button></div>`);
      draft = avatarBlob;
      paintAvatar(dialog.querySelector("[data-account-avatar-face]"));
    }
    async function selectAvatar(file) {
      if (!file || busy) return;
      if (!["image/png", "image/jpeg", "image/webp"].includes(file.type) || file.size > 2 * 1024 * 1024) {
        message("Chọn ảnh PNG, JPG hoặc WebP không quá 2 MB."); return;
      }
      const target = dialog, key = identity;
      lock(true); message("");
      let bitmap;
      try {
        bitmap = await createImageBitmap(file);
        if (!bitmap.width || !bitmap.height || bitmap.width * bitmap.height > 24 * 1024 * 1024) throw new Error();
        const canvas = document.createElement("canvas");
        canvas.width = canvas.height = 256;
        const edge = Math.min(bitmap.width, bitmap.height);
        canvas.getContext("2d").drawImage(bitmap, (bitmap.width - edge) / 2, (bitmap.height - edge) / 2, edge, edge, 0, 0, 256, 256);
        const blob = await new Promise(resolve => canvas.toBlob(resolve, "image/png"));
        if (!blob || blob.size > 512 * 1024) throw new Error();
        if (disposed || dialog !== target || identity !== key) return;
        draft = blob;
        draftChanged = true;
        revoke(draftUrl); draftUrl = objectUrl(blob);
        paintAvatar(dialog.querySelector("[data-account-avatar-face]"), draftUrl);
      } catch { if (!disposed && dialog === target) message("Không đọc được ảnh này. Hãy chọn ảnh khác."); }
      finally { bitmap?.close(); if (!disposed && dialog === target) lock(false); }
    }
    async function saveAvatar(remove = false) {
      if (busy || !dialog || !remove && !draftChanged) return;
      const key = identity, target = dialog, blob = remove ? null : draft;
      const version = ++revision;
      lock(true); message("");
      try {
        await storeAvatar(key, blob ? "put" : "delete", blob);
        if (disposed || key !== identity || version !== revision || dialog !== target) return;
        setAvatar(blob);
        closeDialog();
        toast(remove ? "Đã xóa ảnh đại diện." : "Đã lưu ảnh đại diện.");
      } catch { if (!disposed && dialog === target) message("Không lưu được ảnh. Hãy thử lại."); }
      finally { if (!disposed) lock(false); }
    }
    function updateCooldown() {
      const button = dialog?.querySelector("[data-account-send-code]");
      if (!button) return;
      const remaining = Math.max(0, Math.ceil((cooldownUntil - Date.now()) / 1000));
      button.disabled = busy || remaining > 0;
      button.textContent = remaining ? `Gửi lại sau ${remaining}s` : "Gửi lại mã";
    }
    function passwordForm() {
      dialog.querySelector("[data-account-password-content]").innerHTML = `<form data-account-password-form><label for="account-code">Mã xác minh trong email</label><input id="account-code" name="code" inputmode="numeric" autocomplete="one-time-code" pattern="[0-9]{6}" minlength="6" maxlength="6" required><label for="account-password">Mật khẩu mới</label><input id="account-password" name="password" type="password" autocomplete="new-password" minlength="8" maxlength="100" required><label for="account-confirm-password">Xác nhận mật khẩu</label><input id="account-confirm-password" type="password" autocomplete="new-password" minlength="8" maxlength="100" required><div class="account-password-actions"><button type="button" class="store-text-button" data-account-send-code>Gửi lại mã</button><button type="submit" class="store-button store-primary">Đổi mật khẩu</button></div></form>`;
      clearInterval(cooldownTimer);
      cooldownTimer = setInterval(updateCooldown, 1000);
      updateCooldown();
      dialog.querySelector("#account-code").focus();
    }
    function showPassword() {
      if (isBlocked()) { toast("Hãy chờ thao tác đang chạy hoàn tất.", true); return; }
      showDialog("Đổi mật khẩu", `<p class="account-note">Xác minh qua email <strong>${esc(user.email)}</strong>.</p><div data-account-password-content><button type="button" class="store-button store-primary" data-account-begin-password>Gửi mã xác minh</button></div>`);
    }
    async function sendCode() {
      if (busy || isBlocked()) return;
      const target = dialog, key = identity;
      lock(true); message("");
      try {
        const result = await request("forgot-password", { email: user.email });
        if (disposed || dialog !== target || identity !== key) return;
        cooldownUntil = Date.now() + Math.max(0, Math.min(3600, result.retryAfterSeconds ?? 45)) * 1000;
        if (!dialog.querySelector("[data-account-password-form]")) passwordForm();
        message(result.message, false);
      } catch (error) { if (!disposed && dialog === target) message(error.message); }
      finally { if (!disposed && dialog === target) lock(false); }
    }
    async function changePassword(form) {
      if (busy || isBlocked()) return;
      const password = form.querySelector("#account-password");
      const confirm = form.querySelector("#account-confirm-password");
      confirm.setCustomValidity(confirm.value === password.value ? "" : "Mật khẩu xác nhận chưa khớp.");
      if (!form.reportValidity()) return;
      const target = dialog;
      lock(true); message("");
      try {
        await request("reset-password", { email: user.email, code: form.querySelector("#account-code").value, password: password.value, confirmPassword: confirm.value });
        if (disposed || dialog !== target) return;
        target.querySelectorAll("input").forEach(input => { input.value = ""; });
        message("Đã đổi mật khẩu. Đang đăng xuất…", false);
        await onPasswordChanged();
      } catch (error) { if (!disposed && dialog === target) message(error.message); }
      finally { if (!disposed && dialog === target) lock(false); }
    }
    function syncMenu() {
      account.querySelector('[data-account-action="logout"]').disabled = logout.disabled || busy;
      account.querySelector('[data-account-action="password"]').disabled = isBlocked() || busy;
    }
    const observer = new MutationObserver(syncMenu);
    observer.observe(logout, { attributes: true, attributeFilter: ["disabled"] });
    account.addEventListener("toggle", () => { summary.setAttribute("aria-expanded", String(account.open)); syncMenu(); }, listen);
    account.addEventListener("keydown", event => {
      if (!["ArrowDown", "ArrowUp", "Home", "End"].includes(event.key)) return;
      const buttons = [...account.querySelectorAll(".account-menu-item:not(:disabled)")];
      if (!buttons.length) return;
      event.preventDefault();
      const fromSummary = event.target === summary;
      account.open = true;
      const current = buttons.indexOf(document.activeElement);
      const next = event.key === "Home" || fromSummary && event.key !== "ArrowUp" ? 0 : event.key === "End" || fromSummary ? buttons.length - 1 : (current + (event.key === "ArrowUp" ? -1 : 1) + buttons.length) % buttons.length;
      buttons[next].focus();
    }, listen);
    host.addEventListener("click", event => {
      const button = event.target.closest("button");
      if (!button || button.disabled || disposed) return;
      const action = button.dataset.accountAction;
      if (action) {
        if (busy) return;
        account.open = false;
        if (action === "profile") showProfile();
        else if (action === "avatar") showAvatar();
        else if (action === "password") showPassword();
        else if (action === "logout") logout.click();
      } else if (button.hasAttribute("data-account-close") && !busy) closeDialog();
      else if (button.hasAttribute("data-account-save-avatar")) void saveAvatar();
      else if (button.hasAttribute("data-account-remove-avatar")) void saveAvatar(true);
      else if (button.hasAttribute("data-account-begin-password")) void sendCode();
      else if (button.hasAttribute("data-account-send-code") && Date.now() >= cooldownUntil) void sendCode();
    }, listen);
    host.addEventListener("change", event => { if (event.target.matches("[data-account-file]")) void selectAvatar(event.target.files[0]); }, listen);
    host.addEventListener("input", event => {
      if (event.target.id === "account-code") event.target.value = event.target.value.replace(/[^0-9]/g, "").slice(0, 6);
      if (dialog?.contains(event.target)) dialog.querySelector("#account-confirm-password")?.setCustomValidity("");
    }, listen);
    host.addEventListener("submit", event => {
      if (!event.target.matches("[data-account-password-form]")) return;
      event.preventDefault(); event.stopPropagation();
      void changePassword(event.target);
    }, listen);
    window.addEventListener("dc-launcher-info", () => { if (identity !== storageKey()) { if (!busy) closeDialog(); void loadAvatar(); } }, listen);
    document.addEventListener("focusin", event => { if (account.open && !account.contains(event.target)) account.open = false; }, listen);
    void loadAvatar();
    return {
      get busy() { return busy; },
      dispose() {
        disposed = true; revision++;
        observer.disconnect(); events.abort(); closeDialog();
        urls.forEach(url => URL.revokeObjectURL(url)); urls.clear();
      },
    };
  }
  window.LauncherAccount = { markup, create };
})();
