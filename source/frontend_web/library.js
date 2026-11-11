(() => {
  "use strict";
  const gameNames = window.DCGameNames;
  const gameName = gameNames.display;
  function create({ host, panel, request, helpers, onRoute, onOrder, toast }) {
    const { escape: esc, image, imageUrl, icons } = helpers;
    const svg = (body) =>
      `<svg viewBox="0 0 24 24" aria-hidden="true">${body}</svg>`;
    const ui = {
      bolt: svg('<path d="m13 2-9 12h7l-1 8 10-13h-7Z"/>'),
      box: svg(
        '<path d="m12 3 9 5v8l-9 5-9-5V8Zm-9 5 9 5 9-5M12 13v8M7.5 5.5l9 5"/>',
      ),
      file: svg('<path d="M14 3H5v18h14V8Zm0 0v5h5M8 12h8M8 16h6"/>'),
      cloud: svg(
        '<path d="M6 18a4 4 0 0 1-1-7.9 6 6 0 0 1 11.7-1.6A4.8 4.8 0 0 1 18 18Z"/>',
      ),
      book: svg(
        '<path d="M12 5v16M3 4h5a4 4 0 0 1 4 4 4 4 0 0 1 4-4h5v15h-5a4 4 0 0 0-4 2 4 4 0 0 0-4-2H3Z"/>',
      ),
      grid: svg('<path d="M3 3h7v7H3Zm11 0h7v7h-7ZM3 14h7v7H3Zm11 0h7v7h-7Z"/>'),
      list: svg('<path d="M8 5h13M8 12h13M8 19h13M3 5h.01M3 12h.01M3 19h.01"/>'),
      more: svg('<circle cx="5" cy="12" r="1"/><circle cx="12" cy="12" r="1"/><circle cx="19" cy="12" r="1"/>'),
      check: svg('<path d="m5 12 4 4L19 6"/>'),
      clock: svg('<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>'),
      alert: svg('<path d="m12 3 10 18H2Zm0 5v5m0 3h.01"/>'),
    };
    const statuses = [
      ["all", "Tất cả"],
      ["ready", "Đã sở hữu"],
      ["pending", "Đang giao"],
      ["failed", "Cần hỗ trợ"],
    ];
    const tabs = [
      ["intro", "Giới thiệu"],
      ["images", "Hình ảnh"],
      ["requirements", "Cấu hình PC"],
    ];
    const fallback = `<span class="art-fallback">${icons.game}<span>DC GAMING</span></span>`;
    const events = new AbortController();
    const listen = { signal: events.signal };
    const scroll = host.querySelector(".store-scroll");
    const activation = window.LauncherActivation.create({
      panel,
      host,
      request,
      helpers,
      toast,
    });
    let disposed = false,
      route = null,
      sequence = 0,
      timer,
      debounce;
    let search = "",
      status = "all",
      sort = "recent",
      view = "grid",
      rows = [],
      next = null;
    let total = 0,
      count = 0,
      hasPending = false,
      loading = false,
      detail = null,
      catalog = null,
      gallery = [],
      selectedImage = 0,
      selectedTab = "intro",
      versionId = null;
    let returnScroll = 0,
      returnVersion = null;
    const alive = (id) => !disposed && route && id === sequence;
    const date = (raw) =>
      raw ? new Date(raw).toLocaleDateString("vi-VN") : "—";
    const badge = (item, withIcon = false) =>
      `<span class="library-badge ${item.status === "ready" ? "is-ready" : item.status === "failed" ? "is-failed" : "is-pending"}">${withIcon ? item.status === "ready" ? ui.check : item.status === "failed" ? ui.alert : ui.clock : ""}<span>${esc(item.status === "ready" ? "Đã sở hữu" : item.statusLabel)}</span></span>`;
    function stop() {
      clearTimeout(timer);
      clearTimeout(debounce);
    }
    function notice(message = "") {
      const target = panel.querySelector("[data-library-notice]");
      if (target) {
        target.textContent = message;
        target.hidden = !message;
      }
    }
    function shell() {
      panel.classList.add("library-page");
      panel.innerHTML = `<h2 class="sr-only" tabindex="-1">Thư viện game</h2>
        <form class="library-toolbar" data-library-form role="search" aria-label="Tìm trong thư viện"><label class="library-search">${icons.search}<span class="sr-only">Tìm trong thư viện</span><input type="search" maxlength="120" data-library-search placeholder="Tìm game trong thư viện…" value="${esc(search)}" autocomplete="off"></label><label class="library-sort"><span class="sr-only">Sắp xếp thư viện</span><select data-library-sort><option value="recent" ${sort === "recent" ? "selected" : ""}>Mới nhận gần đây</option><option value="name" ${sort === "name" ? "selected" : ""}>Tên A–Z</option></select></label><button class="store-button" type="button" data-library-refresh>${icons.refresh}<span>Làm mới</span></button><div class="library-views" role="group" aria-label="Kiểu hiển thị thư viện"><button type="button" data-library-view="grid" aria-pressed="${view === "grid"}" aria-label="Dạng lưới" title="Dạng lưới">${ui.grid}</button><button type="button" data-library-view="list" aria-pressed="${view === "list"}" aria-label="Dạng danh sách" title="Dạng danh sách">${ui.list}</button></div><button class="sr-only" type="submit">Tìm kiếm</button></form>
        <div class="library-filters" role="group" aria-label="Lọc thư viện">${statuses.map(([value, label]) => `<button type="button" data-library-status="${value}" aria-pressed="${status === value}">${label}<span data-library-status-count="${value}"></span></button>`).join("")}</div>
        <p class="commerce-notice is-error" data-library-notice role="status" hidden></p><div data-library-results aria-live="polite"></div><div class="feed-footer" data-library-footer></div>`;
    }
    function card(item) {
      const title = esc(gameName(item.gameName));
      const id = esc(item.versionId);
      return `<article class="library-card"><div class="library-card-cover"><button type="button" class="library-art" data-library-open="${id}" aria-label="Xem ${title}">${fallback}${image(item.photoUrl)}</button>${badge(item, true)}<details class="library-card-menu" data-library-menu><summary aria-label="Tùy chọn ${title}" title="Tùy chọn game">${ui.more}</summary><div class="library-menu-actions"><button type="button" data-library-open="${id}">Xem chi tiết</button>${item.orderId ? `<button type="button" data-library-order="${esc(item.orderId)}">Xem đơn hàng</button>` : ""}</div></details></div><div class="library-card-body"><h3 title="${title}">${title}</h3><div class="library-card-footer"><p class="library-version" title="${esc(item.versionName)}">${esc(item.versionName)}</p><button type="button" class="store-button offer-button" data-library-open="${id}">Xem chi tiết</button></div></div></article>`;
    }
    function renderRows() {
      panel.querySelectorAll("[data-library-status]").forEach((button) => {
        const value = button.dataset.libraryStatus;
        button.setAttribute("aria-pressed", String(value === status));
        button.querySelector("span").textContent =
          value === "all"
            ? ` (${total})`
            : value === status
              ? ` (${count})`
              : "";
      });
      panel.querySelector("[data-library-results]").innerHTML = rows.length
        ? `<div class="library-grid" data-view="${view}">${rows.map(card).join("")}</div>`
        : `<div class="store-empty">${icons.game}<h3>${total ? "Không tìm thấy game" : "Thư viện đang trống"}</h3><p>${total ? "Thử từ khóa khác hoặc thay đổi bộ lọc." : "Game đã mua sẽ xuất hiện tại đây, cùng thông tin nhận sản phẩm."}</p><button type="button" class="store-button store-primary" ${total ? "data-library-reset" : 'data-store-nav="store"'}>${total ? "Xóa bộ lọc" : "Khám phá cửa hàng"}${icons.arrow}</button></div>`;
      panel.querySelector("[data-library-footer]").innerHTML =
        next !== null
          ? `<button type="button" class="store-button" data-library-more>Tải thêm game ${icons.arrow}</button>`
          : "";
    }
    function schedule() {
      clearTimeout(timer);
      if (disposed || !route) return;
      timer = setTimeout(
        () => {
          if (document.hidden || loading) schedule();
          else void refresh(true);
        },
        (
          route === "library-detail"
            ? detail?.item.status !== "ready"
            : hasPending
        )
          ? 7000
          : 30000,
      );
    }
    async function loadList({ more = false, quiet = false } = {}) {
      const id = ++sequence;
      clearTimeout(timer);
      loading = true;
      notice();
      panel.setAttribute("aria-busy", "true");
      const moreButton = panel.querySelector("[data-library-more]");
      if (moreButton) moreButton.disabled = true;
      if (!quiet && !more) {
        panel.querySelector("[data-library-results]").innerHTML =
          '<div class="commerce-loading" role="status"><span class="spinner"></span>Đang tải thư viện…</div>';
        panel.querySelector("[data-library-footer]").innerHTML = "";
      }
      const pages = quiet ? Math.max(1, Math.ceil(rows.length / 24)) : 1;
      const query = { search, status, sort };
      try {
        let offset = more ? next : 0,
          loaded = [],
          result;
        for (let page = 0; page < pages; page++) {
          result = await request("library", { ...query, offset });
          if (!alive(id)) return;
          loaded.push(...result.items);
          offset = result.nextOffset ?? null;
          if (offset === null) break;
        }
        const updated = [
          ...new Map(
            (more ? [...rows, ...loaded] : loaded).map((item) => [
              item.versionId,
              item,
            ]),
          ).values(),
        ];
        const changed =
          JSON.stringify(updated) !== JSON.stringify(rows) ||
          total !== result.total ||
          count !== result.totalResults ||
          next !== offset;
        rows = updated;
        next = offset;
        total = result.total;
        count = result.totalResults;
        hasPending = result.hasPending;
        if (!quiet || changed) {
          const focus = document.activeElement?.dataset.libraryOpen;
          renderRows();
          if (focus)
            [...panel.querySelectorAll("[data-library-open]")]
              .find((button) => button.dataset.libraryOpen === focus)
              ?.focus({ preventScroll: true });
        }
      } catch (error) {
        if (!alive(id)) return;
        notice(`Chưa cập nhật được thư viện: ${error.message}`);
        if (!quiet && !more)
          panel.querySelector("[data-library-results]").innerHTML =
            `<div class="store-empty">${icons.refresh}<h3>Chưa tải được thư viện</h3><button type="button" class="store-button" data-library-refresh>Thử lại ${icons.refresh}</button></div>`;
      } finally {
        if (alive(id)) {
          loading = false;
          panel.setAttribute("aria-busy", "false");
          const button = panel.querySelector("[data-library-more]");
          if (button) button.disabled = false;
          schedule();
        }
      }
    }
    function detailShell() {
      panel.classList.remove("library-page");
      panel.innerHTML = `<nav class="detail-breadcrumb library-breadcrumb" aria-label="Vị trí trang"><button type="button" class="store-text-button detail-back" data-library-back>${icons.arrow}Thư viện</button><span class="breadcrumb-divider">/</span><span class="breadcrumb-name" data-library-name>Chi tiết game</span></nav><p class="commerce-notice is-error" data-library-notice role="status" hidden></p><div data-library-detail></div>`;
    }
    function description() {
      const content = window.LauncherProduct.richText(
        catalog?.description?.html,
        (index) => {
          const item = catalog.description.images?.[index];
          const source = imageUrl(item?.imageUrl);
          if (!source) return null;
          const img = document.createElement("img");
          img.src = source;
          img.alt = gameNames.replaceMentions(item.alt, detail?.item.gameName, catalog?.steamMetadata?.name);
          img.loading = "lazy";
          img.decoding = "async";
          return img;
        },
        null,
        { name: detail?.item.gameName, steamName: catalog?.steamMetadata?.name },
      );
      return content.trim()
        ? `<div class="steam-description">${content}</div>`
        : '<p class="detail-placeholder">Giới thiệu game đang được cập nhật. Bạn có thể xem hướng dẫn nhận game bên dưới.</p>';
    }
    function requirements() {
      const context = { name: detail?.item.gameName, steamName: catalog?.steamMetadata?.name };
      const minimum = window.LauncherProduct.richText(
        catalog?.minimumRequirementsHtml,
        null, null, context,
      );
      const recommended = window.LauncherProduct.richText(
        catalog?.recommendedRequirementsHtml,
        null, null, context,
      );
      if (!minimum.trim() && !recommended.trim())
        return '<p class="detail-placeholder">Cấu hình PC đang được cập nhật.</p>';
      return `<div class="requirements-grid"><section><h3>Tối thiểu</h3>${minimum || '<p class="detail-placeholder">Đang cập nhật.</p>'}</section><section><h3>Đề nghị</h3>${recommended || '<p class="detail-placeholder">Đang cập nhật.</p>'}</section></div>`;
    }
    function thumbnails() {
      return gallery
        .map(
          (item, index) =>
            `<button type="button" class="detail-thumbnail" data-library-image="${index}" aria-label="Xem ảnh ${index + 1}" aria-pressed="${index === selectedImage}">${fallback}${image(imageUrl(item.thumbnailUrl) || item.imageUrl)}</button>`,
        )
        .join("");
    }
    function selectImage(index) {
      if (!Number.isInteger(index) || index < 0 || index >= gallery.length)
        return;
      selectedImage = index;
      const stage = panel.querySelector("[data-library-stage]");
      stage.innerHTML = fallback + image(gallery[index].imageUrl, "", false);
      const img = stage.querySelector("img");
      if (img) img.alt = `${gameName(detail.item.gameName)} — ảnh ${index + 1}`;
      panel.querySelector("[data-library-image-count]").textContent =
        `${index + 1} / ${gallery.length}`;
      panel
        .querySelectorAll("[data-library-image]")
        .forEach((button) =>
          button.setAttribute(
            "aria-pressed",
            String(Number(button.dataset.libraryImage) === index),
          ),
        );
      panel.querySelector("[data-library-previous]").disabled = index === 0;
      panel.querySelector("[data-library-next]").disabled =
        index === gallery.length - 1;
    }
    function selectTab(id, focus = false) {
      if (!tabs.some(([key]) => key === id)) return;
      selectedTab = id;
      panel.querySelectorAll("[data-library-tab]").forEach((button) => {
        const active = button.dataset.libraryTab === id;
        button.setAttribute("aria-selected", String(active));
        button.tabIndex = active ? 0 : -1;
        panel.querySelector(
          `#library-panel-${button.dataset.libraryTab}`,
        ).hidden = !active;
        if (active && focus) button.focus({ preventScroll: true });
      });
    }
    function activationMarkup(item) {
      return activation.markup(item, detail);
    }
    function detailMarkup() {
      const item = detail.item;
      const instructions =
        detail.instructions ||
        "Thông tin nhận sản phẩm đang được cập nhật. Hãy xem đơn hàng hoặc liên hệ hỗ trợ kèm mã đơn.";
      gallery = [{ imageUrl: item.photoUrl }, ...(catalog?.gallery || [])]
        .filter((entry) => imageUrl(entry.imageUrl))
        .filter(
          (entry, index, all) =>
            all.findIndex((other) => other.imageUrl === entry.imageUrl) ===
            index,
        );
      selectedImage = Math.min(selectedImage, Math.max(0, gallery.length - 1));
      panel.querySelector("[data-library-name]").textContent = gameName(item.gameName);
      const focus = document.activeElement;
      const packageOpen = panel.querySelector(".library-package")?.open;
      const focusSelector = focus?.matches("[data-library-tab]")
        ? `[data-library-tab="${focus.dataset.libraryTab}"]`
        : focus?.matches("[data-library-image]")
          ? `[data-library-image="${focus.dataset.libraryImage}"]`
          : focus?.matches("[data-library-guide]")
            ? "[data-library-guide]"
            : null;
      panel.querySelector("[data-library-detail]").innerHTML =
        `<div class="library-detail-grid"><div class="library-game-content"><section class="library-media" aria-label="Hình ảnh game"><div class="library-detail-art" data-library-stage>${fallback}${image(gallery[selectedImage]?.imageUrl, "", false)}</div><div class="library-media-caption library-detail-meta">${badge(item)}<span>${esc(item.versionName)}</span><span>${catalog?.steamAppId > 0 ? "Steam · Windows" : "Game PC"}</span></div></section>
        ${gallery.length ? `<div class="gallery-toolbar"><span data-library-image-count aria-live="polite">${selectedImage + 1} / ${gallery.length}</span><div><button type="button" class="store-icon-button gallery-previous" data-library-previous aria-label="Ảnh trước" ${selectedImage === 0 ? "disabled" : ""}>${icons.chevron}</button><button type="button" class="store-icon-button" data-library-next aria-label="Ảnh tiếp theo" ${selectedImage === gallery.length - 1 ? "disabled" : ""}>${icons.chevron}</button></div></div><div class="detail-thumbnails library-thumbnails">${thumbnails()}</div>` : ""}
        <div class="library-game-title"><h2 tabindex="-1">${esc(gameName(item.gameName))}</h2><p>${esc(item.versionName)}</p></div><section class="library-information"><div class="detail-tabs" role="tablist" aria-label="Thông tin game">${tabs.map(([id, label]) => `<button type="button" id="library-tab-${id}" role="tab" data-library-tab="${id}" aria-controls="library-panel-${id}" aria-selected="${id === selectedTab}" tabindex="${id === selectedTab ? 0 : -1}">${label}</button>`).join("")}</div>
        <div class="detail-rich" id="library-panel-intro" role="tabpanel" aria-labelledby="library-tab-intro" tabindex="0" ${selectedTab !== "intro" ? "hidden" : ""}>${description()}</div><div id="library-panel-images" role="tabpanel" aria-labelledby="library-tab-images" tabindex="0" ${selectedTab !== "images" ? "hidden" : ""}>${gallery.length ? `<div class="detail-image-grid">${thumbnails()}</div>` : '<p class="detail-placeholder">Hình ảnh đang được cập nhật.</p>'}</div><div class="detail-rich" id="library-panel-requirements" role="tabpanel" aria-labelledby="library-tab-requirements" tabindex="0" ${selectedTab !== "requirements" ? "hidden" : ""}>${requirements()}</div></section>
        <section class="library-delivery" data-library-delivery tabindex="-1"><div class="library-delivery-heading"><h3>${item.status === "ready" ? "Hướng dẫn nhận game" : "Trạng thái giao sản phẩm"}</h3><button type="button" class="store-icon-button" data-library-refresh aria-label="Cập nhật thông tin">${icons.refresh}</button></div><p class="library-message">${esc(detail.message)}</p>${item.status === "ready" ? `<div class="library-instructions">${esc(instructions)}</div>${detail.instructions && detail.instructions.length <= 2048 ? '<button type="button" class="store-text-button" data-library-copy="instructions">Sao chép hướng dẫn</button>' : ""}${detail.deliveryNote ? `<h4>Thông tin giao hàng</h4><div class="library-instructions">${esc(detail.deliveryNote)}</div>${detail.deliveryNote.length <= 2048 ? '<button type="button" class="store-text-button" data-library-copy="note">Sao chép thông tin</button>' : ""}` : ""}` : `<div class="library-waiting">${item.status === "failed" ? icons.bell : icons.refresh}<p>${item.status === "failed" ? "Mở đơn hàng để kiểm tra thông tin và mã đơn cần hỗ trợ." : "Trạng thái sẽ tự cập nhật khi sản phẩm được giao."}</p></div>`}
        <dl class="library-receipt"><div><dt>Ngày mua</dt><dd>${date(item.purchasedAt)}</dd></div>${item.acquiredAt ? `<div><dt>Ngày nhận</dt><dd>${date(item.acquiredAt)}</dd></div>` : ""}<div><dt>Mã đơn</dt><dd>${esc(item.orderCode)}<button type="button" class="store-text-button" data-library-copy="code" aria-label="Sao chép mã đơn">Sao chép</button></dd></div></dl><button type="button" class="store-button" data-library-order="${esc(item.orderId)}">${icons.order}Xem đơn hàng</button></section></div>${activationMarkup(item)}</div>`;
      if (gallery.length) selectImage(selectedImage);
      if (packageOpen !== undefined)
        panel.querySelector(".library-package").open = packageOpen;
      if (focusSelector)
        panel.querySelector(focusSelector)?.focus({ preventScroll: true });
    }
    async function loadCatalog(id, result) {
      try {
        const product = await request("store-detail", {
          slug: result.catalogSlug,
        });
        if (!alive(id)) return;
        if (product.gameId === result.item.gameId) {
          catalog = product;
          detailMarkup();
        }
      } catch {
        // Removed/unavailable store entries must not block access to an owned game.
      }
    }
    async function loadDetail(quiet = false) {
      const id = ++sequence;
      clearTimeout(timer);
      loading = true;
      notice();
      if (!quiet)
        panel.querySelector("[data-library-detail]").innerHTML =
          '<div class="commerce-loading"><span class="spinner"></span>Đang tải thông tin…</div>';
      try {
        const result = await request("library-detail", { versionId });
        if (!alive(id)) return;
        const changed = JSON.stringify(detail) !== JSON.stringify(result);
        const justDelivered =
          detail &&
          detail.item.status !== "ready" &&
          result.item.status === "ready";
        detail = result;
        if (!quiet || changed) detailMarkup();
        activation.connect(result.item, result);
        if (justDelivered) toast("Game đã được thêm vào thư viện của bạn.");
        if (result.catalogSlug && !catalog) void loadCatalog(id, result);
      } catch (error) {
        if (!alive(id)) return;
        detail = null; // Never leave old delivery secrets visible after access is revoked.
        catalog = null;
        gallery = [];
        activation.close();
        panel.querySelector("[data-library-detail]").innerHTML =
          `<div class="store-empty" role="alert">${icons.bell}<h3>${error.code === "library_error" ? "Sản phẩm không còn khả dụng" : "Chưa tải được thông tin"}</h3><p>${esc(error.message)}</p><button type="button" class="store-button" data-library-refresh>Thử lại ${icons.refresh}</button></div>`;
      } finally {
        if (alive(id)) {
          loading = false;
          schedule();
        }
      }
    }
    async function refresh(quiet = false) {
      if (route === "library") await loadList({ quiet });
      else if (route === "library-detail") await loadDetail(quiet);
    }
    async function open(view = "library", id = null) {
      if (disposed) return;
      stop();
      sequence++;
      route = view;
      loading = false;
      panel.hidden = false;
      panel.setAttribute("aria-busy", "false");
      onRoute(view);
      if (view === "library-detail") {
        scroll.scrollTop = 0;
        versionId = id;
        detail = null;
        catalog = null;
        gallery = [];
        selectedImage = 0;
        selectedTab = "intro";
        detailShell();
        await loadDetail();
      } else {
        rows = [];
        next = null;
        shell();
        await loadList();
      }
      if (!disposed && route === view)
        panel.querySelector("h2")?.focus({ preventScroll: true });
    }
    function back() {
      stop();
      sequence++;
      route = "library";
      loading = false;
      detail = null;
      catalog = null;
      gallery = [];
      activation.close();
      onRoute(route);
      shell();
      renderRows();
      scroll.scrollTop = returnScroll;
      [...panel.querySelectorAll("[data-library-open]")]
        .find((button) => button.dataset.libraryOpen === returnVersion)
        ?.focus({ preventScroll: true });
      void loadList({ quiet: true });
    }
    function filters() {
      rows = [];
      next = null;
      scroll.scrollTop = 0;
      void loadList();
    }
    panel.addEventListener(
      "click",
      (event) => {
        if (!route) return;
        const button = event.target.closest("button");
        if (!button || button.disabled) return;
        if (button.dataset.libraryOpen) {
          returnScroll = scroll.scrollTop;
          returnVersion = button.dataset.libraryOpen;
          void open("library-detail", returnVersion);
        } else if (button.hasAttribute("data-library-back")) back();
        else if (button.hasAttribute("data-library-refresh")) void refresh();
        else if (button.hasAttribute("data-library-view")) {
          view = button.dataset.libraryView === "list" ? "list" : "grid";
          const grid = panel.querySelector(".library-grid");
          if (grid) grid.dataset.view = view;
          panel.querySelectorAll("[data-library-view]").forEach((entry) =>
            entry.setAttribute("aria-pressed", String(entry.dataset.libraryView === view)),
          );
        }
        else if (button.hasAttribute("data-library-more") && !loading)
          void loadList({ more: true });
        else if (button.hasAttribute("data-library-reset")) {
          search = "";
          status = "all";
          shell();
          filters();
        } else if (button.hasAttribute("data-library-status")) {
          status = button.dataset.libraryStatus;
          panel
            .querySelectorAll("[data-library-status]")
            .forEach((entry) =>
              entry.setAttribute("aria-pressed", String(entry === button)),
            );
          stop();
          filters();
        } else if (button.hasAttribute("data-library-image"))
          selectImage(Number(button.dataset.libraryImage));
        else if (button.hasAttribute("data-library-previous"))
          selectImage(selectedImage - 1);
        else if (button.hasAttribute("data-library-next"))
          selectImage(selectedImage + 1);
        else if (button.hasAttribute("data-library-tab"))
          selectTab(button.dataset.libraryTab);
        else if (button.hasAttribute("data-library-guide")) {
          const guide = panel.querySelector("[data-library-delivery]");
          guide?.scrollIntoView({ block: "start" });
          guide?.focus({ preventScroll: true });
        } else if (button.dataset.libraryOrder)
          onOrder(button.dataset.libraryOrder);
        else if (button.dataset.libraryCopy && detail) {
          const text = {
            code: detail.item.orderCode,
            instructions: detail.instructions,
            note: detail.deliveryNote,
          }[button.dataset.libraryCopy];
          if (text)
            void request("copy-text", { text })
              .then(() => toast("Đã sao chép."))
              .catch((error) => toast(error.message, true));
        }
      },
      listen,
    );
    panel.addEventListener(
      "input",
      (event) => {
        if (!event.target.matches("[data-library-search]")) return;
        search = event.target.value.trim();
        sequence++;
        stop();
        debounce = setTimeout(filters, 300);
      },
      listen,
    );
    panel.addEventListener(
      "change",
      (event) => {
        if (event.target.matches("[data-library-sort]")) {
          sort = event.target.value;
          stop();
          filters();
        }
      },
      listen,
    );
    panel.addEventListener(
      "keydown",
      (event) => {
        if (event.key === "Escape") {
          const menu = event.target.closest("[data-library-menu]");
          if (menu?.open) {
            menu.open = false;
            menu.querySelector("summary").focus();
            event.stopPropagation();
          }
        }
        const tab = event.target.closest("[data-library-tab]");
        if (
          !route ||
          !tab ||
          !["ArrowLeft", "ArrowRight", "Home", "End"].includes(event.key)
        )
          return;
        event.preventDefault();
        const index = tabs.findIndex(([id]) => id === tab.dataset.libraryTab);
        const next =
          event.key === "Home"
            ? 0
            : event.key === "End"
              ? tabs.length - 1
              : (index + (event.key === "ArrowRight" ? 1 : -1) + tabs.length) %
                tabs.length;
        selectTab(tabs[next][0], true);
      },
      listen,
    );
    panel.addEventListener(
      "submit",
      (event) => {
        if (event.target.matches("[data-library-form]")) {
          event.preventDefault();
          stop();
          filters();
        }
      },
      listen,
    );
    const resume = () => {
      if (route && !document.hidden && !loading) void refresh(true);
    };
    document.addEventListener("visibilitychange", resume, listen);
    window.addEventListener("focus", resume, listen);
    const closeMenus = (event) => {
      if (route !== "library") return;
      panel.querySelectorAll("[data-library-menu][open]").forEach((menu) => {
        if (!menu.contains(event.target)) menu.open = false;
      });
    };
    document.addEventListener("click", closeMenus, listen);
    document.addEventListener("focusin", closeMenus, listen);
    function close() {
      activation.close();
      stop();
      sequence++;
      route = null;
      detail = null;
      catalog = null;
      gallery = [];
      loading = false;
      panel.setAttribute("aria-busy", "false");
      panel.classList.remove("library-page");
    }
    return {
      open,
      close,
      dispose() {
        disposed = true;
        close();
        rows = [];
        events.abort();
        activation.dispose();
      },
    };
  }
  window.LauncherLibrary = { create };
})();
