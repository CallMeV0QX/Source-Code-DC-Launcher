(() => {
  "use strict";

  const suffix = "Key Steam Việt Hóa";
  const marketingWords = "(?:(?:key\\s*(?:game\\s*)?|game\\s*)steam(?:\\s*online)?(?:\\s*[-–—|·]?\\s*viet\\s*hoa)?|viet\\s*hoa)";
  const marketingSegment = "(?:\\s*[-–—|+·]\\s*|\\s+)" + marketingWords;
  const marketingTail = new RegExp(marketingSegment + "\\s*$", "i");
  const wordCharacter = /[\p{L}\p{N}_]/u;
  const blocks = new Set(["P", "DIV", "LI", "H1", "H2", "H3", "H4", "H5", "H6", "BLOCKQUOTE", "FIGCAPTION", "TD", "TH"]);
  const untouched = new Set(["SCRIPT", "STYLE", "CODE", "PRE", "TEXTAREA"]);

  const fold = value => value.normalize("NFD").replace(/\p{M}/gu, "").replace(/đ/g, "d").replace(/Đ/g, "D").toLowerCase();
  const escapePattern = value => value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");

  function foldedText(value) {
    let text = "";
    const offsets = [];
    for (let offset = 0; offset < value.length;) {
      const character = String.fromCodePoint(value.codePointAt(offset));
      const part = fold(character);
      for (let index = 0; index < part.length; index++) offsets.push(offset);
      text += part;
      offset += character.length;
    }
    offsets.push(value.length);
    return { text, offsets };
  }

  function baseTitle(raw) {
    let title = String(raw ?? "").trim().normalize("NFC");
    while (title) {
      const value = foldedText(title);
      const match = marketingTail.exec(value.text);
      if (!match) break;
      title = title.slice(0, value.offsets[match.index]).trimEnd();
    }
    return title;
  }

  function display(raw) {
    const title = baseTitle(raw);
    return title ? `${title} - ${suffix}` : "";
  }

  function replacements(text, catalogName, steamName) {
    const replacement = display(catalogName);
    if (!replacement || !text) return [];
    const aliases = [...new Set([baseTitle(catalogName), baseTitle(steamName)].filter(Boolean).map(fold))]
      .sort((left, right) => right.length - left.length)
      .map(alias => alias.split(/\s+/u).map(escapePattern).join("\\s+"));
    const matcher = new RegExp("(?:" + aliases.join("|") + ")(?:(?:" + marketingSegment + "))*", "gu");
    const value = foldedText(text);
    const urls = [...text.matchAll(/(?:https?:\/\/|www\.|mailto:)\S+|[\w.+-]+@[\w.-]+\.[A-Za-z]{2,}/giu)]
      .map(match => ({ start: match.index, end: match.index + match[0].length }));
    const result = [];
    for (const match of value.text.matchAll(matcher)) {
      const before = value.text[match.index - 1];
      const after = value.text[match.index + match[0].length];
      if ((before && wordCharacter.test(before)) || (after && wordCharacter.test(after))) continue;
      const start = value.offsets[match.index];
      const end = value.offsets[match.index + match[0].length];
      if (urls.some(url => start < url.end && end > url.start)) continue;
      result.push({ start, end, replacement });
    }
    return result;
  }

  function replaceMentions(raw, catalogName, steamName = null) {
    let text = String(raw ?? "");
    for (const match of replacements(text, catalogName, steamName).reverse())
      text = text.slice(0, match.start) + match.replacement + text.slice(match.end);
    return text;
  }

  // Change text nodes only. Links, media URLs, attributes, literal code and the
  // surrounding inert markup stay intact, including names split across inline tags.
  function replaceTextNodes(root, catalogName, steamName = null) {
    let group = [];
    const flush = () => {
      if (!group.length) return;
      let combined = "";
      const segments = group.map(node => {
        const start = combined.length;
        combined += node.data;
        return { node, start, end: combined.length };
      });
      for (const match of replacements(combined, catalogName, steamName).reverse()) {
        let first = true;
        for (const segment of segments) {
          if (match.start >= segment.end || match.end <= segment.start) continue;
          const start = Math.max(0, match.start - segment.start);
          const end = Math.min(segment.end - segment.start, match.end - segment.start);
          segment.node.data = segment.node.data.slice(0, start) + (first ? match.replacement : "") + segment.node.data.slice(end);
          first = false;
        }
      }
      group = [];
    };
    const visit = node => {
      if (node.nodeType === 3) { group.push(node); return; }
      if (node.nodeType !== 1 && node !== root) return;
      const tag = node.tagName;
      if (untouched.has(tag) || ["BR", "HR", "IMG", "VIDEO", "IFRAME"].includes(tag)) { flush(); return; }
      const block = blocks.has(tag);
      if (block) flush();
      for (const child of node.childNodes) visit(child);
      if (block) flush();
    };
    visit(root);
    flush();
    return root;
  }

  window.DCGameNames = Object.freeze({ suffix, display, baseTitle, replaceMentions, replaceTextNodes });
})();
