(() => {
  "use strict";

  const copy = {
    zh: {
      title: "EchoLingo · 回声译 — 让陌生的语言，有熟悉的回声。",
      pinOn: "取消固定演示浮窗",
      pinOff: "固定演示浮窗",
      caption: "流程示意 · 不读取真实屏幕。",
      translating: "正在翻译…",
      pinnedSuffix: " · 已固定",
      replay: { ready: "播放", complete: "重播", busy: "从头播放" },
      status: {
        ready: "等待播放",
        selectingSelection: "拖动选中文字",
        selectingOcr: "左键框选区域",
        shortcutSelection: "按下 Alt + D",
        shortcutOcr: "按下 Alt + S",
        recognizing: "本机 OCR 识别中",
        translating: "正在翻译示例文字",
        complete: "翻译完成",
      },
      demo: {
        selection: {
          name: "选词翻译",
          source: "Good tools let you stay in the flow.",
          result: "好工具，让你专注当下。",
          steps: ["选中文字", "按快捷键", "浮窗翻译", "继续阅读"],
          ready: {
            label: "点击播放，看看选词翻译如何发生。",
            description: "从拖动选中文字，到快捷键唤起译文，完整走一遍。",
          },
          stages: [
            { phase: "selecting", duration: 1600, step: 0, label: "1. 在原应用中，拖动选中文字。", description: "先选中想理解的文字。回声译此时还未出现。" },
            { phase: "shortcut", duration: 1200, step: 1, label: "2. 按下 Alt + D，呼出选词翻译。", description: "快捷键取得刚才的选区；Mac 对应 Option + D。" },
            { phase: "translating", duration: 1200, step: 2, label: "3. 浮窗出现，自动填入原文并翻译。", description: "不用切换到翻译网站，也不用手动复制粘贴。" },
          ],
          complete: {
            label: "4. 译文在手边，继续阅读。",
            description: "选中文字 → 按 Alt + D → 浮窗翻译 → 继续阅读。原文和译文就在同一处。",
          },
        },
        ocr: {
          name: "区域 OCR",
          source: "Stay curious. Keep exploring.",
          result: "保持好奇，继续探索。",
          steps: ["按快捷键", "左键框选", "松开识字", "自动翻译"],
          ready: {
            label: "点击播放，看看图片文字如何变成译文。",
            description: "从快捷键进入框选，到松开鼠标自动识字并翻译，完整走一遍。",
          },
          stages: [
            { phase: "shortcut", duration: 1300, step: 0, label: "1. 按下 Alt + S，开始区域 OCR。", description: "桌面保持实时可见，进入框选状态；Mac 对应 Option + S。" },
            { phase: "selecting", duration: 2000, step: 1, label: "2. 按住鼠标左键，拖出想识别的区域。", description: "只框选需要的文字，图片或无法选中的文字都可以尝试。" },
            { phase: "recognizing", duration: 1200, step: 2, label: "3. 松开左键，在本机识别区域内的文字。", description: "识别完成后，文字会自动填入回声译，无需再复制粘贴。" },
            { phase: "translating", duration: 1000, step: 3, label: "4. 原文自动填入浮窗，接着翻译。", description: "一次框选，接上识字与翻译；此处仅使用预设示例。" },
          ],
          complete: {
            label: "完成：图片里的字，也有了回声。",
            description: "按 Alt + S → 左键框选 → 松开识字 → 自动翻译。整个流程由你主动触发。",
          },
        },
      },
      services: {
        local: {
          title: "离线，也能读懂。",
          description: "Windows 中英离线翻译包内置语言模型，无需 API Key。文本在本机处理，不会自动切换到云端服务。",
          tags: ["Windows", "中英互译", "无需 API Key"],
          footnote: "预览包能力以对应版本说明为准。",
        },
        system: {
          title: "接上 Mac 自带的翻译能力。",
          description: "macOS 26 及以上可使用 Apple 系统翻译，调用已安装的语言模型，无需配置 API Key。",
          tags: ["macOS 26+", "系统语言模型", "免 API Key"],
          footnote: "需要先在设置中准备支持的语言模型；普通翻译不会自动下载模型。此能力不适用于 Windows。",
        },
        api: {
          title: "翻译服务，由你选择。",
          description: "接入支持的 OpenAI 兼容接口、DeepL 或 LibreTranslate。按自己的需求配置端点、模型与提示词。",
          tags: ["OpenAI 兼容", "DeepL", "LibreTranslate"],
          footnote: "需自行配置服务；费用、联网及数据处理方式由所选服务决定。此网页只演示选项，不接收或保存密钥。",
        },
      },
    },
    en: {
      title: "EchoLingo — A familiar echo for unfamiliar words.",
      pinOn: "Unpin the preview",
      pinOff: "Pin the preview",
      caption: "Illustrated flow. Your screen is not read.",
      translating: "Translating…",
      pinnedSuffix: " · Pinned",
      replay: { ready: "Play", complete: "Replay", busy: "Play from the start" },
      status: {
        ready: "Ready to play",
        selectingSelection: "Dragging to select text",
        selectingOcr: "Dragging a region",
        shortcutSelection: "Press Alt + D",
        shortcutOcr: "Press Alt + S",
        recognizing: "Reading text on this device",
        translating: "Translating the sample",
        complete: "Translation ready",
      },
      demo: {
        selection: {
          name: "selection",
          source: "Good tools let you stay in the flow.",
          result: "好工具，让你专注当下。",
          steps: ["Select", "Shortcut", "Translate", "Continue"],
          ready: {
            label: "Play the selection flow.",
            description: "From dragging over a sentence to the shortcut that brings up a translation.",
          },
          stages: [
            { phase: "selecting", duration: 1600, step: 0, label: "1. Drag to select text in the app you are using.", description: "Select the words you want to understand. EchoLingo is not on screen yet." },
            { phase: "shortcut", duration: 1200, step: 1, label: "2. Press Alt + D to translate the selection.", description: "The shortcut reads the selection you just made. On a Mac, that is Option + D." },
            { phase: "translating", duration: 1200, step: 2, label: "3. A popup appears, fills in the text, and translates it.", description: "There is no need to open a translation site, or to copy and paste." },
          ],
          complete: {
            label: "4. The translation stays beside the page. Keep reading.",
            description: "Select text, press Alt + D, read the popup, and continue. The source and translation stay together.",
          },
        },
        ocr: {
          name: "OCR",
          source: "Stay curious. Keep exploring.",
          result: "保持好奇，继续探索。",
          steps: ["Press shortcut", "Drag a region", "Release to read", "Translate"],
          ready: {
            label: "Play the OCR flow.",
            description: "From the shortcut, to releasing the mouse so the words are read and translated.",
          },
          stages: [
            { phase: "shortcut", duration: 1300, step: 0, label: "1. Press Alt + S to start region OCR.", description: "The desktop stays visible while you enter selection mode. On a Mac, that is Option + S." },
            { phase: "selecting", duration: 2000, step: 1, label: "2. Hold the left mouse button and drag out a region.", description: "Frame only the words you need. Images, and text you cannot select, are both fine to try." },
            { phase: "recognizing", duration: 1200, step: 2, label: "3. Release. The words are recognized on this device.", description: "When recognition finishes, the text is filled into EchoLingo. No extra copy and paste." },
            { phase: "translating", duration: 1000, step: 3, label: "4. The text lands in the popup, then it is translated.", description: "One region connects recognition and translation. This preview uses a fixed sample." },
          ],
          complete: {
            label: "Done. Words in the picture have an echo too.",
            description: "Press Alt + S, drag with the left button, release to read, then translate. You start the flow yourself.",
          },
        },
      },
      services: {
        local: {
          title: "Offline, and still readable.",
          description: "The Windows build includes an on-device Chinese–English model. No API key is required, and the text stays on your computer.",
          tags: ["Windows", "Chinese ↔ English", "No API key"],
          footnote: "What a preview build includes is described in that version’s notes. It does not silently switch to a cloud service.",
        },
        system: {
          title: "Use the translation built into your Mac.",
          description: "On macOS 26 and later, EchoLingo can use Apple system translation with language models you have already installed. No API key.",
          tags: ["macOS 26+", "System language model", "No API key"],
          footnote: "Prepare a supported language model in Settings first. A normal translation does not download a model for you. This is not available on Windows.",
        },
        api: {
          title: "Bring the translation service you want.",
          description: "Connect a supported OpenAI-compatible endpoint, DeepL, or LibreTranslate. Set the endpoint, model, and prompt yourself.",
          tags: ["OpenAI-compatible", "DeepL", "LibreTranslate"],
          footnote: "You configure the service. Fees, network use, and data handling are decided by that provider. This page only shows the options. It does not receive or store keys.",
        },
      },
    },
  };

  const locale = () => (document.documentElement.dataset.locale === "en" ? "en" : "zh");
  const text = () => copy[locale()];

  const setText = (element, value) => {
    if (!element) return;
    element.textContent = value;
  };

  const initialize = () => {
    const scene = document.querySelector("#demo-scene");
    const source = document.querySelector("#demo-source");
    const result = document.querySelector("#demo-result");
    const caption = document.querySelector("#demo-caption");
    const status = document.querySelector("#demo-status");
    const stepLabel = document.querySelector("#demo-step-label");
    const stepDescription = document.querySelector("#demo-step-description");
    const progressSteps = [...document.querySelectorAll("#demo-progress [data-step-index]")];
    const replay = document.querySelector("#demo-replay");
    const replayLabel = replay?.querySelector("[data-replay-label]");
    const pin = document.querySelector("#demo-pin");
    const modeButtons = [...document.querySelectorAll("[data-demo-mode]")];
    const serviceButtons = [...document.querySelectorAll("[data-service]")];
    const serviceTitle = document.querySelector("#service-title");
    const serviceDescription = document.querySelector("#service-description");
    const serviceTags = document.querySelector("#service-tags");
    const serviceFootnote = document.querySelector("#service-footnote");
    const reducedMotion = typeof window.matchMedia === "function"
      ? window.matchMedia("(prefers-reduced-motion: reduce)")
      : null;

    let mode = modeButtons.find((button) => button.getAttribute("aria-pressed") === "true")?.dataset.demoMode || "selection";
    if (!Object.hasOwn(text().demo, mode)) mode = "selection";
    let service = serviceButtons.find((button) => button.getAttribute("aria-pressed") === "true")?.dataset.service || "local";
    if (!Object.hasOwn(text().services, service)) service = "local";
    let pinned = pin?.getAttribute("aria-pressed") === "true";
    let phase = "ready";
    let generation = 0;
    const timers = new Set();

    const setMeta = () => {
      const title = text().title;
      document.title = title;
      const ogTitle = document.querySelector('meta[property="og:title"]');
      if (ogTitle) ogTitle.setAttribute("content", title);
      const ogLocale = document.querySelector('meta[property="og:locale"]');
      if (ogLocale) ogLocale.setAttribute("content", locale() === "en" ? "en_US" : "zh_CN");
      for (const button of document.querySelectorAll("[data-set-locale]")) {
        button.setAttribute("aria-pressed", String(button.dataset.setLocale === locale()));
      }
    };

    const updateStatus = () => {
      const strings = text().status;
      const labels = {
        ready: strings.ready,
        selecting: mode === "ocr" ? strings.selectingOcr : strings.selectingSelection,
        shortcut: mode === "ocr" ? strings.shortcutOcr : strings.shortcutSelection,
        recognizing: strings.recognizing,
        translating: strings.translating,
        complete: strings.complete,
      };
      setText(status, `${labels[phase] || ""}${pinned ? text().pinnedSuffix : ""}`);
    };

    const renderPin = () => {
      if (scene) scene.dataset.pinned = String(pinned);
      if (pin) {
        const label = pinned ? text().pinOn : text().pinOff;
        pin.setAttribute("aria-pressed", String(pinned));
        pin.setAttribute("aria-label", label);
        pin.title = label;
      }
      updateStatus();
    };

    const setPhase = (nextPhase, stage = null) => {
      phase = nextPhase;
      const example = text().demo[mode];
      const details = stage || example[phase];
      if (scene) {
        scene.dataset.phase = phase;
        scene.setAttribute("aria-busy", String(phase !== "ready" && phase !== "complete"));
      }
      setText(source, phase === "translating" || phase === "complete" ? example.source : "");
      setText(result, phase === "complete" ? example.result : phase === "translating" ? text().translating : "");
      setText(stepLabel, details?.label || "");
      setText(stepDescription, details?.description || "");
      for (const step of progressSteps) {
        const index = Number(step.dataset.stepIndex);
        const state = phase === "complete" || (stage && index < stage.step)
          ? "complete"
          : stage && index === stage.step ? "current" : "pending";
        step.dataset.state = state;
        if (state === "current") step.setAttribute("aria-current", "step");
        else step.removeAttribute("aria-current");
      }
      const replayKind = phase === "complete" ? "complete" : phase === "ready" ? "ready" : "busy";
      const replayName = example.name;
      const replayText = replayKind === "busy"
        ? text().replay.busy
        : locale() === "zh"
          ? `${text().replay[replayKind]}${replayName}流程`
          : `${text().replay[replayKind]} the ${replayName} flow`;
      setText(replayLabel, replayText);
      updateStatus();
    };

    const cancelAnimation = () => {
      generation += 1;
      for (const timer of timers) window.clearTimeout(timer);
      timers.clear();
    };

    const schedule = (delay, callback) => {
      const expectedGeneration = generation;
      const timer = window.setTimeout(() => {
        timers.delete(timer);
        if (expectedGeneration === generation) callback();
      }, delay);
      timers.add(timer);
    };

    const renderMode = () => {
      if (scene) scene.dataset.mode = mode;
      for (const button of modeButtons) {
        button.setAttribute("aria-pressed", String(button.dataset.demoMode === mode));
      }
      setText(caption, text().caption);
      const example = text().demo[mode];
      for (const step of progressSteps) {
        setText(step.querySelector(".step-name"), example.steps[Number(step.dataset.stepIndex)] || "");
      }
    };

    const completeDemo = () => setPhase("complete");

    const playDemo = () => {
      cancelAnimation();
      setPhase("ready");
      if (scene) void scene.offsetWidth;
      renderMode();
      if (reducedMotion?.matches || !scene) {
        completeDemo();
        return;
      }
      let elapsed = 0;
      const stages = text().demo[mode].stages;
      for (const [index, stage] of stages.entries()) {
        if (index === 0) setPhase(stage.phase, stage);
        else schedule(elapsed, () => setPhase(stage.phase, stage));
        elapsed += stage.duration;
      }
      schedule(elapsed, completeDemo);
    };

    const selectService = (next) => {
      if (!Object.hasOwn(text().services, next)) return;
      service = next;
      const details = text().services[service];
      for (const button of serviceButtons) {
        button.setAttribute("aria-pressed", String(button.dataset.service === service));
      }
      setText(serviceTitle, details.title);
      setText(serviceDescription, details.description);
      setText(serviceFootnote, details.footnote);
      if (serviceTags) {
        serviceTags.replaceChildren(...details.tags.map((label) => {
          const tag = document.createElement("span");
          tag.textContent = label;
          return tag;
        }));
      }
    };

    const relocalize = () => {
      setMeta();
      renderMode();
      renderPin();
      if (phase === "complete" || phase === "ready") setPhase(phase);
      else {
        cancelAnimation();
        setPhase("ready");
      }
      selectService(service);
    };

    for (const button of modeButtons) {
      button.addEventListener("click", () => {
        const nextMode = button.dataset.demoMode;
        if (!Object.hasOwn(text().demo, nextMode)) return;
        mode = nextMode;
        playDemo();
      });
    }
    replay?.addEventListener("click", playDemo);
    pin?.addEventListener("click", () => {
      pinned = !pinned;
      renderPin();
    });

    const onMotionPreferenceChange = () => {
      if (reducedMotion?.matches && phase !== "ready" && phase !== "complete") {
        cancelAnimation();
        completeDemo();
      }
    };
    if (typeof reducedMotion?.addEventListener === "function") {
      reducedMotion.addEventListener("change", onMotionPreferenceChange);
    } else if (typeof reducedMotion?.addListener === "function") {
      reducedMotion.addListener(onMotionPreferenceChange);
    }

    for (const button of serviceButtons) {
      button.addEventListener("click", () => selectService(button.dataset.service));
    }

    for (const button of document.querySelectorAll("[data-set-locale]")) {
      button.addEventListener("click", () => {
        const next = button.dataset.setLocale === "en" ? "en" : "zh";
        if (next === locale()) return;
        document.documentElement.dataset.locale = next;
        document.documentElement.lang = next === "en" ? "en" : "zh-CN";
        try {
          localStorage.setItem("echolingo-locale", next);
        } catch {
          /* The page still switches for this visit when storage is unavailable. */
        }
        relocalize();
      });
    }

    const navLinks = [...document.querySelectorAll("header nav a[href^='#']")];
    const linksBySection = new Map();
    for (const link of navLinks) {
      let id;
      try {
        id = decodeURIComponent(link.getAttribute("href").slice(1));
      } catch {
        continue;
      }
      const section = id ? document.getElementById(id) : null;
      if (!section) continue;
      if (!linksBySection.has(section)) linksBySection.set(section, []);
      linksBySection.get(section).push(link);
    }

    const setCurrentSection = (section) => {
      const currentLinks = linksBySection.get(section);
      if (!currentLinks) return;
      for (const link of navLinks) {
        if (currentLinks.includes(link)) link.setAttribute("aria-current", "location");
        else link.removeAttribute("aria-current");
      }
    };

    if (linksBySection.size && typeof window.IntersectionObserver === "function") {
      const visibleSections = new Set();
      const observer = new IntersectionObserver((entries) => {
        for (const entry of entries) {
          if (entry.isIntersecting) visibleSections.add(entry.target);
          else visibleSections.delete(entry.target);
        }
        const nearest = [...visibleSections].sort((left, right) =>
          Math.abs(left.getBoundingClientRect().top) - Math.abs(right.getBoundingClientRect().top)
        )[0];
        if (nearest) setCurrentSection(nearest);
      }, { rootMargin: "-20% 0px -55% 0px", threshold: [0.2, 0.5] });
      for (const section of linksBySection.keys()) observer.observe(section);
    }

    setText(document.querySelector("#current-year"), String(new Date().getFullYear()));
    window.addEventListener("pagehide", () => {
      cancelAnimation();
    });

    if (status) {
      status.removeAttribute("role");
      status.setAttribute("aria-live", "off");
    }

    renderMode();
    renderPin();
    setPhase("ready");
    selectService(service);
    setMeta();
  };

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", initialize, { once: true });
  } else {
    initialize();
  }
})();
