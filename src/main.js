// src/main.js
// v105.5 FULL MAIN FILE
// - fixed-step loop
// - resize / focus / hidden-tab recovery
// - keeps current Game(canvas) API
// - stable canvas sizing for #overworld

import Game from "./game.js";

const canvas = document.getElementById("overworld");
if (!canvas) {
  throw new Error('Missing <canvas id="overworld"> in index.html');
}

const ctx = canvas.getContext("2d", { alpha: false });
if (!ctx) {
  throw new Error("Could not get 2D canvas context");
}
const bootLoading = document.getElementById("boot-loading");
const bootLoadingStatus = document.getElementById("boot-loading-status");
const bootLoadingPercent = document.getElementById("boot-loading-percent");

let game = null;
let rafId = 0;
let running = false;
let booted = false;
let lastTime = performance.now();
let accumulator = 0;
let resumeTimer = 0;
let resizeQueued = false;
let renderScale = 1;
let frameEmaMs = 16.67;
let dynamicScaleCooldown = 0;
let bootVisualProgress = 0;
let bootTargetProgress = 0;
let bootLoadingShownAt = 0;
const BOOT_MIN_VISIBLE_MS = 1350;

const STEP = 1 / 60;
const MAX_FRAME = 0.05;
const MAX_STEPS = 4;

setupCanvasElement();
window.addEventListener("error", (event) => {
  showFatalError(event.error || event.message || "Unknown browser error");
});
window.addEventListener("unhandledrejection", (event) => {
  showFatalError(event.reason || "Unhandled promise rejection");
});

try {
  boot();
} catch (err) {
  showFatalError(err);
}

function setupCanvasElement() {
  if (!canvas.hasAttribute("tabindex")) {
    canvas.tabIndex = 0;
  }

  canvas.setAttribute("role", "application");
  canvas.setAttribute("aria-label", "Broke Knight game canvas");

  canvas.style.display = "block";
  canvas.style.outline = "none";
  canvas.style.userSelect = "none";
  canvas.style.webkitUserSelect = "none";
  canvas.style.touchAction = "none";
}

function getDPR() {
  const device = Math.max(1, window.devicePixelRatio || 1);
  return device;
}

function getCssSize() {
  const w = Math.max(320, window.innerWidth | 0);
  const h = Math.max(240, window.innerHeight | 0);
  return { w, h };
}

function applyCanvasSize(cssW, cssH, dpr) {
  canvas.style.width = `${cssW}px`;
  canvas.style.height = `${cssH}px`;

  const pixelW = Math.max(1, Math.floor(cssW * dpr));
  const pixelH = Math.max(1, Math.floor(cssH * dpr));

  if (canvas.width !== pixelW || canvas.height !== pixelH) {
    canvas.width = pixelW;
    canvas.height = pixelH;
  }

  canvas.style.imageRendering = "auto";
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  ctx.imageSmoothingEnabled = true;
}

function resizeCanvas() {
  const { w, h } = getCssSize();
  const dpr = getDPR();

  applyCanvasSize(w, h, dpr);

  if (game?.resize) {
    game.resize(w, h);
  } else if (game) {
    game.w = w;
    game.h = h;
  }
}

function queueResize() {
  if (resizeQueued) return;
  resizeQueued = true;

  requestAnimationFrame(() => {
    resizeQueued = false;
    resizeCanvas();
  });
}

function focusCanvas() {
  try {
    canvas.focus({ preventScroll: true });
  } catch (_) {
    try {
      canvas.focus();
    } catch (_) {}
  }
}

function cancelLoop() {
  if (rafId) {
    cancelAnimationFrame(rafId);
    rafId = 0;
  }
  running = false;
}

function render() {
  if (!game) return;
  game.draw?.();
}

function showFatalError(err) {
  cancelLoop();
  hideBootLoading(true);

  const message = err?.stack || err?.message || String(err || "Unknown error");
  console.error("Broke Knight crashed:", err);

  let panel = document.getElementById("fatal-error");
  if (!panel) {
    panel = document.createElement("pre");
    panel.id = "fatal-error";
    document.body.appendChild(panel);
  }

  panel.textContent = `Broke Knight hit an error.\n\n${message}`;
}

function setBootLoadingStatus(text) {
  if (bootLoadingStatus) bootLoadingStatus.textContent = text;
}

function clamp01(v) {
  return Math.max(0, Math.min(1, Number.isFinite(v) ? v : 0));
}

function setBootLoadingPercent(progress = 0) {
  const p = clamp01(progress);
  if (bootLoadingPercent) bootLoadingPercent.textContent = `${Math.round(p * 100)}%`;
  const card = bootLoading?.querySelector?.(".boot-card");
  if (card) card.style.setProperty("--boot-progress", `${Math.round(p * 100)}%`);
}

function setBootLoadingTarget(progress = 0, immediate = false) {
  bootTargetProgress = Math.max(bootTargetProgress, clamp01(progress));
  if (immediate) {
    bootVisualProgress = bootTargetProgress;
    setBootLoadingPercent(bootVisualProgress);
  }
}

function tickBootLoadingVisual(dt = STEP) {
  if (!bootLoading || bootLoading.style.display === "none") return;
  const gap = bootTargetProgress - bootVisualProgress;
  if (gap <= 0.0005) return;
  const maxStep = Math.max(0.004, dt * 0.18);
  const easedStep = Math.max(maxStep, gap * 0.1);
  bootVisualProgress = Math.min(bootTargetProgress, bootVisualProgress + easedStep);
  setBootLoadingPercent(bootVisualProgress);
}

