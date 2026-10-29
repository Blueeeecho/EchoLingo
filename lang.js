(() => {
  "use strict";

  const key = "echolingo-locale";
  let saved = null;
  try {
    saved = localStorage.getItem(key);
  } catch {
    saved = null;
  }

  let locale;
  if (saved === "zh" || saved === "en") {
    locale = saved;
  } else {
    const primary = (navigator.languages && navigator.languages[0]) || navigator.language || "";
    locale = String(primary).toLowerCase().startsWith("zh") ? "zh" : "en";
  }

  const root = document.documentElement;
  root.dataset.locale = locale;
  root.lang = locale === "en" ? "en" : "zh-CN";
})();
