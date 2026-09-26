// No DOM, cookies, form values, or private-session data crosses this boundary.
export function sanitizedTab(tab) {
  if (!tab || tab.incognito !== false || !Number.isSafeInteger(tab.id) || tab.id < 0 ||
      !Number.isSafeInteger(tab.windowId) || tab.windowId < 0 || typeof tab.url !== "string" ||
      new TextEncoder().encode(tab.url).length > 4096 || /[\u0000-\u001f]/.test(tab.url)) return null;
  let url;
  try { url = new URL(tab.url); } catch { return null; }
  if (!["https:", "http:"].includes(url.protocol) || !url.hostname || url.username || url.password) return null;
  url.search = "";
  url.hash = "";
  return { tabID: tab.id, windowID: tab.windowId, url: url.href,
    title: typeof tab.title === "string" ? Array.from(tab.title).slice(0, 512).join("") : "",
    active: tab.active === true };
}

export function browserKind(navigator) {
  if (navigator?.brave) return "brave";
  if (navigator?.userAgent?.includes("Edg/")) return "edge";
  if (navigator?.userAgent?.includes("Chrome/")) return "chrome";
  return "chromium";
}
