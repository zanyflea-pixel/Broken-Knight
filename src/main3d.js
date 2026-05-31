const canvas = document.getElementById("three-canvas");
if (!canvas) {
  throw new Error('Missing <canvas id="three-canvas"> in index-3d.html');
}
const overlayCanvas = document.getElementById("ui-canvas");
if (!overlayCanvas) {
  throw new Error('Missing <canvas id="ui-canvas"> in index-3d.html');
}
const bootLoading = document.getElementById("boot-loading");
const bootLoadingStatus = document.getElementById("boot-loading-status");
const bootLoadingPercent = document.getElementById("boot-loading-percent");
const bootModePlay = document.getElementById("boot-mode-play");
const bootModeBuild = document.getElementById("boot-mode-build");
const bootModeRiverBuild = document.getElementById("boot-mode-river-build");

const BOOT_MIN_VISIBLE_MS = 950;
let bootProgress = 0;
let bootShownAt = 0;

function clamp01(value) {
  return Math.max(0, Math.min(1, Number.isFinite(value) ? value : 0));
}

function setBootLoadingStatus(text) {
  if (bootLoadingStatus) bootLoadingStatus.textContent = text || "Preparing startup...";
}

function setBootLoadingPercent(progress = 0) {
  bootProgress = clamp01(progress);
  if (bootLoadingPercent) bootLoadingPercent.textContent = `${Math.round(bootProgress * 100)}%`;
  const card = bootLoading?.querySelector?.(".boot-card");
  if (card) card.style.setProperty("--boot-progress", `${Math.round(bootProgress * 100)}%`);
}

function showBootLoading(text = "Preparing startup...") {
  if (!bootLoading) return;
  setBootLoadingStatus(text);
  setBootLoadingPercent(0);
  bootShownAt = performance.now();
  bootLoading.classList.remove("is-hidden");
  bootLoading.style.display = "grid";
}

function hideBootLoading() {
  if (!bootLoading) return;
  bootLoading.classList.add("is-hidden");
  setTimeout(() => {
    if (bootLoading.classList.contains("is-hidden")) {
      bootLoading.style.display = "none";
    }
  }, 240);
}

async function holdBootLoadingUntilSettled(app) {
  if (!app) return;
  const settleStart = performance.now();
  const settleTimeoutMs = 12000;
  while (performance.now() - settleStart < settleTimeoutMs) {
    const snap = app.getBootSnapshot?.();
    if (!snap) break;
    const mapped = 0.52 + clamp01(snap.progress) * 0.47;
    setBootLoadingStatus(snap.status || "Finalizing world...");
    setBootLoadingPercent(mapped);
    if (snap.warm || app.isBootSettled?.()) return;
    if ((snap.progress || 0) >= 0.9 && performance.now() - settleStart >= 2500) return;
    await wait(120);
  }
  setBootLoadingStatus("Entering the world...");
  setBootLoadingPercent(0.99);
}

function wait(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function getLaunchMode() {
  return "play";
}

function setLaunchMode(mode) {
  bootModePlay?.classList.toggle("is-active", mode === "play");
  bootModeBuild?.classList.toggle("is-active", mode === "build");
  bootModeRiverBuild?.classList.toggle("is-active", mode === "river-build");
}

function waitForModeChoice() {
  let mode = getLaunchMode();
  setLaunchMode(mode);
  return Promise.resolve(mode);
}

function nextPaint() {
  return new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)));
}

function showFatalError(err) {
  hideBootLoading();
  const message = err?.stack || err?.message || String(err || "Unknown error");
  console.error("Broke Knight 3D crashed:", err);

  let panel = document.getElementById("fatal-error");
  if (!panel) {
    panel = document.createElement("pre");
    panel.id = "fatal-error";
    document.body.appendChild(panel);
  }

  panel.textContent = `Broke Knight 3D hit an error.\n\n${message}`;
}

window.addEventListener("error", (event) => {
  showFatalError(event.error || event.message || event);
});

window.addEventListener("unhandledrejection", (event) => {
  showFatalError(event.reason || event);
});

showBootLoading("Preparing startup...");

async function bootBrokeKnight3D() {
  setBootLoadingStatus("Opening play mode...");
  setBootLoadingPercent(0.01);
  const launchMode = await waitForModeChoice();
  setBootLoadingStatus(
    launchMode === "river-build"
      ? "Opening river build sandbox..."
      : launchMode === "build"
        ? "Opening world forge..."
        : "Opening play mode..."
  );
  setBootLoadingPercent(0.02);
  await nextPaint();
  setBootLoadingStatus("Loading 3D engine...");
  setBootLoadingPercent(0.03);
  await nextPaint();
  const { default: World3DApp } = await import("./render3d/world3d.js?v=20260529g");
  setBootLoadingStatus("Starting renderer...");
  setBootLoadingPercent(0.07);
  await nextPaint();

  const app = new World3DApp(canvas, overlayCanvas, {
    hudEl: document.querySelector(".hud"),
    footerEl: document.querySelector(".footer-note"),
    actionsEl: document.querySelector(".hud-actions"),
    summaryEl: document.getElementById("three-summary"),
    seedEl: document.getElementById("hud-seed"),
    heroEl: document.getElementById("hud-hero"),
    roadsEl: document.getElementById("hud-roads"),
    riversEl: document.getElementById("hud-rivers"),
    bridgesEl: document.getElementById("hud-bridges"),
    townsEl: document.getElementById("hud-towns"),
    recenterBtn: document.getElementById("recenter-camera"),
  });
  window.__bk3dApp = app;
  window.__bk3dGame = app.game || null;

  await app.start({
    launchMode,
    onBootProgress: (status, progress) => {
      setBootLoadingStatus(status || "Preparing startup...");
      if (progress != null) setBootLoadingPercent(progress);
    },
  });
  window.__bk3dGame = app.game || null;
  await holdBootLoadingUntilSettled(app);
  const elapsed = performance.now() - bootShownAt;
  if (elapsed < BOOT_MIN_VISIBLE_MS) {
    await wait(BOOT_MIN_VISIBLE_MS - elapsed);
  }
  setBootLoadingStatus("Ready");
  setBootLoadingPercent(1);
  hideBootLoading();
}

bootBrokeKnight3D().catch((err) => {
  showFatalError(err);
});


















