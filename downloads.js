(() => {
  "use strict";

  const root = document.querySelector("#download-stats");
  if (!root) return;

  // Public metadata only: never download an installer or count page visits/clicks.
  const endpoint = "https://api.github.com/repos/Blueeeecho/EchoLingo/releases";
  const cacheKey = "echolingo-installer-downloads-v1";
  const freshFor = 15 * 60 * 1000;
  const retainFor = 7 * 24 * 60 * 60 * 1000;
  const validCount = (value) => Number.isSafeInteger(value) && value >= 0;

  const setStatus = (zh, en) => {
    root.querySelector('[data-download-status="zh"]').textContent = zh;
    root.querySelector('[data-download-status="en"]').textContent = en;
  };

  const showCounts = (snapshot) => {
    for (const platform of ["total", "windows", "macos"]) {
      root.querySelector(`[data-download-count="${platform}"]`).textContent =
        snapshot[platform].toLocaleString("en-US");
    }
  };

  const showUpdated = (snapshot, stale = false) => {
    const date = new Date(snapshot.updatedAt);
    const options = { month: "short", day: "numeric", hour: "2-digit", minute: "2-digit" };
    const zhDate = date.toLocaleString("zh-CN", options);
    const enDate = date.toLocaleString("en-US", options);
    setStatus(
      stale ? `暂时无法更新，显示缓存 · 上次同步 ${zhDate}` : `同步于 ${zhDate} · 本地缓存 15 分钟`,
      stale ? `Update unavailable; cached counts · Last synced ${enDate}` : `Synced ${enDate} · Cached locally for 15 minutes`,
    );
  };

  const readCache = () => {
    try {
      const value = JSON.parse(localStorage.getItem(cacheKey));
      const age = Date.now() - value?.updatedAt;
      if (value && Number.isFinite(value.updatedAt) && age >= 0 && age <= retainFor &&
          [value.windows, value.macos, value.total].every(validCount) &&
          value.total === value.windows + value.macos) return value;
    } catch { /* Storage may be disabled or contain an older/invalid value. */ }
    return null;
  };

  const refresh = async () => {
    const cached = readCache();
    if (cached) {
      showCounts(cached);
      showUpdated(cached);
      if (Date.now() - cached.updatedAt < freshFor) return;
    }

    root.setAttribute("aria-busy", "true");
    setStatus(
      cached ? "正在更新 GitHub 下载量，暂显示缓存…" : "正在读取 GitHub 下载量…",
      cached ? "Updating GitHub counts; showing cached data…" : "Loading download counts from GitHub…",
    );

    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 10000);
    try {
      const counts = { windows: 0, macos: 0 };
      const seenAssets = new Set();
      let hasNext = true;
      // Follow pagination without trusting a response-provided URL or publishing partial totals.
      for (let page = 1; hasNext; page += 1) {
        const response = await fetch(`${endpoint}?per_page=100&page=${page}`, {
          headers: { Accept: "application/vnd.github+json" },
          credentials: "omit",
          referrerPolicy: "no-referrer",
          signal: controller.signal,
        });
        if (!response.ok) throw new Error(`GitHub status ${response.status}`);
        const releases = await response.json();
        if (!Array.isArray(releases)) throw new Error("Invalid releases response");
        for (const release of releases) {
          if (release.draft || !release.published_at) continue;
          if (!Array.isArray(release.assets)) throw new Error("Missing release assets");
          for (const asset of release.assets) {
            // Only EchoLingo installers: source ZIPs, manifests, checksums, etc. never match.
            const name = typeof asset.name === "string" ? asset.name : "";
            const platform = /^EchoLingo_.+\.(exe|msi)$/i.test(name) ? "windows"
              : /^EchoLingo_.+\.(dmg|pkg)$/i.test(name) ? "macos" : null;
            if (!platform || asset.state !== "uploaded") continue;
            if (!validCount(asset.download_count) || !Number.isSafeInteger(asset.id)) {
              throw new Error("Invalid installer count");
            }
            if (seenAssets.has(asset.id)) continue;
            seenAssets.add(asset.id);
            counts[platform] += asset.download_count;
          }
        }
        hasNext = /(?:^|,)\s*<[^>]+>;\s*rel="next"/.test(response.headers.get("link") || "");
      }
      const snapshot = { ...counts, total: counts.windows + counts.macos, updatedAt: Date.now() };
      if (![snapshot.windows, snapshot.macos, snapshot.total].every(validCount)) {
        throw new Error("Invalid total");
      }
      showCounts(snapshot);
      showUpdated(snapshot);
      try {
        localStorage.setItem(cacheKey, JSON.stringify(snapshot));
      } catch { /* A blocked/full local cache must not break the live counts. */ }
    } catch {
      if (cached) showUpdated(cached, true);
      else setStatus(
        "下载量暂不可用（网络或 GitHub 限流），不影响下载安装。",
        "Counts temporarily unavailable (network or GitHub rate limit). Downloads still work.",
      );
    } finally {
      clearTimeout(timeout);
      root.setAttribute("aria-busy", "false");
    }
  };

  void refresh();
})();