function showBootLoading(text = "Building the world...") {
  if (!bootLoading) return;
  setBootLoadingStatus(text);
  bootVisualProgress = 0;
  bootTargetProgress = 0;
  bootLoadingShownAt = performance.now();
  setBootLoadingPercent(0);
  bootLoading.classList.remove("is-hidden");
  bootLoading.style.display = "flex";
}

function hideBootLoading(immediate = false) {
  if (!bootLoading) return;
  if (immediate) {
    bootLoading.classList.add("is-hidden");
    bootLoading.style.display = "none";
    return;
  }
  bootLoading.classList.add("is-hidden");
  setTimeout(() => {
    if (bootLoading.classList.contains("is-hidden")) {
      bootLoading.style.display = "none";
    }
  }, 220);
}

function tick(now) {
  if (!running) return;

  rafId = requestAnimationFrame(tick);

  let frame = (now - lastTime) / 1000;
  lastTime = now;

  if (!Number.isFinite(frame) || frame < 0) {
    frame = STEP;
  }

  frame = Math.min(MAX_FRAME, frame);
  accumulator += frame;
  const frameMs = frame * 1000;
  frameEmaMs = frameEmaMs * 0.88 + frameMs * 0.12;
  dynamicScaleCooldown = Math.max(0, dynamicScaleCooldown - frame);
  try {
    let steps = 0;
    while (accumulator >= STEP && steps < MAX_STEPS) {
      game?.update?.(STEP);
      accumulator -= STEP;
      steps++;
    }

    if (steps >= MAX_STEPS) {
      accumulator = 0;
    }

    render();
    game?.noteFrame?.(frame);
    updateBootLoadingProgress();
    tickBootLoadingVisual(frame);
    maybeAdjustRenderScale();
  } catch (err) {
    showFatalError(err);
  }
}

function updateBootLoadingProgress() {
  if (!bootLoading || bootLoading.style.display === "none" || !game) return;
  const progress = game.getBootProgress?.() ?? 1;
  const status = game.getBootStatusText?.() || "Building the world...";
  setBootLoadingStatus(status);
  setBootLoadingTarget(progress);
  const shownLongEnough = performance.now() - bootLoadingShownAt >= BOOT_MIN_VISIBLE_MS;
  if ((game.isBootWarm?.() || progress >= 0.999) && bootVisualProgress >= 0.995 && shownLongEnough) hideBootLoading();
}

function maybeAdjustRenderScale() {
  if (renderScale !== 1) {
    renderScale = 1;
    resizeCanvas();
  }
  if (game) game.renderScale = 1;
}

function startLoop() {
  if (running) return;
  running = true;
  lastTime = performance.now();
  accumulator = 0;
  frameEmaMs = 16.67;
  if (game) game.renderScale = renderScale;
  rafId = requestAnimationFrame(tick);
}

function hardResume() {
  cancelLoop();
  resizeCanvas();

  if (game?.input?.clearAll) {
    game.input.clearAll();
  } else if (game?.input?.endFrame) {
    game.input.endFrame();
  }

  focusCanvas();
  startLoop();
}

function flushSave() {
  try {
    game?.flushSave?.();
  } catch (err) {
    console.warn("Final save failed", err);
  }
}

function softResumeSoon() {
  if (resumeTimer) return;

  resumeTimer = setTimeout(() => {
    resumeTimer = 0;
    if (!document.hidden) {
      hardResume();
    }
  }, 60);
}

function boot() {
  if (booted) return;
  booted = true;
  showBootLoading("Preparing startup...");
  setBootLoadingTarget(0.04, true);
  resizeCanvas();
  requestAnimationFrame(() => {
    setBootLoadingStatus("Reading your save...");
    setBootLoadingTarget(0.12);
    setTimeout(() => {
      setBootLoadingStatus("Packing your gear...");
      setBootLoadingTarget(0.22);
      setTimeout(() => {
        setBootLoadingStatus("Building the world...");
        setBootLoadingTarget(0.34);
        setTimeout(() => {
          try {
            game = new Game(canvas, {
              onBootProgress: (status, progress) => {
                setBootLoadingStatus(status || "Building the world...");
                if (progress != null) setBootLoadingTarget(progress);
              },
            });

            if (game?.resize) {
              const { w, h } = getCssSize();
              game.resize(w, h);
            }

            focusCanvas();
            startLoop();
          } catch (err) {
            showFatalError(err);
          }
        }, 220);
      }, 180);
    }, 120);
  });
}

window.addEventListener("resize", () => {
  queueResize();
});

window.addEventListener("orientationchange", () => {
  queueResize();
  softResumeSoon();
});

window.addEventListener("focus", () => {
  softResumeSoon();
});

window.addEventListener("blur", () => {
  flushSave();
  if (game?.input?.clearAll) {
    game.input.clearAll();
  } else if (game?.input?.endFrame) {
    game.input.endFrame();
  }
});

document.addEventListener("visibilitychange", () => {
  if (document.hidden) {
    flushSave();
    cancelLoop();
  } else {
    softResumeSoon();
  }
});

window.addEventListener("pageshow", () => {
  softResumeSoon();
});

window.addEventListener("pagehide", () => {
  flushSave();
});

window.addEventListener("beforeunload", () => {
  flushSave();
});

canvas.addEventListener("mousedown", () => {
  focusCanvas();
});
