(() => {
  "use strict";
  const gameNames = window.DCGameNames;
  const gameName = gameNames.display;

  // Rebuild editorial text with a small set of inert elements. Never copy HTML
  // attributes, links, frames or raw media sources into the trusted WebView.
  function richText(raw, resolveImage = null, resolveVideo = null, nameContext = null) {
    const template = document.createElement("template");
    template.innerHTML = String(raw || "");
    const allowed = new Set([
      "P",
      "DIV",
      "SPAN",
      "BR",
      "STRONG",
      "B",
      "EM",
      "I",
      "U",
      "S",
      "H2",
      "H3",
      "H4",
      "UL",
      "OL",
      "LI",
      "BLOCKQUOTE",
      "HR",
      "FIGURE",
      "FIGCAPTION",
      "CODE",
      "PRE",
    ]);
    const blocked = new Set([
      "SCRIPT",
      "STYLE",
      "IFRAME",
      "OBJECT",
      "EMBED",
      "SVG",
      "MATH",
      "FORM",
      "INPUT",
      "BUTTON",
      "TEMPLATE",
      "VIDEO",
      "SOURCE",
    ]);
    const output = document.createElement("div");
    function copy(from, to) {
      for (const node of from.childNodes) {
        if (node.nodeType === Node.TEXT_NODE)
          to.append(document.createTextNode(node.textContent));
        else if (
          node.nodeType === Node.ELEMENT_NODE &&
          !blocked.has(node.tagName)
        ) {
          if (node.tagName === "IMG" && resolveImage) {
            const index = node.getAttribute("data-steam-image");
            if (/^(0|[1-9][0-9]?)$/.test(index || "")) {
              const img = resolveImage(Number(index));
              if (img) to.append(img);
            }
          } else if (allowed.has(node.tagName)) {
            const element = document.createElement(node.tagName.toLowerCase());
            copy(node, element);
            to.append(element);
          } else copy(node, to);
        }
      }
    }
    copy(template.content, output);
    if (nameContext?.name)
      gameNames.replaceTextNodes(output, nameContext.name, nameContext.steamName);
    return output.innerHTML;
  }

  function metadataRows(metadata, escape) {
    if (!metadata) return "";
    const names = values => Array.isArray(values)
      ? [...new Set(values.filter(value => typeof value === "string" && value.trim()).map(value => value.trim()))].join(" · ") : "";
    const release = typeof metadata.releaseDate === "string" ? metadata.releaseDate.trim() : "";
    return [
      ["Sản phẩm", metadata.name ? gameName(metadata.name) : ""],
      ["Nhà phát triển", names(metadata.developers)],
      ["Nhà phát hành", names(metadata.publishers)],
      ["Phát hành", metadata.comingSoon === true ? release ? `${release} · Sắp phát hành` : "Sắp phát hành" : release],
      ["Thể loại", names(metadata.genres)],
      ["Hệ điều hành", names(metadata.platforms)],
    ].filter(([, value]) => value).map(([label, value]) => `<div><dt>${escape(label)}</dt><dd>${escape(value)}</dd></div>`).join("");
  }

  function mount(
    host,
    { slug, request, onBack, onPurchase, onLibrary, helpers },
  ) {
    const { escape, image, imageUrl, price, icons } = helpers;
    const events = new AbortController();
    const options = { signal: events.signal };
    let disposed = false,
      requestId = 0,
      game = null,
      gallery = [],
      selectedImage = 0;
    let ownership = { ownedVersionIds: [], pendingVersionIds: [] };
    const tabs = [
      ["intro", "Giới thiệu"],
      ["images", "Hình ảnh"],
      ["requirements", "Cấu hình"],
    ];
    const fallback = `<span class="art-fallback">${icons.game}<span>DC GAMING</span></span>`;
    const placeholder = (message) =>
      `<p class="detail-placeholder">${escape(message)}</p>`;

    function frame(content, name = "Chi tiết sản phẩm") {
      host.innerHTML = `<nav class="detail-breadcrumb" aria-label="Vị trí trang"><button type="button" class="store-text-button detail-back" data-detail-back>${icons.arrow}Quay lại</button><span class="breadcrumb-divider">/</span><span class="breadcrumb-name">${escape(name)}</span></nav>${content}`;
    }
    function description(value) {
      const content = richText(value?.html, (index) => {
        const item = value?.images?.[index];
        const source = imageUrl(item?.imageUrl);
        if (!source) return null;
        const img = document.createElement("img");
        img.src = source;
        img.alt = item.alt || "Hình ảnh sản phẩm";
        img.loading = "lazy";
        img.decoding = "async";
        return img;
      });
      return content.trim()
        ? '<div class="steam-description" data-local-description>' + content + '</div>'
        : placeholder("Mô tả sản phẩm đang được cập nhật.");
    }

    function requirements() {
      const minimum = richText(game.minimumRequirementsHtml);
      const recommended = richText(game.recommendedRequirementsHtml);
      if (!minimum.trim() && !recommended.trim())
        return placeholder("Cấu hình yêu cầu đang được cập nhật.");
      return `<p class="requirements-source">Cấu hình PC</p><div class="requirements-grid"><section><h3>Tối thiểu</h3>${minimum || placeholder("Đang cập nhật.")}</section><section><h3>Đề nghị</h3>${recommended || placeholder("Đang cập nhật.")}</section></div>`;
    }
    function renderGallery() {
      const target = host.querySelector("[data-gallery-stage]");
      target.innerHTML =
        fallback +
        (gallery.length
          ? image(gallery[selectedImage].imageUrl, "detail-main-image", false)
          : "");
      const img = target.querySelector("img");
      if (img) img.alt = `${gameName(game.name)} — ảnh ${selectedImage + 1}`;
      host.querySelector("[data-gallery-count]").textContent = gallery.length
        ? `${selectedImage + 1} / ${gallery.length}`
        : "Chưa có hình ảnh";
      host
        .querySelectorAll("[data-gallery-index]")
        .forEach((b) =>
          b.setAttribute(
            "aria-pressed",
            String(Number(b.dataset.galleryIndex) === selectedImage),
          ),
        );
      host.querySelector("[data-gallery-previous]").disabled =
        selectedImage === 0;
      host.querySelector("[data-gallery-next]").disabled =
        selectedImage >= gallery.length - 1;
    }
    function selectImage(index) {
      if (!Number.isInteger(index) || index < 0 || index >= gallery.length)
        return;
      selectedImage = index;
      renderGallery();
    }
    function renderPrice() {
      const id = host.querySelector("[data-version]")?.value;
      const version = game.versions.find((v) => v.versionId === id);
      host.querySelector("[data-detail-price]").innerHTML = price(
        version || { steamPrice: game.steamPrice },
      );
      host.querySelector("[data-sale-name]").textContent =
        version?.saleName && version.discountPercent > 0
          ? version.saleName
          : "";
      const owned = ownership.ownedVersionIds.includes(id);
      const pending = ownership.pendingVersionIds.includes(id);
      const buy = host.querySelector("[data-buy-now]");
      const add = host.querySelector("[data-add-to-cart]");
      buy.innerHTML = `${owned || pending ? "Vào thư viện" : version ? "Mua ngay" : "Chưa mở bán"}${icons.arrow}`;
      buy.disabled = !version;
      add.disabled = !version || owned || pending;
      add.innerHTML = `${icons.cart}${owned ? "Đã sở hữu" : pending ? "Đã mua · Đang giao" : "Thêm vào giỏ"}`;
      host.querySelector(".detail-purchase-note").textContent = owned
        ? "Phiên bản này đã có trong thư viện của bạn."
        : pending
          ? "Bạn đã thanh toán phiên bản này. Theo dõi giao hàng trong thư viện."
          : "Chọn phiên bản và kiểm tra tổng tiền trước khi thanh toán.";
    }
    function render() {
      gallery = [{ imageUrl: game.photoUrl }, ...(game.gallery || [])]
        .filter((item) => imageUrl(item.imageUrl))
        .filter(
          (item, index, all) =>
            all.findIndex((other) => other.imageUrl === item.imageUrl) ===
            index,
        );
      selectedImage = 0;
      const versions = game.versions || [];
      game.versions = versions;
      const best = [...versions].sort(
        (a, b) => a.currentPrice - b.currentPrice,
      )[0];
      const categoryNames = (game.categories || [])
        .map((c) => c.name)
        .join(" · ");
      const thumbs = gallery
        .map(
          (item, i) =>
            `<button class="detail-thumbnail" type="button" data-gallery-index="${i}" aria-label="Xem ảnh ${i + 1}" aria-pressed="${i === 0}">${fallback}${image(imageUrl(item.thumbnailUrl) || item.imageUrl)}</button>`,
        )
        .join("");
      frame(
        `<div class="detail-grid"><section class="detail-media" aria-label="Hình ảnh sản phẩm"><div class="detail-stage" data-gallery-stage></div><div class="gallery-toolbar"><span data-gallery-count aria-live="polite"></span><div><button class="store-icon-button gallery-previous" type="button" data-gallery-previous aria-label="Ảnh trước">${icons.chevron}</button><button class="store-icon-button" type="button" data-gallery-next aria-label="Ảnh tiếp theo">${icons.chevron}</button></div></div><div class="detail-thumbnails">${thumbs}</div></section>
        <aside class="detail-purchase" aria-labelledby="product-title"><p class="eyebrow">DC Gaming / Game PC</p><h2 id="product-title" tabindex="-1">${escape(gameName(game.name))}</h2>${game.steamMetadata?.shortDescription ? `<p class="detail-categories">${escape(game.steamMetadata.shortDescription)}</p>` : ""}${categoryNames ? `<p class="detail-categories">${escape(categoryNames)}</p>` : ""}
        ${versions.length ? `<label class="detail-version-label" for="product-version">Chọn phiên bản</label><select id="product-version" data-version>${versions.map((v) => `<option value="${escape(v.versionId)}" ${v.versionId === best.versionId ? "selected" : ""}>${escape(v.name || "Tiêu chuẩn")}</option>`).join("")}</select>` : placeholder("Sản phẩm chưa có phiên bản đang mở bán.")}
        <div class="detail-price" data-detail-price></div><p class="detail-sale-name" data-sale-name></p>
        <div class="detail-purchase-actions"><button class="store-button store-primary" type="button" data-buy-now ${versions.length ? "" : "disabled"}>${versions.length ? "Mua ngay" : "Chưa mở bán"}${icons.arrow}</button><button class="store-button" type="button" data-add-to-cart ${versions.length ? "" : "disabled"}>${icons.cart}Thêm vào giỏ</button></div><p class="detail-purchase-note">Chọn phiên bản và kiểm tra tổng tiền trước khi thanh toán.</p>
        <dl class="detail-facts"><div><dt>Nền tảng</dt><dd>${game.steamAppId > 0 ? "Steam / PC" : "PC"}</dd></div>${categoryNames ? `<div><dt>Thể loại</dt><dd>${escape(categoryNames)}</dd></div>` : ""}${metadataRows(game.steamMetadata, escape)}<div><dt>Phiên bản</dt><dd>${versions.length ? versions.length + " lựa chọn" : "Đang cập nhật"}</dd></div></dl></aside>
        <section class="detail-information"><div class="detail-tabs" role="tablist" aria-label="Thông tin sản phẩm">${tabs.map(([id, label], i) => `<button type="button" id="tab-${id}" role="tab" data-detail-tab="${id}" aria-controls="panel-${id}" aria-selected="${i === 0}" tabindex="${i === 0 ? 0 : -1}">${label}</button>`).join("")}</div>
        <div class="detail-rich" id="panel-intro" role="tabpanel" aria-labelledby="tab-intro" tabindex="0">${description(game.description)}</div>
        <div id="panel-images" role="tabpanel" aria-labelledby="tab-images" tabindex="0" hidden>${gallery.length ? `<div class="detail-image-grid">${thumbs}</div>` : placeholder("Hình ảnh sản phẩm đang được cập nhật.")}</div>
        <div class="detail-rich" id="panel-requirements" role="tabpanel" aria-labelledby="tab-requirements" tabindex="0" hidden>${requirements()}</div></section></div>`,
        gameName(game.name),
      );
      renderGallery();
      renderPrice();
      host.querySelector("#product-title").focus({ preventScroll: true });
    }
    function selectTab(id, focus = false) {
      if (!tabs.some(([key]) => key === id)) return;
      host.querySelectorAll("[data-detail-tab]").forEach((button) => {
        const selected = button.dataset.detailTab === id;
        button.setAttribute("aria-selected", String(selected));
        button.tabIndex = selected ? 0 : -1;
        host.querySelector(`#panel-${button.dataset.detailTab}`).hidden =
          !selected;
        if (selected && focus) button.focus();
      });
    }
    async function load() {
      const id = ++requestId;
      host.setAttribute("aria-busy", "true");
      frame(
        `<div class="detail-loading" role="status"><span class="spinner"></span>Đang tải thông tin sản phẩm…</div><div class="detail-grid" aria-hidden="true"><div class="skeleton detail-skeleton-art"></div><div class="skeleton detail-skeleton-card"></div></div>`,
      );
      host.querySelector("[data-detail-back]").focus({ preventScroll: true });
      try {
        const result = await request("store-detail", { slug });
        if (disposed || id !== requestId) return;
        const owned = await request("library-ownership", {
          gameId: result.gameId,
        });
        if (disposed || id !== requestId) return;
        ownership = owned;
        game = result;
        render();
      } catch (error) {
        if (disposed || id !== requestId) return;
        const missing = error.code === "product_not_found";
        frame(
          `<div class="store-empty" role="alert">${icons.game}<h3>${missing ? "Sản phẩm không còn có sẵn" : "Chưa tải được sản phẩm"}</h3><p>${escape(error.message)}</p>${missing ? "" : `<button class="store-button" type="button" data-detail-retry>${icons.refresh}Thử lại</button>`}</div>`,
        );
        host.querySelector("[data-detail-back]").focus({ preventScroll: true });
      } finally {
        if (!disposed && id === requestId)
          host.setAttribute("aria-busy", "false");
      }
    }
    host.addEventListener(
      "click",
      (event) => {
        const button = event.target.closest("button");
        if (!button || button.disabled) return;
        if (
          button.hasAttribute("data-buy-now") ||
          button.hasAttribute("data-add-to-cart")
        )
          void purchase(button);
        else if (button.hasAttribute("data-detail-back")) onBack();
        else if (button.hasAttribute("data-detail-retry")) void load();
        else if (button.hasAttribute("data-gallery-index")) {
          selectImage(Number(button.dataset.galleryIndex));
          if (button.closest(".detail-image-grid"))
            host
              .querySelector(".detail-media")
              .scrollIntoView({ block: "start" });
        } else if (button.hasAttribute("data-gallery-previous"))
          selectImage(selectedImage - 1);
        else if (button.hasAttribute("data-gallery-next"))
          selectImage(selectedImage + 1);
        else if (button.dataset.detailTab) selectTab(button.dataset.detailTab);
      },
      options,
    );
    async function purchase(button) {
      const version = host.querySelector("[data-version]");
      if (!version?.value) return;
      if (
        ownership.ownedVersionIds.includes(version.value) ||
        ownership.pendingVersionIds.includes(version.value)
      ) {
        onLibrary?.(version.value);
        return;
      }
      const controls = [
        ...host.querySelectorAll(
          ".detail-purchase-actions button, [data-version]",
        ),
      ];
      controls.forEach((element) => {
        element.disabled = true;
      });
      const previous = button.innerHTML;
      button.innerHTML = '<span class="spinner"></span>Đang thêm…';
      try {
        await onPurchase(version.value, button.hasAttribute("data-buy-now"));
      } finally {
        if (!disposed) {
          button.innerHTML = previous;
          controls.forEach((element) => {
            element.disabled = false;
          });
        }
      }
    }
    host.addEventListener(
      "change",
      (event) => {
        if (event.target.matches("[data-version]")) renderPrice();
      },
      options,
    );
    host.addEventListener(
      "keydown",
      (event) => {
        if (!event.target.matches("[data-detail-tab]")) return;
        const index = tabs.findIndex(
          ([id]) => id === event.target.dataset.detailTab,
        );
        const next = {
          ArrowRight: (index + 1) % tabs.length,
          ArrowLeft: (index + tabs.length - 1) % tabs.length,
          Home: 0,
          End: tabs.length - 1,
        }[event.key];
        if (next !== undefined) {
          event.preventDefault();
          selectTab(tabs[next][0], true);
        }
      },
      options,
    );
    void load();
    return {
      dispose() {
        disposed = true;
        requestId++;
        events.abort();
        host.replaceChildren();
      },
    };
  }
  window.LauncherProduct = { mount, richText, metadataRows };
})();
