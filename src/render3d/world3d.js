import * as THREE from "three";

const TERRAIN_SIZE = 24000;
const TERRAIN_SEGMENTS = 128;
const LOCAL_TERRAIN_SIZE = 4200;
const LOCAL_TERRAIN_SEGMENTS = 220;
const BUILD_LOCAL_TERRAIN_SIZE = 2800;
const BUILD_LOCAL_TERRAIN_SEGMENTS = 360;
const BUILD_LOCAL_TERRAIN_SMOOTH_PASSES = 2;
const RIVER_SAMPLE_STRIDE = 2;
const ROAD_SAMPLE_STRIDE = 1;
const STEP = 1 / 60;
const MAX_FRAME = 0.05;
const MAX_STEPS = 4;
const OVERWORLD_PROP_RADIUS = 1650;

function smoothstep(edge0, edge1, x) {
  const t = clamp((x - edge0) / Math.max(0.0001, edge1 - edge0), 0, 1);
  return t * t * (3 - 2 * t);
}

function distPointToSeg(px, py, ax, ay, bx, by) {
  const dx = bx - ax;
  const dy = by - ay;
  if (dx === 0 && dy === 0) return Math.hypot(px - ax, py - ay);
  const t = clamp(((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy), 0, 1);
  const qx = ax + t * dx;
  const qy = ay + t * dy;
  return Math.hypot(px - qx, py - qy);
}

function clamp(value, min, max) {
  return Math.max(min, Math.min(max, value));
}

function sectionFootprintFrac(x, y, cx, cy, angle, length, width) {
  const halfL = Math.max(1, length * 0.5);
  const halfW = Math.max(1, width * 0.5);
  const dx = x - cx;
  const dy = y - cy;
  const cosA = Math.cos(-(angle || 0));
  const sinA = Math.sin(-(angle || 0));
  const lx = dx * cosA - dy * sinA;
  const ly = dx * sinA + dy * cosA;
  const capRadius = Math.min(halfW, halfL);
  const spineHalf = Math.max(0, halfL - capRadius);
  const clampedX = clamp(lx, -spineHalf, spineHalf);
  const dist = Math.hypot(lx - clampedX, ly);
  return clamp(1 - dist / Math.max(1, capRadius), 0, 1);
}

function sectionStampFrac(x, y, band, width) {
  if (!band) return 0;
  const pts = Array.isArray(band.pathPoints) ? band.pathPoints : [];
  if (!pts.length) return 0;
  const radius = Math.max(18, width * 0.62);
  let best = 0;
  for (const p of pts) {
    const dx = x - p.x;
    const dy = y - p.y;
    const frac = clamp(1 - Math.hypot(dx, dy) / radius, 0, 1);
    if (frac > best) best = frac;
  }
  return best;
}

function buildSectionRiverFrac(world, x, y) {
  if (!world?._riverBands?.length) return 0;
  let topA = 0;
  let topB = 0;
  let topC = 0;
  for (const band of world._riverBands) {
    if (!band?.authored) continue;
    if (band.sectionKind !== "straight" && band.sectionKind !== "wide") continue;
    const visualWidth = world._riverVisualWidth?.(band) || 24;
    const riverWidth = Math.max(80, visualWidth * 1.92);
    const sectionFrac = sectionFootprintFrac(
      x,
      y,
      band.sectionCenterX ?? 0,
      band.sectionCenterY ?? 0,
      band.sectionAngle || 0,
      (band.sectionLength || (band.sectionKind === "wide" ? 328 : 264)) + riverWidth * 1.2,
      riverWidth * 2.85
    );
    const stampFrac = sectionStampFrac(x, y, band, riverWidth * 2.35);
    const frac = Math.max(sectionFrac, stampFrac);
    if (frac >= topA) {
      topC = topB;
      topB = topA;
      topA = frac;
    } else if (frac >= topB) {
      topC = topB;
      topB = frac;
    } else if (frac > topC) {
      topC = frac;
    }
  }
  return clamp(1 - (1 - topA) * (1 - topB * 0.96) * (1 - topC * 0.88), 0, 1);
}

function angleDelta(a, b) {
  let d = (a || 0) - (b || 0);
  while (d > Math.PI) d -= Math.PI * 2;
  while (d < -Math.PI) d += Math.PI * 2;
  return Math.abs(d);
}

function progressId(point) {
  return point?.id != null ? String(point.id) : `${point?.x ?? 0},${point?.y ?? 0}`;
}

export default class World3DApp {
  constructor(canvas, overlayCanvas, ui = {}) {
    this.canvas = canvas;
    this.overlayCanvas = overlayCanvas;
    this.ui = ui;

    this.renderer = new THREE.WebGLRenderer({
      canvas,
      antialias: true,
      alpha: false,
      powerPreference: "high-performance",
    });
    this.renderer.outputColorSpace = THREE.SRGBColorSpace;
    this.renderer.toneMapping = THREE.ACESFilmicToneMapping;
    this.renderer.toneMappingExposure = 1.08;
    this.renderer.shadowMap.enabled = true;
    this.renderer.shadowMap.type = THREE.PCFSoftShadowMap;
    this.renderer.shadowMap.autoUpdate = false;
    this.renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 1.0));

    this.scene = new THREE.Scene();
    this.scene.background = new THREE.Color(0x091018);
    this.scene.fog = new THREE.FogExp2(0x091018, 0.000075);

    this.camera = new THREE.PerspectiveCamera(56, 1, 8, 60000);
    this.raycaster = new THREE.Raycaster();
    this.groundPlane = new THREE.Plane(new THREE.Vector3(0, 1, 0), 0);
    this.pointerNdc = new THREE.Vector2();
    this.pointerWorld = new THREE.Vector3();
    this.clock = new THREE.Clock();
    this.rafId = 0;
    this.running = false;
    this.lastTime = 0;
    this.accumulator = 0;

    this.game = null;
    this.world = null;
    this.bootStatus = "Preparing startup...";
    this.bootProgress = 0;
    this.onBootProgress = null;
    this.cameraTarget = new THREE.Vector3();
    this.cameraOffset = new THREE.Vector3(880, 720, 880);
    this.cameraOrbit = {
      enabled: false,
      pointerId: null,
      lastX: 0,
      lastY: 0,
      yaw: Math.atan2(880, 880),
      pitch: 0.55,
      distance: Math.hypot(880, 720, 880),
    };
    this.cameraZoom = {
      current: 1,
      target: 1,
      min: 0.42,
      max: 1,
      step: 0.12,
    };
    this.buildCamera = {
      active: false,
      x: 0,
      y: 0,
      move: { forward: false, back: false, left: false, right: false, fast: false },
    };
    this.heroHeight = {
      current: 0,
      initialized: false,
    };
    this.heroHeading = 0;
    this.overworldVisible = true;
    this.dungeonSceneVersion = "";
    this.materialCache = new Map();
    this.atmosphere = {
      fogColor: new THREE.Color(0x091018),
      bgColor: new THREE.Color(0x091018),
      density: 0.000075,
    };
    this.atmosphereTargets = {
      fog: new THREE.Color(0x091018),
      bg: new THREE.Color(0x091018),
      ambientSky: new THREE.Color(0xb7d7ff),
      ambientGround: new THREE.Color(0x322a22),
      sun: new THREE.Color(0xffefd8),
    };
    this.shadowState = {
      frame: 0,
      dirty: true,
      lastHeroX: 0,
      lastHeroY: 0,
      lastDungeonActive: false,
    };
    this.hudState = {
      elapsed: 0,
      interval: 0.12,
      dirty: true,
    };
    this.debugState = {
      elapsed: 0,
      interval: 0.18,
      dirty: true,
    };

    this.overworldGroup = new THREE.Group();
    this.overworldDetailGroup = new THREE.Group();
    this.dungeonGroup = new THREE.Group();
    this.enemyGroup = new THREE.Group();
    this.projectileGroup = new THREE.Group();
    this.lootGroup = new THREE.Group();
    this.landmarkGroup = new THREE.Group();
    this.previewGroup = new THREE.Group();

    this.heroMarker = null;
    this.heroBoat = null;
    this.enemyMeshes = new Map();
    this.projectileMeshes = new Map();
    this.lootMeshes = new Map();
    this.landmarkEntries = [];
    this.dungeonRoomMeshes = new Map();
    this.dungeonDoorMeshes = new Map();
    this.dungeonCacheMeshes = new Map();
    this.dungeonHoardGroup = null;
    this.dungeonSceneMeta = {
      currentRoomId: null,
      roomClear: false,
    };
    this.detailCenter = { x: 0, y: 0 };
    this.detailRefreshDistance = 2000;
    this.worldPropsGroup = null;
    this.worldPropsCenter = { x: 0, y: 0 };
    this.worldPropsRefreshDistance = 1100;
    this.worldPropsReady = false;
    this.worldPropsSignature = "";
    this.worldPropsRefreshAt = 0;
    this.worldWarmAnnounced = false;
    this.detailBootLite = false;
    this.ambientLight = null;
    this.sunLight = null;
    this.waterShimmer = null;
    this.terrainMesh = null;
    this.waterMesh = null;
    this.terrainHeightfield = null;
    this.localTerrainHeightfield = null;
    this.localTerrainMesh = null;
    this.localTerrainCenter = { x: 0, y: 0 };
    this.localTerrainRefreshDistance = 900;
    this.lastEditorRevision = -1;
    this.pendingEditorRefreshKind = null;
    this.editorRefreshQueued = false;

    this.debug = {
      enabled: false,
      paused: false,
      wireframe: false,
      fps: 0,
      frameMs: 0,
      frames: 0,
      accum: 0,
      panel: null,
      body: null,
    };

    this.resize = this.resize.bind(this);
    this.animate = this.animate.bind(this);
    this.recenter = this.recenter.bind(this);
    this.onKeyDown = this.onKeyDown.bind(this);
    this.onKeyUp = this.onKeyUp.bind(this);
    this.onPointerDown = this.onPointerDown.bind(this);
    this.onPointerMove = this.onPointerMove.bind(this);
    this.onPointerUp = this.onPointerUp.bind(this);
    this.onContextMenu = this.onContextMenu.bind(this);
    this.onWheel = this.onWheel.bind(this);
  }

  async start(opts = {}) {
    this.onBootProgress = typeof opts.onBootProgress === "function" ? opts.onBootProgress : null;
    this.launchMode = opts.launchMode === "play" ? "play" : opts.launchMode === "river-build" ? "river-build" : "build";
    this.setupOverlayCanvas();
    this.resize();
    this.setBootProgress("Preparing startup...", 0.03);
    await this.nextFrame();

    this.setBootProgress("Loading gameplay systems...", 0.08);
    const { default: Game } = await import("../game.js?v=20260524s");
    await this.nextFrame();

    this.game = new Game(this.overlayCanvas, {
      renderMode: "ui-only",
      startMode: this.launchMode === "play" ? "play" : "build",
      worldVariant: this.launchMode === "river-build" ? "river-build" : "default",
      getMoveIntent: (moveInput) => this.getCameraRelativeMoveIntent(moveInput),
      getAimWorldPoint: (mouseState) => this.getMouseAimWorldPoint(mouseState),
      onEditorWorldChanged: (kind) => this.queueEditorWorldRefresh(kind),
      contextAttributes: { alpha: true, desynchronized: true },
      onBootProgress: (status, progress) => {
        const mapped = 0.08 + clamp(progress ?? 0, 0, 1) * 0.44;
        this.setBootProgress(status || "Building the world...", mapped);
      },
    });
    this.resize();
    this.world = this.game.world;
    this.setBootProgress(this.game.getBootStatusText?.() || "Building the world...", 0.12);
    await this.primeWorldBoot();
    await this.buildSceneBoot();
    this.createDebugPanel();
    this.updateHud();
    this.recenter(true);
    this.focusOverlayCanvas();

    window.addEventListener("resize", this.resize);
    window.addEventListener("keydown", this.onKeyDown);
    window.addEventListener("keyup", this.onKeyUp);
    this.ui.recenterBtn?.addEventListener("click", this.recenter);
    this.overlayCanvas.addEventListener("mousedown", () => this.focusOverlayCanvas());
    this.overlayCanvas.addEventListener("pointerdown", () => this.focusOverlayCanvas());
    this.overlayCanvas.addEventListener("pointerdown", this.onPointerDown);
    this.overlayCanvas.addEventListener("pointermove", this.onPointerMove);
    this.overlayCanvas.addEventListener("pointerup", this.onPointerUp);
    this.overlayCanvas.addEventListener("pointercancel", this.onPointerUp);
    this.overlayCanvas.addEventListener("contextmenu", this.onContextMenu);
    this.overlayCanvas.addEventListener("wheel", this.onWheel, { passive: false });
    window.addEventListener("pointerup", this.onPointerUp);

    this.running = true;
    this.lastTime = performance.now();
    this.setBootProgress("Ready", 1);
    this.rafId = requestAnimationFrame(this.animate);
  }

  queueEditorWorldRefresh(kind = "terrain") {
    const next = kind === "detail" ? "detail" : "terrain";
    this.lastEditorRevision = this.world?.getEditorRevision?.() ?? this.lastEditorRevision;
    if (this.pendingEditorRefreshKind !== "terrain") {
      this.pendingEditorRefreshKind = next;
    }
    if (this.editorRefreshQueued) return;
    this.editorRefreshQueued = true;
    requestAnimationFrame(() => {
      this.editorRefreshQueued = false;
      const queuedKind = this.pendingEditorRefreshKind || "terrain";
      this.pendingEditorRefreshKind = null;
      this.refreshEditorWorldNow(queuedKind);
    });
  }

  refreshEditorWorldNow(kind = "terrain") {
    const buildMode = this.game?.mode === "build";
    if (kind !== "detail") {
      if (buildMode) {
        this.rebuildLocalTerrainPatch(true);
      } else {
        this.addTerrain();
        this.addWater();
        this.rebuildLocalTerrainPatch(true);
      }
    }
    if (buildMode) {
      this.rebuildOverworldDetail(false, false, true);
    } else {
      this.rebuildOverworldDetail(false, kind === "detail" || !buildMode, false);
    }
    this.lastEditorRevision = this.world?.getEditorRevision?.() ?? this.lastEditorRevision;
    this.shadowState.dirty = true;
    this.hudState.dirty = true;
  }

  setupOverlayCanvas() {
    this.overlayCanvas.style.background = "transparent";
    this.overlayCanvas.style.userSelect = "none";
    this.overlayCanvas.style.webkitUserSelect = "none";
  }

  setBootProgress(status, progress) {
    if (status) this.bootStatus = status;
    if (progress != null) this.bootProgress = Math.max(this.bootProgress, clamp(progress, 0, 1));
    this.onBootProgress?.(this.bootStatus, this.bootProgress);
  }

  getBootSnapshot() {
    const worldProgress = this.game?.getBootProgress?.() ?? this.bootProgress ?? 0;
    const status = this.game?.getBootStatusText?.() || this.bootStatus || "Preparing startup...";
    return {
      status,
      progress: clamp(worldProgress, 0, 1),
      warm: !!this.game?.isBootWarm?.(),
    };
  }

  isBootSettled() {
    return !!this.game?.isBootWarm?.();
  }

  nextFrame() {
    return new Promise((resolve) => requestAnimationFrame(resolve));
  }

  focusOverlayCanvas() {
    try {
      this.overlayCanvas.focus({ preventScroll: true });
    } catch (_) {
      try {
        this.overlayCanvas.focus();
      } catch (_) {}
    }
  }

  async primeWorldBoot() {
    const start = performance.now();
    const maxBootMs = 520;
    const handoffProgress = 0.08;
    while (!this.game?.isBootWarm?.()) {
      const end = performance.now() + 7;
      do {
        this.world?.update?.(STEP);
      } while (!this.game?.isBootWarm?.() && performance.now() < end);
      const worldProgress = this.game?.getBootProgress?.() || 0;
      this.setBootProgress(this.game.getBootStatusText?.() || "Building the world...", 0.08 + worldProgress * 0.44);
      if (worldProgress >= handoffProgress || performance.now() - start >= maxBootMs) break;
      await this.nextFrame();
    }
    this.setBootProgress("Forging the 3D scene...", 0.52);
  }

  resetSceneGroups() {
    this.scene.clear();
    this.enemyMeshes.clear();
    this.projectileMeshes.clear();
    this.lootMeshes.clear();
    this.landmarkEntries.length = 0;

    this.scene.add(this.overworldGroup);
    this.overworldGroup.add(this.overworldDetailGroup);
    this.scene.add(this.dungeonGroup);
    this.scene.add(this.enemyGroup);
    this.scene.add(this.projectileGroup);
    this.scene.add(this.lootGroup);
    this.scene.add(this.previewGroup);
  }

  async buildSceneBoot() {
    const tasks = [
      ["Clearing the old frame...", () => this.resetSceneGroups()],
      ["Lighting the horizon...", () => { this.addLights(); this.addSkyDome(); }],
      ["Raising the terrain...", () => { this.addTerrain(); this.addWater(); this.rebuildLocalTerrainPatch(true); }],
      ["Forging the overworld...", () => { this.rebuildOverworldDetail(true, false, true); }],
      ["Marking points of interest...", () => { this.addHeroMarker(); this.syncDungeonScene(); }],
    ];

    for (let i = 0; i < tasks.length; i++) {
      const [status, run] = tasks[i];
      this.setBootProgress(status, 0.58 + (i / tasks.length) * 0.34);
      run();
      await this.nextFrame();
    }
    this.setBootProgress("Rousing the knight...", 0.95);
  }

  addLights() {
    const ambient = new THREE.HemisphereLight(0xc8e2ff, 0x3b3127, 1.24);
    this.scene.add(ambient);
    this.ambientLight = ambient;

    const sun = new THREE.DirectionalLight(0xfff1d1, 2.25);
    sun.position.set(2600, 3800, 1400);
    sun.castShadow = true;
    sun.shadow.mapSize.set(896, 896);
    sun.shadow.camera.near = 400;
    sun.shadow.camera.far = 9000;
    sun.shadow.camera.left = -4200;
    sun.shadow.camera.right = 4200;
    sun.shadow.camera.top = 4200;
    sun.shadow.camera.bottom = -4200;
    this.scene.add(sun);
    this.sunLight = sun;
  }

  addSkyDome() {
    const skyGeo = new THREE.SphereGeometry(28000, 32, 18);
    const skyMat = new THREE.ShaderMaterial({
      side: THREE.BackSide,
      uniforms: {
        zenithColor: { value: new THREE.Color(0x34608f) },
        upperColor: { value: new THREE.Color(0x79a5c8) },
        horizonColor: { value: new THREE.Color(0xf0c791) },
        groundGlow: { value: new THREE.Color(0x13202f) },
        sunDirection: { value: new THREE.Vector3(0.54, 0.78, 0.31).normalize() },
      },
      vertexShader: `
        varying vec3 vWorldPosition;
        void main() {
          vec4 worldPosition = modelMatrix * vec4(position, 1.0);
          vWorldPosition = worldPosition.xyz;
          gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
        }
      `,
      fragmentShader: `
        uniform vec3 zenithColor;
        uniform vec3 upperColor;
        uniform vec3 horizonColor;
        uniform vec3 groundGlow;
        uniform vec3 sunDirection;
        varying vec3 vWorldPosition;
        void main() {
          vec3 dir = normalize(vWorldPosition + vec3(0.0, 1800.0, 0.0));
          float up = clamp(dir.y * 0.5 + 0.5, 0.0, 1.0);
          float horizonBand = 1.0 - smoothstep(0.02, 0.34, abs(dir.y));
          float upperMix = smoothstep(0.2, 0.92, up);
          vec3 sky = mix(groundGlow, horizonColor, horizonBand * 0.9);
          sky = mix(sky, upperColor, smoothstep(0.08, 0.58, up));
          sky = mix(sky, zenithColor, upperMix);

          float sunDot = max(dot(dir, sunDirection), 0.0);
          float sunCore = pow(sunDot, 220.0);
          float sunHalo = pow(sunDot, 18.0) * 0.45;
          sky += vec3(1.0, 0.86, 0.64) * (sunCore * 1.35 + sunHalo);

          float cloudA = sin(dir.x * 5.5 + dir.z * 4.0) * 0.5 + 0.5;
          float cloudB = sin(dir.x * 9.0 - dir.z * 6.5) * 0.5 + 0.5;
          float cloudC = sin(dir.x * 12.0 + dir.z * 10.0) * 0.5 + 0.5;
          float cloudField = cloudA * 0.45 + cloudB * 0.35 + cloudC * 0.2;
          float cloudMask = smoothstep(0.58, 0.86, cloudField) * smoothstep(0.18, 0.86, up) * 0.24;
          sky = mix(sky, sky + vec3(0.24, 0.24, 0.22), cloudMask);

          gl_FragColor = vec4(sky, 1.0);
        }
      `,
      depthWrite: false,
    });
    this.scene.add(new THREE.Mesh(skyGeo, skyMat));

    const sunHalo = new THREE.Mesh(
      new THREE.PlaneGeometry(5200, 5200),
      new THREE.MeshBasicMaterial({
        color: 0xffd7a0,
        transparent: true,
        opacity: 0.14,
        depthWrite: false,
        blending: THREE.AdditiveBlending,
      })
    );
    sunHalo.position.set(11200, 13800, 7200);
    sunHalo.lookAt(0, 0, 0);
    this.scene.add(sunHalo);

    const sunDisc = new THREE.Mesh(
      new THREE.SphereGeometry(760, 24, 18),
      new THREE.MeshBasicMaterial({
        color: 0xffefbf,
        transparent: true,
        opacity: 0.98,
      })
    );
    sunDisc.position.set(11200, 13800, 7200);
    this.scene.add(sunDisc);
  }

  addTerrain() {
    const suppressAuthoredRiverTerrain = this.game?.mode === "build" && this.world?.suppressEditorRiverCarve;
    if (this.terrainMesh?.parent) {
      this.terrainMesh.parent.remove(this.terrainMesh);
      this.disposeGroup(this.terrainMesh);
      this.terrainMesh = null;
    }
    const geometry = new THREE.PlaneGeometry(TERRAIN_SIZE, TERRAIN_SIZE, TERRAIN_SEGMENTS, TERRAIN_SEGMENTS);
    geometry.rotateX(-Math.PI * 0.5);
    const pos = geometry.attributes.position;
    const colors = [];
    const heights = new Float32Array(pos.count);
    const blendWeights = new Float32Array(pos.count);
    const roadColor = new THREE.Color(0x715334);
    const roadWearColor = new THREE.Color(0xd0ae87);
    const riverBankColor = new THREE.Color(0x425d73);
    const riverWaterColor = new THREE.Color(0x4f99df);

    for (let i = 0; i < pos.count; i++) {
      const x = pos.getX(i);
      const z = pos.getZ(i);
      const sample = this.world._sampleCell(x, z);
      let height = this.heightAt(x, z, sample);
      const color = this.colorForSample(sample);
      const roadDist = this.roadDistanceAt(x, z);
      const riverInfo = this.world._nearestRiverInfo?.(x, z);
      let riverFrac = 0;
      if (riverInfo?.band) {
        const riverWidth = Math.max(80, (this.world._riverVisualWidth?.(riverInfo.band) || 34) * 1.78);
        const riverDist = Math.sqrt(riverInfo.dist2 || 0);
        riverFrac = clamp(1 - riverDist / riverWidth, 0, 1);
        if (suppressAuthoredRiverTerrain && riverInfo.band?.authored && (riverInfo.band.sectionKind === "straight" || riverInfo.band.sectionKind === "wide")) {
          const sectionFrac = sectionFootprintFrac(
            x,
            z,
            riverInfo.band.sectionCenterX ?? 0,
            riverInfo.band.sectionCenterY ?? 0,
            riverInfo.band.sectionAngle || 0,
            riverInfo.band.sectionLength || (riverInfo.band.sectionKind === "wide" ? 328 : 264),
            riverWidth * 2.45
          );
          const stampFrac = sectionStampFrac(x, z, riverInfo.band, riverWidth * 2.2);
          riverFrac = Math.max(riverFrac, sectionFrac, stampFrac);
        }
      }

      if (suppressAuthoredRiverTerrain) {
        riverFrac = Math.max(riverFrac, buildSectionRiverFrac(this.world, x, z));
      }
      if (riverFrac > 0.01 && sample.zone !== "ocean") {
        const authoredPreview = suppressAuthoredRiverTerrain && riverInfo?.band?.authored;
        const shoulder = smoothstep(0.02, authoredPreview ? 0.82 : 0.68, riverFrac);
        const bank = smoothstep(0.12, authoredPreview ? 0.92 : 0.84, riverFrac);
        const core = smoothstep(0.26, authoredPreview ? 0.98 : 0.96, riverFrac);
        if (!authoredPreview) {
          color.lerp(riverBankColor, Math.min(0.92, shoulder * 0.54 + bank * 0.26));
          if (riverFrac > 0.18) {
            color.lerp(riverWaterColor, Math.min(0.98, core * 0.96));
          }
          const carved = height - (shoulder * 8 + bank * 12 + core * 18);
          const bed = -12 - core * 22;
          height = Math.min(carved, bed);
          blendWeights[i] = Math.max(blendWeights[i], Math.min(1, shoulder * 0.98));
        } else {
          const rim = smoothstep(0.01, 0.74, riverFrac);
          const bowl = smoothstep(0.10, 0.995, riverFrac);
          const vShape = Math.pow(clamp(riverFrac, 0, 1), 1.9);
          color.lerp(riverBankColor, Math.min(0.68, rim * 0.42));
          height -= rim * 10.0 + bowl * 18.0 + vShape * 72.0;
          blendWeights[i] = Math.max(blendWeights[i], Math.min(1, 0.84 + rim * 0.16));
        }
      } else {
        riverFrac = 0;
      }

      if (Number.isFinite(roadDist) && roadDist < 128 && sample.zone !== "ocean") {
        const shoulderFrac = 1 - clamp(roadDist / 128, 0, 1);
        const centerFrac = 1 - clamp(roadDist / 42, 0, 1);
        const rutFrac = 1 - clamp(roadDist / 18, 0, 1);
        color.lerp(roadColor, 1.0 * shoulderFrac);
        if (centerFrac > 0.01) color.lerp(roadWearColor, 1.0 * centerFrac);
        height -= shoulderFrac * 9.6 + centerFrac * 4.6 + rutFrac * 2.5;
        blendWeights[i] = Math.max(blendWeights[i], Math.min(1, shoulderFrac * 0.92));
      }

      heights[i] = height;
      colors.push(color.r, color.g, color.b);
    }

    const stride = TERRAIN_SEGMENTS + 1;
    const smoothedHeights = new Float32Array(heights);
    for (let y = 1; y < TERRAIN_SEGMENTS; y++) {
      for (let x = 1; x < TERRAIN_SEGMENTS; x++) {
        const idx = y * stride + x;
        const blend = blendWeights[idx];
        if (blend <= 0.04) continue;
        const north = heights[(y - 1) * stride + x];
        const south = heights[(y + 1) * stride + x];
        const west = heights[y * stride + (x - 1)];
        const east = heights[y * stride + (x + 1)];
        const avg = (heights[idx] * 2 + north + south + west + east) / 6;
        smoothedHeights[idx] = heights[idx] * (1 - blend * 0.42) + avg * (blend * 0.42);
      }
    }

    for (let i = 0; i < pos.count; i++) {
      pos.setY(i, smoothedHeights[i]);
      heights[i] = smoothedHeights[i];
    }

    geometry.setAttribute("color", new THREE.Float32BufferAttribute(colors, 3));
    geometry.computeVertexNormals();

    const material = new THREE.MeshStandardMaterial({
      vertexColors: true,
      roughness: 0.97,
      metalness: 0.02,
    });

    const terrain = new THREE.Mesh(geometry, material);
    terrain.receiveShadow = true;
    this.overworldGroup.add(terrain);
    this.terrainMesh = terrain;
    this.terrainHeightfield = {
      size: TERRAIN_SIZE,
      segments: TERRAIN_SEGMENTS,
      centerX: 0,
      centerY: 0,
      heights,
    };
  }

  rebuildLocalTerrainPatch(force = false) {
    if (!this.game || this.game?.dungeon?.active) return;
    const buildMode = this.game?.mode === "build";
    const suppressAuthoredRiverTerrain = buildMode && this.world?.suppressEditorRiverCarve;
    const activeCenter = this.getActiveWorldCenter();
    const centerX = activeCenter.x;
    const centerY = activeCenter.y;
    const dx = centerX - (this.localTerrainCenter?.x || 0);
    const dy = centerY - (this.localTerrainCenter?.y || 0);
    if (!force && this.localTerrainMesh && dx * dx + dy * dy < this.localTerrainRefreshDistance * this.localTerrainRefreshDistance) return;

    if (this.localTerrainMesh?.parent) {
      this.localTerrainMesh.parent.remove(this.localTerrainMesh);
      this.disposeGroup(this.localTerrainMesh);
    }

    const terrainSize = buildMode ? BUILD_LOCAL_TERRAIN_SIZE : LOCAL_TERRAIN_SIZE;
    const terrainSegments = buildMode ? BUILD_LOCAL_TERRAIN_SEGMENTS : LOCAL_TERRAIN_SEGMENTS;
    const geometry = new THREE.PlaneGeometry(terrainSize, terrainSize, terrainSegments, terrainSegments);
    geometry.rotateX(-Math.PI * 0.5);
    const pos = geometry.attributes.position;
    const colors = [];
    const heights = new Float32Array(pos.count);
    const blendWeights = new Float32Array(pos.count);
    const roadColor = new THREE.Color(0x715334);
    const roadWearColor = new THREE.Color(0xd0ae87);
    const riverBankColor = new THREE.Color(0x425d73);
    const riverWaterColor = new THREE.Color(0x4f99df);

    for (let i = 0; i < pos.count; i++) {
      const x = pos.getX(i) + centerX;
      const z = pos.getZ(i) + centerY;
      const sample = this.world._sampleCell(x, z);
      let height = this.heightAt(x, z, sample);
      const color = this.colorForSample(sample);
      const roadDist = this.roadDistanceAt(x, z);
      const riverInfo = this.world._nearestRiverInfo?.(x, z);
      let riverFrac = 0;
      if (riverInfo?.band) {
        const riverWidth = Math.max(80, (this.world._riverVisualWidth?.(riverInfo.band) || 34) * 1.92);
        const riverDist = Math.sqrt(riverInfo.dist2 || 0);
        riverFrac = clamp(1 - riverDist / riverWidth, 0, 1);
        if (suppressAuthoredRiverTerrain && riverInfo.band?.authored && (riverInfo.band.sectionKind === "straight" || riverInfo.band.sectionKind === "wide")) {
          const sectionFrac = sectionFootprintFrac(
            x,
            z,
            riverInfo.band.sectionCenterX ?? 0,
            riverInfo.band.sectionCenterY ?? 0,
            riverInfo.band.sectionAngle || 0,
            riverInfo.band.sectionLength || (riverInfo.band.sectionKind === "wide" ? 328 : 264),
            riverWidth * 2.45
          );
          const stampFrac = sectionStampFrac(x, z, riverInfo.band, riverWidth * 2.2);
          riverFrac = Math.max(riverFrac, sectionFrac, stampFrac);
        }
      }

      if (suppressAuthoredRiverTerrain) {
        riverFrac = Math.max(riverFrac, buildSectionRiverFrac(this.world, x, z));
      }
      if (riverFrac > 0.01 && sample.zone !== "ocean") {
        const authoredPreview = suppressAuthoredRiverTerrain && riverInfo?.band?.authored;
        const shoulder = smoothstep(0.02, authoredPreview ? 0.86 : 0.72, riverFrac);
        const bank = smoothstep(0.12, authoredPreview ? 0.94 : 0.88, riverFrac);
        const core = smoothstep(0.24, authoredPreview ? 0.985 : 0.97, riverFrac);
        if (!authoredPreview) {
          color.lerp(riverBankColor, Math.min(0.94, shoulder * 0.56 + bank * 0.24));
          if (riverFrac > 0.18) {
            color.lerp(riverWaterColor, Math.min(0.98, core * 0.98));
          }
          const carved = height - (shoulder * 9 + bank * 14 + core * 20);
          const bed = -13 - core * 24;
          height = Math.min(carved, bed);
          blendWeights[i] = Math.max(blendWeights[i], Math.min(1, shoulder));
        } else {
          const rim = smoothstep(0.01, 0.78, riverFrac);
          const bowl = smoothstep(0.10, 0.998, riverFrac);
          const vShape = Math.pow(clamp(riverFrac, 0, 1), 1.9);
          color.lerp(riverBankColor, Math.min(0.7, rim * 0.44));
          height -= rim * 11.0 + bowl * 20.0 + vShape * 80.0;
          blendWeights[i] = Math.max(blendWeights[i], Math.min(1, 0.88 + rim * 0.12));
        }
      }

      if (Number.isFinite(roadDist) && roadDist < 128 && sample.zone !== "ocean") {
        const shoulderFrac = 1 - clamp(roadDist / 128, 0, 1);
        const centerFrac = 1 - clamp(roadDist / 42, 0, 1);
        const rutFrac = 1 - clamp(roadDist / 18, 0, 1);
        color.lerp(roadColor, 1.0 * shoulderFrac);
        if (centerFrac > 0.01) color.lerp(roadWearColor, 1.0 * centerFrac);
        height -= shoulderFrac * 10.4 + centerFrac * 5.2 + rutFrac * 2.9;
        blendWeights[i] = Math.max(blendWeights[i], Math.min(1, shoulderFrac));
      }

      heights[i] = height;
      colors.push(color.r, color.g, color.b);
    }

    const stride = terrainSegments + 1;
    const smoothPasses = buildMode ? BUILD_LOCAL_TERRAIN_SMOOTH_PASSES : 2;
    let sourceHeights = new Float32Array(heights);
    let targetHeights = new Float32Array(heights);
    for (let pass = 0; pass < smoothPasses; pass++) {
      targetHeights.set(sourceHeights);
      for (let y = 1; y < terrainSegments; y++) {
        for (let x = 1; x < terrainSegments; x++) {
          const idx = y * stride + x;
          const blend = blendWeights[idx];
          if (blend <= 0.04) continue;
          const north = sourceHeights[(y - 1) * stride + x];
          const south = sourceHeights[(y + 1) * stride + x];
          const west = sourceHeights[y * stride + (x - 1)];
          const east = sourceHeights[y * stride + (x + 1)];
          const northWest = sourceHeights[(y - 1) * stride + (x - 1)];
          const northEast = sourceHeights[(y - 1) * stride + (x + 1)];
          const southWest = sourceHeights[(y + 1) * stride + (x - 1)];
          const southEast = sourceHeights[(y + 1) * stride + (x + 1)];
          const avg = (
            sourceHeights[idx] * 4 +
            north + south + west + east +
            (northWest + northEast + southWest + southEast) * 0.7
          ) / 10.8;
          const strength = blend * (buildMode ? 0.72 : 0.5);
          targetHeights[idx] = sourceHeights[idx] * (1 - strength) + avg * strength;
        }
      }
      const swap = sourceHeights;
      sourceHeights = targetHeights;
      targetHeights = swap;
    }
    const smoothedHeights = sourceHeights;

    for (let i = 0; i < pos.count; i++) {
      pos.setY(i, smoothedHeights[i]);
      heights[i] = smoothedHeights[i];
    }

    geometry.setAttribute("color", new THREE.Float32BufferAttribute(colors, 3));
    geometry.computeVertexNormals();
    const material = new THREE.MeshStandardMaterial({
      vertexColors: true,
      roughness: 0.97,
      metalness: 0.02,
    });
    const terrain = new THREE.Mesh(geometry, material);
    terrain.receiveShadow = true;
    terrain.position.set(centerX, 0.06, centerY);
    this.overworldGroup.add(terrain);
    this.localTerrainMesh = terrain;
    this.localTerrainHeightfield = {
      size: terrainSize,
      segments: terrainSegments,
      centerX,
      centerY,
      heights,
    };
    this.localTerrainCenter = { x: centerX, y: centerY };
  }

  roadDistanceAt(x, y) {
    const roads = this.world?.roads || [];
    if (!roads.length) return Infinity;
    let best = Infinity;
    for (const road of roads) {
      const pad = (road.width || 24) + 80;
      const bounds = this.getRoadBounds(road);
      const minX = bounds.minX - pad;
      const maxX = bounds.maxX + pad;
      const minY = bounds.minY - pad;
      const maxY = bounds.maxY + pad;
      if (x < minX || x > maxX || y < minY || y > maxY) continue;
      const pts = road.points || [];
      for (let i = 1; i < pts.length; i++) {
        const a = pts[i - 1];
        const b = pts[i];
        const d = distPointToSeg(x, y, a.x, a.y, b.x, b.y);
        if (d < best) best = d;
      }
    }
    return best;
  }

  getRoadBounds(road) {
    if (
      Number.isFinite(road?.minX) &&
      Number.isFinite(road?.minY) &&
      Number.isFinite(road?.maxX) &&
      Number.isFinite(road?.maxY)
    ) {
      return {
        minX: road.minX,
        minY: road.minY,
        maxX: road.maxX,
        maxY: road.maxY,
      };
    }
    let minX = Infinity;
    let minY = Infinity;
    let maxX = -Infinity;
    let maxY = -Infinity;
    for (const p of road?.points || []) {
      if (!p) continue;
      if (p.x < minX) minX = p.x;
      if (p.y < minY) minY = p.y;
      if (p.x > maxX) maxX = p.x;
      if (p.y > maxY) maxY = p.y;
    }
    return { minX, minY, maxX, maxY };
  }

  addWater() {
    if (this.waterMesh?.parent) {
      this.waterMesh.parent.remove(this.waterMesh);
      this.disposeGroup(this.waterMesh);
      this.waterMesh = null;
    }
    if (this.waterShimmer?.parent) {
      this.waterShimmer.parent.remove(this.waterShimmer);
      this.disposeGroup(this.waterShimmer);
      this.waterShimmer = null;
    }
    const geo = new THREE.PlaneGeometry(TERRAIN_SIZE, TERRAIN_SIZE, 1, 1);
    geo.rotateX(-Math.PI * 0.5);
    const mat = new THREE.MeshStandardMaterial({
      color: 0x1b3f5f,
      transparent: true,
      opacity: 0.7,
      roughness: 0.18,
      metalness: 0.04,
    });
    const water = new THREE.Mesh(geo, mat);
    water.position.y = -2.5;
    water.renderOrder = 1;
    this.overworldGroup.add(water);
    this.waterMesh = water;

    const shimmer = new THREE.Mesh(
      new THREE.PlaneGeometry(TERRAIN_SIZE * 0.92, TERRAIN_SIZE * 0.92, 1, 1),
      new THREE.MeshBasicMaterial({
        color: 0x79bfdc,
        transparent: true,
        opacity: 0.08,
        depthWrite: false,
        blending: THREE.AdditiveBlending,
      })
    );
    shimmer.rotation.x = -Math.PI * 0.5;
    shimmer.position.y = -1.7;
    shimmer.renderOrder = 2;
    this.overworldGroup.add(shimmer);
    this.waterShimmer = shimmer;
  }

  getSharedMaterial(key, factory) {
    let material = this.materialCache.get(key);
    if (!material) {
      material = factory();
      this.materialCache.set(key, material);
    }
    return material;
  }

  addRoads(group = this.overworldDetailGroup, centerX = this.game?.hero?.x || 0, centerY = this.game?.hero?.y || 0, radius = OVERWORLD_PROP_RADIUS + 700) {
    const roadGroup = new THREE.Group();
    roadGroup.name = "roads";
    group.add(roadGroup);
  }

  addRivers(group = this.overworldDetailGroup, centerX = this.game?.hero?.x || 0, centerY = this.game?.hero?.y || 0, radius = OVERWORLD_PROP_RADIUS + 700) {
    if (this.world?.variant === "river-build") {
      const riverGroup = new THREE.Group();
      riverGroup.name = "rivers";
      group.add(riverGroup);
      return;
    }
    const riverGroup = new THREE.Group();
    riverGroup.name = "rivers";
    const waterY = (this.waterMesh?.position?.y ?? -2.5) + 0.08;
    const waterMat = new THREE.MeshStandardMaterial({
      color: 0x2e6187,
      roughness: 0.2,
      metalness: 0.03,
      transparent: true,
      opacity: 0.94,
      side: THREE.DoubleSide,
      depthWrite: true,
    });
    const buildRiverMat = new THREE.MeshBasicMaterial({
      color: 0x4fa8e8,
      transparent: true,
      opacity: 0.72,
      side: THREE.DoubleSide,
      depthWrite: false,
      polygonOffset: true,
      polygonOffsetFactor: -2,
      polygonOffsetUnits: -2,
    });

    const buildMode = this.game?.mode === "build";
    const riverBuildMode = buildMode && this.world?.variant === "river-build";
    const authoredStraightSections = [];
    for (const band of this.world._riverBands || []) {
      const raw = this.world._clipRiverPathToCoast?.(this.world._riverPath?.(band) || [], 0.245) || this.world._riverPath?.(band) || [];
      if (!raw || raw.length < 2) continue;
      const visualWidth = this.world._riverVisualWidth?.(band) || 24;
      const width = Math.max(22, visualWidth * 1.18);
      const buildRadius = Math.max(80, visualWidth * 1.92);
      let near = false;
      const limit = radius + width * 2;
      const limit2 = limit * limit;
      for (const p of raw) {
        const dx = p.x - centerX;
        const dy = p.y - centerY;
        if (dx * dx + dy * dy <= limit2) {
          near = true;
          break;
        }
      }
      if (!near) continue;
      const smooth = band?.authored ? raw : this.smoothPath(raw, 20, 0.12);
      const authoredSection = buildMode && band?.authored && !!band.sectionKind;
      if (authoredSection && band.sectionKind === "straight" && !riverBuildMode) {
        authoredStraightSections.push({
          band,
          raw,
          visualWidth,
          buildRadius,
        });
        continue;
      }
      if (authoredSection && band.sectionKind === "straight" && riverBuildMode) {
        const mesh = this.makeRiverBuildSectionChannel(
          band.sectionCenterX ?? centerX,
          band.sectionCenterY ?? centerY,
          band.sectionAngle || 0,
          band.sectionLength || 264,
          Math.max(56, buildRadius * 2.1),
        );
        if (mesh) {
          mesh.renderOrder = 4;
          riverGroup.add(mesh);
        }
        continue;
      }
      const mesh = authoredSection
        ? ((band.sectionKind === "straight" || band.sectionKind === "wide")
            ? this.makeSectionWaterStamp(
                band.sectionCenterX ?? centerX,
                band.sectionCenterY ?? centerY,
                band.sectionAngle || 0,
                band.sectionLength || (band.sectionKind === "wide" ? 328 : 264),
                buildRadius * 2.42,
                buildRiverMat,
                0.22
              )
            : this.makeSurfacePaintRibbon(
                this.smoothPath(raw, 16, 0.1),
                buildRadius * 2.42,
                0.22,
                buildRiverMat,
                Math.max(36, buildRadius * 0.46)
              ))
        : buildMode
          ? this.makeSurfacePaintRibbon(
              smooth,
              buildRadius * 2,
              0.12,
              buildRiverMat,
              Math.max(28, buildRadius * 0.34)
            )
          : this.makeFlatWaterRibbon(smooth, width * 1.42, waterY, waterMat);
      if (!mesh) continue;
      mesh.renderOrder = 4;
      riverGroup.add(mesh);
    }
    if (buildMode && authoredStraightSections.length && !riverBuildMode) {
      this.addConnectedBuildRiverSections(riverGroup, authoredStraightSections, buildRiverMat);
    }
    group.add(riverGroup);
  }

  makeRiverBuildSectionChannel(cx, cy, angle, length, width) {
    const halfL = Math.max(42, length * 0.5 + width * 0.06);
    const outerHalf = Math.max(18, width * 0.52);
    const waterHalf = Math.max(12, width * 0.34);
    const capRadius = Math.min(outerHalf, halfL);
    const spineHalf = Math.max(0, halfL - capRadius);
    const cosA = Math.cos(angle || 0);
    const sinA = Math.sin(angle || 0);
    const arcSteps = 14;
    const ring = [];
    const rightCenter = { x: spineHalf, y: 0 };
    const leftCenter = { x: -spineHalf, y: 0 };

    for (let i = 0; i <= arcSteps; i++) {
      const t = i / arcSteps;
      const a = -Math.PI * 0.5 + t * Math.PI;
      ring.push({
        x: rightCenter.x + Math.cos(a) * capRadius,
        y: rightCenter.y + Math.sin(a) * capRadius,
      });
    }
    for (let i = 0; i <= arcSteps; i++) {
      const t = i / arcSteps;
      const a = Math.PI * 0.5 + t * Math.PI;
      ring.push({
        x: leftCenter.x + Math.cos(a) * capRadius,
        y: leftCenter.y + Math.sin(a) * capRadius,
      });
    }

    const worldPts = ring.map((p) => {
      const wx = cx + p.x * cosA - p.y * sinA;
      const wy = cy + p.x * sinA + p.y * cosA;
      const top = this.sampleRenderedTerrainSmoothHeight(wx, wy, Math.max(16, outerHalf * 0.4)) + 0.3;
      return { x: wx, y: wy, top };
    });
    if (worldPts.length < 6) return null;
    let floorTop = Infinity;
    for (const p of worldPts) floorTop = Math.min(floorTop, p.top);
    const trenchY = floorTop - Math.max(18, outerHalf * 0.42);
    const waterY = trenchY + Math.max(10, outerHalf * 0.22);

    const trenchVerts = [];
    const trenchIndices = [];
    const waterOutline = [];
    for (let i = 0; i < worldPts.length; i++) {
      const p = worldPts[i];
      trenchVerts.push(p.x, p.top, p.y, p.x, trenchY, p.y);
      if (i > 0) {
        const a = (i - 1) * 2;
        const b = a + 1;
        const c = i * 2;
        const d = c + 1;
        trenchIndices.push(a, c, b, b, c, d);
      }
    }
    if (worldPts.length >= 2) {
      const a = (worldPts.length - 1) * 2;
      const b = a + 1;
      trenchIndices.push(a, 0, b, b, 0, 1);
    }
    const trenchGeo = new THREE.BufferGeometry();
    trenchGeo.setAttribute("position", new THREE.Float32BufferAttribute(trenchVerts, 3));
    trenchGeo.setIndex(trenchIndices);
    trenchGeo.computeVertexNormals();
    const trenchMesh = new THREE.Mesh(
      trenchGeo,
      new THREE.MeshStandardMaterial({
        color: 0x2b231d,
        roughness: 0.96,
        metalness: 0.02,
        side: THREE.DoubleSide,
      })
    );

    const waterPerimeter = [];
    for (let i = 0; i <= arcSteps; i++) {
      const t = i / arcSteps;
      const a = -Math.PI * 0.5 + t * Math.PI;
      waterPerimeter.push({
        x: rightCenter.x + Math.cos(a) * Math.min(waterHalf, halfL),
        y: rightCenter.y + Math.sin(a) * Math.min(waterHalf, halfL),
      });
    }
    for (let i = 0; i <= arcSteps; i++) {
      const t = i / arcSteps;
      const a = Math.PI * 0.5 + t * Math.PI;
      waterPerimeter.push({
        x: leftCenter.x + Math.cos(a) * Math.min(waterHalf, halfL),
        y: leftCenter.y + Math.sin(a) * Math.min(waterHalf, halfL),
      });
    }
    const waterVerts = [cx, waterY, cy];
    for (const p of waterPerimeter) {
      const wx = cx + p.x * cosA - p.y * sinA;
      const wy = cy + p.x * sinA + p.y * cosA;
      waterVerts.push(wx, waterY, wy);
    }
    const waterIndices = [];
    for (let i = 1; i <= waterPerimeter.length; i++) {
      const next = i === waterPerimeter.length ? 1 : i + 1;
      waterIndices.push(0, i, next);
    }
    const waterGeo = new THREE.BufferGeometry();
    waterGeo.setAttribute("position", new THREE.Float32BufferAttribute(waterVerts, 3));
    waterGeo.setIndex(waterIndices);
    waterGeo.computeVertexNormals();
    const waterMesh = new THREE.Mesh(
      waterGeo,
      new THREE.MeshBasicMaterial({
        color: 0x57b7ff,
        transparent: true,
        opacity: 0.78,
        side: THREE.DoubleSide,
        depthWrite: false,
      })
    );

    const g = new THREE.Group();
    g.add(trenchMesh);
    g.add(waterMesh);
    return g;
  }

  addConnectedBuildRiverSections(group, sections, material) {
    const groups = this.groupStraightRiverSections(sections);
    for (const sectionGroup of groups) {
      if (!sectionGroup.length) continue;
      const centerline = [];
      let totalWidth = 0;
      for (const section of sectionGroup) {
        const pts = section.band?.points || section.raw || [];
        if (pts.length < 2) continue;
        if (!centerline.length) centerline.push({ x: pts[0].x, y: pts[0].y });
        centerline.push({ x: pts[pts.length - 1].x, y: pts[pts.length - 1].y });
        totalWidth += Math.max(70, section.buildRadius * 1.34);
      }
      if (centerline.length < 2) continue;
      const smoothed = this.smoothPath(centerline, 24, 0.08);
      const width = totalWidth / Math.max(1, sectionGroup.length);
      const channel = this.makeConnectedBuildRiverChannel(smoothed, width * 1.04, material);
      if (channel) {
        channel.renderOrder = 4;
        group.add(channel);
      }
    }
  }

  makeConnectedBuildRiverChannel(points, width, waterMaterial) {
    if (!points?.length || points.length < 2) return null;
    const group = new THREE.Group();
    const trenchVertices = [];
    const trenchIndices = [];
    const waterVertices = [];
    const waterIndices = [];
    const outerHalf = width * 0.52;
    const innerHalf = width * 0.36;
    const depth = Math.max(16, width * 0.18);
    for (let i = 0; i < points.length; i++) {
      const prev = points[Math.max(0, i - 1)];
      const here = points[i];
      const next = points[Math.min(points.length - 1, i + 1)];
      const dx = next.x - prev.x;
      const dy = next.y - prev.y;
      const len = Math.hypot(dx, dy) || 1;
      const nx = -dy / len;
      const ny = dx / len;
      const surface = this.sampleRenderedTerrainSmoothHeight(here.x, here.y, Math.max(18, width * 0.18));
      const topY = surface + 0.35;
      const bottomY = surface - depth;
      const outerLX = here.x + nx * outerHalf;
      const outerLY = here.y + ny * outerHalf;
      const outerRX = here.x - nx * outerHalf;
      const outerRY = here.y - ny * outerHalf;
      const innerLX = here.x + nx * innerHalf;
      const innerLY = here.y + ny * innerHalf;
      const innerRX = here.x - nx * innerHalf;
      const innerRY = here.y - ny * innerHalf;
      trenchVertices.push(
        outerLX, topY, outerLY,
        innerLX, bottomY, innerLY,
        innerRX, bottomY, innerRY,
        outerRX, topY, outerRY
      );
      const waterY = bottomY + depth * 0.82;
      waterVertices.push(
        innerLX, waterY, innerLY,
        innerRX, waterY, innerRY
      );
      if (i > 0) {
        const a = (i - 1) * 4;
        const b = i * 4;
        trenchIndices.push(
          a, b, a + 1, a + 1, b, b + 1,
          a + 1, b + 1, a + 2, a + 2, b + 1, b + 2,
          a + 2, b + 2, a + 3, a + 3, b + 2, b + 3
        );
        const wa = (i - 1) * 2;
        const wb = i * 2;
        waterIndices.push(wa, wb, wa + 1, wa + 1, wb, wb + 1);
      }
    }
    const trenchGeometry = new THREE.BufferGeometry();
    trenchGeometry.setAttribute("position", new THREE.Float32BufferAttribute(trenchVertices, 3));
    trenchGeometry.setIndex(trenchIndices);
    trenchGeometry.computeVertexNormals();
    const trenchMaterial = new THREE.MeshStandardMaterial({
      color: 0x5b3f2a,
      roughness: 0.96,
      metalness: 0.01,
      side: THREE.DoubleSide,
    });
    const trenchMesh = new THREE.Mesh(trenchGeometry, trenchMaterial);
    group.add(trenchMesh);
    const waterGeometry = new THREE.BufferGeometry();
    waterGeometry.setAttribute("position", new THREE.Float32BufferAttribute(waterVertices, 3));
    waterGeometry.setIndex(waterIndices);
    waterGeometry.computeVertexNormals();
    const waterMesh = new THREE.Mesh(waterGeometry, waterMaterial);
    group.add(waterMesh);
    return group;
  }

  groupStraightRiverSections(sections) {
    const remaining = sections.slice();
    const groups = [];
    const endpointDist = 170;
    const angleLimit = Math.PI / 9;
    while (remaining.length) {
      const seed = remaining.shift();
      const group = [seed];
      let changed = true;
      while (changed) {
        changed = false;
        for (let i = remaining.length - 1; i >= 0; i--) {
          const candidate = remaining[i];
          if (this.shouldJoinRiverSectionGroup(group, candidate, endpointDist, angleLimit)) {
            group.push(candidate);
            remaining.splice(i, 1);
            changed = true;
          }
        }
      }
      groups.push(this.sortRiverSectionGroup(group));
    }
    return groups;
  }

  shouldJoinRiverSectionGroup(group, candidate, endpointDist, angleLimit) {
    for (const section of group) {
      const a = section.band;
      const b = candidate.band;
      if (!a?.points?.length || !b?.points?.length) continue;
      const angleA = a.sectionAngle || 0;
      const angleB = b.sectionAngle || 0;
      if (angleDelta(angleA, angleB) > angleLimit) continue;
      const aPts = [a.points[0], a.points[a.points.length - 1]];
      const bPts = [b.points[0], b.points[b.points.length - 1]];
      for (const pa of aPts) {
        for (const pb of bPts) {
          if (Math.hypot(pa.x - pb.x, pa.y - pb.y) <= endpointDist) return true;
        }
      }
    }
    return false;
  }

  sortRiverSectionGroup(group) {
    if (group.length <= 1) return group;
    const avgAngle = group.reduce((sum, section) => sum + (section.band?.sectionAngle || 0), 0) / group.length;
    const dirX = Math.cos(avgAngle);
    const dirY = Math.sin(avgAngle);
    return group.slice().sort((a, b) => {
      const ap = (a.band?.sectionCenterX || 0) * dirX + (a.band?.sectionCenterY || 0) * dirY;
      const bp = (b.band?.sectionCenterX || 0) * dirX + (b.band?.sectionCenterY || 0) * dirY;
      return ap - bp;
    });
  }

  addBridges(group = this.overworldDetailGroup, centerX = this.game?.hero?.x || 0, centerY = this.game?.hero?.y || 0, radius = OVERWORLD_PROP_RADIUS + 600) {
    const bridgeGroup = new THREE.Group();
    bridgeGroup.name = "bridges";
    const woodMat = new THREE.MeshStandardMaterial({ color: 0x8c6943, roughness: 0.93, metalness: 0.02 });
    const plankMat = new THREE.MeshStandardMaterial({ color: 0xb48b5e, roughness: 0.88, metalness: 0.02 });
    const railMat = new THREE.MeshStandardMaterial({ color: 0x5b4127, roughness: 0.95, metalness: 0.03 });
    const ropeMat = new THREE.MeshStandardMaterial({ color: 0x9e7b53, roughness: 0.96, metalness: 0.01 });

    for (const bridge of this.world.bridges || []) {
      const dx = (bridge.cx || 0) - centerX;
      const dy = (bridge.cy || 0) - centerY;
      if (dx * dx + dy * dy > radius * radius) continue;
      const length = Math.max(36, bridge.length || 80);
      const width = Math.max(26, (bridge.width || 34) * 0.72);
      const angle = -(bridge.angle || 0);
      const dirX = Math.cos(bridge.angle || 0);
      const dirY = Math.sin(bridge.angle || 0);
      const half = length * 0.5;
      const startX = bridge.start?.x ?? ((bridge.cx || 0) - dirX * half);
      const startY = bridge.start?.y ?? ((bridge.cy || 0) - dirY * half);
      const endX = bridge.end?.x ?? ((bridge.cx || 0) + dirX * half);
      const endY = bridge.end?.y ?? ((bridge.cy || 0) + dirY * half);
      const waterLift = (this.waterMesh?.position?.y ?? -2.5) + 9;
      const startBase = Math.max(this.sampleRenderedTerrainHeight(startX, startY), waterLift);
      const endBase = Math.max(this.sampleRenderedTerrainHeight(endX, endY), waterLift);
      const segments = Math.max(4, Math.round(length / 22));
      for (let i = 0; i < segments; i++) {
        const t = segments === 1 ? 0.5 : i / (segments - 1);
        const localX = (t - 0.5) * length;
        const camber = Math.sin(t * Math.PI) * 5.5;
        const segCenterX = startX + (endX - startX) * t;
        const segCenterY = startY + (endY - startY) * t;
        const baseHeight = startBase + (endBase - startBase) * t;
        const pos = new THREE.Vector3(segCenterX, baseHeight + 12 + camber, segCenterY);

        const deck = new THREE.Mesh(new THREE.BoxGeometry(length / segments + 4, 3.6, width), woodMat);
        deck.position.copy(pos);
        deck.rotation.y = angle;
        deck.castShadow = true;
        deck.receiveShadow = true;
        bridgeGroup.add(deck);

        const plank = new THREE.Mesh(new THREE.BoxGeometry(length / segments + 3, 1.2, width * 0.88), plankMat);
        plank.position.copy(pos);
        plank.position.y += 2.2;
        plank.rotation.y = angle;
        plank.receiveShadow = true;
        bridgeGroup.add(plank);

        for (const side of [-1, 1]) {
          const post = new THREE.Mesh(new THREE.BoxGeometry(2.8, 12 + camber * 0.14, 2.8), railMat);
          post.position.copy(pos);
          post.position.y += 7.5;
          const postOffset = new THREE.Vector3(0, 0, side * (width * 0.42));
          postOffset.applyAxisAngle(new THREE.Vector3(0, 1, 0), angle);
          post.position.add(postOffset);
          post.castShadow = true;
          bridgeGroup.add(post);
        }
      }

      for (const side of [-1, 1]) {
        const rail = this.makeRaisedBridgeRail(length, width * 0.43 * side, 18.5, angle, {
          x: startX,
          y: startY,
          z: startBase + 12,
        }, {
          x: endX,
          y: endY,
          z: endBase + 12,
        }, ropeMat);
        if (rail) bridgeGroup.add(rail);
      }
    }

    group.add(bridgeGroup);
  }

  makeRaisedBridgeRail(length, lateralOffset, height, angle, start, end, material) {
    const points = [];
    const segments = Math.max(5, Math.round(length / 20));
    for (let i = 0; i < segments; i++) {
      const t = segments === 1 ? 0.5 : i / (segments - 1);
      const camber = Math.sin(t * Math.PI) * 5.5;
      const baseX = start.x + (end.x - start.x) * t;
      const baseY = start.y + (end.y - start.y) * t;
      const baseZ = start.z + (end.z - start.z) * t;
      const point = new THREE.Vector3(baseX, baseZ + camber + height, baseY);
      const lateral = new THREE.Vector3(0, 0, lateralOffset);
      lateral.applyAxisAngle(new THREE.Vector3(0, 1, 0), angle);
      point.add(lateral);
      points.push(point);
    }
    const curve = new THREE.CatmullRomCurve3(points);
    const geometry = new THREE.TubeGeometry(curve, Math.max(18, segments * 3), 1.1, 6, false);
    const mesh = new THREE.Mesh(geometry, material);
    mesh.castShadow = true;
    return mesh;
  }

  addDocks(group = this.overworldDetailGroup, centerX = this.game?.hero?.x || 0, centerY = this.game?.hero?.y || 0, radius = OVERWORLD_PROP_RADIUS + 700) {
    const dockGroup = new THREE.Group();
    const dockMat = new THREE.MeshStandardMaterial({ color: 0x8a6b47, roughness: 0.95, metalness: 0.02 });
    const poleMat = new THREE.MeshStandardMaterial({ color: 0x5d4228, roughness: 0.98, metalness: 0.02 });

    for (const dock of this.world.docks || []) {
      const dx = (dock.x || 0) - centerX;
      const dy = (dock.y || 0) - centerY;
      if (dx * dx + dy * dy > radius * radius) continue;
      const pos = this.toVec3(dock.x, dock.y, 22);
      const deck = new THREE.Mesh(new THREE.BoxGeometry(44, 4, 26), dockMat);
      deck.position.copy(pos);
      deck.castShadow = true;
      dockGroup.add(deck);

      for (const side of [-1, 1]) {
        const post = new THREE.Mesh(new THREE.CylinderGeometry(1.8, 1.8, 10, 6), poleMat);
        post.position.set(pos.x + side * 18, pos.y - 3, pos.z + 9);
        dockGroup.add(post);
      }
    }

    group.add(dockGroup);
  }

  addSettlements(group = this.overworldDetailGroup, centerX = this.game?.hero?.x || 0, centerY = this.game?.hero?.y || 0, radius = OVERWORLD_PROP_RADIUS + 900) {
    const settlementGroup = new THREE.Group();
    const townMat = new THREE.MeshStandardMaterial({ color: 0xc4b18c, roughness: 0.92, metalness: 0.01 });
    const roofMat = new THREE.MeshStandardMaterial({ color: 0x5f4030, roughness: 0.96, metalness: 0.01 });
    const campMat = new THREE.MeshStandardMaterial({ color: 0x7e674a, roughness: 0.96, metalness: 0.01 });

    const addHouse = (x, y, sx, sz, h, opts = {}) => {
      const bodyMat = new THREE.MeshStandardMaterial({
        color: opts.color || 0xc4b18c,
        roughness: 0.9,
        metalness: 0.01,
      });
      const body = new THREE.Mesh(new THREE.BoxGeometry(sx, h, sz), bodyMat);
      body.position.copy(this.toVec3(x, y, h * 0.5 + 14));
      body.castShadow = true;
      body.receiveShadow = true;
      settlementGroup.add(body);

      const roof = new THREE.Mesh(new THREE.ConeGeometry(Math.max(sx, sz) * 0.7, h * 0.58, 4), roofMat);
      roof.position.copy(this.toVec3(x, y, h + 18));
      roof.rotation.y = Math.PI * 0.25;
      roof.castShadow = true;
      settlementGroup.add(roof);

      const door = new THREE.Mesh(new THREE.BoxGeometry(Math.max(10, sx * 0.14), Math.max(18, h * 0.42), 3.4), campMat);
      door.position.copy(this.toVec3(x, y + sz * 0.5 - 5, Math.max(14, h * 0.18)));
      settlementGroup.add(door);

      const lintel = new THREE.Mesh(new THREE.BoxGeometry(Math.max(16, sx * 0.24), 3.2, 4.2), roofMat);
      lintel.position.copy(this.toVec3(x, y + sz * 0.5 - 5, Math.max(24, h * 0.34)));
      settlementGroup.add(lintel);

      if (opts.service) {
        const signColor = opts.service === "vendor" ? 0xd8b56d : opts.service === "forge" ? 0x9aa9c0 : opts.service === "healer" ? 0xa7d9b5 : 0xc9cfd7;
        const sign = new THREE.Mesh(new THREE.BoxGeometry(10, 10, 2), new THREE.MeshStandardMaterial({ color: signColor, roughness: 0.78, metalness: 0.08 }));
        sign.position.copy(this.toVec3(x - sx * 0.18, y + sz * 0.5 - 5, Math.max(30, h * 0.42)));
        settlementGroup.add(sign);
      }
    };

    const withinRadius = (x, y) => {
      const dx = x - centerX;
      const dy = y - centerY;
      return dx * dx + dy * dy <= radius * radius;
    };

    if (this.world.startTown && withinRadius(this.world.startTown.x, this.world.startTown.y)) {
      addHouse(this.world.startTown.x, this.world.startTown.y, 120, 100, 58, { color: 0xbfa786 });
      for (const building of this.world.startTown.buildings || []) {
        addHouse(
          this.world.startTown.x + (building.x || 0),
          this.world.startTown.y + (building.y || 0),
          Math.max(26, (building.w || 40) * 0.85),
          Math.max(24, (building.h || 40) * 0.85),
          34,
          { color: building.color || "#7b654f", service: building.service || "" }
        );
      }
    }

    for (const town of this.world.towns || []) {
      if (!withinRadius(town.x, town.y)) continue;
      addHouse(town.x, town.y, 74, 58, 38, { color: 0xb69a74 });
      addHouse(town.x - 38, town.y + 42, 44, 34, 28, { color: 0x9f835f });
      addHouse(town.x + 46, town.y - 34, 40, 30, 26, { color: 0x8d775e });
    }

    for (const camp of this.world.camps || []) {
      if (!withinRadius(camp.x, camp.y)) continue;
      const tent = new THREE.Mesh(new THREE.ConeGeometry(14, 18, 4), campMat);
      tent.position.copy(this.toVec3(camp.x, camp.y, 18));
      tent.rotation.y = Math.PI * 0.25;
      tent.castShadow = true;
      settlementGroup.add(tent);
    }

    group.add(settlementGroup);
  }

  addLandmarks(group = this.overworldDetailGroup, centerX = this.game?.hero?.x || 0, centerY = this.game?.hero?.y || 0, radius = OVERWORLD_PROP_RADIUS + 950) {
    this.landmarkEntries.length = 0;
    const landmarkGroup = this.landmarkGroup;
    const mats = {
      waystone: new THREE.MeshStandardMaterial({ color: 0x7fe8ff, emissive: 0x174a5c, emissiveIntensity: 0.45, roughness: 0.65 }),
      dungeon: new THREE.MeshStandardMaterial({ color: 0x5e3a76, emissive: 0x28113d, emissiveIntensity: 0.55, roughness: 0.9 }),
      shrine: new THREE.MeshStandardMaterial({ color: 0xe6d8b6, emissive: 0x4d3a16, emissiveIntensity: 0.28, roughness: 0.72 }),
      cache: new THREE.MeshStandardMaterial({ color: 0xd4a650, roughness: 0.62, metalness: 0.18 }),
      herb: new THREE.MeshStandardMaterial({ color: 0x80d66e, emissive: 0x1b4818, emissiveIntensity: 0.2, roughness: 0.86 }),
      secret: new THREE.MeshStandardMaterial({ color: 0xbfd7c8, emissive: 0x243a32, emissiveIntensity: 0.2, roughness: 0.8 }),
      dragon: new THREE.MeshStandardMaterial({ color: 0x9d4434, emissive: 0x47150f, emissiveIntensity: 0.38, roughness: 0.82 }),
    };

    const addBeacon = (x, y, color, height = 140, radius = 7) => {
      const beacon = new THREE.Mesh(
        new THREE.CylinderGeometry(radius, radius * 0.45, height, 10, 1, true),
        new THREE.MeshBasicMaterial({ color, transparent: true, opacity: 0.24, depthWrite: false })
      );
      beacon.position.copy(this.toVec3(x, y, height * 0.5 + 28));
      return beacon;
    };

    const pushEntry = (type, point, mesh, beacon = null) => {
      const entry = { type, id: progressId(point), mesh, beacon };
      this.landmarkEntries.push(entry);
      landmarkGroup.add(mesh);
      if (beacon) landmarkGroup.add(beacon);
    };

    const withinRadius = (x, y) => {
      const dx = x - centerX;
      const dy = y - centerY;
      return dx * dx + dy * dy <= radius * radius;
    };

    for (const w of this.world.waystones || []) {
      if (!withinRadius(w.x, w.y)) continue;
      const mesh = new THREE.Mesh(new THREE.ConeGeometry(16, 58, 5), mats.waystone);
      mesh.position.copy(this.toVec3(w.x, w.y, 42));
      mesh.castShadow = true;
      pushEntry("waystone", w, mesh, addBeacon(w.x, w.y, 0x7fe8ff, 180, 5));
    }

    for (const d of this.world.dungeons || []) {
      if (!withinRadius(d.x, d.y)) continue;
      const mesh = new THREE.Mesh(new THREE.TorusGeometry(32, 6, 10, 28), mats.dungeon);
      mesh.position.copy(this.toVec3(d.x, d.y, 48));
      mesh.rotation.x = Math.PI * 0.5;
      mesh.castShadow = true;
      pushEntry("dungeon", d, mesh, addBeacon(d.x, d.y, 0xdc7cff, 210, 7));
    }

    for (const s of this.world.shrines || []) {
      if (!withinRadius(s.x, s.y)) continue;
      const shrine = new THREE.Group();
      const base = new THREE.Mesh(new THREE.CylinderGeometry(22, 28, 12, 8), mats.shrine);
      base.position.copy(this.toVec3(s.x, s.y, 18));
      base.castShadow = true;
      shrine.add(base);
      const pillar = new THREE.Mesh(new THREE.CylinderGeometry(8, 10, 48, 8), mats.shrine);
      pillar.position.copy(this.toVec3(s.x, s.y, 46));
      pillar.castShadow = true;
      shrine.add(pillar);
      pushEntry("shrine", s, shrine);
    }

    for (const c of this.world.caches || []) {
      if (!withinRadius(c.x, c.y)) continue;
      const mesh = new THREE.Mesh(new THREE.BoxGeometry(26, 18, 18), mats.cache);
      mesh.position.copy(this.toVec3(c.x, c.y, 22));
      mesh.castShadow = true;
      pushEntry("cache", c, mesh);
    }

    for (const herb of this.world.herbs || []) {
      if (!withinRadius(herb.x, herb.y)) continue;
      const mesh = new THREE.Mesh(new THREE.ConeGeometry(8, 26, 5), mats.herb);
      mesh.position.copy(this.toVec3(herb.x, herb.y, 22));
      mesh.castShadow = true;
      pushEntry("herb", herb, mesh);
    }

    for (const s of this.world.secrets || []) {
      if (!withinRadius(s.x, s.y)) continue;
      const mesh = new THREE.Mesh(new THREE.OctahedronGeometry(14), mats.secret);
      mesh.position.copy(this.toVec3(s.x, s.y, 32));
      mesh.castShadow = true;
      pushEntry("secret", s, mesh);
    }

    for (const lair of this.world.dragonLairs || []) {
      if (!withinRadius(lair.x, lair.y)) continue;
      const mesh = new THREE.Mesh(new THREE.ConeGeometry(48, 70, 7), mats.dragon);
      mesh.position.copy(this.toVec3(lair.x, lair.y, 46));
      mesh.castShadow = true;
      pushEntry("dragon", lair, mesh, addBeacon(lair.x, lair.y, 0xff8a5c, 240, 9));
    }

    group.add(landmarkGroup);
  }

  addWorldProps(parentGroup = this.overworldDetailGroup, centerX = this.game?.hero?.x || 0, centerY = this.game?.hero?.y || 0) {
    if (this.worldPropsGroup?.parent) {
      this.worldPropsGroup.parent.remove(this.worldPropsGroup);
      this.disposeGroup(this.worldPropsGroup);
      this.worldPropsGroup = null;
    }
    const group = new THREE.Group();
    const trunkMat = new THREE.MeshStandardMaterial({ color: 0x4c3523, roughness: 0.96 });
    const leafMat = new THREE.MeshStandardMaterial({ color: 0x3f6f42, roughness: 0.96, emissive: 0x102010, emissiveIntensity: 0.04 });
    const ashLeafMat = new THREE.MeshStandardMaterial({ color: 0x746d6d, roughness: 0.96, emissive: 0x161313, emissiveIntensity: 0.03 });
    const rockMat = new THREE.MeshStandardMaterial({ color: 0x7d817f, roughness: 0.94 });
    const brushMat = new THREE.MeshStandardMaterial({ color: 0x79895a, roughness: 0.96 });
    const dryBrushMat = new THREE.MeshStandardMaterial({ color: 0xa08a60, roughness: 0.97 });
    const trunkGeo = new THREE.CylinderGeometry(4, 6, 34, 6);
    const leafGeo = new THREE.ConeGeometry(20, 58, 8);
    const rockGeo = new THREE.DodecahedronGeometry(12, 0);
    const brushGeo = new THREE.ConeGeometry(7, 18, 5);
    const dummy = new THREE.Object3D();
    const activeRadius = this.world?.isBootWarm?.() ? OVERWORLD_PROP_RADIUS : Math.round(OVERWORLD_PROP_RADIUS * 0.58);
    const withinPropRadius = (x, y) => {
      const dx = x - centerX;
      const dy = y - centerY;
      return dx * dx + dy * dy <= activeRadius * activeRadius;
    };
    const trees = [];
    const ashTrees = [];
    const rocks = [];
    const clutter = [];
    const dryClutter = [];

    for (const tree of this.world._trees || []) {
      if (!withinPropRadius(tree.x, tree.y)) continue;
      if (this.roadDistanceAt(tree.x, tree.y) < 52) continue;
      const sample = this.world._sampleCell(tree.x, tree.y);
      const target = sample.zone === "ashlands" || sample.zone === "ash fields" ? ashTrees : trees;
      target.push({ x: tree.x, y: tree.y, scale: Math.max(0.7, tree.scale || 1) });
    }

    for (const rock of this.world._rocks || []) {
      if (!withinPropRadius(rock.x, rock.y)) continue;
      if (this.roadDistanceAt(rock.x, rock.y) < 28) continue;
      rocks.push({
        x: rock.x,
        y: rock.y,
        scale: Math.max(0.7, rock.scale || 1),
        rotX: (rock.seed || 0) * 0.01,
        rotY: (rock.seed || 0) * 0.013,
      });
    }

    for (const item of this.world._clutter || []) {
      if (!withinPropRadius(item.x, item.y)) continue;
      if (this.roadDistanceAt(item.x, item.y) < 42) continue;
      const sample = this.world._sampleCell(item.x, item.y);
      const target = sample.zone === "stone flats" || sample.zone === "ashlands" || sample.zone === "highlands" ? dryClutter : clutter;
      target.push({
        x: item.x,
        y: item.y,
        scale: Math.max(sample.zone === "stone flats" || sample.zone === "ashlands" || sample.zone === "highlands" ? 0.7 : 0.55, item.scale || 1),
        rotY: ((item.seed || 0) * 0.017) % (Math.PI * 2),
      });
    }

    const addInstances = (geo, mat, entries, liftScale, options = {}) => {
      if (!entries.length) return;
      const mesh = new THREE.InstancedMesh(geo, mat, entries.length);
      mesh.castShadow = options.castShadow !== false;
      mesh.receiveShadow = !!options.receiveShadow;
      entries.forEach((entry, index) => {
        const scale = entry.scale || 1;
        dummy.position.copy(this.toVec3(entry.x, entry.y, (liftScale || 0) * scale));
        dummy.rotation.set(entry.rotX || 0, entry.rotY || 0, entry.rotZ || 0);
        dummy.scale.setScalar(scale);
        dummy.updateMatrix();
        mesh.setMatrixAt(index, dummy.matrix);
      });
      mesh.instanceMatrix.needsUpdate = true;
      group.add(mesh);
    }

    addInstances(trunkGeo, trunkMat, trees, 26);
    addInstances(leafGeo, leafMat, trees, 64);
    addInstances(trunkGeo, trunkMat, ashTrees, 26);
    addInstances(leafGeo, ashLeafMat, ashTrees, 64);
    addInstances(rockGeo, rockMat, rocks, 16);
    addInstances(brushGeo, brushMat, clutter, 14);
    addInstances(brushGeo, dryBrushMat, dryClutter, 14);

    this.worldPropsGroup = group;
    this.worldPropsCenter = { x: centerX, y: centerY };
    this.worldPropsSignature = `${this.world?._trees?.length || 0}|${this.world?._rocks?.length || 0}|${this.world?._clutter?.length || 0}`;
    this.worldPropsRefreshAt = performance.now ? performance.now() : 0;
    parentGroup.add(group);
    this.worldPropsReady = !!this.world?.isBootWarm?.();
  }

  rebuildWorldPropsOnly(centerX = null, centerY = null) {
    if (!this.overworldDetailGroup) return;
    const center = centerX == null || centerY == null ? this.getActiveWorldCenter() : { x: centerX, y: centerY };
    this.addWorldProps(this.overworldDetailGroup, center.x, center.y);
    this.hudState.dirty = true;
  }

  disposeGroup(group) {
    if (!group) return;
    group.traverse((obj) => {
      obj.geometry?.dispose?.();
      const materials = Array.isArray(obj.material) ? obj.material : obj.material ? [obj.material] : [];
      for (const material of materials) material?.dispose?.();
    });
  }

  rebuildOverworldDetail(initial = false, includeProps = true, bootLite = false) {
    const center = this.getActiveWorldCenter();
    const centerX = center.x;
    const centerY = center.y;
    if (!initial && this.overworldDetailGroup) {
      this.overworldGroup.remove(this.overworldDetailGroup);
      this.disposeGroup(this.overworldDetailGroup);
    }
    this.overworldDetailGroup = new THREE.Group();
    this.landmarkGroup = new THREE.Group();
    this.detailCenter = { x: centerX, y: centerY };
    this.detailBootLite = !!bootLite;
    this.addRoads(this.overworldDetailGroup, centerX, centerY);
    this.addRivers(this.overworldDetailGroup, centerX, centerY);
    this.addBridges(this.overworldDetailGroup, centerX, centerY);
    this.addDocks(this.overworldDetailGroup, centerX, centerY);
    if (!bootLite) {
      this.addSettlements(this.overworldDetailGroup, centerX, centerY);
      this.addLandmarks(this.overworldDetailGroup, centerX, centerY);
    }
    if (includeProps) this.addWorldProps(this.overworldDetailGroup, centerX, centerY);
    else this.worldPropsGroup = null;
    this.overworldGroup.add(this.overworldDetailGroup);
    this.shadowState.dirty = true;
    this.hudState.dirty = true;
  }

  getActiveWorldCenter() {
    const buildMode = this.game?.mode === "build";
    if (buildMode && this.buildCamera?.active) {
      return {
        x: this.buildCamera.x || 0,
        y: this.buildCamera.y || 0,
      };
    }
    return {
      x: this.game?.hero?.x || 0,
      y: this.game?.hero?.y || 0,
    };
  }

  addHeroMarker() {
    const group = new THREE.Group();
    const makeMat = (color, roughness, metalness, extra = {}) =>
      new THREE.MeshStandardMaterial({ color, roughness, metalness, ...extra });
    const materials = {
      armor: makeMat(0x7f93aa, 0.52, 0.3),
      helm: makeMat(0xb9c9d8, 0.42, 0.36),
      cloth: makeMat(0x7a2634, 0.94, 0),
      trim: makeMat(0xd2b070, 0.64, 0.12),
      leather: makeMat(0x5a4030, 0.92, 0.02),
      skin: makeMat(0xe2c3b0, 0.95, 0),
      blade: makeMat(0xdce9f5, 0.32, 0.52),
      glow: makeMat(0x9ccfff, 0.28, 0.08, { emissive: 0x26435a, emissiveIntensity: 0.16 }),
      shadow: makeMat(0x4d1e29, 0.98, 0),
    };

    const root = new THREE.Group();
    root.scale.setScalar(0.74);
    const hips = new THREE.Group();
    const chest = new THREE.Group();
    chest.position.y = 17.5;
    root.add(hips);
    root.add(chest);

    const pelvis = new THREE.Mesh(new THREE.BoxGeometry(12.5, 7, 8.8), materials.armor);
    pelvis.position.set(0, 7.6, 0.8);
    pelvis.castShadow = true;
    hips.add(pelvis);

    const tabardBack = new THREE.Mesh(new THREE.BoxGeometry(11, 24, 2), materials.shadow);
    tabardBack.position.set(0, 14, -8);
    tabardBack.rotation.x = 0.18;
    tabardBack.castShadow = true;
    chest.add(tabardBack);

    const cloak = new THREE.Mesh(new THREE.BoxGeometry(16, 26, 2.2), materials.cloth);
    cloak.position.set(0, 13.5, -11);
    cloak.rotation.x = 0.14;
    cloak.castShadow = true;
    chest.add(cloak);

    const torso = new THREE.Mesh(new THREE.CapsuleGeometry(10.5, 18, 5, 10), materials.armor);
    torso.position.set(0, 8.6, 0);
    torso.scale.set(1.05, 1.08, 0.86);
    torso.castShadow = true;
    chest.add(torso);

    const chestPlate = new THREE.Mesh(new THREE.BoxGeometry(14, 18, 8), materials.glow);
    chestPlate.position.set(0, 8.8, 2.2);
    chestPlate.castShadow = true;
    chest.add(chestPlate);

    const tabard = new THREE.Mesh(new THREE.BoxGeometry(8.5, 22, 1.6), materials.cloth);
    tabard.position.set(0, 8, 5.2);
    tabard.castShadow = true;
    chest.add(tabard);

    const belt = new THREE.Mesh(new THREE.BoxGeometry(13.5, 3, 7.5), materials.trim);
    belt.position.set(0, 0.8, 1.5);
    belt.castShadow = true;
    chest.add(belt);

    const buckle = new THREE.Mesh(new THREE.BoxGeometry(4.2, 4.4, 1.5), materials.blade);
    buckle.position.set(0, 0.8, 5.2);
    chest.add(buckle);

    for (const side of [-1, 1]) {
      const pauldron = new THREE.Mesh(new THREE.SphereGeometry(5.8, 10, 10), materials.armor);
      pauldron.position.set(side * 10.5, 16.6, 0.6);
      pauldron.scale.set(1.05, 0.72, 1.2);
      pauldron.castShadow = true;
      chest.add(pauldron);
    }

    const neck = new THREE.Mesh(new THREE.CylinderGeometry(3.5, 3.8, 5, 8), materials.skin);
    neck.position.set(0, 21, 0.5);
    chest.add(neck);

    const helm = new THREE.Mesh(new THREE.SphereGeometry(8.8, 14, 12), materials.helm);
    helm.position.set(0, 26.4, 0);
    helm.scale.set(1, 1.04, 1.08);
    helm.castShadow = true;
    chest.add(helm);

    const visor = new THREE.Mesh(new THREE.BoxGeometry(10, 8, 6.4), materials.armor);
    visor.position.set(0, 25.6, 5.4);
    visor.castShadow = true;
    chest.add(visor);

    const crest = new THREE.Mesh(new THREE.BoxGeometry(2.2, 10, 6), materials.cloth);
    crest.position.set(0, 33.5, -1.2);
    crest.castShadow = true;
    chest.add(crest);

    const plume = new THREE.Mesh(new THREE.BoxGeometry(2, 11, 4.8), materials.trim);
    plume.position.set(0, 35.8, -0.2);
    plume.rotation.x = -0.25;
    plume.castShadow = true;
    chest.add(plume);

    const makeLeg = (side) => {
      const leg = new THREE.Group();
      leg.position.set(side * 4.8, 4.4, 0);
      const thigh = new THREE.Mesh(new THREE.CapsuleGeometry(3.8, 10, 4, 8), materials.armor);
      thigh.position.y = -6;
      thigh.castShadow = true;
      leg.add(thigh);
      const shin = new THREE.Mesh(new THREE.CapsuleGeometry(3.2, 8, 4, 8), materials.armor);
      shin.position.y = -16;
      shin.castShadow = true;
      leg.add(shin);
      const boot = new THREE.Mesh(new THREE.BoxGeometry(6.8, 4, 12), materials.leather);
      boot.position.set(0, -22.5, 3.4);
      boot.castShadow = true;
      leg.add(boot);
      return { leg, boot };
    };

    const leftLegRig = makeLeg(-1);
    const rightLegRig = makeLeg(1);
    hips.add(leftLegRig.leg);
    hips.add(rightLegRig.leg);

    const makeArm = (side) => {
      const arm = new THREE.Group();
      arm.position.set(side * 10.4, 29.8, 0.2);
      const upper = new THREE.Mesh(new THREE.CapsuleGeometry(3.2, 10, 4, 8), materials.armor);
      upper.rotation.z = side * 0.12;
      upper.castShadow = true;
      arm.add(upper);
      const fore = new THREE.Mesh(new THREE.CapsuleGeometry(2.8, 10, 4, 8), materials.armor);
      fore.position.set(side * 1.2, -9.5, 0.4);
      fore.castShadow = true;
      arm.add(fore);
      const glove = new THREE.Mesh(new THREE.SphereGeometry(3.2, 8, 8), materials.skin);
      glove.position.set(side * 1.6, -15.5, 1.4);
      glove.castShadow = true;
      arm.add(glove);
      return { arm, fore, glove };
    };

    const swordArmRig = makeArm(1);
    const shieldArmRig = makeArm(-1);
    root.add(swordArmRig.arm);
    root.add(shieldArmRig.arm);

    const sword = new THREE.Group();
    sword.position.set(4.5, -16, 2);
    const guard = new THREE.Mesh(new THREE.BoxGeometry(7, 1.7, 2.4), materials.trim);
    guard.castShadow = true;
    sword.add(guard);
    const grip = new THREE.Mesh(new THREE.CylinderGeometry(1.1, 1.1, 7, 6), materials.leather);
    grip.rotation.z = Math.PI * 0.5;
    grip.position.set(2.5, -0.5, 0);
    grip.castShadow = true;
    sword.add(grip);
    const pommel = new THREE.Mesh(new THREE.SphereGeometry(1.6, 8, 8), materials.trim);
    pommel.position.set(6.4, -0.5, 0);
    sword.add(pommel);
    const blade = new THREE.Mesh(new THREE.BoxGeometry(28, 1.8, 2.2), materials.blade);
    blade.position.set(-12, 0, 0);
    blade.castShadow = true;
    sword.add(blade);
    const bladeTip = new THREE.Mesh(new THREE.ConeGeometry(1.6, 6, 4), materials.blade);
    bladeTip.position.set(-29, 0, 0);
    bladeTip.rotation.z = -Math.PI * 0.5;
    bladeTip.castShadow = true;
    sword.add(bladeTip);
    sword.rotation.z = -0.95;
    swordArmRig.arm.add(sword);

    const shield = new THREE.Group();
    shield.position.set(-7.5, -9, 2.5);
    shield.rotation.y = -0.3;
    const shieldBody = new THREE.Mesh(new THREE.CylinderGeometry(7.5, 8.8, 3.4, 6), materials.armor);
    shieldBody.rotation.z = Math.PI * 0.5;
    shieldBody.castShadow = true;
    shield.add(shieldBody);
    const shieldFace = new THREE.Mesh(new THREE.CylinderGeometry(6.4, 7.4, 1.2, 6), materials.glow);
    shieldFace.rotation.z = Math.PI * 0.5;
    shieldFace.position.x = 1.8;
    shield.add(shieldFace);
    shieldArmRig.arm.add(shield);

    const boat = new THREE.Group();
    const hullMat = new THREE.MeshStandardMaterial({ color: 0x8a6240, roughness: 0.9, metalness: 0.04 });
    const trimMat = new THREE.MeshStandardMaterial({ color: 0xc8a06b, roughness: 0.84, metalness: 0.06 });
    const hull = new THREE.Mesh(new THREE.BoxGeometry(54, 12, 24), hullMat);
    hull.position.y = 10;
    hull.castShadow = true;
    boat.add(hull);
    const bow = new THREE.Mesh(new THREE.ConeGeometry(12, 24, 4), hullMat);
    bow.rotation.z = -Math.PI * 0.5;
    bow.position.set(38, 10, 0);
    bow.castShadow = true;
    boat.add(bow);
    const stern = new THREE.Mesh(new THREE.ConeGeometry(9, 16, 4), hullMat);
    stern.rotation.z = Math.PI * 0.5;
    stern.position.set(-33, 10, 0);
    stern.castShadow = true;
    boat.add(stern);
    const deck = new THREE.Mesh(new THREE.BoxGeometry(42, 2, 18), trimMat);
    deck.position.y = 15;
    boat.add(deck);
    const mast = new THREE.Mesh(
      new THREE.CylinderGeometry(2.2, 2.2, 42, 6),
      new THREE.MeshStandardMaterial({ color: 0xd9cfbf, roughness: 0.85, metalness: 0.02 })
    );
    mast.position.set(0, 34, 0);
    boat.add(mast);
    const sail = new THREE.Mesh(
      new THREE.BoxGeometry(1.2, 28, 22),
      new THREE.MeshStandardMaterial({ color: 0xe9e1d3, roughness: 0.92, metalness: 0.01 })
    );
    sail.position.set(8, 36, 0);
    boat.add(sail);
    for (const side of [-1, 1]) {
      const rail = new THREE.Mesh(new THREE.BoxGeometry(42, 2, 1.6), trimMat);
      rail.position.set(0, 17, side * 11.2);
      boat.add(rail);
    }
    boat.visible = false;
    group.add(boat);

    group.add(root);
    group.position.copy(this.toVec3(this.game.hero.x, this.game.hero.y, 0));
    group.userData.heroRig = {
      root,
      chest,
      hips,
      cloak,
      tabard,
      swordArm: swordArmRig.arm,
      shieldArm: shieldArmRig.arm,
      leftLeg: leftLegRig.leg,
      rightLeg: rightLegRig.leg,
      sword,
      shield,
      materials,
    };

    this.heroMarker = group;
    this.heroBoat = boat;
    this.scene.add(group);
  }

  createEnemyMesh(enemy) {
    const group = new THREE.Group();
    const primary = new THREE.Color(enemy?.colorA || "#d95b5b");
    const secondary = new THREE.Color(enemy?.colorB || "#5b6470");

    const bodyMat = new THREE.MeshStandardMaterial({
      color: primary,
      roughness: enemy?.kind === "wisp" ? 0.32 : 0.82,
      metalness: enemy?.kind === "sentinel" ? 0.24 : 0.04,
      emissive: enemy?.kind === "wisp" ? secondary : new THREE.Color(0x000000),
      emissiveIntensity: enemy?.kind === "wisp" ? 0.42 : 0,
    });
    const accentMat = new THREE.MeshStandardMaterial({
      color: secondary,
      roughness: 0.86,
      metalness: enemy?.boss ? 0.12 : 0.02,
    });

    const radius = Math.max(8, enemy?.radius || enemy?.r || 10);
    const tall = enemy?.kind === "dragon" ? radius * 2.4 : enemy?.kind === "brute" || enemy?.kind === "sentinel" ? radius * 1.8 : radius * 1.35;
    const body =
      enemy?.kind === "dragon"
        ? new THREE.Mesh(new THREE.CapsuleGeometry(radius * 0.95, tall, 7, 12), bodyMat)
        : enemy?.kind === "wisp"
          ? new THREE.Mesh(new THREE.SphereGeometry(radius * 1.2, 16, 12), bodyMat)
          : enemy?.kind === "blob"
            ? new THREE.Mesh(new THREE.SphereGeometry(radius * 0.92, 14, 12), bodyMat)
          : new THREE.Mesh(new THREE.CapsuleGeometry(radius * 0.75, tall, 6, 10), bodyMat);
    body.position.y = tall * 0.5 + radius * 0.8;
    body.castShadow = true;
    group.add(body);

    const head = new THREE.Mesh(new THREE.SphereGeometry(Math.max(5, radius * 0.48), 10, 8), accentMat);
    head.position.set(0, body.position.y + radius * 0.9, -2);
    head.castShadow = true;
    group.add(head);

    if (enemy?.kind === "dragon") {
      const wingMat = new THREE.MeshStandardMaterial({
        color: secondary,
        roughness: 0.82,
        metalness: 0.04,
        emissive: primary,
        emissiveIntensity: 0.08,
        side: THREE.DoubleSide,
      });
      for (const side of [-1, 1]) {
        const wing = new THREE.Mesh(new THREE.BoxGeometry(radius * 0.9, radius * 0.22, radius * 2.5), wingMat);
        wing.position.set(side * radius * 1.25, body.position.y + radius * 0.8, -radius * 0.1);
        wing.rotation.z = side * 0.55;
        wing.rotation.x = 0.22;
        wing.castShadow = true;
        group.add(wing);
      }
      const horn = new THREE.Mesh(new THREE.ConeGeometry(radius * 0.18, radius * 0.9, 5), accentMat);
      horn.position.set(radius * 0.28, head.position.y + radius * 0.35, -radius * 0.55);
      horn.rotation.z = -0.32;
      group.add(horn);
      const hornB = horn.clone();
      hornB.position.x *= -1;
      hornB.rotation.z *= -1;
      group.add(hornB);
      const tail = new THREE.Mesh(new THREE.CapsuleGeometry(radius * 0.22, radius * 1.2, 4, 8), bodyMat);
      tail.position.set(0, body.position.y * 0.75, -radius * 1.35);
      tail.rotation.x = Math.PI * 0.5;
      tail.castShadow = true;
      group.add(tail);
    } else if (enemy?.kind === "sentinel") {
      for (const side of [-1, 1]) {
        const plate = new THREE.Mesh(new THREE.BoxGeometry(radius * 0.5, radius * 1.2, radius * 0.35), accentMat);
        plate.position.set(side * radius * 0.8, body.position.y + radius * 0.3, 0);
        plate.rotation.z = side * 0.16;
        plate.castShadow = true;
        group.add(plate);
      }
      const crest = new THREE.Mesh(new THREE.BoxGeometry(radius * 0.18, radius * 0.9, radius * 0.48), accentMat);
      crest.position.set(0, head.position.y + radius * 0.5, -radius * 0.2);
      group.add(crest);
    } else if (enemy?.kind === "wisp") {
      const wispHalo = new THREE.Mesh(
        new THREE.TorusGeometry(radius * 1.45, Math.max(1.2, radius * 0.08), 8, 20),
        new THREE.MeshBasicMaterial({ color: secondary, transparent: true, opacity: 0.34, depthWrite: false })
      );
      wispHalo.position.y = body.position.y;
      wispHalo.rotation.x = Math.PI * 0.5;
      group.add(wispHalo);
    } else if (enemy?.kind === "brute") {
      for (const side of [-1, 1]) {
        const fist = new THREE.Mesh(new THREE.BoxGeometry(radius * 0.44, radius * 0.52, radius * 0.44), accentMat);
        fist.position.set(side * radius * 0.9, radius * 0.95, radius * 0.1);
        fist.castShadow = true;
        group.add(fist);
      }
    } else if (enemy?.kind === "wolf") {
      body.scale.set(1.36, 0.78, 0.9);
      body.rotation.z = Math.PI * 0.5;
      body.position.y = radius * 1.12;
      head.scale.set(1.12, 0.9, 1.38);
      head.position.set(radius * 0.95, radius * 1.6, 0);
      for (const side of [-1, 1]) {
        const ear = new THREE.Mesh(new THREE.ConeGeometry(radius * 0.16, radius * 0.55, 4), accentMat);
        ear.position.set(radius * 1.16, radius * 2.18, side * radius * 0.24);
        ear.rotation.z = side * 0.18;
        group.add(ear);
      }
      for (const lx of [-0.6, 0.6]) {
        for (const lz of [-0.34, 0.34]) {
          const leg = new THREE.Mesh(new THREE.CylinderGeometry(radius * 0.14, radius * 0.18, radius * 1.25, 6), accentMat);
          leg.position.set(lx * radius * 1.2, radius * 0.44, lz * radius * 1.1);
          leg.castShadow = true;
          group.add(leg);
        }
      }
      const tail = new THREE.Mesh(new THREE.CapsuleGeometry(radius * 0.1, radius * 0.8, 4, 6), accentMat);
      tail.position.set(-radius * 1.18, radius * 1.55, 0);
      tail.rotation.z = -0.85;
      group.add(tail);
    } else if (enemy?.kind === "blob") {
      body.scale.set(1.15, 0.78, 1.15);
      body.position.y = radius * 0.98;
      head.scale.set(0.82, 0.76, 0.92);
      head.position.set(0, radius * 1.82, radius * 0.12);
      for (const side of [-1, 1]) {
        const horn = new THREE.Mesh(new THREE.ConeGeometry(radius * 0.14, radius * 0.55, 4), accentMat);
        horn.position.set(side * radius * 0.34, radius * 2.18, -radius * 0.18);
        horn.rotation.z = side * 0.26;
        horn.rotation.x = 0.22;
        group.add(horn);
        const arm = new THREE.Mesh(new THREE.CapsuleGeometry(radius * 0.12, radius * 0.62, 4, 6), accentMat);
        arm.position.set(side * radius * 0.78, radius * 0.9, radius * 0.1);
        arm.rotation.z = side * 0.48;
        group.add(arm);
        const leg = new THREE.Mesh(new THREE.CapsuleGeometry(radius * 0.14, radius * 0.56, 4, 6), accentMat);
        leg.position.set(side * radius * 0.28, radius * 0.22, 0);
        group.add(leg);
      }
      const jaw = new THREE.Mesh(new THREE.BoxGeometry(radius * 0.56, radius * 0.22, radius * 0.42), bodyMat);
      jaw.position.set(0, radius * 1.48, radius * 0.58);
      group.add(jaw);
    } else {
      for (const side of [-1, 1]) {
        const leg = new THREE.Mesh(new THREE.CapsuleGeometry(radius * 0.14, radius * 0.95, 4, 6), accentMat);
        leg.position.set(side * radius * 0.34, radius * 0.42, 0);
        leg.castShadow = true;
        group.add(leg);
      }
      for (const side of [-1, 1]) {
        const arm = new THREE.Mesh(new THREE.CapsuleGeometry(radius * 0.12, radius * 0.84, 4, 6), accentMat);
        arm.position.set(side * radius * 0.74, body.position.y - radius * 0.08, 0);
        arm.rotation.z = side * 0.22;
        arm.castShadow = true;
        group.add(arm);
      }
      if (enemy?.kind === "caster") {
        const hood = new THREE.Mesh(new THREE.ConeGeometry(radius * 0.56, radius * 0.96, 6), bodyMat);
        hood.position.set(0, head.position.y + radius * 0.28, -radius * 0.12);
        group.add(hood);
        const staff = new THREE.Mesh(new THREE.CylinderGeometry(radius * 0.08, radius * 0.08, radius * 2.2, 6), accentMat);
        staff.position.set(radius * 0.86, radius * 1.28, 0);
        staff.rotation.z = 0.22;
        group.add(staff);
      } else if (enemy?.kind === "mender") {
        const hood = new THREE.Mesh(new THREE.ConeGeometry(radius * 0.54, radius * 0.88, 6), bodyMat);
        hood.position.set(0, head.position.y + radius * 0.26, -radius * 0.1);
        group.add(hood);
        const satchel = new THREE.Mesh(new THREE.BoxGeometry(radius * 0.62, radius * 0.46, radius * 0.28), bodyMat);
        satchel.position.set(-radius * 0.66, body.position.y - radius * 0.08, -radius * 0.42);
        group.add(satchel);
        const staff = new THREE.Mesh(new THREE.CylinderGeometry(radius * 0.08, radius * 0.08, radius * 2.05, 6), accentMat);
        staff.position.set(radius * 0.82, radius * 1.24, 0);
        staff.rotation.z = 0.18;
        group.add(staff);
      } else if (enemy?.kind === "thorn" || enemy?.kind === "ashling") {
        for (const side of [-1, 1]) {
          const spike = new THREE.Mesh(new THREE.ConeGeometry(radius * 0.18, radius * 0.65, 5), accentMat);
          spike.position.set(side * radius * 0.4, body.position.y + radius * 0.42, -radius * 0.42);
          spike.rotation.z = side * 0.35;
          group.add(spike);
        }
      } else if (enemy?.kind === "duelist" || enemy?.kind === "scout" || enemy?.kind === "stalker") {
        const shoulderCape = new THREE.Mesh(new THREE.BoxGeometry(radius * 1.18, radius * 0.85, radius * 0.12), bodyMat);
        shoulderCape.position.set(0, body.position.y + radius * 0.18, -radius * 0.52);
        shoulderCape.rotation.x = 0.18;
        group.add(shoulderCape);
        if (enemy?.kind !== "stalker") {
          const blade = new THREE.Mesh(new THREE.BoxGeometry(radius * 0.92, radius * 0.08, radius * 0.12), accentMat);
          blade.position.set(radius * 0.96, radius * 1.18, 0);
          blade.rotation.z = 0.28;
          group.add(blade);
        }
      }
    }

    if (enemy?.elite || enemy?.boss) {
      const halo = new THREE.Mesh(
        new THREE.TorusGeometry(radius * 1.18, Math.max(1.8, radius * 0.12), 8, 18),
        new THREE.MeshStandardMaterial({
          color: enemy.boss ? 0xff8a5c : 0xffd36e,
          emissive: enemy.boss ? 0x63210f : 0x6b5211,
          emissiveIntensity: 0.46,
          roughness: 0.48,
          metalness: 0.08,
        })
      );
      halo.position.y = body.position.y + radius * 2.2;
      halo.rotation.x = Math.PI * 0.5;
      group.add(halo);
    }

    const healthBack = new THREE.Mesh(
      new THREE.BoxGeometry(radius * 3.1, 3, 2),
      new THREE.MeshBasicMaterial({ color: 0x1b1512, depthWrite: false })
    );
    healthBack.position.set(0, body.position.y + radius * 2.8, 0);
    group.add(healthBack);

    const health = new THREE.Mesh(
      new THREE.BoxGeometry(radius * 2.95, 4, 2.4),
      new THREE.MeshBasicMaterial({ color: 0xff6b5c, depthWrite: false })
    );
    health.position.set(0, body.position.y + radius * 2.8, 1);
    group.add(health);
    group.userData.health = health;
    group.userData.body = body;
    return group;
  }

  createProjectileMesh(projectile) {
    if (projectile?.nova) {
      return new THREE.Mesh(
        new THREE.TorusGeometry(Math.max(8, projectile.hitRadius || 14), 1.6, 10, 28),
        new THREE.MeshBasicMaterial({
          color: projectile?.color || 0xd6f5ff,
          transparent: true,
          opacity: 0.4,
          depthWrite: false,
        })
      );
    }

    const radius = Math.max(2, projectile?.radius || 4);
    return new THREE.Mesh(
      new THREE.SphereGeometry(radius, 10, 10),
      new THREE.MeshStandardMaterial({
        color: projectile?.color || 0xffffff,
        emissive: projectile?.color || 0xffffff,
        emissiveIntensity: 0.4,
        roughness: 0.28,
        metalness: 0.08,
      })
    );
  }

  createLootMesh(loot) {
    if (!loot?.kind || loot.kind === "gold") {
      const group = new THREE.Group();
      const mat = new THREE.MeshStandardMaterial({ color: 0xefc24a, roughness: 0.48, metalness: 0.22, emissive: 0x4a3410, emissiveIntensity: 0.08 });
      for (let i = 0; i < 4; i++) {
        const coin = new THREE.Mesh(new THREE.SphereGeometry(4 + (i % 2), 8, 8), mat);
        coin.scale.y = 0.32;
        coin.position.set((i - 1.5) * 3.8, 4 + (i % 2), ((i % 2) - 0.5) * 5);
        coin.castShadow = true;
        group.add(coin);
      }
      return group;
    }

    let geometry = new THREE.OctahedronGeometry(7);
    let material = new THREE.MeshStandardMaterial({ color: 0xefc24a, roughness: 0.55, metalness: 0.18 });
    if (loot?.kind === "potion") {
      geometry = new THREE.CylinderGeometry(4.2, 5.4, 11, 10);
      material = new THREE.MeshStandardMaterial({
        color: loot?.data?.potionType === "mana" ? 0x6aa6ff : 0xdf5b72,
        roughness: 0.42,
        metalness: 0.06,
        emissive: loot?.data?.potionType === "mana" ? 0x16386b : 0x4c1825,
        emissiveIntensity: 0.28,
      });
    } else if (loot?.kind === "key") {
      geometry = new THREE.TorusGeometry(5.8, 1.5, 8, 18);
      material = new THREE.MeshStandardMaterial({ color: 0x8be9ff, roughness: 0.4, metalness: 0.22 });
    } else if (loot?.kind === "gear") {
      geometry = new THREE.BoxGeometry(8, 24, 4);
      material = new THREE.MeshStandardMaterial({
        color: loot?.data?.color || 0xd9dee8,
        emissive: loot?.data?.rarity === "epic" ? 0x4b2a15 : 0x000000,
        emissiveIntensity: loot?.data?.rarity === "epic" ? 0.22 : 0,
        roughness: 0.44,
        metalness: 0.3,
      });
    }

    const mesh = new THREE.Mesh(geometry, material);
    mesh.castShadow = true;
    return mesh;
  }

  getDungeonTheme3D() {
    return this.game?._dungeonTheme?.(Math.max(1, this.game?.dungeon?.floor || 1)) || {
      name: "Dungeon",
      floor0: "#252830",
      floor1: "#1a1f27",
      floor2: "#12161d",
      haze: "rgba(160,200,255,0.03)",
      accent: "rgba(180,144,96,0.28)",
      propA: "#4b5260",
      propB: "#343a44",
    };
  }

  shadeColorHex(hex, amount = 0) {
    const color = new THREE.Color(hex);
    const f = clamp(amount, -1, 1);
    if (f >= 0) color.lerp(new THREE.Color(0xffffff), f);
    else color.lerp(new THREE.Color(0x000000), -f);
    return color;
  }

  createDungeonDecorMesh(item, theme) {
    const propA = this.shadeColorHex(theme.propA || "#4b5260", 0);
    const propB = this.shadeColorHex(theme.propB || "#343a44", 0);
    const accent = this.shadeColorHex(theme.floor0 || "#252830", 0.32);
    const root = new THREE.Group();
    const sx = item?.sx || 1;
    const sy = item?.sy || 1;
    root.scale.set(sx, 1, sy);

    const makeBox = (w, h, d, color, x = 0, y = 0, z = 0, castShadow = true) => {
      const mesh = new THREE.Mesh(
        new THREE.BoxGeometry(w, h, d),
        this.getSharedMaterial(
          `decor:${color.getHexString ? color.getHexString() : color}:${w}:${h}:${d}`,
          () => new THREE.MeshStandardMaterial({ color, roughness: 0.92, metalness: 0.04 })
        )
      );
      mesh.position.set(x, y, z);
      mesh.castShadow = castShadow;
      mesh.receiveShadow = true;
      root.add(mesh);
      return mesh;
    };

    switch (item?.kind) {
      case "pillar":
        makeBox(22, 48, 22, propB, 0, 24, 0);
        makeBox(30, 8, 30, propA, 0, 4, 0);
        makeBox(32, 8, 32, propA, 0, 48, 0);
        break;
      case "rubble":
        for (let i = 0; i < 4; i++) {
          const size = 8 + (i % 2) * 5;
          const rock = new THREE.Mesh(
            new THREE.DodecahedronGeometry(size, 0),
            new THREE.MeshStandardMaterial({ color: i % 2 ? propB : propA, roughness: 0.96, metalness: 0.02 })
          );
          rock.position.set(-18 + i * 11, size * 0.5, -4 + (i % 2) * 8);
          rock.rotation.set(i * 0.2, i * 0.35, i * 0.12);
          rock.castShadow = true;
          root.add(rock);
        }
        break;
      case "crate":
        makeBox(34, 24, 26, this.shadeColorHex("#5a4632", 0), 0, 12, 0);
        makeBox(36, 3, 28, this.shadeColorHex("#8a6b4a", 0.08), 0, 25, 0, false);
        break;
      case "table":
        makeBox(52, 4, 24, this.shadeColorHex("#61462f", 0.02), 0, 18, 0);
        for (const ox of [-18, 18]) {
          for (const oz of [-8, 8]) makeBox(4, 18, 4, this.shadeColorHex("#3b2a1e", 0), ox, 9, oz);
        }
        break;
      case "shelf":
        makeBox(56, 24, 10, this.shadeColorHex("#3a2f24", 0), 0, 12, 0);
        makeBox(58, 3, 12, this.shadeColorHex("#71573b", 0.08), 0, 4, 0, false);
        makeBox(58, 3, 12, this.shadeColorHex("#71573b", 0.08), 0, 14, 0, false);
        break;
      case "banner":
        makeBox(6, 12, 6, this.shadeColorHex("#3f2636", 0), 0, 34, -1);
        makeBox(24, 28, 3, this.shadeColorHex("#7a4da0", 0.02), 0, 14, 0);
        break;
      case "brazer":
      case "sconce": {
        const bowl = new THREE.Mesh(
          new THREE.CylinderGeometry(7, 9, 7, 8),
          new THREE.MeshStandardMaterial({ color: this.shadeColorHex("#584b3a", 0), roughness: 0.9, metalness: 0.08 })
        );
        bowl.position.y = 7;
        bowl.castShadow = true;
        root.add(bowl);
        const flame = new THREE.Mesh(
          new THREE.SphereGeometry(item.kind === "sconce" ? 8 : 10, 10, 10),
          new THREE.MeshStandardMaterial({
            color: 0xffbd64,
            emissive: 0xff8a34,
            emissiveIntensity: 0.6,
            roughness: 0.3,
            metalness: 0,
          })
        );
        flame.position.y = 18;
        flame.scale.y = 1.5;
        root.add(flame);
        const halo = new THREE.Mesh(
          new THREE.PlaneGeometry(item.kind === "sconce" ? 44 : 56, item.kind === "sconce" ? 44 : 56),
          new THREE.MeshBasicMaterial({ color: 0xffc86a, transparent: true, opacity: 0.12, depthWrite: false, blending: THREE.AdditiveBlending })
        );
        halo.position.y = 18;
        halo.rotation.x = -Math.PI * 0.5;
        root.add(halo);
        break;
      }
      case "pool": {
        const pool = new THREE.Mesh(
          new THREE.CylinderGeometry(34, 38, 3, 24),
          new THREE.MeshStandardMaterial({
            color: 0x5ab8ff,
            emissive: 0x173b57,
            emissiveIntensity: 0.22,
            transparent: true,
            opacity: 0.84,
            roughness: 0.18,
            metalness: 0.04,
          })
        );
        pool.position.y = 2;
        pool.scale.z = 0.58;
        root.add(pool);
        const rim = new THREE.Mesh(
          new THREE.TorusGeometry(36, 2.2, 8, 24),
          new THREE.MeshStandardMaterial({ color: 0xa0e8ff, roughness: 0.62, metalness: 0.08 })
        );
        rim.rotation.x = Math.PI * 0.5;
        rim.position.y = 3.5;
        rim.scale.set(1, 1, 0.62);
        root.add(rim);
        break;
      }
      case "dais":
        makeBox(112, 12, 60, this.shadeColorHex("#463027", 0), 0, 6, 0);
        makeBox(82, 12, 40, this.shadeColorHex("#6a4938", 0.06), 0, 18, 0);
        break;
      case "bones":
        for (const side of [-1, 1]) {
          const bone = new THREE.Mesh(new THREE.CapsuleGeometry(2.6, 22, 4, 6), this.getSharedMaterial("decor:bone", () => new THREE.MeshStandardMaterial({ color: 0xd6ccb8, roughness: 0.92, metalness: 0.02 })));
          bone.position.set(side * 10, 4, side * 6);
          bone.rotation.z = side * 0.85;
          root.add(bone);
        }
        break;
      case "stalagmite":
        for (let i = 0; i < 3; i++) {
          const spike = new THREE.Mesh(new THREE.ConeGeometry(8 + i * 2, 24 + i * 8, 5), new THREE.MeshStandardMaterial({ color: this.shadeColorHex("#49362d", 0.02), roughness: 0.95, metalness: 0.02 }));
          spike.position.set((i - 1) * 14, 12 + i * 4, (i % 2 ? -1 : 1) * 8);
          spike.castShadow = true;
          root.add(spike);
        }
        break;
      case "treasure":
        makeBox(34, 20, 24, this.shadeColorHex("#71492d", 0), 0, 10, 0);
        makeBox(36, 4, 26, this.shadeColorHex("#d7af61", 0.04), 0, 16, 0, false);
        break;
      case "lava": {
        const pool = new THREE.Mesh(
          new THREE.CylinderGeometry(28, 34, 2.6, 20),
          new THREE.MeshStandardMaterial({
            color: 0xff7a34,
            emissive: 0xb63012,
            emissiveIntensity: 0.6,
            roughness: 0.26,
            metalness: 0.02,
            transparent: true,
            opacity: 0.95,
          })
        );
        pool.position.y = 2;
        pool.scale.z = 0.7;
        root.add(pool);
        break;
      }
      default:
        makeBox(16, 16, 16, accent, 0, 8, 0);
        break;
    }

    return root;
  }

  createDungeonScene() {
    this.dungeonGroup.clear();
    this.dungeonRoomMeshes.clear();
    this.dungeonDoorMeshes.clear();
    this.dungeonCacheMeshes.clear();
    this.dungeonHoardGroup = null;
    const layout = this.game?.dungeon?.layout;
    if (!layout) return;

    const isDragonLair = this.game?.dungeon?.kind === "dragon-lair";
    const theme = this.getDungeonTheme3D();
    const palette = isDragonLair
      ? {
          floor0: "#4a2d1c",
          floor1: "#2a1911",
          floor2: "#120b08",
          propA: "#9c5532",
          propB: "#564136",
        }
      : theme;
    const floorMat = new THREE.MeshStandardMaterial({
      color: this.shadeColorHex(palette.floor1 || "#1d2027", isDragonLair ? 0.1 : 0.22),
      emissive: this.shadeColorHex(palette.floor0 || "#2a2d33", isDragonLair ? 0.12 : 0.06),
      emissiveIntensity: 0.08,
      roughness: 0.94,
      metalness: 0.04,
    });
    const floorAccentMat = new THREE.MeshStandardMaterial({
      color: this.shadeColorHex(palette.floor0 || "#2a2d33", isDragonLair ? 0.2 : 0.34),
      emissive: this.shadeColorHex(palette.propA || "#4b5260", isDragonLair ? 0.14 : 0.08),
      emissiveIntensity: 0.1,
      roughness: 0.86,
      metalness: 0.06,
    });
    const bossFloorMat = new THREE.MeshStandardMaterial({
      color: this.shadeColorHex(palette.propA || "#4b5260", isDragonLair ? 0.12 : 0.28),
      emissive: this.shadeColorHex(palette.propA || "#4b5260", isDragonLair ? 0.28 : 0.14),
      emissiveIntensity: 0.14,
      roughness: 0.84,
      metalness: 0.08,
    });
    const wallMat = new THREE.MeshStandardMaterial({
      color: this.shadeColorHex(palette.floor2 || "#12161d", isDragonLair ? 0.08 : 0.18),
      emissive: this.shadeColorHex(palette.floor1 || "#1d2027", isDragonLair ? 0.08 : 0.04),
      emissiveIntensity: 0.05,
      roughness: 0.9,
      metalness: 0.08,
    });
    const lairRockMat = isDragonLair
      ? new THREE.MeshStandardMaterial({
          color: 0x46352c,
          roughness: 0.97,
          metalness: 0.02,
        })
      : null;
    const trimMat = new THREE.MeshStandardMaterial({
      color: this.shadeColorHex(palette.propB || "#343a44", isDragonLair ? 0.22 : 0.34),
      roughness: 0.78,
      metalness: 0.12,
    });
    const hazeMat = new THREE.MeshBasicMaterial({
      color: this.shadeColorHex(palette.propA || "#4b5260", isDragonLair ? 0.3 : 0.42),
      transparent: true,
      opacity: isDragonLair ? 0.04 : 0.07,
      depthWrite: false,
      blending: THREE.AdditiveBlending,
    });
    const lineMat = new THREE.MeshBasicMaterial({
      color: this.shadeColorHex(palette.propA || "#4b5260", isDragonLair ? 0.62 : 0.5),
      transparent: true,
      opacity: 0.28,
      depthWrite: false,
    });
    const bossRingMat = new THREE.MeshBasicMaterial({
      color: this.shadeColorHex(palette.propA || "#4b5260", isDragonLair ? 0.92 : 0.72),
      transparent: true,
      opacity: 0.34,
      depthWrite: false,
      side: THREE.DoubleSide,
    });
    const addWallBox = (x, y, w, h, tall = 56) => {
      if (w <= 4 || h <= 4) return;
      const wall = new THREE.Mesh(
        new THREE.BoxGeometry(Math.max(6, w), tall, Math.max(6, h)),
        wallMat
      );
      wall.position.copy(this.toDungeonVec3(x, y, tall * 0.5));
      wall.castShadow = true;
      wall.receiveShadow = true;
      this.dungeonGroup.add(wall);
    };
    const addWallSegmentsForRoom = (room) => {
      const wall = room.kind === "corridor" ? 8 : 10;
      const openingsBySide = { top: [], right: [], bottom: [], left: [] };
      for (const opening of room.openings || []) openingsBySide[opening.side].push(opening);
      const left = room.x - room.w * 0.5;
      const right = room.x + room.w * 0.5;
      const top = room.y - room.h * 0.5;
      const bottom = room.y + room.h * 0.5;

      const addHorizontal = (side) => {
        const y = side === "top" ? top + wall * 0.5 : bottom - wall * 0.5;
        const openings = openingsBySide[side].slice().sort((a, b) => a.center - b.center);
        let cursor = left;
        for (const opening of openings) {
          const gapLeft = Math.max(left, opening.center - opening.span * 0.5);
          const gapRight = Math.min(right, opening.center + opening.span * 0.5);
          if (gapLeft > cursor) addWallBox((cursor + gapLeft) * 0.5, y, gapLeft - cursor, wall);
          cursor = Math.max(cursor, gapRight);
        }
        if (cursor < right) addWallBox((cursor + right) * 0.5, y, right - cursor, wall);
      };
      const addVertical = (side) => {
        const x = side === "left" ? left + wall * 0.5 : right - wall * 0.5;
        const openings = openingsBySide[side].slice().sort((a, b) => a.center - b.center);
        let cursor = top;
        for (const opening of openings) {
          const gapTop = Math.max(top, opening.center - opening.span * 0.5);
          const gapBottom = Math.min(bottom, opening.center + opening.span * 0.5);
          if (gapTop > cursor) addWallBox(x, (cursor + gapTop) * 0.5, wall, gapTop - cursor);
          cursor = Math.max(cursor, gapBottom);
        }
        if (cursor < bottom) addWallBox(x, (cursor + bottom) * 0.5, wall, bottom - cursor);
      };
      addHorizontal("top");
      addHorizontal("bottom");
      addVertical("left");
      addVertical("right");
    };

    const surfaceRects = [...(layout.rooms || []), ...(layout.corridors || [])];
    for (const room of surfaceRects) {
      const roomGroup = new THREE.Group();
      const isBoss = room.type === "boss";
      const isCorridor = room.kind === "corridor";

      const floor = new THREE.Mesh(
        new THREE.BoxGeometry(Math.max(24, room.w || 80), 6, Math.max(24, room.h || 80)),
        isBoss ? bossFloorMat : floorMat
      );
      floor.position.copy(this.toDungeonVec3(room.x, room.y, -1));
      floor.receiveShadow = true;
      roomGroup.add(floor);

      if (isDragonLair) {
        for (let i = 0; i < 8; i++) {
          const rock = new THREE.Mesh(
            new THREE.DodecahedronGeometry(10 + (i % 3) * 4, 0),
            lairRockMat
          );
          const side = i < 4 ? -1 : 1;
          const edgeT = (i % 4) / 3;
          rock.position.copy(this.toDungeonVec3(
            room.x + side * room.w * 0.42,
            room.y - room.h * 0.32 + edgeT * room.h * 0.64,
            10 + (i % 2) * 4
          ));
          rock.rotation.set(i * 0.24, i * 0.37, i * 0.16);
          rock.castShadow = true;
          rock.receiveShadow = true;
          roomGroup.add(rock);
        }
      }

      const inset = isCorridor ? 20 : 28;
      const inner = new THREE.Mesh(
        new THREE.BoxGeometry(Math.max(16, room.w - inset), 1.6, Math.max(16, room.h - inset)),
        isBoss ? floorAccentMat : trimMat
      );
      inner.position.copy(this.toDungeonVec3(room.x, room.y, 2.8));
      inner.receiveShadow = true;
      roomGroup.add(inner);

      if (!isDragonLair) {
        const lineA = new THREE.Mesh(
          new THREE.PlaneGeometry(Math.max(24, room.w - inset - 24), 3.2),
          lineMat
        );
        lineA.rotation.x = -Math.PI * 0.5;
        lineA.position.copy(this.toDungeonVec3(room.x, room.y - (room.h * 0.18), 3.95));
        roomGroup.add(lineA);

        const lineB = new THREE.Mesh(
          new THREE.PlaneGeometry(3.2, Math.max(24, room.h - inset - 24)),
          lineMat
        );
        lineB.rotation.x = -Math.PI * 0.5;
        lineB.position.copy(this.toDungeonVec3(room.x + (room.w * 0.18), room.y, 3.96));
        roomGroup.add(lineB);

        const haze = new THREE.Mesh(new THREE.PlaneGeometry(Math.max(40, room.w - 36), Math.max(40, room.h - 36)), hazeMat);
        haze.rotation.x = -Math.PI * 0.5;
        haze.position.copy(this.toDungeonVec3(room.x, room.y, 3.8));
        roomGroup.add(haze);
      } else {
        const scorchPlate = new THREE.Mesh(
          new THREE.PlaneGeometry(Math.max(52, room.w - 42), Math.max(52, room.h - 42)),
          new THREE.MeshBasicMaterial({
            color: room.type === "boss" ? 0x5e1d0f : 0x3a1f15,
            transparent: true,
            opacity: room.type === "boss" ? 0.34 : 0.16,
            depthWrite: false,
          })
        );
        scorchPlate.rotation.x = -Math.PI * 0.5;
        scorchPlate.position.copy(this.toDungeonVec3(room.x, room.y, 3.85));
        roomGroup.add(scorchPlate);

        const rimMat = new THREE.MeshStandardMaterial({
          color: 0x4d372d,
          roughness: 0.96,
          metalness: 0.02,
        });
        for (let i = 0; i < 5; i++) {
          const tooth = new THREE.Mesh(new THREE.DodecahedronGeometry(8 + (i % 2) * 3, 0), rimMat);
          tooth.position.copy(this.toDungeonVec3(
            room.x - room.w * 0.34 + i * (room.w * 0.17),
            room.y - room.h * 0.33,
            8 + (i % 3) * 2
          ));
          tooth.castShadow = true;
          tooth.receiveShadow = true;
          roomGroup.add(tooth);
        }
      }

      if (!isCorridor) {
        if (room.type === "boss") {
          const ring = new THREE.Mesh(
            new THREE.RingGeometry(Math.max(42, Math.min(room.w, room.h) * 0.12), Math.max(60, Math.min(room.w, room.h) * 0.18), 28),
            bossRingMat
          );
          ring.rotation.x = -Math.PI * 0.5;
          ring.position.copy(this.toDungeonVec3(room.x, room.y + room.h * 0.08, 4.05));
          roomGroup.add(ring);
        } else if (room.type === "shrine") {
          const shrineMark = new THREE.Mesh(
            new THREE.RingGeometry(34, 52, 22),
            new THREE.MeshBasicMaterial({
              color: 0x8fdfff,
              transparent: true,
              opacity: 0.28,
              depthWrite: false,
              side: THREE.DoubleSide,
            })
          );
          shrineMark.rotation.x = -Math.PI * 0.5;
          shrineMark.position.copy(this.toDungeonVec3(room.x, room.y, 4.02));
          roomGroup.add(shrineMark);
        } else if (room.type === "key") {
          const keyStripe = new THREE.Mesh(
            new THREE.PlaneGeometry(Math.max(56, room.w * 0.24), 8),
            new THREE.MeshBasicMaterial({
              color: 0xe1c170,
              transparent: true,
              opacity: 0.24,
              depthWrite: false,
            })
          );
          keyStripe.rotation.x = -Math.PI * 0.5;
          keyStripe.position.copy(this.toDungeonVec3(room.x, room.y + room.h * 0.06, 4.02));
          roomGroup.add(keyStripe);
        } else if (room.type === "loot" || room.type === "armory") {
          const plate = new THREE.Mesh(
            new THREE.PlaneGeometry(Math.max(44, room.w * 0.2), Math.max(44, room.h * 0.16)),
            new THREE.MeshBasicMaterial({
              color: room.type === "loot" ? 0xdab164 : 0xaebfd4,
              transparent: true,
              opacity: 0.18,
              depthWrite: false,
            })
          );
          plate.rotation.x = -Math.PI * 0.5;
          plate.position.copy(this.toDungeonVec3(room.x, room.y, 4.0));
          roomGroup.add(plate);
        }
      }

      if (!isCorridor && room.decor?.length) {
        for (const item of room.decor) {
          const mesh = this.createDungeonDecorMesh(item, palette);
          mesh.position.copy(this.toDungeonVec3(item.x, item.y, 0));
          roomGroup.add(mesh);
        }
      } else if (isCorridor && room.decor?.length) {
        for (const item of room.decor) {
          const mesh = this.createDungeonDecorMesh(item, palette);
          mesh.position.copy(this.toDungeonVec3(item.x, item.y, 0));
          roomGroup.add(mesh);
        }
      }

      if (isDragonLair && room.type === "boss") {
        for (let i = 0; i < 5; i++) {
          const scorch = new THREE.Mesh(
            new THREE.RingGeometry(24 + i * 7, 34 + i * 8, 22),
            new THREE.MeshBasicMaterial({ color: i % 2 ? 0xff8a44 : 0x5a1e0e, transparent: true, opacity: i % 2 ? 0.12 : 0.22, depthWrite: false, side: THREE.DoubleSide })
          );
          scorch.rotation.x = -Math.PI * 0.5;
          scorch.position.copy(this.toDungeonVec3(room.x + (i - 2) * 34, room.y + room.h * 0.08 - i * 8, 4.12));
          roomGroup.add(scorch);
        }
      }

      this.dungeonGroup.add(roomGroup);
      if (room.id) this.dungeonRoomMeshes.set(room.id, roomGroup);
      addWallSegmentsForRoom(room);
    }

    for (const blocked of layout.blockedRects || []) {
      const tall = Math.max(blocked.w, blocked.h) > 160 ? 58 : 54;
      const wall = new THREE.Mesh(
        new THREE.BoxGeometry(Math.max(6, blocked.w), tall, Math.max(6, blocked.h)),
        wallMat
      );
      wall.position.copy(this.toDungeonVec3(blocked.x, blocked.y, tall * 0.5));
      wall.castShadow = true;
      wall.receiveShadow = true;
      this.dungeonGroup.add(wall);
      if (isDragonLair && Math.max(blocked.w, blocked.h) > 26) {
        const cap = new THREE.Mesh(
          new THREE.BoxGeometry(Math.max(6, blocked.w) + 8, 6, Math.max(6, blocked.h) + 8),
          trimMat
        );
        cap.position.copy(this.toDungeonVec3(blocked.x, blocked.y, tall + 3));
        this.dungeonGroup.add(cap);
      }
    }

    const stairMat = new THREE.MeshStandardMaterial({
      color: this.shadeColorHex(theme.propA || "#4b5260", 0.32),
      roughness: 0.82,
      metalness: 0.08,
      emissive: this.shadeColorHex(theme.propA || "#4b5260", 0.08),
      emissiveIntensity: 0.12,
    });
    const makeStairMarker = (point, color = 0xa8c0d8, lift = 0) => {
      const marker = new THREE.Group();
      for (let i = 0; i < 4; i++) {
        const step = new THREE.Mesh(new THREE.BoxGeometry(48 - i * 8, 5, 24), stairMat);
        step.position.set(0, i * 4 + 2, i * 8 - 10);
        step.castShadow = true;
        step.receiveShadow = true;
        marker.add(step);
      }
      const sigil = new THREE.Mesh(
        new THREE.RingGeometry(18, 26, 20),
        new THREE.MeshBasicMaterial({ color, transparent: true, opacity: 0.55, side: THREE.DoubleSide, depthWrite: false })
      );
      sigil.rotation.x = -Math.PI * 0.5;
      sigil.position.y = 2.2;
      marker.add(sigil);
      marker.position.copy(this.toDungeonVec3(point.x, point.y, lift));
      return marker;
    };

    if (layout.returnStair) this.dungeonGroup.add(makeStairMarker(layout.returnStair, 0xa8c0d8, 0));
    if (layout.exitStair) this.dungeonGroup.add(makeStairMarker(layout.exitStair, 0xffd36e, 6));

    if (layout.hoard) {
      const hoardGroup = new THREE.Group();
      const pileMat = new THREE.MeshStandardMaterial({
        color: 0xe2b85e,
        emissive: 0x5e3a0f,
        emissiveIntensity: 0.18,
        roughness: 0.54,
        metalness: 0.3,
      });
      for (let i = 0; i < 14; i++) {
        const coin = new THREE.Mesh(new THREE.SphereGeometry(10 + (i % 3) * 2, 8, 8), pileMat);
        coin.position.set(((i % 5) - 2) * 12, 8 + (i % 4) * 3, Math.floor(i / 5) * 12 - 10);
        coin.scale.set(1.1, 0.42, 1.1);
        coin.castShadow = true;
        coin.receiveShadow = true;
        hoardGroup.add(coin);
      }
      const chest = new THREE.Mesh(
        new THREE.BoxGeometry(34, 20, 22),
        new THREE.MeshStandardMaterial({ color: 0x6f4b30, roughness: 0.88, metalness: 0.04 })
      );
      chest.position.set(0, 12, -24);
      chest.castShadow = true;
      chest.receiveShadow = true;
      hoardGroup.add(chest);
      const chestBand = new THREE.Mesh(
        new THREE.BoxGeometry(36, 4, 24),
        new THREE.MeshStandardMaterial({ color: 0xdab164, roughness: 0.48, metalness: 0.24 })
      );
      chestBand.position.set(0, 16, -24);
      hoardGroup.add(chestBand);
      hoardGroup.position.copy(this.toDungeonVec3(layout.hoard.x, layout.hoard.y, 0));
      this.dungeonHoardGroup = hoardGroup;
      this.dungeonGroup.add(hoardGroup);
    }

    for (const room of layout.rooms || []) {
      if (room.type === "start" || room.type === "boss") continue;
      const anchor = this.game?._getDungeonRoomCacheAnchor?.(room);
      if (!anchor) continue;
      const cacheGroup = new THREE.Group();
      const cache = new THREE.Mesh(
        new THREE.BoxGeometry(22, 14, 16),
        new THREE.MeshStandardMaterial({ color: 0x7c5b39, roughness: 0.9, metalness: 0.04 })
      );
      cache.position.y = 9;
      cache.castShadow = true;
      cache.receiveShadow = true;
      cacheGroup.add(cache);
      const band = new THREE.Mesh(
        new THREE.BoxGeometry(24, 3, 18),
        new THREE.MeshStandardMaterial({ color: 0xc8a66a, roughness: 0.56, metalness: 0.22 })
      );
      band.position.y = 14;
      cacheGroup.add(band);
      cacheGroup.position.copy(this.toDungeonVec3(anchor.x, anchor.y, 0));
      this.dungeonCacheMeshes.set(room.id, cacheGroup);
      this.dungeonGroup.add(cacheGroup);
    }

    for (const door of layout.doors || []) {
      const doorGroup = new THREE.Group();
      const frameSpan = Math.max(18, door.frameSpan || (door.vertical ? door.h || 56 : door.w || 56));
      const jambThickness = 8;
      const openingDepth = 8;
      const frameMat = new THREE.MeshStandardMaterial({
        color: door.locked === "key" ? 0xb88d52 : 0x6f655e,
        roughness: 0.84,
        metalness: door.locked === "key" ? 0.18 : 0.06,
      });
      if (door.vertical) {
        for (const side of [-1, 1]) {
          const jamb = new THREE.Mesh(new THREE.BoxGeometry(jambThickness, 42, frameSpan + 10), frameMat);
          jamb.position.set(side * 10, 21, 0);
          jamb.castShadow = true;
          jamb.receiveShadow = true;
          doorGroup.add(jamb);
        }
        const lintel = new THREE.Mesh(new THREE.BoxGeometry(28, 8, frameSpan + 14), frameMat);
        lintel.position.set(0, 44, 0);
        lintel.castShadow = true;
        lintel.receiveShadow = true;
        doorGroup.add(lintel);
      } else {
        for (const side of [-1, 1]) {
          const jamb = new THREE.Mesh(new THREE.BoxGeometry(frameSpan + 10, 42, jambThickness), frameMat);
          jamb.position.set(0, 21, side * 10);
          jamb.castShadow = true;
          jamb.receiveShadow = true;
          doorGroup.add(jamb);
        }
        const lintel = new THREE.Mesh(new THREE.BoxGeometry(frameSpan + 14, 8, 28), frameMat);
        lintel.position.set(0, 44, 0);
        lintel.castShadow = true;
        lintel.receiveShadow = true;
        doorGroup.add(lintel);
      }

      const slab = new THREE.Mesh(
        new THREE.BoxGeometry(
          door.vertical ? openingDepth : frameSpan,
          28,
          door.vertical ? frameSpan : openingDepth
        ),
        new THREE.MeshStandardMaterial({
          color: isDragonLair ? 0x5a3c31 : (door.locked === "key" ? 0x8f6c43 : 0x7e6e60),
          roughness: 0.86,
          metalness: isDragonLair ? 0.12 : (door.locked === "key" ? 0.16 : 0.05),
        })
      );
      const pivot = new THREE.Group();
      if (door.vertical) {
        pivot.position.set(-10, 14, -frameSpan * 0.5);
        slab.position.set(0, 0, frameSpan * 0.5);
      } else {
        pivot.position.set(-frameSpan * 0.5, 14, -10);
        slab.position.set(frameSpan * 0.5, 0, 0);
      }
      slab.castShadow = true;
      slab.receiveShadow = true;
      pivot.add(slab);
      doorGroup.add(pivot);

      if (isDragonLair) {
        for (let i = -2; i <= 2; i++) {
          const bar = new THREE.Mesh(
            new THREE.BoxGeometry(door.vertical ? 3.2 : frameSpan * 0.16, 26, door.vertical ? frameSpan * 0.16 : 3.2),
            new THREE.MeshStandardMaterial({ color: 0x2b2523, roughness: 0.9, metalness: 0.16 })
          );
          if (door.vertical) bar.position.set(0, 0, i * (frameSpan * 0.18));
          else bar.position.set(i * (frameSpan * 0.18), 0, 0);
          slab.add(bar);
        }
      }

      if (door.locked === "key") {
        const lock = new THREE.Mesh(
          new THREE.TorusGeometry(4, 1.2, 6, 12),
          new THREE.MeshStandardMaterial({ color: 0xe1c170, roughness: 0.44, metalness: 0.28 })
        );
        lock.position.set(0, 14, door.vertical ? 8 : 0);
        lock.rotation.y = door.vertical ? 0 : Math.PI * 0.5;
        doorGroup.add(lock);
      }

      doorGroup.position.copy(this.toDungeonVec3(door.x, door.y, 0));
      this.dungeonDoorMeshes.set(door.id, {
        group: doorGroup,
        slab,
        pivot,
        openAngle: door.vertical ? -Math.PI * 0.52 : Math.PI * 0.52,
      });
      this.dungeonGroup.add(doorGroup);
    }

    this.syncDungeonStateVisuals();
  }

  syncDungeonStateVisuals() {
    const layout = this.game?.dungeon?.layout;
    if (!this.game?.dungeon?.active || !layout) return;

    const currentRoomId = this.game?.dungeon?.currentRoomId || null;
    const roomClear = currentRoomId ? !this.game._dungeonHasLivingEnemies?.(currentRoomId) : false;
    if (
      currentRoomId !== this.dungeonSceneMeta.currentRoomId ||
      roomClear !== this.dungeonSceneMeta.roomClear
    ) {
      this.dungeonSceneMeta.currentRoomId = currentRoomId;
      this.dungeonSceneMeta.roomClear = roomClear;
      this.shadowState.dirty = true;
    }

    for (const room of layout.rooms || []) {
      const group = this.dungeonRoomMeshes.get(room.id);
      if (!group) continue;
      const active = room.id === currentRoomId;
      const cleared = !!room.cleared;
      group.traverse((obj) => {
        if (!obj.material || Array.isArray(obj.material)) return;
        if (!("emissiveIntensity" in obj.material)) return;
        if (obj.geometry?.type === "PlaneGeometry") {
          obj.material.opacity = active ? 0.22 : room.type === "boss" ? 0.16 : 0.1;
          return;
        }
        obj.material.emissiveIntensity = active ? 0.16 : cleared ? 0.1 : obj.material.emissiveIntensity || 0;
      });
    }

    for (const door of layout.doors || []) {
      const entry = this.dungeonDoorMeshes.get(door.id);
      if (!entry) continue;
      entry.group.visible = true;
      if (entry.pivot) {
        const openFrac = door.open ? 1 : 0;
        entry.pivot.rotation.y = entry.openAngle * openFrac;
      }
      if (entry.slab?.material && !Array.isArray(entry.slab.material)) {
        entry.slab.material.emissiveIntensity = door.locked === "key" ? 0.08 : door.unlocked ? 0.06 : 0;
      }
    }

    for (const room of layout.rooms || []) {
      const cache = this.dungeonCacheMeshes.get(room.id);
      if (cache) cache.visible = !room.cacheOpened;
    }

    if (this.dungeonHoardGroup) {
      this.dungeonHoardGroup.visible = !this.game?.dungeon?.hoardOpened;
    }
  }

  syncDungeonScene() {
    const layout = this.game?.dungeon?.layout;
    const active = !!this.game?.dungeon?.active && !!layout;
    const version = active
      ? JSON.stringify({
          kind: this.game.dungeon.kind || "depths",
          floor: this.game.dungeon.floor || 1,
          rooms: (layout.rooms || []).length,
          corridors: (layout.corridors || []).length,
          doors: (layout.doors || []).length,
          blocked: (layout.blockedRects || []).length,
          hoard: !!layout.hoard,
        })
      : "";

    if (version !== this.dungeonSceneVersion) {
      this.dungeonSceneVersion = version;
      this.createDungeonScene();
      this.shadowState.dirty = true;
    }

    if (this.overworldVisible === active) {
      this.overworldVisible = !active;
      this.overworldGroup.visible = !active;
      this.landmarkGroup.visible = !active;
      this.dungeonGroup.visible = active;
    } else {
      this.dungeonGroup.visible = active;
    }
    if (active) this.syncDungeonStateVisuals();
  }

  toDungeonVec3(x, y, lift = 0) {
    return new THREE.Vector3(x, lift, y);
  }

  samplePolyline(points, stride = 1) {
    if (!points?.length) return [];
    const out = [];
    let prev = null;
    for (let i = 0; i < points.length; i += Math.max(1, stride)) {
      const point = points[i];
      if (!point || !Number.isFinite(point.x) || !Number.isFinite(point.y)) continue;
      if (prev && Math.hypot(point.x - prev.x, point.y - prev.y) < 1) continue;
      out.push(point);
      prev = point;
    }
    const last = points[points.length - 1];
    if (last && Number.isFinite(last.x) && Number.isFinite(last.y)) {
      const tail = out[out.length - 1];
      if (!tail || Math.hypot(last.x - tail.x, last.y - tail.y) >= 1) out.push(last);
    }
    return out;
  }

  smoothPath(points, subdivisions = 4, tension = 0.2) {
    if (!points?.length || points.length < 3) return points || [];
    const curve = new THREE.CatmullRomCurve3(
      points.map((p) => new THREE.Vector3(p.x, 0, p.y)),
      false,
      "centripetal",
      tension
    );
    const samples = Math.max(points.length - 1, 1) * Math.max(1, subdivisions);
    return curve.getPoints(samples).map((p) => ({ x: p.x, y: p.z }));
  }

  makePathRibbon(points, width, lift, material) {
    if (!points?.length || points.length < 2) return null;

    const vertices = [];
    const indices = [];
    const half = width * 0.5;

    for (let i = 0; i < points.length; i++) {
      const prev = points[Math.max(0, i - 1)];
      const here = points[i];
      const next = points[Math.min(points.length - 1, i + 1)];
      const dx = next.x - prev.x;
      const dy = next.y - prev.y;
      const len = Math.hypot(dx, dy) || 1;
      const nx = -dy / len;
      const ny = dx / len;

      const leftX = here.x + nx * half;
      const leftY = here.y + ny * half;
      const rightX = here.x - nx * half;
      const rightY = here.y - ny * half;
      const left = new THREE.Vector3(leftX, this.pathSurfaceHeightAt(leftX, leftY, Math.max(10, width * 0.2)) + lift + 3.5, leftY);
      const right = new THREE.Vector3(rightX, this.pathSurfaceHeightAt(rightX, rightY, Math.max(10, width * 0.2)) + lift + 3.5, rightY);
      vertices.push(left.x, left.y, left.z, right.x, right.y, right.z);

      if (i > 0) {
        const a = (i - 1) * 2;
        const b = a + 1;
        const c = i * 2;
        const d = c + 1;
        indices.push(a, c, b, b, c, d);
      }
    }

    const geometry = new THREE.BufferGeometry();
    geometry.setAttribute("position", new THREE.Float32BufferAttribute(vertices, 3));
    geometry.setIndex(indices);
    geometry.computeVertexNormals();
    return new THREE.Mesh(geometry, material);
  }

  makeGroundPathRibbon(points, width, lift, material) {
    if (!points?.length || points.length < 2) return null;

    const vertices = [];
    const indices = [];
    const half = width * 0.5;

    for (let i = 0; i < points.length; i++) {
      const prev = points[Math.max(0, i - 1)];
      const here = points[i];
      const next = points[Math.min(points.length - 1, i + 1)];
      const dx = next.x - prev.x;
      const dy = next.y - prev.y;
      const len = Math.hypot(dx, dy) || 1;
      const nx = -dy / len;
      const ny = dx / len;

      const leftX = here.x + nx * half;
      const leftY = here.y + ny * half;
      const rightX = here.x - nx * half;
      const rightY = here.y - ny * half;
      const centerHeight = this.roadSurfaceHeightAt(here.x, here.y, Math.max(10, width * 0.22)) + lift + 2.2;

      vertices.push(leftX, centerHeight, leftY, rightX, centerHeight, rightY);

      if (i > 0) {
        const a = (i - 1) * 2;
        const b = a + 1;
        const c = i * 2;
        const d = c + 1;
        indices.push(a, c, b, b, c, d);
      }
    }

    const geometry = new THREE.BufferGeometry();
    geometry.setAttribute("position", new THREE.Float32BufferAttribute(vertices, 3));
    geometry.setIndex(indices);
    geometry.computeVertexNormals();
    return new THREE.Mesh(geometry, material);
  }

  makeTerrainHugRibbon(points, width, lift, material, spread = 12, options = {}) {
    if (!points?.length || points.length < 2) return null;

    const vertices = [];
    const indices = [];
    const half = width * 0.5;
    const smoothing = clamp(options.smoothing ?? 0.96, 0, 1);
    const ceilingWeight = clamp(options.ceilingWeight ?? 0.03, 0, 0.2);
    const minClearance = options.minClearance ?? 0.1;

    for (let i = 0; i < points.length; i++) {
      const prev = points[Math.max(0, i - 1)];
      const here = points[i];
      const next = points[Math.min(points.length - 1, i + 1)];
      const dx = next.x - prev.x;
      const dy = next.y - prev.y;
      const len = Math.hypot(dx, dy) || 1;
      const nx = -dy / len;
      const ny = dx / len;

      const leftX = here.x + nx * half;
      const leftY = here.y + ny * half;
      const rightX = here.x - nx * half;
      const rightY = here.y - ny * half;
      const blur = Math.max(8, spread * 0.4);
      const leftH = this.sampleRenderedTerrainSmoothHeight(leftX, leftY, blur) + lift;
      const rightH = this.sampleRenderedTerrainSmoothHeight(rightX, rightY, blur) + lift;
      const centerH = this.sampleRenderedTerrainSmoothHeight(here.x, here.y, blur) + lift;
      const prevH = this.sampleRenderedTerrainSmoothHeight(prev.x, prev.y, blur) + lift;
      const nextH = this.sampleRenderedTerrainSmoothHeight(next.x, next.y, blur) + lift;
      const lineH = (prevH + centerH + nextH) / 3;
      const safeH = this.sampleRenderedTerrainCeiling(here.x, here.y) + lift;
      const smoothedCenter = Math.max(centerH * (1 - ceilingWeight) + (lineH * smoothing + safeH * ceilingWeight) * smoothing, centerH + minClearance);
      const edgeDrop = Math.min(0.2, width * 0.0035);

      vertices.push(
        leftX, Math.max(leftH, smoothedCenter - edgeDrop), leftY,
        rightX, Math.max(rightH, smoothedCenter - edgeDrop), rightY
      );

      if (i > 0) {
        const a = (i - 1) * 2;
        const b = a + 1;
        const c = i * 2;
        const d = c + 1;
        indices.push(a, c, b, b, c, d);
      }
    }

    const geometry = new THREE.BufferGeometry();
    geometry.setAttribute("position", new THREE.Float32BufferAttribute(vertices, 3));
    geometry.setIndex(indices);
    geometry.computeVertexNormals();
    return new THREE.Mesh(geometry, material);
  }

  makeFlatWaterRibbon(points, width, y, material) {
    if (!points?.length || points.length < 2) return null;

    const vertices = [];
    const indices = [];
    const half = width * 0.5;

    for (let i = 0; i < points.length; i++) {
      const prev = points[Math.max(0, i - 1)];
      const here = points[i];
      const next = points[Math.min(points.length - 1, i + 1)];
      const dx = next.x - prev.x;
      const dy = next.y - prev.y;
      const len = Math.hypot(dx, dy) || 1;
      const nx = -dy / len;
      const ny = dx / len;

      const leftX = here.x + nx * half;
      const leftY = here.y + ny * half;
      const rightX = here.x - nx * half;
      const rightY = here.y - ny * half;

      vertices.push(leftX, y, leftY, rightX, y, rightY);

      if (i > 0) {
        const a = (i - 1) * 2;
        const b = a + 1;
        const c = i * 2;
        const d = c + 1;
        indices.push(a, c, b, b, c, d);
      }
    }

    const geometry = new THREE.BufferGeometry();
    geometry.setAttribute("position", new THREE.Float32BufferAttribute(vertices, 3));
    geometry.setIndex(indices);
    geometry.computeVertexNormals();
    return new THREE.Mesh(geometry, material);
  }

  makeSectionWaterStamp(cx, cy, angle, length, width, material, lift = 0.12) {
    const halfL = Math.max(20, length * 0.5 + width * 0.22);
    const halfW = Math.max(10, width * 0.5);
    const capRadius = Math.min(halfW, halfL);
    const spineHalf = Math.max(0, halfL - capRadius);
    const cosA = Math.cos(angle || 0);
    const sinA = Math.sin(angle || 0);
    const arcSteps = 12;
    const perimeter = [];

    const rightCenter = { x: spineHalf, y: 0 };
    const leftCenter = { x: -spineHalf, y: 0 };

    for (let i = 0; i <= arcSteps; i++) {
      const t = i / arcSteps;
      const a = -Math.PI * 0.5 + t * Math.PI;
      perimeter.push({
        x: rightCenter.x + Math.cos(a) * capRadius,
        y: rightCenter.y + Math.sin(a) * capRadius,
      });
    }
    for (let i = 0; i <= arcSteps; i++) {
      const t = i / arcSteps;
      const a = Math.PI * 0.5 + t * Math.PI;
      perimeter.push({
        x: leftCenter.x + Math.cos(a) * capRadius,
        y: leftCenter.y + Math.sin(a) * capRadius,
      });
    }

    const worldPts = perimeter.map((p) => {
      const wx = cx + p.x * cosA - p.y * sinA;
      const wy = cy + p.x * sinA + p.y * cosA;
      const h = this.sampleRenderedTerrainSmoothHeight(wx, wy, Math.max(18, halfW * 0.5));
      return new THREE.Vector3(wx, h, wy);
    });
    let minY = Infinity;
    let maxY = -Infinity;
    let avgY = 0;
    for (const p of worldPts) {
      if (p.y < minY) minY = p.y;
      if (p.y > maxY) maxY = p.y;
      avgY += p.y;
    }
    avgY /= Math.max(1, worldPts.length);
    const centerGround = this.sampleRenderedTerrainSmoothHeight(cx, cy, Math.max(18, halfW * 0.5));
    const channelY = Math.max(
      centerGround - Math.max(2.2, halfW * 0.05),
      avgY - Math.max(2.4, halfW * 0.06),
      minY + Math.max(10, halfW * 0.28)
    ) + lift;
    const bottomY = Math.min(channelY - Math.max(14, halfW * 0.28), maxY - Math.max(5, halfW * 0.08));
    const topGeometry = new THREE.BufferGeometry();
    const topVertices = [cx, channelY, cy];
    for (const p of worldPts) topVertices.push(p.x, channelY, p.z);
    const indices = [];
    for (let i = 1; i <= worldPts.length; i++) {
      const next = i === worldPts.length ? 1 : i + 1;
      indices.push(0, i, next);
    }
    topGeometry.setAttribute("position", new THREE.Float32BufferAttribute(topVertices, 3));
    topGeometry.setIndex(indices);
    topGeometry.computeVertexNormals();

    const sideVertices = [];
    const sideIndices = [];
    for (let i = 0; i < worldPts.length; i++) {
      const p = worldPts[i];
      sideVertices.push(p.x, channelY, p.z, p.x, bottomY, p.z);
      if (i > 0) {
        const a = (i - 1) * 2;
        const b = a + 1;
        const c = i * 2;
        const d = c + 1;
        sideIndices.push(a, c, b, b, c, d);
      }
    }
    if (worldPts.length >= 2) {
      const a = (worldPts.length - 1) * 2;
      const b = a + 1;
      sideIndices.push(a, 0, b, b, 0, 1);
    }
    const sideGeometry = new THREE.BufferGeometry();
    sideGeometry.setAttribute("position", new THREE.Float32BufferAttribute(sideVertices, 3));
    sideGeometry.setIndex(sideIndices);
    sideGeometry.computeVertexNormals();
    const sideMaterial = new THREE.MeshBasicMaterial({
      color: 0x22506e,
      side: THREE.DoubleSide,
      transparent: true,
      opacity: 0.92,
      polygonOffset: true,
      polygonOffsetFactor: -1,
      polygonOffsetUnits: -1,
    });
    const group = new THREE.Group();
    const topMesh = new THREE.Mesh(topGeometry, material);
    const sideMesh = new THREE.Mesh(sideGeometry, sideMaterial);
    group.add(sideMesh);
    group.add(topMesh);
    return group;
  }

  makeSurfacePaintRibbon(points, width, lift, material, spread = 12) {
    if (!points?.length || points.length < 2) return null;

    const expanded = [points[0]];
    for (let i = 1; i < points.length; i++) {
      const a = points[i - 1];
      const b = points[i];
      const dx = b.x - a.x;
      const dy = b.y - a.y;
      const len = Math.hypot(dx, dy);
      if (!Number.isFinite(len) || len < 1) continue;
      const ah = this.sampleRenderedTerrainSmoothHeight(a.x, a.y, Math.max(10, spread * 0.55));
      const bh = this.sampleRenderedTerrainSmoothHeight(b.x, b.y, Math.max(10, spread * 0.55));
      const hDelta = Math.abs(bh - ah);
      const steps = Math.max(1, Math.ceil(Math.max(len / 16, hDelta / 10)));
      for (let s = 1; s <= steps; s++) {
        const t = s / steps;
        expanded.push({
          x: a.x + dx * t,
          y: a.y + dy * t,
        });
      }
    }

    const vertices = [];
    const indices = [];
    const half = width * 0.5;

    for (let i = 0; i < expanded.length; i++) {
      const prev = expanded[Math.max(0, i - 1)];
      const here = expanded[i];
      const next = expanded[Math.min(expanded.length - 1, i + 1)];
      const dx = next.x - prev.x;
      const dy = next.y - prev.y;
      const len = Math.hypot(dx, dy) || 1;
      const nx = -dy / len;
      const ny = dx / len;

      const leftX = here.x + nx * half;
      const leftY = here.y + ny * half;
      const rightX = here.x - nx * half;
      const rightY = here.y - ny * half;
      const centerH = this.sampleRenderedTerrainSmoothHeight(here.x, here.y, Math.max(10, spread * 0.55)) + lift;

      vertices.push(leftX, centerH, leftY, rightX, centerH, rightY);

      if (i > 0) {
        const a = (i - 1) * 2;
        const b = a + 1;
        const c = i * 2;
        const d = c + 1;
        indices.push(a, c, b, b, c, d);
      }
    }

    const geometry = new THREE.BufferGeometry();
    geometry.setAttribute("position", new THREE.Float32BufferAttribute(vertices, 3));
    geometry.setIndex(indices);
    geometry.computeVertexNormals();
    return new THREE.Mesh(geometry, material);
  }

  makeRiverDiscPreview(points, width, y, material) {
    if (!points?.length || points.length < 2) return null;
    const group = new THREE.Group();
    const radius = Math.max(12, width * 0.52);
    const step = Math.max(10, radius * 0.42);
    const geometry = new THREE.CircleGeometry(radius, 18);
    const stampMat = material.clone();
    stampMat.depthWrite = false;
    stampMat.opacity = Math.min(1, (stampMat.opacity ?? 0.94) * 0.96);

    let carry = 0;
    for (let i = 1; i < points.length; i++) {
      const a = points[i - 1];
      const b = points[i];
      const dx = b.x - a.x;
      const dy = b.y - a.y;
      const len = Math.hypot(dx, dy);
      if (!Number.isFinite(len) || len < 1) continue;
      let dist = Math.max(step - carry, 0);
      while (dist <= len) {
        const t = len > 0 ? dist / len : 0;
        const x = a.x + dx * t;
        const yy = a.y + dy * t;
        const mesh = new THREE.Mesh(geometry, stampMat);
        mesh.rotation.x = -Math.PI * 0.5;
        const groundY = this.sampleRenderedTerrainSmoothHeight(x, yy, Math.max(14, radius * 0.4));
        mesh.position.set(x, Math.max(y, groundY + 0.8), yy);
        group.add(mesh);
        dist += step;
      }
      carry = Math.max(0, dist - len);
    }

    if (!group.children.length) return null;
    return group;
  }

  makeRiverTubePreview(points, radius, y, material) {
    if (!points?.length || points.length < 2) return null;
    const curve = new THREE.CatmullRomCurve3(
      points.map((p) => new THREE.Vector3(p.x, 0, p.y)),
      false,
      "centripetal",
      0.06
    );
    const tubularSegments = Math.max(64, points.length * 10);
    const geometry = new THREE.TubeGeometry(curve, tubularSegments, Math.max(10, radius), 18, false);
    const mesh = new THREE.Mesh(geometry, material.clone());
    mesh.position.y = y;
    mesh.scale.y = 0.12;
    return mesh;
  }


  pathSurfaceHeightAt(x, y, spread = 12) {
    return this.sampleRenderedTerrainSmoothHeight(x, y, spread);
  }

  visualGroundHeightAt(x, y, spread = 16, clearance = 0) {
    const terrain = this.sampleRenderedTerrainSmoothHeight(x, y, Math.max(10, spread * 0.55));
    const roadDist = this.roadDistanceAt(x, y);
    const onRoad = Number.isFinite(roadDist) && roadDist < 26;
    const target = onRoad ? Math.max(terrain, this.roadSurfaceHeightAt(x, y, spread) - 0.35) : terrain;
    return target + clearance;
  }

  roadSurfaceHeightAt(x, y, spread = 12) {
    const terrain = this.sampleRenderedTerrainSmoothHeight(x, y, Math.max(10, spread * 0.5));
    const center = this.sampleRenderedTerrainHeight(x, y);
    return Math.max(terrain + 0.18, center + 0.12);
  }

  sampleRenderedTerrainHeight(x, y) {
    const local = this.localTerrainHeightfield;
    if (local?.heights?.length) {
      const half = local.size * 0.5;
      const dx = x - (local.centerX || 0);
      const dy = y - (local.centerY || 0);
      if (Math.abs(dx) <= half && Math.abs(dy) <= half) {
        return this.sampleTerrainFieldHeight(local, x, y) + 0.06;
      }
    }
    return this.sampleTerrainFieldHeight(this.terrainHeightfield, x, y);
  }

  sampleTerrainFieldHeight(field, x, y) {
    if (!field?.heights?.length) return this.heightAt(x, y);
    const half = field.size * 0.5;
    const localX = x - (field.centerX || 0);
    const localY = y - (field.centerY || 0);
    const fx = clamp(((localX + half) / field.size) * field.segments, 0, field.segments);
    const fy = clamp(((localY + half) / field.size) * field.segments, 0, field.segments);
    const x0 = Math.floor(fx);
    const y0 = Math.floor(fy);
    const x1 = Math.min(field.segments, x0 + 1);
    const y1 = Math.min(field.segments, y0 + 1);
    const tx = fx - x0;
    const ty = fy - y0;
    const stride = field.segments + 1;
    const h00 = field.heights[y0 * stride + x0];
    const h10 = field.heights[y0 * stride + x1];
    const h01 = field.heights[y1 * stride + x0];
    const h11 = field.heights[y1 * stride + x1];
    const top = h00 * (1 - tx) + h10 * tx;
    const bottom = h01 * (1 - tx) + h11 * tx;
    return top * (1 - ty) + bottom * ty;
  }

  sampleRenderedTerrainSmoothHeight(x, y, spread = 16) {
    const c = this.sampleRenderedTerrainHeight(x, y);
    const e = this.sampleRenderedTerrainHeight(x + spread, y);
    const w = this.sampleRenderedTerrainHeight(x - spread, y);
    const n = this.sampleRenderedTerrainHeight(x, y - spread);
    const s = this.sampleRenderedTerrainHeight(x, y + spread);
    const ne = this.sampleRenderedTerrainHeight(x + spread * 0.7, y - spread * 0.7);
    const nw = this.sampleRenderedTerrainHeight(x - spread * 0.7, y - spread * 0.7);
    const se = this.sampleRenderedTerrainHeight(x + spread * 0.7, y + spread * 0.7);
    const sw = this.sampleRenderedTerrainHeight(x - spread * 0.7, y + spread * 0.7);
    return c * 0.3 + (e + w + n + s) * 0.12 + (ne + nw + se + sw) * 0.055;
  }

  sampleRenderedTerrainCeiling(x, y) {
    const field = this.localTerrainHeightfield?.heights?.length ? this.localTerrainHeightfield : this.terrainHeightfield;
    if (!field?.heights?.length) return this.heightAt(x, y);
    const half = field.size * 0.5;
    const localX = x - (field.centerX || 0);
    const localY = y - (field.centerY || 0);
    const fx = clamp(((localX + half) / field.size) * field.segments, 0, field.segments);
    const fy = clamp(((localY + half) / field.size) * field.segments, 0, field.segments);
    const x0 = Math.floor(fx);
    const y0 = Math.floor(fy);
    const x1 = Math.min(field.segments, x0 + 1);
    const y1 = Math.min(field.segments, y0 + 1);
    const stride = field.segments + 1;
    const h00 = field.heights[y0 * stride + x0];
    const h10 = field.heights[y0 * stride + x1];
    const h01 = field.heights[y1 * stride + x0];
    const h11 = field.heights[y1 * stride + x1];
    return Math.max(h00, h10, h01, h11);
  }

  makePathStripGroup(points, width, lift, thickness, material) {
    if (!points?.length || points.length < 2) return null;
    const group = new THREE.Group();
    for (let i = 1; i < points.length; i++) {
      const a = points[i - 1];
      const b = points[i];
      const dx = b.x - a.x;
      const dy = b.y - a.y;
      const len = Math.hypot(dx, dy);
      if (!Number.isFinite(len) || len < 2) continue;
      const centerX = (a.x + b.x) * 0.5;
      const centerY = (a.y + b.y) * 0.5;
      const aHeight = this.heightAt(a.x, a.y);
      const bHeight = this.heightAt(b.x, b.y);
      const midHeight = this.heightAt(centerX, centerY);
      const centerHeight = Math.max(aHeight, bHeight, midHeight) + lift + Math.max(1.4, thickness * 0.5) + 4.5;
      const mesh = new THREE.Mesh(new THREE.BoxGeometry(len + 6, Math.max(0.4, thickness), width), material);
      mesh.position.set(centerX, centerHeight, centerY);
      mesh.rotation.y = -Math.atan2(dy, dx);
      mesh.castShadow = false;
      mesh.receiveShadow = true;
      group.add(mesh);
    }
    return group.children.length ? group : null;
  }

  makePathSlabGroup(points, width, lift, thickness, material) {
    if (!points?.length || points.length < 2) return null;
    const group = new THREE.Group();
    for (let i = 1; i < points.length; i++) {
      const a = points[i - 1];
      const b = points[i];
      const dx = b.x - a.x;
      const dy = b.y - a.y;
      const len = Math.hypot(dx, dy);
      if (!Number.isFinite(len) || len < 2) continue;
      const maxPiece = 12;
      const pieces = Math.max(1, Math.ceil(len / maxPiece));
      for (let piece = 0; piece < pieces; piece++) {
        const t0 = piece / pieces;
        const t1 = (piece + 1) / pieces;
        const ax = a.x + dx * t0;
        const ay = a.y + dy * t0;
        const bx = a.x + dx * t1;
        const by = a.y + dy * t1;
        const segDx = bx - ax;
        const segDy = by - ay;
        const segLen = Math.hypot(segDx, segDy);
        if (!Number.isFinite(segLen) || segLen < 1) continue;

        const centerX = (ax + bx) * 0.5;
        const centerY = (ay + by) * 0.5;
        const spread = Math.max(12, width * 0.22);
        const aHeight = this.roadSurfaceHeightAt(ax, ay, spread);
        const bHeight = this.roadSurfaceHeightAt(bx, by, spread);
        const midHeight = this.roadSurfaceHeightAt(centerX, centerY, spread);
        const clearance = Math.max(1.1, thickness * 0.55);
        const startHeight = aHeight + lift + clearance;
        const endHeight = bHeight + lift + clearance;
        const centerHeight = (startHeight + endHeight) * 0.5;

        const mesh = new THREE.Mesh(new THREE.BoxGeometry(segLen + 6, Math.max(0.18, thickness), width), material);
        mesh.position.set(centerX, centerHeight, centerY);
        const dir = new THREE.Vector3(segDx, endHeight - startHeight, segDy).normalize();
        mesh.quaternion.setFromUnitVectors(new THREE.Vector3(1, 0, 0), dir);
        mesh.castShadow = false;
        mesh.receiveShadow = true;
        group.add(mesh);
      }
    }
    return group.children.length ? group : null;
  }

  makePathMarkerGroup(points, width, lift, step, color, opacity = 1) {
    if (!points?.length || points.length < 2) return null;
    const group = new THREE.Group();
    const geometry = new THREE.CircleGeometry(Math.max(8, width * 0.5), 12);
    const material = new THREE.MeshBasicMaterial({
      color,
      transparent: opacity < 1,
      opacity,
      side: THREE.DoubleSide,
      depthWrite: false,
    });
    let carry = 0;
    for (let i = 1; i < points.length; i++) {
      const a = points[i - 1];
      const b = points[i];
      const dx = b.x - a.x;
      const dy = b.y - a.y;
      const len = Math.hypot(dx, dy);
      if (!Number.isFinite(len) || len < 2) continue;
      let dist = Math.max(step - carry, 0);
      while (dist <= len) {
        const t = len > 0 ? dist / len : 0;
        const x = a.x + dx * t;
        const y = a.y + dy * t;
        const mesh = new THREE.Mesh(geometry, material);
        mesh.rotation.x = -Math.PI * 0.5;
        mesh.position.set(x, this.pathSurfaceHeightAt(x, y, Math.max(8, width * 0.2)) + lift + 2.5, y);
        group.add(mesh);
        dist += step;
      }
      carry = Math.max(0, dist - len);
    }
    return group.children.length ? group : null;
  }

  colorForSample(sample) {
    if (sample.isWater) return new THREE.Color(0x23496b);
    switch (sample.zone) {
      case "mountain":
        return new THREE.Color(0x717782);
      case "stone flats":
        return new THREE.Color(0x8b8477);
      case "ashlands":
        return new THREE.Color(0x625252);
      case "old fields":
        return new THREE.Color(0x71804f);
      case "highlands":
        return new THREE.Color(0x657458);
      case "forest":
        return new THREE.Color(0x44603d);
      case "meadow":
      default:
        return new THREE.Color(0x5e7745);
    }
  }

  heightAt(x, y, sample = null) {
    const s = sample || this.world._sampleCell(x, y);
    const ground = this.world._groundAt(x, y);
    if (this.world?.variant === "river-build") {
      return (ground - 0.46) * 420;
    }
    const ridge = this.world._mountainInfluenceAt?.(x, y) || 0;
    const pass = this.world._mountainPassInfluenceAt?.(x, y) || 0;
    const edgeAbs = Math.max(Math.abs(x), Math.abs(y));
    const edgeBandFrac = clamp((edgeAbs - (this.world.mapHalfSize - 720)) / 720, 0, 1);
    let h = Math.max(0, ground - 0.18) * 240;
    h += ridge * 260;
    h -= pass * 80;
    if (s.zone === "mountain") h += 180;
    if (s.zone === "stone flats") h += 70;
    h += edgeBandFrac * 700;
    if (s.isWater) h = Math.min(h, -8);
    return h;
  }

  toVec3(x, y, lift = 0) {
    if (this.game?.dungeon?.active) return this.toDungeonVec3(x, y, lift);
    return new THREE.Vector3(x, this.sampleRenderedTerrainHeight(x, y) + lift, y);
  }

  recenter(immediate = false) {
    this.cameraTarget.copy(this.toVec3(this.game.hero.x, this.game.hero.y, this.game.dungeon.active ? 30 : 26));
    const desiredOffset = this.game?.dungeon?.active ? new THREE.Vector3(520, 460, 520) : new THREE.Vector3(880, 720, 880);
    this.cameraZoom.target = 1;
    this.cameraZoom.current = 1;
    this.cameraOrbit.distance = desiredOffset.length() * this.cameraZoom.current;
    this.cameraOrbit.yaw = Math.atan2(desiredOffset.x, desiredOffset.z);
    this.cameraOrbit.pitch = clamp(
      Math.asin(clamp(desiredOffset.y / Math.max(1, this.cameraOrbit.distance), -0.92, 0.92)),
      0.06,
      1.15
    );
    this.cameraOffset.copy(desiredOffset);
    if (immediate) {
      this.camera.position.copy(this.cameraTarget).add(this.cameraOffset);
    }
    this.camera.lookAt(this.cameraTarget);
  }

  onContextMenu(event) {
    event.preventDefault();
  }

  onPointerDown(event) {
    if (event.button !== 2) return;
    event.preventDefault();
    this.focusOverlayCanvas();
    this.cameraOrbit.enabled = true;
    this.cameraOrbit.pointerId = event.pointerId;
    this.cameraOrbit.lastX = event.clientX;
    this.cameraOrbit.lastY = event.clientY;
    this.overlayCanvas.setPointerCapture?.(event.pointerId);
  }

  onPointerMove(event) {
    if (!this.cameraOrbit.enabled || this.cameraOrbit.pointerId !== event.pointerId) return;
    event.preventDefault();
    const dx = event.clientX - this.cameraOrbit.lastX;
    const dy = event.clientY - this.cameraOrbit.lastY;
    this.cameraOrbit.lastX = event.clientX;
    this.cameraOrbit.lastY = event.clientY;
    this.cameraOrbit.yaw -= dx * 0.0085;
    this.cameraOrbit.pitch = clamp(this.cameraOrbit.pitch + dy * 0.0045, 0.06, 1.15);
  }

  onPointerUp(event) {
    if (!this.cameraOrbit.enabled) return;
    if (event.pointerId != null && this.cameraOrbit.pointerId != null && event.pointerId !== this.cameraOrbit.pointerId) return;
    this.cameraOrbit.enabled = false;
    this.cameraOrbit.pointerId = null;
  }

  onKeyDown(event) {
    const key = String(event?.key || "").toLowerCase();
    if (key === "`" || key === "f3") {
      this.toggleDebug();
      event.preventDefault();
    } else if (this.game?.mode === "build" && (key === "w" || key === "arrowup")) {
      this.buildCamera.move.forward = true;
      event.preventDefault();
    } else if (this.game?.mode === "build" && (key === "s" || key === "arrowdown")) {
      this.buildCamera.move.back = true;
      event.preventDefault();
    } else if (this.game?.mode === "build" && (key === "a" || key === "arrowleft")) {
      this.buildCamera.move.left = true;
      event.preventDefault();
    } else if (this.game?.mode === "build" && (key === "d" || key === "arrowright")) {
      this.buildCamera.move.right = true;
      event.preventDefault();
    } else if (this.game?.mode === "build" && key === "shift") {
      this.buildCamera.move.fast = true;
    } else if (this.game?.mode === "build" && key === "f") {
      this.recenter(true);
      event.preventDefault();
    } else if (key === "=" || key === "+" || key === "add") {
      this.adjustZoom(-1);
      event.preventDefault();
    } else if (key === "-" || key === "_" || key === "subtract") {
      this.adjustZoom(1);
      event.preventDefault();
    }
  }

  onKeyUp(event) {
    const key = String(event?.key || "").toLowerCase();
    if (key === "w" || key === "arrowup") this.buildCamera.move.forward = false;
    else if (key === "s" || key === "arrowdown") this.buildCamera.move.back = false;
    else if (key === "a" || key === "arrowleft") this.buildCamera.move.left = false;
    else if (key === "d" || key === "arrowright") this.buildCamera.move.right = false;
    else if (key === "shift") this.buildCamera.move.fast = false;
  }

  onWheel(event) {
    if (this.game?.menu?.open) return;
    event.preventDefault();
    this.adjustZoom(event.deltaY > 0 ? 1 : -1);
  }

  adjustZoom(direction) {
    const delta = (this.cameraZoom.step || 0.12) * direction;
    this.cameraZoom.target = clamp(this.cameraZoom.target + delta, this.cameraZoom.min, this.cameraZoom.max);
  }

  getCameraRelativeMoveIntent(moveInput) {
    const mx = moveInput?.x || 0;
    const my = moveInput?.y || 0;
    if (Math.abs(mx) <= 0.0001 && Math.abs(my) <= 0.0001) return moveInput;

    const forward = this.cameraTarget.clone().sub(this.camera.position);
    forward.y = 0;
    if (forward.lengthSq() < 0.0001) {
      forward.set(-Math.sin(this.cameraOrbit.yaw), 0, -Math.cos(this.cameraOrbit.yaw));
    }
    forward.normalize();

    const right = new THREE.Vector3(-forward.z, 0, forward.x).normalize();
    const desired = new THREE.Vector3()
      .addScaledVector(right, mx)
      .addScaledVector(forward, -my);

    return { x: desired.x, y: desired.z };
  }

  getMouseAimWorldPoint(mouseState) {
    const hero = this.game?.hero;
    if (!hero || !this.overlayCanvas) return null;

    const width = Math.max(1, this.game?.w || this.overlayCanvas.width || 1);
    const height = Math.max(1, this.game?.h || this.overlayCanvas.height || 1);
    const sx = clamp(mouseState?.x ?? width * 0.5, 0, width);
    const sy = clamp(mouseState?.y ?? height * 0.5, 0, height);

    this.pointerNdc.set((sx / width) * 2 - 1, -((sy / height) * 2 - 1));
    this.raycaster.setFromCamera(this.pointerNdc, this.camera);

    const buildMode = this.game?.mode === "build";
    const activeCenter = buildMode ? this.getActiveWorldCenter() : { x: hero.x, y: hero.y };
    const planeY = buildMode
      ? this.sampleRenderedTerrainSmoothHeight(activeCenter.x, activeCenter.y, 24)
      : this.toVec3(hero.x, hero.y, 0).y;
    this.groundPlane.constant = -planeY;
    if (this.raycaster.ray.intersectPlane(this.groundPlane, this.pointerWorld)) {
      return { x: this.pointerWorld.x, y: this.pointerWorld.z };
    }

    const forward = this.cameraTarget.clone().sub(this.camera.position);
    forward.y = 0;
    if (forward.lengthSq() < 0.0001) {
      forward.set(-Math.sin(this.cameraOrbit.yaw), 0, -Math.cos(this.cameraOrbit.yaw));
    }
    forward.normalize().multiplyScalar(420);
    return { x: activeCenter.x + forward.x, y: activeCenter.y + forward.z };
  }

  updateHeroHeight(dt) {
    const hero = this.game?.hero;
    if (!hero || this.game?.dungeon?.active) {
      this.heroHeight.initialized = false;
      this.heroHeight.current = 0;
      return;
    }

    const targetHeight = this.visualGroundHeightAt(hero.x, hero.y, 18, 8);
    if (!this.heroHeight.initialized) {
      this.heroHeight.current = targetHeight;
      this.heroHeight.initialized = true;
      return;
    }

    const delta = targetHeight - this.heroHeight.current;
    const maxRise = 95 * dt;
    const maxDrop = 120 * dt;
    const limited = clamp(delta, -maxDrop, maxRise);
    const smoothing = targetHeight > this.heroHeight.current ? 0.72 : 0.82;
    this.heroHeight.current += limited * smoothing;
  }

  syncHeroVisual() {
    const hero = this.game.hero;
    const dir = hero?.faceDir || hero?.aimDir || hero?.lastMove || { x: 1, y: 0 };
    this.heroHeading = Math.atan2(dir.x || 0, dir.y || 1);

    const position = this.game.dungeon.active
      ? this.toVec3(hero.x, hero.y, 11)
      : new THREE.Vector3(hero.x, this.heroHeight.current, hero.y);
    this.heroMarker.position.copy(position);
    this.heroMarker.rotation.y = this.heroHeading;

    const hurtPulse = 1 + clamp(hero?.state?.hurtT || 0, 0, 0.6) * 0.18;
    const dashPulse = 1 + clamp(hero?.state?.dashT || 0, 0, 0.8) * 0.10;
    this.heroMarker.scale.setScalar(Math.max(hurtPulse, dashPulse));
    this.heroBoat.visible = !!hero?.state?.sailing;
    if (this.heroBoat.visible !== this.shadowState.lastSailing) {
      this.shadowState.lastSailing = this.heroBoat.visible;
      this.shadowState.dirty = true;
    }

    const rig = this.heroMarker.userData?.heroRig;
    if (!rig) return;
    rig.root.visible = !this.heroBoat.visible;

    const gear = hero?.equip || {};
    rig.materials.armor.color.set(gear.armor?.color || "#7f93aa");
    rig.materials.helm.color.set(gear.helm?.color || "#b9c9d8");
    rig.materials.blade.color.set(gear.weapon?.color || "#dce9f5");
    rig.materials.leather.color.set(gear.boots?.color || "#5a4030");

    const rareGlow =
      gear.weapon?.rarity === "epic" || gear.armor?.rarity === "epic" || gear.helm?.rarity === "epic"
        ? { color: "#c995ff", intensity: 0.3 }
        : gear.weapon?.rarity === "rare" || gear.armor?.rarity === "rare" || gear.helm?.rarity === "rare"
          ? { color: "#88cfff", intensity: 0.22 }
          : { color: gear.armor?.color || "#9ccfff", intensity: 0.16 };
    rig.materials.glow.color.set(rareGlow.color);
    rig.materials.glow.emissive.set(rareGlow.color);
    rig.materials.glow.emissiveIntensity = rareGlow.intensity;

    const moveMag = Math.hypot(hero?.vx || 0, hero?.vy || 0);
    const strideT = performance.now() * 0.009;
    const stride = Math.min(1, moveMag / Math.max(1, hero.getMoveSpeed?.(this.world) || 150));
    const walkSwing = Math.sin(strideT) * 0.55 * stride;
    const dashLean = clamp(hero?.state?.dashT || 0, 0, 1) * 0.28;
    const hurtTilt = clamp(hero?.state?.hurtT || 0, 0, 0.4) * 0.1;

    rig.chest.rotation.x = dashLean - 0.04;
    rig.chest.rotation.z = hurtTilt;
    rig.hips.rotation.y = Math.sin(strideT * 0.5) * 0.08 * stride;
    rig.leftLeg.rotation.x = walkSwing;
    rig.rightLeg.rotation.x = -walkSwing;
    rig.swordArm.rotation.x = -0.45 - walkSwing * 0.35 - dashLean * 0.6;
    rig.swordArm.rotation.z = -0.22;
    rig.shieldArm.rotation.x = 0.28 + walkSwing * 0.22;
    rig.shieldArm.rotation.z = 0.26;
    rig.sword.rotation.y = 0.18 + clamp(hero?.state?.dashT || 0, 0, 1) * 0.42;
    rig.shield.rotation.z = 0.06 + Math.sin(strideT * 0.5) * 0.04;
    rig.cloak.rotation.x = 0.14 + stride * 0.16 + dashLean * 0.25;
    rig.tabard.rotation.x = stride * 0.08;
    rig.root.position.y = Math.sin(strideT * 0.5) * 0.55 * stride;
  }

  syncEnemyMeshes() {
    const live = new Set();
    for (const enemy of this.game.enemies || []) {
      if (!enemy?.alive) continue;
      live.add(enemy);
      let mesh = this.enemyMeshes.get(enemy);
      if (!mesh) {
        mesh = this.createEnemyMesh(enemy);
        this.enemyMeshes.set(enemy, mesh);
        this.enemyGroup.add(mesh);
      }

      mesh.position.copy(this.toVec3(enemy.x, enemy.y, 0));
      const facingX = enemy.vx || this.game.hero.x - enemy.x;
      const facingY = enemy.vy || this.game.hero.y - enemy.y;
      mesh.rotation.y = Math.atan2(facingX || 0, facingY || 1);
      const pulse = 1 + clamp(enemy.hitFlashT || 0, 0, 0.4) * 0.28;
      mesh.scale.setScalar(pulse);

      const health = mesh.userData.health;
      if (health) {
        const frac = clamp((enemy.hp || 0) / Math.max(1, enemy.maxHp || 1), 0, 1);
        health.scale.x = Math.max(0.001, frac);
        health.position.x = ((enemy.radius || 10) * 1.48) * (frac - 1);
      }
    }

    for (const [enemy, mesh] of this.enemyMeshes) {
      if (live.has(enemy)) continue;
      this.enemyGroup.remove(mesh);
      this.enemyMeshes.delete(enemy);
    }
  }

  syncProjectileMeshes() {
    const live = new Set();
    for (const projectile of this.game.projectiles || []) {
      if (!projectile?.alive) continue;
      live.add(projectile);
      let mesh = this.projectileMeshes.get(projectile);
      if (!mesh) {
        mesh = this.createProjectileMesh(projectile);
        this.projectileMeshes.set(projectile, mesh);
        this.projectileGroup.add(mesh);
      }

      mesh.position.copy(this.toVec3(projectile.x, projectile.y, projectile.nova ? 18 : 16));
      if (projectile.nova) {
        const scale = Math.max(0.35, (projectile.hitRadius || 14) / 14);
        mesh.scale.setScalar(scale);
        mesh.rotation.x = Math.PI * 0.5;
        mesh.material.opacity = clamp((projectile.life || 0) / Math.max(0.01, projectile.maxLife || 1), 0, 1) * 0.42;
      }
    }

    for (const [projectile, mesh] of this.projectileMeshes) {
      if (live.has(projectile)) continue;
      this.projectileGroup.remove(mesh);
      mesh.geometry?.dispose?.();
      mesh.material?.dispose?.();
      this.projectileMeshes.delete(projectile);
    }
  }

  syncLootMeshes() {
    const live = new Set();
    for (const loot of this.game.loot || []) {
      if (!loot?.alive) continue;
      live.add(loot);
      let mesh = this.lootMeshes.get(loot);
      if (!mesh) {
        mesh = this.createLootMesh(loot);
        this.lootMeshes.set(loot, mesh);
        this.lootGroup.add(mesh);
      }

      const bob = Math.sin((loot.t || 0) * 6) * 2;
      mesh.position.copy(this.toVec3(loot.x, loot.y, 18 + bob));
      mesh.rotation.y += 0.02;
    }

    for (const [loot, mesh] of this.lootMeshes) {
      if (live.has(loot)) continue;
      this.lootGroup.remove(mesh);
      mesh.geometry?.dispose?.();
      mesh.material?.dispose?.();
      this.lootMeshes.delete(loot);
    }
  }

  syncLandmarkState() {
    const progress = this.game.progress || {};
    for (const entry of this.landmarkEntries) {
      let visible = true;
      if (entry.type === "cache") visible = !progress.openedCaches?.has?.(entry.id);
      else if (entry.type === "herb") visible = !progress.pickedHerbs?.has?.(entry.id);
      else if (entry.type === "secret") visible = !progress.discoveredSecrets?.has?.(entry.id);
      else if (entry.type === "shrine") visible = !progress.claimedShrines?.has?.(entry.id);
      entry.mesh.visible = visible;
      if (entry.beacon) entry.beacon.visible = visible;
    }
  }

  updateFollowCamera(dt) {
    this.updateHeroHeight(dt);
    const buildMode = this.game?.mode === "build" && !this.game?.dungeon?.active;
    if (buildMode && !this.buildCamera.active) {
      this.buildCamera.active = true;
      this.buildCamera.x = this.game.hero.x;
      this.buildCamera.y = this.game.hero.y;
    } else if (!buildMode) {
      this.buildCamera.active = false;
    }
    if (buildMode) {
      const forward = new THREE.Vector3(
        -Math.sin(this.cameraOrbit.yaw),
        0,
        -Math.cos(this.cameraOrbit.yaw)
      ).normalize();
      const right = new THREE.Vector3(-forward.z, 0, forward.x).normalize();
      const move = this.buildCamera.move;
      const speed = (move.fast ? 2200 : 1200) * dt * this.cameraZoom.current;
      if (move.forward) {
        this.buildCamera.x += forward.x * speed;
        this.buildCamera.y += forward.z * speed;
      }
      if (move.back) {
        this.buildCamera.x -= forward.x * speed;
        this.buildCamera.y -= forward.z * speed;
      }
      if (move.left) {
        this.buildCamera.x -= right.x * speed;
        this.buildCamera.y -= right.z * speed;
      }
      if (move.right) {
        this.buildCamera.x += right.x * speed;
        this.buildCamera.y += right.z * speed;
      }
    }
    const target = this.game.dungeon.active
      ? this.toVec3(this.game.hero.x, this.game.hero.y, 30)
      : buildMode
        ? new THREE.Vector3(this.buildCamera.x, this.visualGroundHeightAt(this.buildCamera.x, this.buildCamera.y, 18, 8) + 26, this.buildCamera.y)
        : new THREE.Vector3(this.game.hero.x, this.heroHeight.current + 26, this.game.hero.y);
    const baseOffset = this.game.dungeon.active ? new THREE.Vector3(520, 460, 520) : new THREE.Vector3(880, 720, 880);
    const zoomMin = this.game.dungeon.active ? 0.58 : 0.42;
    if (this.cameraZoom.min !== zoomMin) {
      this.cameraZoom.min = zoomMin;
      this.cameraZoom.target = clamp(this.cameraZoom.target, this.cameraZoom.min, this.cameraZoom.max);
      this.cameraZoom.current = clamp(this.cameraZoom.current, this.cameraZoom.min, this.cameraZoom.max);
    }
    this.cameraZoom.current += (this.cameraZoom.target - this.cameraZoom.current) * clamp(dt * 6, 0, 1);
    const baseDistance = baseOffset.length() * this.cameraZoom.current;
    this.cameraOrbit.distance += (baseDistance - this.cameraOrbit.distance) * clamp(dt * 4.2, 0, 1);
    const planar = Math.cos(this.cameraOrbit.pitch) * this.cameraOrbit.distance;
    const desiredOffset = new THREE.Vector3(
      Math.sin(this.cameraOrbit.yaw) * planar,
      Math.sin(this.cameraOrbit.pitch) * this.cameraOrbit.distance,
      Math.cos(this.cameraOrbit.yaw) * planar
    );
    this.cameraOffset.lerp(desiredOffset, clamp(dt * 3.2, 0, 1));
    this.cameraTarget.lerp(target, clamp(dt * 4.5, 0, 1));

    const desiredPos = this.cameraTarget.clone().add(this.cameraOffset);
    this.camera.position.lerp(desiredPos, clamp(dt * 3.8, 0, 1));
    this.camera.lookAt(this.cameraTarget);
  }

  syncSceneFromGame(dt) {
    const editorRevision = this.world?.getEditorRevision?.() ?? -1;
    if (editorRevision !== this.lastEditorRevision) {
      this.queueEditorWorldRefresh("terrain");
      this.lastEditorRevision = editorRevision;
      this.shadowState.dirty = true;
      this.hudState.dirty = true;
    }
    this.rebuildLocalTerrainPatch(false);
    const buildMode = this.game?.mode === "build";
    if (buildMode) {
      this.syncHeroVisual();
      this.updateFollowCamera(dt);
      this.updateAtmosphere(dt);
      this.syncChromeVisibility();
      this.updateBuildPreview();
      this.enemyGroup.visible = false;
      this.projectileGroup.visible = false;
      this.lootGroup.visible = false;
      return;
    }
    this.clearPreviewGroup();
    this.enemyGroup.visible = true;
    this.projectileGroup.visible = true;
    this.lootGroup.visible = true;
    this.syncDungeonScene();
    this.syncHeroVisual();
    this.syncEnemyMeshes();
    this.syncProjectileMeshes();
    this.syncLootMeshes();
    this.syncLandmarkState();
    this.updateFollowCamera(dt);
    this.updateAtmosphere(dt);
    this.syncChromeVisibility();
  }

  clearPreviewGroup() {
    if (!this.previewGroup) return;
    while (this.previewGroup.children.length) {
      const child = this.previewGroup.children.pop();
      if (!child) break;
      child.parent?.remove(child);
      child.traverse?.((obj) => {
        obj.geometry?.dispose?.();
        const mats = Array.isArray(obj.material) ? obj.material : obj.material ? [obj.material] : [];
        for (const mat of mats) mat?.dispose?.();
      });
    }
  }

  makePreviewLine(points, color = 0x8fd8ff, lineWidth = 3) {
    if (!points?.length || points.length < 2) return null;
    const positions = [];
    for (const p of points) positions.push(p.x, p.y, p.z);
    const geometry = new THREE.BufferGeometry();
    geometry.setAttribute("position", new THREE.Float32BufferAttribute(positions, 3));
    const line = new THREE.Line(
      geometry,
      new THREE.LineBasicMaterial({
        color,
        transparent: true,
        opacity: 0.95,
        depthWrite: false,
      })
    );
    line.renderOrder = 12;
    return line;
  }

  makePreviewLoop(points, color = 0x8fd8ff) {
    if (!points?.length || points.length < 2) return null;
    const closed = [...points, points[0]];
    return this.makePreviewLine(closed, color);
  }

  getRiverPiecePoints(x, y, piece = "straight", angle = 0, width = 120) {
    const templates = {
      straight: [
        { x: -96, y: 0 },
        { x: -48, y: 0 },
        { x: 0, y: 0 },
        { x: 48, y: 0 },
        { x: 96, y: 0 },
      ],
      left: [
        { x: -92, y: 0 },
        { x: -52, y: 0 },
        { x: -12, y: 10 },
        { x: 24, y: 40 },
        { x: 40, y: 88 },
      ],
      wide: [
        { x: -118, y: 0 },
        { x: -59, y: 0 },
        { x: 0, y: 0 },
        { x: 59, y: 0 },
        { x: 118, y: 0 },
      ],
    };
    const base = templates[piece] || templates.straight;
    const a = Number.isFinite(+angle) ? +angle : 0;
    const cosA = Math.cos(a);
    const sinA = Math.sin(a);
    const pts2d = base.map((p) => ({
      x: x + p.x * cosA - p.y * sinA,
      y: y + p.x * sinA + p.y * cosA,
    }));
    const smooth = this.smoothPath(pts2d, 12, 0.12);
    return smooth.map((p) => new THREE.Vector3(
      p.x,
      this.sampleRenderedTerrainSmoothHeight(p.x, p.y, Math.max(12, width * 0.12)) + 1.2,
      p.y
    ));
  }

  buildOffsetPreview(points, halfWidth) {
    const left = [];
    const right = [];
    for (let i = 0; i < points.length; i++) {
      const prev = points[Math.max(0, i - 1)];
      const here = points[i];
      const next = points[Math.min(points.length - 1, i + 1)];
      const dx = next.x - prev.x;
      const dz = next.z - prev.z;
      const len = Math.hypot(dx, dz) || 1;
      const nx = -dz / len;
      const nz = dx / len;
      left.push(new THREE.Vector3(here.x + nx * halfWidth, here.y, here.z + nz * halfWidth));
      right.push(new THREE.Vector3(here.x - nx * halfWidth, here.y, here.z - nz * halfWidth));
    }
    return { left, right };
  }

  updateBuildPreview() {
    this.clearPreviewGroup();
    if (this.game?.mode !== "build" || this.game?._isMouseOverEditorHud?.()) return;
    const editor = this.game?.editor;
    const x = this.game?.mouse?.worldX;
    const y = this.game?.mouse?.worldY;
    if (!editor || !Number.isFinite(x) || !Number.isFinite(y)) return;

    if (editor.tool === "river") {
      const requestedWidth = Math.max(56, editor.strokeWidth * 0.95);
      const pieceData = this.world?.createEditorRiverPieceData?.(
        x,
        y,
        "straight",
        editor.riverAngle || 0,
        requestedWidth
      );
      if (!pieceData) return;
      const center = pieceData.points.map((p) => new THREE.Vector3(
        p.x,
        this.sampleRenderedTerrainSmoothHeight(p.x, p.y, Math.max(12, pieceData.visualWidth * 0.12)) + 1.2,
        p.y
      ));
      const previewWidth = pieceData.visualWidth;
      const edges = this.buildOffsetPreview(center, previewWidth * 0.5);
      const leftLine = this.makePreviewLine(edges.left, 0xd6efff);
      const rightLine = this.makePreviewLine(edges.right, 0xd6efff);
      if (leftLine) this.previewGroup.add(leftLine);
      if (rightLine) this.previewGroup.add(rightLine);
      return;
    }

    if (editor.tool === "bridge") {
      const length = Math.max(96, editor.strokeWidth * 1.4);
      const width = Math.max(26, editor.strokeWidth * 0.52);
      const a = editor.riverAngle || 0;
      const cosA = Math.cos(a);
      const sinA = Math.sin(a);
      const corners2d = [
        { x: -length * 0.5, y: -width * 0.5 },
        { x: length * 0.5, y: -width * 0.5 },
        { x: length * 0.5, y: width * 0.5 },
        { x: -length * 0.5, y: width * 0.5 },
      ];
      const corners = corners2d.map((p) => {
        const wx = x + p.x * cosA - p.y * sinA;
        const wy = y + p.x * sinA + p.y * cosA;
        return new THREE.Vector3(wx, this.sampleRenderedTerrainSmoothHeight(wx, wy, 16) + 1.4, wy);
      });
      const loop = this.makePreviewLoop(corners, 0xe8d1a5);
      if (loop) this.previewGroup.add(loop);
      return;
    }

    if (editor.tool === "dock") {
      const w = 60;
      const h = 32;
      const corners = [
        new THREE.Vector3(x - w * 0.5, this.sampleRenderedTerrainSmoothHeight(x - w * 0.5, y - h * 0.5, 12) + 1.2, y - h * 0.5),
        new THREE.Vector3(x + w * 0.5, this.sampleRenderedTerrainSmoothHeight(x + w * 0.5, y - h * 0.5, 12) + 1.2, y - h * 0.5),
        new THREE.Vector3(x + w * 0.5, this.sampleRenderedTerrainSmoothHeight(x + w * 0.5, y + h * 0.5, 12) + 1.2, y + h * 0.5),
        new THREE.Vector3(x - w * 0.5, this.sampleRenderedTerrainSmoothHeight(x - w * 0.5, y + h * 0.5, 12) + 1.2, y + h * 0.5),
      ];
      const loop = this.makePreviewLoop(corners, 0xd6bd96);
      if (loop) this.previewGroup.add(loop);
      return;
    }

    const radius = ["raise", "lower", "water", "erase", "flatten", "smooth"].includes(editor.tool)
      ? Math.max(18, editor.brushSize * 0.5)
      : 18;
    const ringPoints = [];
    for (let i = 0; i < 24; i++) {
      const t = (i / 24) * Math.PI * 2;
      const px = x + Math.cos(t) * radius;
      const py = y + Math.sin(t) * radius;
      ringPoints.push(new THREE.Vector3(px, this.sampleRenderedTerrainSmoothHeight(px, py, 12) + 0.8, py));
    }
    const ring = this.makePreviewLoop(ringPoints, 0x8fd8ff);
    if (ring) this.previewGroup.add(ring);
  }

  updateAtmosphere(dt) {
    const dungeonActive = !!this.game?.dungeon?.active;
    const targetFog = this.atmosphereTargets.fog;
    const targetBg = this.atmosphereTargets.bg;
    const ambientSky = this.atmosphereTargets.ambientSky;
    const ambientGround = this.atmosphereTargets.ambientGround;
    const sunColor = this.atmosphereTargets.sun;
    targetFog.set(0x091018);
    targetBg.set(0x091018);
    let targetDensity = 0.000075;
    ambientSky.set(0xb7d7ff);
    ambientGround.set(0x322a22);
    sunColor.set(0xffefd8);
    let ambientIntensity = 1.12;
    let sunIntensity = 2.0;

    if (dungeonActive) {
      const theme = this.getDungeonTheme3D();
      targetFog.copy(this.shadeColorHex(theme.floor1 || "#1d2027", 0.24));
      targetBg.copy(this.shadeColorHex(theme.floor0 || "#2a2d33", 0.04));
      targetDensity = 0.00011;
      ambientSky.copy(this.shadeColorHex(theme.propA || "#4b5260", 0.44));
      ambientGround.copy(this.shadeColorHex(theme.floor1 || "#1d2027", 0.06));
      sunColor.copy(this.shadeColorHex(theme.propB || "#343a44", 0.32));
      ambientIntensity = 0.92;
      sunIntensity = 1.42;
    } else {
      const zone = this.world?.getZoneName?.(this.game?.hero?.x || 0, this.game?.hero?.y || 0) || "";
      if (zone.includes("ash")) {
        targetFog.set(0x22181a);
        targetBg.set(0x1a1114);
        targetDensity = 0.000095;
        ambientSky.set(0xb39387);
        ambientGround.set(0x3d2920);
        sunColor.set(0xffcba0);
      } else if (zone.includes("mountain") || zone.includes("stone")) {
        targetFog.set(0x101722);
        targetBg.set(0x0c131d);
        targetDensity = 0.000085;
        ambientSky.set(0xc0d6ee);
        ambientGround.set(0x38404a);
        sunColor.set(0xf6e4cb);
      } else if (zone.includes("forest") || zone.includes("root")) {
        targetFog.set(0x0f1712);
        targetBg.set(0x0d140f);
        targetDensity = 0.000082;
        ambientSky.set(0xa3d0ae);
        ambientGround.set(0x283021);
        sunColor.set(0xffefcc);
      }
    }

    const t = clamp(dt * 2.4, 0, 1);
    this.atmosphere.fogColor.lerp(targetFog, t);
    this.atmosphere.bgColor.lerp(targetBg, t);
    this.atmosphere.density += (targetDensity - this.atmosphere.density) * t;
    this.scene.fog.color.copy(this.atmosphere.fogColor);
    this.scene.fog.density = this.atmosphere.density;
    this.scene.background.copy(this.atmosphere.bgColor);
    if (this.ambientLight) {
      this.ambientLight.color.lerp(ambientSky, t);
      this.ambientLight.groundColor.lerp(ambientGround, t);
      this.ambientLight.intensity += (ambientIntensity - this.ambientLight.intensity) * t;
    }
    if (this.sunLight) {
      this.sunLight.color.lerp(sunColor, t);
      this.sunLight.intensity += (sunIntensity - this.sunLight.intensity) * t;
    }
    if (this.waterShimmer && !dungeonActive) {
      this.waterShimmer.rotation.z += dt * 0.015;
      this.waterShimmer.material.opacity = 0.06 + Math.sin(performance.now() * 0.0004) * 0.02;
    }
  }

  updateShadowRefresh() {
    const hero = this.game?.hero;
    if (!hero) return;
    this.shadowState.frame++;
    const moved = Math.hypot(hero.x - (this.shadowState.lastHeroX || 0), hero.y - (this.shadowState.lastHeroY || 0));
    const dungeonActive = !!this.game?.dungeon?.active;
    if (moved > 85 || dungeonActive !== this.shadowState.lastDungeonActive) {
      this.shadowState.dirty = true;
      this.shadowState.lastHeroX = hero.x;
      this.shadowState.lastHeroY = hero.y;
      this.shadowState.lastDungeonActive = dungeonActive;
    }

    const moving = Math.hypot(hero.vx || 0, hero.vy || 0) > 10;
    const cadence = moving ? 6 : 15;
    this.renderer.shadowMap.needsUpdate = this.shadowState.dirty || this.shadowState.frame % cadence === 0;
    this.shadowState.dirty = false;
  }

  updateHudIfNeeded(dt) {
    this.hudState.elapsed += dt;
    if (!this.hudState.dirty && this.hudState.elapsed < this.hudState.interval) return;
    this.hudState.elapsed = 0;
    this.hudState.dirty = false;
    this.updateHud();
  }

  updateDebugPanelIfNeeded(dt) {
    this.debugState.elapsed += dt;
    if (!this.debug.enabled) return;
    if (!this.debugState.dirty && this.debugState.elapsed < this.debugState.interval) return;
    this.debugState.elapsed = 0;
    this.debugState.dirty = false;
    this.updateDebugPanel();
  }

  updateDebugStats(dt) {
    this.debug.frames++;
    this.debug.accum += dt;
    this.debug.frameMs = this.debug.frameMs * 0.9 + dt * 1000 * 0.1;
    if (this.debug.accum >= 0.5) {
      this.debug.fps = this.debug.frames / this.debug.accum;
      this.debug.frames = 0;
      this.debug.accum = 0;
    }
  }

  createDebugPanel() {
    const panel = document.createElement("section");
    panel.id = "debug-panel-3d";
    panel.style.cssText = [
      "position:fixed",
      "right:16px",
      "bottom:16px",
      "z-index:8",
      "width:min(360px,calc(100vw - 32px))",
      "padding:12px",
      "border-radius:10px",
      "border:1px solid rgba(150,190,220,0.22)",
      "background:rgba(8,13,20,0.84)",
      "box-shadow:0 18px 44px rgba(0,0,0,0.32)",
      "backdrop-filter:blur(10px)",
      "color:rgba(236,242,248,0.95)",
      "font:12px/1.35 Consolas, 'Segoe UI', monospace",
      "display:none",
    ].join(";");

    const title = document.createElement("div");
    title.style.cssText = "display:flex;align-items:center;justify-content:space-between;gap:10px;margin-bottom:10px;font-family:'Segoe UI',Arial,sans-serif;font-weight:700;";
    title.innerHTML = "<span>3D Debug</span><span style=\"font-weight:500;color:rgba(204,217,229,0.82)\">F3 / `</span>";
    panel.appendChild(title);

    const controls = document.createElement("div");
    controls.style.cssText = "display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:8px;margin-bottom:10px;";
    const buttons = [
      ["Pause Sim", () => { this.debug.paused = !this.debug.paused; this.updateDebugPanel(); }],
      ["Wireframe", () => this.toggleWireframe()],
      ["Recenter", () => this.recenter(true)],
      ["Heal", () => {
        const stats = this.game.hero.getStats?.() || {};
        this.game.hero.hp = stats.maxHp || this.game.hero.maxHp || 100;
        this.game.hero.mana = stats.maxMana || this.game.hero.maxMana || 0;
        this.updateDebugPanel();
      }],
      ["Flush Save", () => this.game.flushSave?.()],
      ["Refresh HUD", () => this.updateHud()],
    ];
    for (const [label, handler] of buttons) {
      const button = document.createElement("button");
      button.type = "button";
      button.textContent = label;
      button.style.cssText = "height:30px;border-radius:8px;border:1px solid rgba(150,190,220,0.22);background:rgba(255,255,255,0.06);color:inherit;cursor:pointer;";
      button.addEventListener("click", handler);
      controls.appendChild(button);
    }
    panel.appendChild(controls);

    const body = document.createElement("pre");
    body.style.cssText = "margin:0;white-space:pre-wrap;color:rgba(217,229,240,0.92);";
    panel.appendChild(body);

    document.body.appendChild(panel);
    this.debug.panel = panel;
    this.debug.body = body;
  }

  toggleDebug() {
    this.debug.enabled = !this.debug.enabled;
    if (this.debug.panel) this.debug.panel.style.display = this.debug.enabled ? "block" : "none";
    this.debugState.dirty = true;
    this.updateDebugPanel();
  }

  toggleWireframe() {
    this.debug.wireframe = !this.debug.wireframe;
    this.scene.traverse((obj) => {
      const materials = Array.isArray(obj.material) ? obj.material : obj.material ? [obj.material] : [];
      for (const material of materials) {
        if ("wireframe" in material) material.wireframe = this.debug.wireframe;
      }
    });
    this.shadowState.dirty = true;
    this.debugState.dirty = true;
    this.updateDebugPanel();
  }

  updateDebugPanel() {
    if (!this.debug.enabled || !this.debug.body || !this.game) return;
    const hero = this.game.hero;
    const stats = hero.getStats?.() || {};
    const objective = this.game.getTrackedObjectiveSummary?.() || this.game.getObjective?.();
    const zone = this.world?.getZoneName?.(hero.x, hero.y) || "-";
    const rendererInfo = this.renderer.info;
    this.debug.body.textContent = [
      `fps ${this.debug.fps.toFixed(1)} | frame ${this.debug.frameMs.toFixed(1)}ms`,
      `hero ${Math.round(hero.x)}, ${Math.round(hero.y)} | hp ${Math.round(hero.hp || 0)}/${Math.round(stats.maxHp || hero.maxHp || 1)} | mana ${Math.round(hero.mana || 0)}/${Math.round(stats.maxMana || hero.maxMana || 0)}`,
      `zone ${zone} | menu ${this.game.menu?.open || "-"} | dungeon ${this.game.dungeon?.active ? `floor ${this.game.dungeon.floor || 1}` : "overworld"}`,
      `enemies ${this.game.enemies?.filter((e) => e?.alive).length || 0} | loot ${this.game.loot?.filter((l) => l?.alive).length || 0} | projectiles ${this.game.projectiles?.filter((p) => p?.alive).length || 0}`,
      `draw calls ${rendererInfo.render.calls} | tris ${rendererInfo.render.triangles}`,
      `sim ${this.debug.paused ? "paused" : "live"} | wire ${this.debug.wireframe ? "on" : "off"}`,
      objective?.title ? `objective ${objective.title}` : "objective explore",
    ].join("\n");
  }

  updateHud() {
    const hero = this.game.hero;
    const objective = this.game.getTrackedObjectiveSummary?.() || this.game.getObjective?.();
    const zone = this.world?.getZoneName?.(hero.x, hero.y) || "Unknown";
    const liveEnemies = (this.game.enemies || []).filter((enemy) => enemy?.alive).length;
    const townCount = (this.world.towns?.length || 0) + (this.world.startTown ? 1 : 0);
    const materials = hero.materials || {};
    const nearbyTown = this.game?._cachedNearbyTown?.name || "";
    const potions = `H${hero.potions?.hp || 0}/M${hero.potions?.mana || 0}`;

    if (this.ui.summaryEl) {
      this.ui.summaryEl.textContent =
        this.game.dungeon?.active
          ? `Dungeon floor ${this.game.dungeon.floor || 1}. ${objective?.title || "Push deeper."} Potions ${potions}. Materials H${materials.herbs || 0} O${materials.ore || 0} S${materials.scrap || 0}.`
          : `${zone}. ${objective?.title || "Explore the world."} ${liveEnemies} active enemies nearby.${nearbyTown ? ` Near ${nearbyTown}.` : ""}`;
    }
    if (this.ui.seedEl) this.ui.seedEl.textContent = String(this.world.seed);
    if (this.ui.heroEl) this.ui.heroEl.textContent = `Lv ${hero.level || 1} ${this.game?._className?.() || "Knight"}  Gold ${hero.gold || 0}  Potions ${potions}  @ ${Math.round(hero.x)}, ${Math.round(hero.y)}`;
    const roadGroup = this.overworldDetailGroup?.children?.find?.((child) => child?.name === "roads");
    const riverGroup = this.overworldDetailGroup?.children?.find?.((child) => child?.name === "rivers");
    const renderedRoadPieces = roadGroup?.children?.length || 0;
    const renderedRiverPieces = riverGroup?.children?.length || 0;
    if (this.ui.roadsEl) this.ui.roadsEl.textContent = roadGroup?.children?.length ? `${this.world.roads?.length || 0} paths / ${renderedRoadPieces} shown` : `${this.world.roads?.length || 0} paths / terrain-carved`;
    if (this.ui.riversEl) this.ui.riversEl.textContent = riverGroup ? `${this.world._riverBands?.length || 0} rivers / ${renderedRiverPieces} shown` : `${this.world._riverBands?.length || 0} rivers / terrain-carved`;
    if (this.ui.bridgesEl) this.ui.bridgesEl.textContent = `${this.world.bridges?.length || 0} bridges / ${this.world.docks?.length || 0} docks`;
    if (this.ui.townsEl) this.ui.townsEl.textContent = `${townCount} settlements`;
  }

  syncChromeVisibility() {
    const muted = this.game?.menu?.open === "class-select";
    this.ui.hudEl?.classList.toggle("is-muted", muted);
    this.ui.actionsEl?.classList.toggle("is-muted", muted);
    this.ui.footerEl?.classList.toggle("is-muted", muted);
    this.hudState.dirty = true;
  }

  refreshOverworldDetailIfNeeded() {
    if (this.game?.dungeon?.active) return;
    const activeCenter = this.getActiveWorldCenter();
    const heroX = activeCenter.x;
    const heroY = activeCenter.y;
    const currentSig = `${this.world?._trees?.length || 0}|${this.world?._rocks?.length || 0}|${this.world?._clutter?.length || 0}`;
    const now = performance.now ? performance.now() : 0;
    const progressivePropRefresh =
      !this.world?.isBootWarm?.() &&
      currentSig !== this.worldPropsSignature &&
      now - (this.worldPropsRefreshAt || 0) >= 1450;
    const dx = heroX - (this.detailCenter?.x || 0);
    const dy = heroY - (this.detailCenter?.y || 0);
    const refreshDist = this.detailRefreshDistance || 1450;
    if (this.overworldDetailGroup && !this.worldPropsGroup && now - (this.worldPropsRefreshAt || 0) >= 450) {
      this.rebuildWorldPropsOnly(heroX, heroY);
      return;
    }
    if (this.detailBootLite && this.world?.isBootWarm?.() && now - (this.worldPropsRefreshAt || 0) >= 900) {
      this.rebuildOverworldDetail(false, true, false);
      return;
    }
    if (progressivePropRefresh) {
      this.rebuildWorldPropsOnly(heroX, heroY);
      return;
    }
    if (this.overworldDetailGroup && dx * dx + dy * dy < refreshDist * refreshDist) return;
    this.rebuildOverworldDetail(false);
  }

  resize() {
    const cssW = Math.max(320, window.innerWidth | 0);
    const cssH = Math.max(240, window.innerHeight | 0);
    const dpr = Math.max(1, window.devicePixelRatio || 1);

    this.canvas.style.width = `${cssW}px`;
    this.canvas.style.height = `${cssH}px`;
    this.overlayCanvas.style.width = `${cssW}px`;
    this.overlayCanvas.style.height = `${cssH}px`;

    this.overlayCanvas.width = Math.max(1, Math.floor(cssW * dpr));
    this.overlayCanvas.height = Math.max(1, Math.floor(cssH * dpr));

    if (this.game?.ctx) {
      this.game.ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      this.game.ctx.imageSmoothingEnabled = true;
    }

    this.camera.aspect = cssW / cssH;
    this.camera.updateProjectionMatrix();
    this.renderer.setSize(cssW, cssH, false);
    this.game?.resize?.(cssW, cssH);
  }

  animate(now) {
    if (!this.running) return;
    this.rafId = requestAnimationFrame(this.animate);

    let frame = (now - this.lastTime) / 1000;
    this.lastTime = now;
    if (!Number.isFinite(frame) || frame < 0) frame = STEP;
    frame = Math.min(MAX_FRAME, frame);
    this.accumulator += frame;
    this.updateDebugStats(frame);

    if (!this.debug.paused) {
      let steps = 0;
      while (this.accumulator >= STEP && steps < MAX_STEPS) {
        this.game.update(STEP);
        this.accumulator -= STEP;
        steps++;
      }
      if (steps >= MAX_STEPS) this.accumulator = 0;
    }

    this.game.noteFrame?.(frame);
    this.refreshOverworldDetailIfNeeded();
    this.syncSceneFromGame(frame);
    this.updateHudIfNeeded(frame);
    this.game.draw();
    this.updateShadowRefresh();
    this.renderer.render(this.scene, this.camera);
    this.updateDebugPanelIfNeeded(frame);
  }
}
