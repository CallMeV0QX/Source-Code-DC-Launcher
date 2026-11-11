(() => {
  "use strict";
  const gameName = window.DCGameNames.display;
  const svg = (body) =>
    `<svg viewBox="0 0 24 24" aria-hidden="true">${body}</svg>`;
  const icons = {
    wallet: svg(
      '<path d="M20 8V5H5a2 2 0 0 1 0-4h13v4M3 3v17h18V8H3"/><path d="M21 12h-6v5h6m-3-2.5h.01"/>',
    ),
    home: svg('<path d="m3 10 9-7 9 7v11h-6v-7H9v7H3Z"/>'),
    grid: svg(
      '<rect x="3" y="3" width="7" height="7" rx="1"/><rect x="14" y="3" width="7" height="7" rx="1"/><rect x="3" y="14" width="7" height="7" rx="1"/><rect x="14" y="14" width="7" height="7" rx="1"/>',
    ),
    cart: svg(
      '<path d="M2 3h3l3 12h11l3-9H6M9 19h.01M18 19h.01"/><circle cx="9" cy="20" r="1"/><circle cx="18" cy="20" r="1"/>',
    ),
    order: svg(
      '<rect x="5" y="3" width="14" height="18" rx="1"/><path d="M9 8h6M9 12h6M9 16h4"/>',
    ),
    search: svg('<circle cx="10.5" cy="10.5" r="6.5"/><path d="m16 16 5 5"/>'),
    bell: svg('<path d="M5 17h14l-2-3V9a5 5 0 0 0-10 0v5Zm5 4h4M12 2v2"/>'),
    arrow: svg('<path d="M4 12h16m-6-6 6 6-6 6"/>'),
    chevron: svg('<path d="m9 5 7 7-7 7"/>'),
    logout: svg('<path d="M9 4H4v16h5m5-12 4 4-4 4m-6-4h13"/>'),
    game: svg(
      '<path d="M7 7h10c3 0 6 12 3 13-2 1-4-4-6-4h-4c-2 0-4 5-6 4C1 19 4 7 7 7Z"/><path d="M7 10v5m-2.5-2.5h5M16 11h.01M18 14h.01"/>',
    ),
    refresh: svg(
      '<path d="M20 7v5h-5M4 17v-5h5M5.5 7a8 8 0 0 1 13-1L20 8M4 16l1.5 2a8 8 0 0 0 13-1"/>',
    ),
    heart: svg('<path d="M20.8 4.6a5.5 5.5 0 0 0-7.8 0L12 5.7l-1.1-1.1a5.5 5.5 0 0 0-7.8 7.8L12 21l8.8-8.6a5.5 5.5 0 0 0 0-7.8Z"/>'),
    tag: svg('<path d="M20 13 11 22 2 13V2h11l9 9Z"/><circle cx="7" cy="7" r="1.5"/>'),
    settings: svg('<path d="m9 3 1-2h4l1 2 3 2 2 .2 2 3-1 2v4l1 2-2 3-2 .2-3 2-1 2h-4l-1-2-3-2-2-.2-2-3 1-2v-4l-1-2 2-3L6 5Z"/><circle cx="12" cy="12" r="3"/>'),
    support: svg('<path d="M4 14v-3a8 8 0 0 1 16 0v7a3 3 0 0 1-3 3h-4"/><rect x="2" y="11" width="5" height="8" rx="2"/><rect x="17" y="11" width="5" height="8" rx="2"/>'),
    filter: svg('<path d="M3 6h18M3 12h18M3 18h18"/><circle cx="8" cy="6" r="2"/><circle cx="16" cy="12" r="2"/><circle cx="9" cy="18" r="2"/>'),
    library: svg('<path d="M3 3h5v18H3Zm8 0h5v18h-5Zm8 0 4 1-2 17-4-1Z"/>'),
  };
  const escape = (value) =>
    String(value ?? "").replace(
      /[&<>"']/g,
      (c) =>
        ({
          "&": "&amp;",
          "<": "&lt;",
          ">": "&gt;",
          '"': "&quot;",
          "'": "&#39;",
        })[c],
    );
  const money = (value) =>
    new Intl.NumberFormat("vi-VN", { maximumFractionDigits: 0 }).format(value) +
    " ₫";
  let active = null;
  let generation = 0;

  function imageUrl(raw) {
    try {
      const url = new URL(raw);
      return url.origin === "https://media.dcgaming.local" &&
        /^\/image\/[a-f0-9]{64}$/.test(url.pathname) &&
        !url.search &&
        !url.hash
        ? url.href
        : "";
    } catch {
      return "";
    }
  }
  function image(raw, className = "", lazy = true, fallbackRaw = null) {
    const fallback = imageUrl(fallbackRaw);
    const url = imageUrl(raw) || fallback;
    return url
      ? `<img class="${className}" src="${escape(url)}"${fallback && fallback !== url ? ` data-fallback-src="${escape(fallback)}"` : ""} alt="" ${lazy ? 'loading="lazy"' : 'fetchpriority="high"'} decoding="async">`
      : "";
  }
  function price(game) {
    const current = game.currentPrice;
    if (typeof current === "number" && current >= 0) {
      const discounted =
        game.originalPrice > current && game.discountPercent > 0;
      return `<div class="product-price">${discounted ? `<span class="discount">-${escape(game.discountPercent)}%</span><del>${money(game.originalPrice)}</del>` : ""}<strong class="${current === 0 ? "price-free" : ""}">${current === 0 ? "Miễn phí" : money(current)}</strong></div>`;
    }
    if (game.steamPrice > 0)
      return `<div class="product-price reference-price"><span>Giá tham khảo Steam</span><strong>${money(game.steamPrice)}</strong></div>`;
    return '<div class="product-price"><span class="price-pending">Đang cập nhật</span></div>';
  }
  function title(game) {
    return `<span class="game-base-title">${escape(window.DCGameNames.baseTitle(game.name))}</span> <span class="game-title-suffix">- ${escape(window.DCGameNames.suffix)}</span>`;
  }
  function favoriteButton(game) {
    const selected = active?.favorites.has(game.gameId) || false;
    return `<button type="button" class="favorite-button" data-favorite="${escape(game.gameId)}" aria-pressed="${selected}" aria-label="${selected ? "Bỏ yêu thích" : "Yêu thích"} ${escape(gameName(game.name))}">${icons.heart}</button>`;
  }
  function product(game) {
    const priced =
      typeof game.currentPrice === "number" && game.currentPrice >= 0;
    return `<article class="product-card" data-game-id="${escape(game.gameId)}">
      <div class="product-cover"><button type="button" class="product-art" data-product="${escape(game.slug)}" aria-label="Xem chi tiết ${escape(gameName(game.name))}"><span class="art-fallback">${icons.game}<span>DC GAMING</span></span>${image(game.photoUrl)}</button>
      ${game.discountPercent > 0 ? `<span class="cover-discount">-${escape(game.discountPercent)}%</span>` : ""}
      ${favoriteButton(game)}
      <button class="store-icon-button product-buy" type="button" ${priced ? `data-add-product="${escape(game.slug)}"` : "disabled"} aria-label="${priced ? "Thêm vào giỏ" : "Chưa mở bán"} ${escape(gameName(game.name))}" title="${priced ? "Chọn phiên bản để thêm vào giỏ" : "Chưa có giá bán"}">${icons.cart}<span class="sr-only">${priced ? "Thêm vào giỏ" : "Chưa mở bán"}</span></button></div>
      <div class="product-info"><h3 title="${escape(gameName(game.name))}">${title(game)}</h3>
      ${price(game)}<div class="product-actions"><button class="store-button product-detail offer-button" type="button" data-product="${escape(game.slug)}">${game.discountPercent > 0 ? "Xem ưu đãi" : "Xem chi tiết"}</button></div></div></article>`;
  }
  function skeleton(count = 6) {
    return `<div class="product-grid">${Array.from({ length: count }, () => '<div class="product-card skeleton" aria-hidden="true"><div class="skeleton-art"></div><div class="skeleton-info"><i></i><i></i><i></i></div></div>').join("")}</div><span class="sr-only">Đang tải game…</span>`;
  }
  function empty(title, message, retry) {
    return `<div class="store-empty">${icons.game}<h3>${escape(title)}</h3><p>${escape(message)}</p>${retry ? `<button class="store-button" type="button" data-retry="${retry}">${icons.refresh}Thử lại</button>` : ""}</div>`;
  }
  function alive(s) {
    return active === s && s.generation === generation;
  }
  function nav(label, icon, route) {
    return `<button type="button" class="nav-item" aria-label="${label}${route ? "" : " — sắp có"}" ${route ? `data-store-nav="${route}"` : 'disabled title="Sắp có"'}>${icons[icon]}<span>${label}</span>${route ? "" : "<small>Sắp có</small>"}</button>`;
  }
  function syncSaleArrows(s) {
    if (!alive(s)) return;
    const rail = s.host.querySelector("[data-sale-scroll]");
    if (!rail) return;
    s.host.querySelector("[data-sale-prev]").disabled = rail.scrollLeft <= 1;
    s.host.querySelector("[data-sale-next]").disabled = rail.scrollLeft + rail.clientWidth >= rail.scrollWidth - 2;
  }
  function renderSaleRow(s) {
    const host = s.host.querySelector("[data-hero]");
    host.hidden = s.route !== "home" || Boolean(s.detail || s.commerceView);
    if (host.hidden) return;
    const source = s.home?.saleGames ?? [...(s.home?.banners || []).map(banner => banner.game), ...(s.home?.featuredGames || [])];
    const games = [...new Map(source.filter(game => game?.slug && Number.isFinite(game.currentPrice)
      && game.currentPrice >= 0 && game.originalPrice > game.currentPrice && game.discountPercent > 0)
      .map(game => [game.gameId, game])).values()];
    const signature = JSON.stringify([games, [...s.favorites], Boolean(s.home)]);
    if (s.saleSignature !== signature) {
      const left = host.querySelector("[data-sale-scroll]")?.scrollLeft || 0;
      const focusedFavorite = host.contains(document.activeElement) ? document.activeElement.dataset.favorite : null;
      host.innerHTML = `<div class="sale-heading"><h2>Game giảm giá</h2><div class="sale-controls"><button class="store-icon-button" type="button" data-sale-prev aria-label="Game giảm giá trước">${icons.chevron}</button><button class="store-icon-button" type="button" data-sale-next aria-label="Game giảm giá tiếp theo">${icons.chevron}</button><button class="store-text-button" type="button" data-sale-all>Xem tất cả ${icons.chevron}</button></div></div>
        <div class="sale-scroll" data-sale-scroll role="list" aria-label="Game đang giảm giá">${games.length ? games.map(game => `<article class="sale-poster" role="listitem" data-sale-game="${escape(game.gameId)}"><button type="button" class="sale-poster-link" data-product="${escape(game.slug)}" aria-label="${escape(gameName(game.name))}, ${money(game.currentPrice)}"><span class="art-fallback">${icons.game}</span>${image(game.portraitUrl, "", true, game.photoUrl)}<span class="sale-poster-shade"></span><span class="cover-discount">-${escape(game.discountPercent)}%</span><span class="sale-poster-copy"><span class="sale-poster-title">${title(game)}</span><del>${money(game.originalPrice)}</del><strong>${game.currentPrice === 0 ? "Miễn phí" : money(game.currentPrice)}</strong></span></button>${favoriteButton(game)}</article>`).join("") : !s.home ? '<div class="sale-placeholder" role="status"><span class="spinner"></span>Đang tải ưu đãi…</div>' : '<p class="sale-placeholder">Chưa có game giảm giá. Khám phá thêm trong cửa hàng.</p>'}</div>`;
      host.querySelector("[data-sale-scroll]").scrollLeft = left;
      if (focusedFavorite) [...host.querySelectorAll("[data-favorite]")]
        .find(button => button.dataset.favorite === focusedFavorite)?.focus({ preventScroll: true });
      s.saleSignature = signature;
    }
    requestAnimationFrame(() => syncSaleArrows(s));
  }
  function updateFilters(s) {
    s.host.querySelectorAll("[data-catalog-mode]").forEach(button =>
      button.setAttribute("aria-pressed", String(button.dataset.catalogMode === s.mode)));
    s.host.querySelectorAll("[data-sidebar-mode]").forEach(button => {
      const selected = !s.detail && !s.commerceView && button.dataset.sidebarMode === s.mode;
      if (selected) button.setAttribute("aria-current", "page");
      else button.removeAttribute("aria-current");
    });
    s.host.querySelector("[data-sort]").value = s.sort;
    s.host.querySelector("[data-sale-only]").checked = s.saleOnly;
  }
  function setMode(s, mode) {
    if (s.commerce?.busy) return;
    s.mode = mode;
    s.saleOnly = mode === "sale";
    s.sort = mode === "newest" ? "newest" : "recommended";
    updateFilters(s);
    go(s, "store", false);
  }
  function toggleFavorite(s, id) {
    if (s.favorites.has(id)) s.favorites.delete(id);
    else if (s.favorites.size >= 40) {
      s.commerce.toast("Bạn có thể lưu tối đa 40 game yêu thích trên máy này.");
      return;
    } else s.favorites.add(id);
    try { localStorage.setItem(s.favoriteKey, JSON.stringify([...s.favorites])); } catch { /* Session-only fallback. */ }
    renderSaleRow(s);
    s.host.querySelectorAll("[data-favorite]").forEach(button => {
      const selected = s.favorites.has(button.dataset.favorite);
      button.setAttribute("aria-pressed", String(selected));
      button.setAttribute("aria-label", button.getAttribute("aria-label").replace(/^(Bỏ yêu thích|Yêu thích)/, selected ? "Bỏ yêu thích" : "Yêu thích"));
    });
    if (s.mode === "favorites") void loadCatalog(s);
  }
  function connection(s, connected) {
    if (!alive(s)) return;
    const target = s.host.querySelector("[data-connection]");
    target.dataset.state = connected ? "online" : "offline";
    target.textContent = connected ? "Đã kết nối" : "Chưa kết nối máy chủ";
  }
  function setBalance(s, balance) {
    if (!alive(s)) return;
    const target = s.host.querySelector("[data-header-balance]");
    target.textContent = Number.isFinite(balance) ? money(balance) : "Chưa tải được";
  }
  async function refreshBalance(s) {
    const id = ++s.balanceRequest;
    try {
      const wallet = await s.request("wallet");
      if (alive(s) && id === s.balanceRequest) setBalance(s, wallet.balance);
    } catch {
      if (alive(s) && id === s.balanceRequest && s.host.querySelector("[data-header-balance]").textContent === "Đang tải…") setBalance(s, null);
    }
  }
  function showSettings(s) {
    if (s.commerce?.busy) return;
    const dialog = s.host.querySelector("[data-launcher-settings]");
    dialog.querySelector("[data-reduce-motion]").checked = document.body.dataset.reducedMotion === "true";
    dialog.showModal();
  }
  function renderCategories(s) {
    const select = s.host.querySelector("[data-category]");
    select.innerHTML =
      '<option value="">Tất cả thể loại</option>' +
      (s.home?.categories || [])
        .map(
          (c) => `<option value="${escape(c.slug)}">${escape(c.name)}</option>`,
        )
        .join("");
    select.value = s.category;
  }
  function scheduleHomeFeed(s) {
    if (!alive(s) || s.feedFrame) return;
    s.feedFrame = requestAnimationFrame(() => {
      s.feedFrame = null;
      const feed = s.homeFeed;
      if (!alive(s) || document.hidden || s.pageHidden || s.route !== "home"
        || !s.home || s.homeLoading || s.detail || s.commerceView
        || s.search || s.category || feed.loading || feed.error
        || feed.nextOffset === null) return;
      const scroll = s.host.querySelector(".store-scroll");
      const footer = s.host.querySelector("[data-feed-footer]");
      const viewport = scroll.getBoundingClientRect();
      const end = footer.getBoundingClientRect();
      if (scroll.scrollTop > 0) feed.started = true;
      if (!feed.started && scroll.scrollHeight > scroll.clientHeight + 2) return;
      if (viewport.height > 0 && footer.getClientRects().length
        && end.bottom >= viewport.top && end.top <= viewport.bottom + 400)
        void loadHomeFeed(s);
    });
  }
  function showHomeFeed(s) {
    if (s.route !== "home") return;
    s.games = s.homeFeed.games;
    s.total = s.homeFeed.total;
    s.nextOffset = s.homeFeed.nextOffset;
    s.loading = s.homeFeed.loading || (!s.home && s.homeLoading);
    s.error = s.homeFeed.error;
    renderProducts(s);
  }
  function renderProducts(s) {
    const target = s.host.querySelector("[data-products]");
    const footer = s.host.querySelector("[data-feed-footer]");
    const status = s.host.querySelector("[data-store-status]");
    s.host.querySelector("[data-section-title]").textContent =
      s.mode === "favorites" ? "Game yêu thích" : s.saleOnly ? "Game đang giảm giá" : "Danh sách trò chơi";
    s.host.querySelector("[data-see-store]").hidden = s.route !== "home";
    s.host.querySelector("[data-result-count]").textContent = s.loading
      ? "Đang tải…"
      : s.route === "store" && !s.error
        ? `${s.total} game`
        : "";
    target.setAttribute("aria-busy", String(s.loading));
    if (s.loading && !s.games.length) target.innerHTML = skeleton();
    else if (s.error && !s.games.length)
      target.innerHTML = empty("Chưa tải được game", s.error, "products");
    else if (!s.games.length)
      target.innerHTML = empty(
        s.search || s.category
          ? "Không tìm thấy game"
          : "Kho game đang được cập nhật",
        s.search || s.category
          ? "Thử từ khóa khác hoặc chọn thể loại khác."
          : "Ghé lại sau để khám phá các tựa game mới.",
      );
    else {
      const grid = target.querySelector(".product-grid");
      // Keep existing cards mounted when adding a page, including focus and images.
      if (grid && s.renderedRoute === s.route && s.renderedGames
        && s.renderedGames.length <= s.games.length
        && s.renderedGames.every((game, index) => game === s.games[index]))
        grid.insertAdjacentHTML("beforeend", s.games.slice(s.renderedGames.length).map(product).join(""));
      else
        target.innerHTML = `<div class="product-grid">${s.games.map(product).join("")}</div>`;
    }
    s.renderedGames = s.games.length ? s.games.slice() : null;
    s.renderedRoute = s.route;
    footer.innerHTML =
      s.error && s.games.length
        ? `<p class="feed-error">${escape(s.error)}</p><button type="button" class="store-button" data-retry="more">${icons.refresh}Thử lại</button>`
        : s.route === "store" && s.nextOffset !== null
          ? `<button class="store-button" type="button" data-load-more ${s.loading ? "disabled" : ""}>${s.loading ? '<span class="spinner"></span>Đang tải…' : "Tải thêm game" + icons.arrow}</button>`
          : s.route === "home" && s.home && s.nextOffset !== null
            ? `<span>${s.loading ? '<span class="spinner"></span>Đang tải thêm game…' : "Cuộn xuống để xem thêm game."}</span>`
          : s.games.length && (s.route === "store" || s.home)
            ? "<p>Bạn đã xem hết danh sách game.</p>"
            : "";
    status.textContent = s.loading
      ? "Đang tải game"
      : s.error || `${s.games.length} game đã hiển thị`;
    scheduleHomeFeed(s);
  }
  function updateRoute(s) {
    s.host.querySelector("h1").textContent = s.commerceView
      ? {
          cart: "Giỏ hàng",
          orders: "Đơn hàng",
          order: "Chi tiết đơn hàng",
          wallet: "Ví DC",
          topup: "Nạp ví DC",
          library: "Thư viện",
          "library-detail": "Chi tiết game",
        }[s.commerceView]
      : s.detail
        ? "Chi tiết game"
        : s.route === "home"
          ? "Trang chủ"
          : "Cửa hàng";
    s.host.querySelector(".store-header").hidden = [
      "library",
      "library-detail",
    ].includes(s.commerceView);
    s.host.querySelectorAll(".nav-item[data-store-nav]").forEach((b) => {
      if (
        b.dataset.storeNav ===
        (s.commerceView
          ? ["library", "library-detail"].includes(s.commerceView)
            ? "library"
            : ["wallet", "topup"].includes(s.commerceView)
              ? "wallet"
              : s.commerceView === "cart"
                ? "cart"
                : "orders"
          : s.detail
            ? "store"
            : s.route)
      )
        b.setAttribute("aria-current", "page");
      else b.removeAttribute("aria-current");
    });
    renderSaleRow(s);
    updateFilters(s);
    scheduleHomeFeed(s);
  }
  async function loadHome(s) {
    if (s.homeLoading) return;
    s.homeLoading = true;
    const notice = s.host.querySelector("[data-home-notice]");
    notice.hidden = true;
    if (!s.home) showHomeFeed(s);
    try {
      const home = await s.request("store-home");
      if (!alive(s)) return;
      if (!s.home) {
        s.homeFeed.games = [...new Map((home.featuredGames || []).map((game) => [game.gameId, game])).values()];
        s.homeFeed.total = s.homeFeed.games.length;
      }
      s.home = home;
      connection(s, true);
      renderCategories(s);
      renderSaleRow(s);
      if (s.route === "home") {
        showHomeFeed(s);
      }
    } catch (error) {
      if (!alive(s)) return;
      connection(s, false);
      notice.innerHTML = `<span>${escape(error.message)}</span><button class="store-text-button" type="button" data-retry="home">${icons.refresh}Thử lại</button>`;
      notice.hidden = false;
      if (s.route === "home") {
        s.loading = false;
        s.error = error.message;
        renderProducts(s);
      }
    } finally {
      if (alive(s)) {
        s.homeLoading = false;
        scheduleHomeFeed(s);
      }
    }
  }
  async function loadHomeFeed(s) {
    const feed = s.homeFeed;
    if (!alive(s) || !s.home || feed.loading || feed.nextOffset === null) return;
    const offset = feed.nextOffset;
    feed.loading = true;
    feed.error = "";
    showHomeFeed(s);
    try {
      const data = await s.request("store-games", { search: "", category: "", offset });
      if (!alive(s)) return;
      connection(s, true);
      const seen = new Set(feed.games.map((game) => game.gameId));
      for (const game of data.games) {
        if (seen.has(game.gameId)) continue;
        seen.add(game.gameId);
        feed.games.push(game);
      }
      feed.total = data.totalResults;
      feed.nextOffset = Number.isSafeInteger(data.nextOffset) && data.nextOffset > offset
        ? data.nextOffset : null;
    } catch (error) {
      if (alive(s)) { feed.error = error.message; connection(s, false); }
    } finally {
      if (alive(s)) {
        feed.loading = false;
        showHomeFeed(s);
      }
    }
  }
  async function loadCatalog(s, append = false) {
    const id = ++s.requestId;
    const offset = append ? s.nextOffset : 0;
    if (offset === null) return;
    s.loading = true;
    s.error = "";
    if (!append) {
      s.games = [];
      s.nextOffset = null;
    }
    renderProducts(s);
    if (s.mode === "favorites" && !s.favorites.size) {
      s.loading = false;
      s.total = 0;
      s.nextOffset = null;
      renderProducts(s);
      return;
    }
    try {
      const data = await s.request("store-games", {
        search: s.search,
        category: s.category,
        sort: s.sort,
        saleOnly: s.saleOnly,
        featuredOnly: s.mode === "featured",
        vietnameseOnly: s.mode === "vietnamese",
        ...(s.mode === "favorites" ? { gameIds: [...s.favorites].join(",") } : {}),
        offset,
      });
      if (!alive(s) || id !== s.requestId || s.route !== "store") return;
      connection(s, true);
      s.games = [
        ...new Map(
          (append ? s.games.concat(data.games) : data.games).map((g) => [
            g.gameId,
            g,
          ]),
        ).values(),
      ];
      s.total = data.totalResults;
      s.nextOffset = data.nextOffset ?? null;
    } catch (error) {
      if (!alive(s) || id !== s.requestId) return;
      s.error = error.message;
      connection(s, false);
    } finally {
      if (alive(s) && id === s.requestId) {
        s.loading = false;
        renderProducts(s);
      }
    }
  }
  function go(s, route, reset = true) {
    if (s.commerce?.busy) return;
    if (["cart", "orders", "wallet", "library"].includes(route)) {
      void s.commerce.open(route);
      return;
    }
    s.commerce?.close();
    s.commerceView = null;
    s.host.querySelector("[data-listing]").hidden = false;
    closeDetail(s, false);
    clearTimeout(s.searchTimer);
    s.route = route;
    ++s.requestId;
    if (reset) {
      s.search = "";
      s.category = "";
      s.mode = "all";
      s.saleOnly = false;
      s.sort = "recommended";
      s.host.querySelector("[data-search]").value = "";
      s.host.querySelector("[data-category]").value = "";
    }
    s.host.querySelector(".store-scroll").scrollTop = 0;
    updateRoute(s);
    if (route === "store") void loadCatalog(s);
    else {
      showHomeFeed(s);
      if (!s.home) void loadHome(s);
    }
  }
  function closeDetail(s, restore = true) {
    if (!s.detail) return;
    s.detail.dispose();
    s.detail = null;
    s.host.querySelector("[data-detail]").hidden = true;
    s.host.querySelector("[data-listing]").hidden = false;
    if (restore) {
      updateRoute(s);
      const focus = s.returnFocus?.isConnected
        ? s.returnFocus
        : s.host.querySelector("[data-product]");
      focus?.focus({ preventScroll: true });
      s.host.querySelector(".store-scroll").scrollTop = s.returnScroll;
    }
  }
  function openDetail(s, slug, button) {
    if (s.commerce?.busy) return;
    s.commerce?.close();
    s.commerceView = null;
    if (!slug) return;
    clearTimeout(s.searchTimer);
    const scroll = s.host.querySelector(".store-scroll");
    if (!s.detail) {
      s.returnScroll = scroll.scrollTop;
      s.returnFocus = button;
    } else s.detail.dispose();
    s.host.querySelector("[data-listing]").hidden = true;
    const panel = s.host.querySelector("[data-detail]");
    panel.hidden = false;
    s.detail = window.LauncherProduct.mount(panel, {
      slug,
      request: s.request,
      onBack: () => closeDetail(s),
      onPurchase: (versionId, buyNow) => s.commerce.add(versionId, buyNow),
      onLibrary: (versionId) => s.commerce.open("library-detail", versionId),
      helpers: { escape, image, imageUrl, price, icons },
    });
    updateRoute(s);
    scroll.scrollTop = 0;
  }
  function mount(host, { request, user, onPasswordChanged }) {
    const s = {
      host,
      request,
      home: null,
      homeLoading: false,
      homeFeed: { games: [], total: 0, nextOffset: 0, loading: false, error: "" },
      feedFrame: null,
      feedObserver: null,
      generation,
      route: "home",
      search: "",
      category: "",
      mode: "all",
      sort: "recommended",
      saleOnly: false,
      balanceRequest: 0,
      favorites: new Set(),
      games: [],
      total: 0,
      nextOffset: null,
      loading: true,
      error: "",
      requestId: 0,
      pageHidden: false,
      searchTimer: null,
      detail: null,
      events: new AbortController(),
    };
    active = s;
    const storageKey = kind => `dc-launcher-${kind}:${window.dcLauncherInfo?.apiOrigin || location.origin}:${user.id || user.email}`;
    const restorePreferences = () => {
      s.favoriteKey = storageKey("favorites");
      s.motionKey = storageKey("motion");
      try {
        const stored = JSON.parse(localStorage.getItem(s.favoriteKey));
        s.favorites = new Set(Array.isArray(stored) ? stored.filter(id => typeof id === "string" && id.length <= 64).slice(0, 40) : []);
        document.body.dataset.reducedMotion = localStorage.getItem(s.motionKey) === "true" ? "true" : "false";
      } catch { s.favorites = new Set(); }
    };
    restorePreferences();
    host.innerHTML = `<header class="launcher-topbar"><div class="launcher-wordmark"><img src="images/dc-monogram-reference-v1.webp" alt="" width="72" height="48"><span>DC GAMING</span></div>
      <nav class="header-main-nav" aria-label="Điều hướng chính">${nav("Trang chủ", "home", "home")}${nav("Cửa hàng", "cart", "store")}${nav("Thư viện", "library", "library")}</nav>
      <div class="launcher-header-tools"><button class="store-icon-button header-cart nav-item" type="button" data-store-nav="cart" aria-label="Mở giỏ hàng">${icons.cart}<b class="cart-badge" data-cart-count hidden>0</b></button>
      <button class="header-wallet nav-item" type="button" data-store-nav="wallet">${icons.wallet}<span><small>Ví DC</small><strong data-header-balance>Đang tải…</strong></span></button>
      ${window.LauncherAccount.markup(user, { escape })}</div></header>
      <aside class="launcher-sidebar"><nav class="sidebar-nav" aria-label="Khám phá cửa hàng"><button class="nav-item" type="button" data-sidebar-mode="all">${icons.grid}<span>Khám phá</span></button><button class="nav-item" type="button" data-sidebar-mode="sale">${icons.tag}<span>Ưu đãi</span></button><button class="nav-item" type="button" data-sidebar-mode="vietnamese">${icons.game}<span>Việt hóa</span></button><button class="nav-item" type="button" data-sidebar-mode="favorites">${icons.heart}<span>Yêu thích</span></button>${nav("Đơn hàng", "order", "orders")}${window.LauncherSteamConnection.markup()}</nav>
      <div class="sidebar-bottom"><button class="nav-item" type="button" data-command="open-support">${icons.support}<span>Hỗ trợ</span></button><button class="nav-item" type="button" data-settings>${icons.settings}<span>Cài đặt</span></button><button class="sidebar-logout" type="button" data-logout>${icons.logout}<span>Đăng xuất</span></button></div></aside>
      <div class="launcher-content"><header class="store-header"><h1 class="sr-only">Trang chủ</h1><form class="store-search" role="search">${icons.search}<input type="search" data-search maxlength="120" placeholder="Tìm kiếm game…" aria-label="Tìm kiếm game" autocomplete="off"><button type="submit" aria-label="Tìm kiếm">${icons.arrow}</button></form><label class="toolbar-category"><span class="sr-only">Thể loại game</span><select data-category aria-label="Thể loại game"><option value="">Tất cả thể loại</option></select></label><button class="store-button offer-button" type="button" data-filter-open>${icons.filter}Bộ lọc</button></header>
      <div class="store-scroll"><div data-listing><div class="home-notice" data-home-notice role="alert" hidden></div><section class="sale-section" data-hero aria-label="Game giảm giá" hidden></section>
      <section class="store-catalog" aria-labelledby="catalog-title"><div class="catalog-heading"><div class="catalog-title"><h2 id="catalog-title" data-section-title>Danh sách trò chơi</h2><span class="result-count" data-result-count></span></div><div class="catalog-tabs" role="group" aria-label="Lọc danh sách game"><button type="button" data-catalog-mode="all" aria-pressed="true">Tất cả</button><button type="button" data-catalog-mode="featured" aria-pressed="false">Nổi bật</button><button type="button" data-catalog-mode="newest" aria-pressed="false">Mới cập nhật</button><button type="button" data-catalog-mode="vietnamese" aria-pressed="false">Việt hóa</button></div><label class="catalog-sort"><span class="sr-only">Sắp xếp game</span><select data-sort aria-label="Sắp xếp game"><option value="recommended">Đề xuất</option><option value="popular">Phổ biến</option><option value="newest">Mới cập nhật</option><option value="price-asc">Giá tăng dần</option><option value="price-desc">Giá giảm dần</option></select></label><button class="sr-only" type="button" data-see-store>Xem cửa hàng</button></div><div data-products></div><div class="feed-footer" data-feed-footer></div></section>
      </div><section class="product-page" data-detail aria-label="Chi tiết sản phẩm" hidden></section><section class="commerce-page" data-commerce aria-label="Giỏ hàng và thanh toán" hidden></section></div><div class="sr-only" data-store-status role="status" aria-live="polite"></div></div>
      <footer class="launcher-statusbar"><span data-connection data-state="loading" role="status">Đang kết nối…</span><span>DC Gaming <span data-launcher-version></span></span></footer><div class="commerce-toast" data-commerce-toast role="status" aria-live="polite" hidden></div>
      <dialog class="commerce-dialog launcher-preferences" data-launcher-settings aria-labelledby="launcher-settings-title"><div class="commerce-dialog-heading"><h2 id="launcher-settings-title">Cài đặt hiển thị</h2><button type="button" class="store-icon-button" data-preferences-close aria-label="Đóng cài đặt">×</button></div><label class="preferences-row"><span>Giảm chuyển động<small>Hạn chế hiệu ứng khi duyệt cửa hàng.</small></span><input type="checkbox" data-reduce-motion></label><p class="preferences-note">Game yêu thích được lưu theo tài khoản trên máy này. Tối đa 40 game.</p><button class="store-button" type="button" data-command="open-website">Mở website DC Gaming ${icons.arrow}</button></dialog>
      <dialog class="commerce-dialog launcher-filter" data-launcher-filter aria-labelledby="launcher-filter-title"><div class="commerce-dialog-heading"><h2 id="launcher-filter-title">Bộ lọc game</h2><button type="button" class="store-icon-button" data-filter-close aria-label="Đóng bộ lọc">×</button></div><label class="preferences-row"><span>Chỉ game đang giảm giá</span><input type="checkbox" data-sale-only></label><p class="preferences-note">Kết hợp cùng từ khóa, thể loại và cách sắp xếp đang chọn.</p><div class="commerce-dialog-actions"><button class="store-button" type="button" data-filter-reset>Xóa bộ lọc</button><button class="store-button offer-button" type="button" data-filter-apply>Áp dụng</button></div></dialog>`;
    const showVersion = () => {
      const version = window.dcLauncherInfo?.version;
      host.querySelector("[data-launcher-version]").textContent = version ? `• v${version}` : "";
    };
    showVersion();
    window.addEventListener("dc-launcher-info", () => {
      if (!alive(s)) return;
      restorePreferences();
      showVersion();
      renderSaleRow(s);
      if (s.mode === "favorites") void loadCatalog(s);
    }, { signal: s.events.signal });
    s.commerce = window.LauncherCommerce.create({
      host,
      request: s.request,
      user,
      onBalance: balance => { ++s.balanceRequest; setBalance(s, balance); },
      onWalletRefresh: () => void refreshBalance(s),
      helpers: { escape, image, imageUrl, money, icons },
      onCount: (count) => {
        const badge = host.querySelector("[data-cart-count]");
        badge.textContent = count;
        badge.hidden = count === 0;
        host
          .querySelector(".header-cart")
          .setAttribute("aria-label", `Giỏ hàng, ${count} sản phẩm`);
      },
      onOpen: (view) => {
        clearTimeout(s.searchTimer);
        if (!s.commerceView && !s.detail)
          s.commerceScroll = host.querySelector(".store-scroll").scrollTop;
        closeDetail(s, false);
        s.commerceView = view;
        host.querySelector("[data-listing]").hidden = true;
        updateRoute(s);
        host.querySelector(".store-scroll").scrollTop = 0;
      },
      onClose: () => {
        s.commerceView = null;
        void refreshBalance(s);
        host.querySelector("[data-listing]").hidden = false;
        updateRoute(s);
        host.querySelector(".store-scroll").scrollTop = s.commerceScroll || 0;
        host.querySelector(".header-cart").focus({ preventScroll: true });
      },
    });
    s.account = window.LauncherAccount.create({
      host, user, request: s.request, helpers: { escape },
      toast: (...args) => s.commerce.toast(...args),
      isBlocked: () => s.commerce.busy || host.querySelector("[data-logout]").disabled,
      onPasswordChanged,
    });
    s.steamConnection = window.LauncherSteamConnection.create({ host, request: s.request, toast: (...args) => s.commerce.toast(...args) });
    const options = { signal: s.events.signal };
    document.addEventListener("pointerdown", event => {
      const account = host.querySelector(".launcher-account");
      if (!account.contains(event.target)) account.open = false;
    }, options);
    host.addEventListener("keydown", event => {
      const account = host.querySelector(".launcher-account");
      if (event.key === "Escape" && account.open) {
        account.open = false;
        account.querySelector("summary").focus();
      }
    }, options);
    document.addEventListener("visibilitychange", () => { syncSaleArrows(s); scheduleHomeFeed(s); }, options);
    window.addEventListener("pagehide", () => { s.pageHidden = true; }, options);
    window.addEventListener("pageshow", () => { s.pageHidden = false; syncSaleArrows(s); scheduleHomeFeed(s); }, options);
    window.addEventListener("resize", () => { syncSaleArrows(s); scheduleHomeFeed(s); }, options);
    const scroll = host.querySelector(".store-scroll");
    if (window.IntersectionObserver) {
      s.feedObserver = new IntersectionObserver(() => scheduleHomeFeed(s), {
        root: scroll,
        rootMargin: "0px 0px 400px 0px",
      });
      s.feedObserver.observe(host.querySelector("[data-feed-footer]"));
    }
    scroll.addEventListener("scroll", () => scheduleHomeFeed(s), { ...options, passive: true });
    host.addEventListener(
      "click",
      (event) => {
        const button = event.target.closest("button");
        if (!button || button.disabled) return;
        if (button.dataset.favorite) {
          event.preventDefault();
          toggleFavorite(s, button.dataset.favorite);
        } else if (button.dataset.catalogMode) setMode(s, button.dataset.catalogMode);
        else if (button.dataset.sidebarMode) {
          if (button.dataset.sidebarMode === "all") go(s, "home");
          else setMode(s, button.dataset.sidebarMode);
        } else if (button.hasAttribute("data-sale-all")) setMode(s, "sale");
        else if (button.hasAttribute("data-sale-prev") || button.hasAttribute("data-sale-next")) {
          const rail = host.querySelector("[data-sale-scroll]");
          const direction = button.hasAttribute("data-sale-prev") ? -1 : 1;
          rail?.scrollBy({ left: direction * rail.clientWidth * .85, behavior: document.body.dataset.reducedMotion === "true" || matchMedia("(prefers-reduced-motion: reduce)").matches ? "instant" : "smooth" });
        } else if (button.hasAttribute("data-settings")) showSettings(s);
        else if (button.hasAttribute("data-preferences-close")) host.querySelector("[data-launcher-settings]").close();
        else if (button.hasAttribute("data-filter-open")) {
          host.querySelector("[data-sale-only]").checked = s.saleOnly;
          host.querySelector("[data-launcher-filter]").showModal();
        } else if (button.hasAttribute("data-filter-close")) host.querySelector("[data-launcher-filter]").close();
        else if (button.hasAttribute("data-filter-reset")) {
          s.mode = "all"; s.saleOnly = false; s.sort = "recommended";
          host.querySelector("[data-launcher-filter]").close();
          go(s, "store");
        } else if (button.hasAttribute("data-filter-apply")) {
          s.saleOnly = host.querySelector("[data-sale-only]").checked;
          if (s.mode === "sale" && !s.saleOnly) s.mode = "all";
          host.querySelector("[data-launcher-filter]").close();
          go(s, "store", false);
        } else if (button.dataset.addProduct) {
          // The explicit card action wins over a pending search navigation.
          // Otherwise its debounce can close the version picker mid-request.
          clearTimeout(s.searchTimer);
          void s.commerce.choose(button.dataset.addProduct);
        }
        else if (button.dataset.product)
          openDetail(s, button.dataset.product, button);
        else if (button.dataset.storeNav) { host.querySelector(".launcher-account").open = false; go(s, button.dataset.storeNav); }
        else if (button.hasAttribute("data-account-orders")) { host.querySelector(".launcher-account").open = false; go(s, "orders"); }
        else if (button.hasAttribute("data-load-more") && !s.loading)
          void loadCatalog(s, true);
        else if (button.dataset.retry) {
          if (button.dataset.retry === "home" || (s.route === "home" && !s.home))
            void loadHome(s);
          else if (s.route === "home") void loadHomeFeed(s);
          else void loadCatalog(s, button.dataset.retry === "more");
        }
      },
      options,
    );
    host.addEventListener(
      "input",
      (event) => {
        if (!event.target.matches("[data-search]")) return;
        s.search = event.target.value.trim();
        clearTimeout(s.searchTimer);
        // Invalidate outstanding responses immediately, before the debounce delay.
        ++s.requestId;
        s.searchTimer = setTimeout(() => go(s, "store", false), 300);
      },
      options,
    );
    host.addEventListener(
      "change",
      (event) => {
        if (event.target.matches("[data-reduce-motion]")) {
          document.body.dataset.reducedMotion = String(event.target.checked);
          try { localStorage.setItem(s.motionKey, String(event.target.checked)); } catch { /* Session-only preference. */ }
        } else if (event.target.matches("[data-sort]")) {
          s.sort = event.target.value;
          if (s.mode === "newest" && s.sort !== "newest") s.mode = "all";
          go(s, "store", false);
        } else if (event.target.matches("[data-category]")) {
          s.category = event.target.value;
          go(s, "store", false);
        }
      },
      options,
    );
    host.addEventListener(
      "submit",
      (event) => {
        if (!event.target.matches(".store-search")) return;
        event.preventDefault();
        event.stopPropagation();
        s.search = host.querySelector("[data-search]").value.trim();
        go(s, "store", false);
      },
      options,
    );
    host.addEventListener(
      "error",
      (event) => {
        if (event.target instanceof HTMLImageElement) {
          const target = event.target;
          const fallback = imageUrl(target.dataset.fallbackSrc);
          delete target.dataset.fallbackSrc;
          if (fallback && fallback !== target.src) {
            target.hidden = false;
            target.src = fallback;
          } else target.hidden = true;
        }
      },
      { ...options, capture: true },
    );
    host.addEventListener("scroll", event => {
      if (event.target.matches?.("[data-sale-scroll]")) syncSaleArrows(s);
    }, { ...options, capture: true });
    updateRoute(s);
    renderProducts(s);
    void refreshBalance(s);
    void loadHome(s);
    void s.commerce.refreshCount();
  }
  function unmount() {
    generation++;
    if (active) {
      active.host.querySelectorAll("dialog[open]").forEach(dialog => dialog.close());
      clearTimeout(active.searchTimer);
      cancelAnimationFrame(active.feedFrame);
      active.feedObserver?.disconnect();
      active.detail?.dispose();
      active.commerce?.dispose();
      active.account?.dispose();
      active.steamConnection?.dispose();
      active.events.abort();
    }
    active = null;
  }
  window.LauncherStore = { mount, unmount, notify: (message, error) => active?.commerce?.toast(message, error) };
})();
