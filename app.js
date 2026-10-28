(() => {
  "use strict";

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
    const pin = document.querySelector("#demo-pin");
    const modeButtons = [...document.querySelectorAll("[data-demo-mode]")];
    const reducedMotion = typeof window.matchMedia === "function"
      ? window.matchMedia("(prefers-reduced-motion: reduce)")
      : null;

    const examples = {
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
          { phase: "selecting", duration: 1600, step: 0, label: "1. 在原应用中，拖动选中文字。", description: "先选中想理解的英文。回声译此时还未出现。" },
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
    };

    let mode = modeButtons.find((button) =>
      button.getAttribute("aria-pressed") === "true" && Object.hasOwn(examples, button.dataset.demoMode)
    )?.dataset.demoMode || "selection";
    let pinned = pin?.getAttribute("aria-pressed") === "true";
    let phase = "ready";
    let generation = 0;
    const timers = new Set();

    const setText = (element, text) => {
      if (!element) return;
      if (element instanceof HTMLInputElement || element instanceof HTMLTextAreaElement) {
        element.value = text;
      } else {
        element.textContent = text;
      }
    };

    const updateStatus = () => {
      const labels = {
        ready: "等待播放",
        selecting: mode === "ocr" ? "左键框选区域" : "拖动选中文字",
        shortcut: mode === "ocr" ? "按下 Alt + S" : "按下 Alt + D",
        recognizing: "本机 OCR 识别中",
        translating: "正在翻译示例文字",
        complete: "翻译完成",
      };
      setText(status, `${labels[phase]}${pinned ? " · 已置顶" : ""}`);
    };

    const setPhase = (nextPhase, stage = null) => {
      phase = nextPhase;
      const example = examples[mode];
      const details = stage || example[phase];
      if (scene) {
        scene.dataset.phase = phase;
        scene.setAttribute("aria-busy", String(phase !== "ready" && phase !== "complete"));
      }
      setText(source, phase === "translating" || phase === "complete" ? example.source : "");
      setText(result, phase === "complete" ? example.result : phase === "translating" ? "正在翻译…" : "");
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
      const replayLabel = phase === "ready"
        ? `播放${example.name}流程`
        : phase === "complete" ? `重播${example.name}流程` : "从头播放";
      setText(replay?.querySelector("[data-replay-label]") || replay, replayLabel);
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
      setText(caption, "流程示意 · 不读取真实屏幕");
      for (const step of progressSteps) {
        setText(step.querySelector(".step-name"), examples[mode].steps[Number(step.dataset.stepIndex)] || "");
      }
    };

    const completeDemo = () => {
      setPhase("complete");
    };

    const playDemo = () => {
      cancelAnimation();
      setPhase("ready");
      // Commit the neutral state so replaying the same step restarts its CSS
      // gesture instead of continuing a previous selection animation.
      if (scene) void scene.offsetWidth;
      renderMode();
      if (reducedMotion?.matches || !scene) {
        completeDemo();
        return;
      }
      let elapsed = 0;
      for (const [index, stage] of examples[mode].stages.entries()) {
        if (index === 0) setPhase(stage.phase, stage);
        else schedule(elapsed, () => setPhase(stage.phase, stage));
        elapsed += stage.duration;
      }
      schedule(elapsed, completeDemo);
    };

    for (const button of modeButtons) {
      button.addEventListener("click", () => {
        const nextMode = button.dataset.demoMode;
        if (!Object.hasOwn(examples, nextMode)) return;
        mode = nextMode;
        playDemo();
      });
    }
    replay?.addEventListener("click", playDemo);

    const renderPin = () => {
      if (scene) scene.dataset.pinned = String(pinned);
      if (pin) {
        const label = pinned ? "取消置顶演示弹窗" : "置顶演示弹窗";
        pin.setAttribute("aria-pressed", String(pinned));
        pin.setAttribute("aria-label", label);
        pin.title = label;
      }
      updateStatus();
    };

    pin?.addEventListener("click", () => {
      pinned = !pinned;
      renderPin();
    });

    const onMotionPreferenceChange = () => {
      if (reducedMotion?.matches && phase !== "ready") {
        cancelAnimation();
        completeDemo();
      }
    };
    if (typeof reducedMotion?.addEventListener === "function") {
      reducedMotion.addEventListener("change", onMotionPreferenceChange);
    } else if (typeof reducedMotion?.addListener === "function") {
      reducedMotion.addListener(onMotionPreferenceChange);
    }

    renderMode();
    renderPin();
    setPhase("ready");
    if (status) {
      status.removeAttribute("role");
      status.setAttribute("aria-live", "off");
    }

    const serviceButtons = [...document.querySelectorAll("[data-service]")];
    const serviceTitle = document.querySelector("#service-title");
    const serviceDescription = document.querySelector("#service-description");
    const serviceTags = document.querySelector("#service-tags");
    const serviceFootnote = document.querySelector("#service-footnote");
    const services = {
      local: {
        title: "中英翻译，离线也能用。",
        description: "Windows 预览包内置中英离线翻译引擎，无需填写 API Key。把常用的中英翻译留在本机处理。",
        tags: ["Windows", "中英离线", "免 API Key"],
        footnote: "安装后即可使用本机中英翻译，也可以在设置中添加自己常用的翻译服务。",
      },
      system: {
        title: "接上 Mac 自带的翻译能力。",
        description: "macOS 26 及以上可使用 Apple 系统翻译，调用已安装的语言模型，无需配置 API Key。",
        tags: ["macOS 26+", "系统语言模型", "免 API Key"],
        footnote: "需要先在设置中准备支持的语言模型；普通翻译不会自动下载模型。此能力不适用于 Windows。",
      },
      api: {
        title: "翻译服务，由你选择。",
        description: "接入支持的 OpenAI 兼容接口、DeepL 或 LibreTranslate。按自己的需求配置服务，让阅读与工作使用同一套顺手的翻译体验。",
        tags: ["OpenAI 兼容", "DeepL", "LibreTranslate"],
        footnote: "需自行配置服务；费用、联网及数据处理方式由所选服务决定。此网页只演示选项，不接收或保存密钥。",
      },
    };

    const selectService = (service) => {
      if (!Object.hasOwn(services, service)) return;
      const details = services[service];
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

    for (const button of serviceButtons) {
      button.addEventListener("click", () => selectService(button.dataset.service));
    }
    selectService(serviceButtons.find((button) =>
      button.getAttribute("aria-pressed") === "true" && Object.hasOwn(services, button.dataset.service)
    )?.dataset.service || "local");

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

    const currentHashSection = () => {
      try {
        return document.getElementById(decodeURIComponent(window.location.hash.slice(1)));
      } catch {
        return null;
      }
    };

    if (linksBySection.size) {
      setCurrentSection(currentHashSection() || linksBySection.keys().next().value);
      window.addEventListener("hashchange", () => setCurrentSection(currentHashSection()));
      if (typeof window.IntersectionObserver === "function") {
        const visibleSections = new Set();
        const observer = new IntersectionObserver((entries) => {
          for (const entry of entries) {
            if (entry.isIntersecting) visibleSections.add(entry.target);
            else visibleSections.delete(entry.target);
          }
          const nearestSection = [...visibleSections].sort((left, right) =>
            Math.abs(left.getBoundingClientRect().top - window.innerHeight * 0.25)
            - Math.abs(right.getBoundingClientRect().top - window.innerHeight * 0.25)
          )[0];
          if (nearestSection) setCurrentSection(nearestSection);
        }, { rootMargin: "-15% 0px -50% 0px", threshold: [0, 0.25, 0.5, 1] });
        for (const section of linksBySection.keys()) observer.observe(section);
      }
    }

    setText(document.querySelector("#current-year"), String(new Date().getFullYear()));
    window.addEventListener("pagehide", () => {
      cancelAnimation();
      completeDemo();
    });
  };

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", initialize, { once: true });
  } else {
    initialize();
  }
})();
