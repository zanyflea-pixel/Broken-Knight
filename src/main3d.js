import World3DApp from "./render3d/world3d.js";

const canvas = document.getElementById("three-canvas");
if (!canvas) {
  throw new Error('Missing <canvas id="three-canvas"> in index-3d.html');
}

const app = new World3DApp(canvas, {
  summaryEl: document.getElementById("three-summary"),
  seedEl: document.getElementById("hud-seed"),
  heroEl: document.getElementById("hud-hero"),
  roadsEl: document.getElementById("hud-roads"),
  riversEl: document.getElementById("hud-rivers"),
  bridgesEl: document.getElementById("hud-bridges"),
  townsEl: document.getElementById("hud-towns"),
  recenterBtn: document.getElementById("recenter-camera"),
});

window.addEventListener("error", (event) => {
  console.error("Broke Knight 3D crashed:", event.error || event.message || event);
});

window.addEventListener("unhandledrejection", (event) => {
  console.error("Broke Knight 3D promise rejection:", event.reason || event);
});

app.start();
