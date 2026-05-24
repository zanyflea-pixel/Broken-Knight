// src/game.js
// v106.3 FULL GAME FILE
// - arrow-only movement
// - fuller gameplay loop
// - inventory / equip / salvage
// - skills / cooldowns / mouse aim
// - shop / waystone / dock / dungeon interactions
// - zone messages / autosave / loot pickup / enemy spawning
// - safe-ground recovery
// - built to work with current world.js / entities.js / ui.js / util.js / save.js

import World from "./world.js";
import { clamp, dist2, norm, RNG, hash2 } from "./util.js";
import { Hero, Enemy, Projectile, Loot, makeGear } from "./entities.js";
import Input from "./input.js";
import UI from "./ui.js";
import Save from "./save.js";

const DEV_RESET_CONFIRM_MS = 2500;
const DEV_TOOL_ACTION_COUNT = 11;
const SHOP_ACTION_COUNT = 4;
const TOWN_ACTION_COUNT = 9;
const EQUIPMENT_SLOTS = ["weapon", "armor", "helm", "boots", "ring", "trinket"];
const SKILL_PANEL_ORDER = ["q", "w", "e", "r"];
const QUEST_PANEL_HEIGHT = 420;
const QUEST_TRACKS = [
  ["1", "story"],
  ["2", "bounty"],
  ["3", "town"],
  ["4", "dungeon"],
  ["5", "dragon"],
  ["6", "treasure"],
  ["7", "secret"],
];
const QUEST_TRACK_ROWS = [
  ["story", "bounty", "town", "dungeon"],
  ["dragon", "treasure", "secret"],
];
const EDITOR_TOOL_IDS = [
  "road", "river", "bridge", "dock",
  "raise", "lower", "water", "erase", "flatten", "smooth",
  "tree", "rock", "clutter",
  "camp", "town", "dungeon", "shrine",
  "cache", "secret", "dragon", "waystone", "herb",
];
const EDITOR_TOOL_GROUPS = [
  {
    label: "Paths",
    tools: ["road", "river", "bridge", "dock"],
  },
  {
    label: "Terrain",
    tools: ["raise", "lower", "water", "erase", "flatten", "smooth"],
  },
  {
    label: "Props",
    tools: ["tree", "rock", "clutter"],
  },
  {
    label: "Places",
    tools: ["camp", "town", "dungeon", "shrine", "cache", "secret", "dragon", "waystone", "herb"],
  },
];

export default class Game {
  constructor(canvas, opts = {}) {
    if (!canvas) throw new Error("Game: canvas is required");

    this.canvas = canvas;
    this.renderMode = opts.renderMode || "full";
    this.startMode =
      opts.startMode === "river-build"
        ? "river-build"
        : opts.startMode === "build"
          ? "build"
          : "play";
    this.worldVariant = opts.worldVariant || (this.startMode === "river-build" ? "river-build" : "default");
    this.getMoveIntent = typeof opts.getMoveIntent === "function" ? opts.getMoveIntent : null;
    this.getAimWorldPoint = typeof opts.getAimWorldPoint === "function" ? opts.getAimWorldPoint : null;
    this.onEditorWorldChanged = typeof opts.onEditorWorldChanged === "function" ? opts.onEditorWorldChanged : null;
    const contextAttributes = {
      alpha: false,
      desynchronized: true,
      ...(opts.contextAttributes || {}),
    };
    this.ctx = canvas.getContext("2d", contextAttributes);

    this.w = canvas.width | 0;
    this.h = canvas.height | 0;

    this.seed = (Date.now() & 0x7fffffff) | 0;

    this.input = new Input(window);
    this.ui = new UI(canvas);
    this.save = new Save("broke-knight-save-v106");
    this._bootSaveData = this.save.load?.() || this.save.read?.() || this.save.get?.() || null;
    this._hadBootSave = !!this._bootSaveData;
    if (Number.isFinite(+this._bootSaveData?.seed)) this.seed = this._bootSaveData.seed | 0;

    this._bootStage = "";
    this._bootProgress = 0;
    const bootProgress = typeof opts.onBootProgress === "function" ? opts.onBootProgress : null;
    const setBootStage = (stage, progress = null) => {
      this._bootStage = stage;
      if (progress != null) this._bootProgress = progress;
      bootProgress?.(stage, progress);
    };

    setBootStage("Reading your save...", 0.08);
    setBootStage("Laying out the world...", 0.18);
    this.world = new World(this.seed, { viewW: this.w, viewH: this.h, variant: this.worldVariant });
    setBootStage("Waking the hero...", 0.38);
    this.hero = new Hero(this.world.spawn?.x ?? 0, this.world.spawn?.y ?? 0);

    this.enemies = [];
    this.projectiles = [];
    this.loot = [];
    this.hitSparks = [];
    this.floatingTexts = [];

    this.camera = {
      x: this.hero.x,
      y: this.hero.y,
      zoom: 1,
      shakeT: 0,
      shakeMag: 0,
      sx: 0,
      sy: 0,
    };

    this.perf = {
      enemyUpdateRadius: 920,
      lootUpdateRadius: 760,
      projectileUpdateRadius: 1120,
      maxEnemies: 30,
      maxLoot: 60,
      maxProjectiles: 56,
      maxFloatingTexts: 48,
      cleanupTimer: 0,
      cleanupEvery: 0.42,
      touchDamageTick: 0.34,
      spawnMinDistance: 840,
      spawnMaxDistance: 1360,
      worldSpawnSafeRadius: 760,
      campSafeRadius: 180,
      enemyLogicRadius: 720,
      projectileLogicRadius: 900,
    };

    this.time = 0;
    this._dtClamp = 0.05;
    this._autosaveT = 8;
    this._spawnTimer = 0;
    this._campRespawnT = 0;
    this._nearbyPoiTimer = 0;
    this._zoneSampleT = 0;
    this._safetyCheckT = 0;
    this._bridgeDiscoveryT = 0;
    this._worldRevealT = 0;
    this._enemyCrowdResolveT = 0;
    this._fps = 0;
    this._frameMs = 0;
    this._frameJank = 0;
    this.renderScale = 1;
    this._fpsAccum = 0;
    this._fpsFrames = 0;
    this._screenFxCache = null;
    this._simPhase = 0;
    this._activeEnemies = [];
    this._activeEnemyRefreshT = 0;
    this._needsInitialSpawn = true;
    this._startupSpawnT = 0.18;
    this._heroTerrainSampleT = 0;
    this._heroTerrainSample = {
      moveModifier: 1,
      zone: "meadow",
      x: this.hero.x,
      y: this.hero.y,
    };

    this.menu = { open: null, mapZoom: 1 };
    this.mode = "play";
    this.invIndex = 0;

    this.msg = "";
    this.msgT = 0;
    this.zoneMsg = "";
    this.zoneMsgT = 0;

    this._touchDamageCd = 0;
    this._dockToggleCd = 0;
    this._interactCd = 0;
    this._lastZoneName = "";
    this._killFlashT = 0;
    this._deathCd = 0;
    this._lastHeroLevel = this.hero.level || 1;

    this._cachedNearbyCamp = null;
    this._cachedNearbyDock = null;
    this._cachedNearbyWaystone = null;
    this._cachedNearbyDungeon = null;
    this._cachedNearbyShrine = null;
    this._cachedNearbyCache = null;
    this._cachedNearbySecret = null;
    this._cachedNearbyTown = null;
    this._cachedNearbyTownDoor = null;
    this._cachedNearbyDragonLair = null;
    this._cachedNearbyHerb = null;
    this.inventoryView = "list";
    this._townServiceFocus = "";

    this._rng = new RNG(hash2(this.seed, 9001));
    this._bootProgress = 0.44;
    this._bootStage = "Opening the roads...";

    this.mouse = {
      x: this.w * 0.5,
      y: this.h * 0.5,
      worldX: this.hero.x,
      worldY: this.hero.y,
      down: false,
      clicked: false,
      aimRecentT: 0,
      moved: false,
    };
    this.touch = {
      enabled: false,
      recentT: 0,
      moveId: null,
      aimId: null,
      baseX: 0,
      baseY: 0,
      x: 0,
      y: 0,
      mx: 0,
      my: 0,
      buttons: {},
    };

    this.skillDefs = {
      q: { key: "q", name: "Spark", mana: 8, cd: 0.22, color: "#8be9ff" },
      w: { key: "w", name: "Nova", mana: 18, cd: 1.8, color: "#d6f5ff" },
      e: { key: "e", name: "Blink", mana: 14, cd: 2.8, color: "#ffd36e" },
      r: { key: "r", name: "Orb", mana: 22, cd: 3.4, color: "#c08cff" },
    };

    this.cooldowns = { q: 0, w: 0, e: 0, r: 0 };

    this.skillProg = {
      q: { xp: 0, level: 1 },
      w: { xp: 0, level: 1 },
      e: { xp: 0, level: 1 },
      r: { xp: 0, level: 1 },
    };

    this.progress = {
      discoveredWaystones: new Set(),
      discoveredDocks: new Set(),
      dungeonBest: 0,
      visitedCamps: new Set(),
      eliteKills: 0,
      bountyCompletions: 0,
      campRenown: {},
      campRestBonusClaimed: {},
      claimedShrines: new Set(),
      openedCaches: new Set(),
      discoveredSecrets: new Set(),
      defeatedDragons: new Set(),
      relicShards: 0,
      storyMilestones: {},
      visitedTowns: new Set(),
      crossedBridges: new Set(),
      herbs: 0,
      pickedHerbs: new Set(),
      materials: { scrap: 0, ore: 0, hide: 0, essence: 0 },
    };

    this.shop = {
      campId: null,
      items: [],
      discount: 0,
    };

    this.dungeon = {
      active: false,
      kind: "depths",
      floor: 0,
      origin: null,
      lairId: null,
      room: null,
      roomIndex: 0,
      totalRooms: 0,
      roomRewarded: false,
      layout: null,
      currentRoomId: null,
      keys: 0,
      roomClearT: 0,
      spawnQueue: [],
      hoardOpened: false,
    };

    this.dev = {
      godMode: false,
      showProfiler: false,
      showSpikeMonitor: false,
    };
    this.editor = {
      tool: "road",
      brushSize: 180,
      strokeWidth: 86,
      terrainPower: 18,
      propScale: 1,
      riverPiece: "straight",
      riverAngle: (53 * Math.PI) / 180,
      showGameHud: false,
      detail: 1,
      dragging: false,
      stroke: [],
      pendingTerrainStamps: [],
      terrainFlushT: 0,
      lastPaintX: NaN,
      lastPaintY: NaN,
      lastPaintT: 0,
      exportText: "",
      lastStatus: "",
      importedAt: 0,
      playMode: false,
    };
    this._editorAutosaveTimer = null;
    this._editorBaseCaptured = false;

    this._recentFrameSamples = [];
    this._spikeStats = {
      worstMs: 0,
      hitch24: 0,
      hitch33: 0,
      hitch50: 0,
      moveWorstMs: 0,
      moveHitches: 0,
      windowSec: 5,
    };
    this._perfLastHeroX = this.hero.x;
    this._perfLastHeroY = this.hero.y;
    this._moveIntentTimer = 0;

    this.trackedObjective = "story";
    this.quest = this._makeBountyQuest();

    this._bindMouse();
    this._loadGame();

    if (!this.hero.inventory) this.hero.inventory = [];
    if (!this.hero.classId) this.hero.classId = "knight";
    if (!this.hero.equip) this.hero.equip = {};
    if (!this.hero.potions) this.hero.potions = { hp: 2, mana: 1 };
    if (!this.hero.lastMove) this.hero.lastMove = { x: 1, y: 0 };
    if (!this.hero.aimDir) this.hero.aimDir = { x: 1, y: 0 };
    if (!this.hero.state) {
      this.hero.state = {
        sailing: false,
        dashT: 0,
        hurtT: 0,
        slowT: 0,
        poisonT: 0,
      };
    }

    this.hero.state.sailing = false;
    this.hero.state.dashT = 0;
    this.hero.state.hurtT = 0;
    this.hero.state.slowT = 0;
    this.hero.state.poisonT = 0;
    this.hero.state.mountainPassAccess = !!this.progress?.storyMilestones?.mountainPassAccess;
    if (this.startMode === "build" || this.startMode === "river-build") {
      this.mode = "build";
      this.menu.open = "editor";
      if (this.startMode === "river-build") {
        this.editor.tool = "river";
        this.editor.showGameHud = false;
      }
    } else if (!this._hadBootSave) this.menu.open = "class-select";

    this._ensureHeroSafe(true);
    this.world?.revealAround?.(this.hero.x, this.hero.y, 780);
    this._refreshHeroTerrainSample(true);
    if (this._worldBuildMigrated) this._saveGame();
  }

  getBootProgress() {
    const worldProgress = this.world?.getBootProgress?.() ?? 1;
    return clamp(0.44 + worldProgress * 0.56, 0, 1);
  }

  getBootStatusText() {
    return this.world?.getBootStatusText?.() || this._bootStage || "Building the world...";
  }

  isBootWarm() {
    return !!this.world?.isBootWarm?.();
  }

  resize(w, h) {
    this.w = w | 0;
    this.h = h | 0;
    this.world?.setViewSize?.(this.w, this.h);
    this.ui?.setViewSize?.(this.w, this.h);
  }

  update(dt) {
    dt = Math.min(this._dtClamp, Math.max(0, dt || 0));
    this.time += dt;
    this._simPhase = (this._simPhase + 1) & 7;
    if (this.touch) this.touch.recentT = Math.max(0, (this.touch.recentT || 0) - dt);

    this._tickMessages(dt);
    this._tickCooldowns(dt);
    this._tickVisualEffects(dt);
    this.mouse.aimRecentT = Math.max(0, (this.mouse.aimRecentT || 0) - dt);
    this._moveIntentTimer = Math.max(0, (this._moveIntentTimer || 0) - dt);
    if (this.mode === "build") {
      this.editor.terrainFlushT = Math.max(0, (this.editor.terrainFlushT || 0) - dt);
      this.world?.setFocusPoint?.(this.hero.x, this.hero.y);
      this._buildWorldTickT = Math.max(0, (this._buildWorldTickT || 0) - dt);
      if (!this.world?.isBootWarm?.() || this._buildWorldTickT <= 0) {
        this.world?.update?.(Math.min(dt, 0.014));
        this._buildWorldTickT = this.world?.isBootWarm?.() ? 0.24 : 0.06;
      }
      this._updateMouseWorld();
      this._handleMenus();
      this._updateCamera(dt);
      this.ui.update?.(dt, this);
      this.input.endFrame();
      this.mouse.clicked = false;
      return;
    }
    this.world?.setFocusPoint?.(this.hero.x, this.hero.y);
    this.world?.update?.(dt);
    this._updateMouseWorld();
    this._updateHeroTerrainSample(dt);
    this._applyTerrainEffects(dt);
    this._worldRevealT -= dt;
    if (this._worldRevealT <= 0) {
      this._worldRevealT = this.dungeon.active ? 0.18 : 0.24;
      this.world?.revealAround?.(this.hero.x, this.hero.y, this.dungeon.active ? 460 : 720);
    }
    this._updateNearbyPOIs(dt);
    this._updateActiveEnemySet(dt);

    this._handleMenus();

    if (this.menu.open === "inventory") {
      this._handleInventoryInput();
    } else if (this.menu.open === "shop") {
      this._handleShopInput();
    } else if (this.menu.open === "town") {
      this._handleTownInput();
    } else if (this.menu.open === "dev") {
      // Dev keys are handled in _handleMenus.
    } else if (this.menu.open === "editor") {
      // Editor tools are handled in _handleMenus.
    } else if (!this.menu.open) {
      this._handleMovement(dt);
      this._handleSkills();
    }

    if (this.menu.open) {
      this.hero.vx = 0;
      this.hero.vy = 0;
    }

    this._handleInteractShortcuts(dt);

    this.hero.update?.(dt);
    this._updateDungeonState(dt);
    this._updateEnemies(dt);
    this._updateProjectiles(dt);
    this._handleHeroDeath(dt);
    this._updateLoot(dt);
    this._checkHeroLevelFeedback();
    this._updateZoneMessage(dt);
    this._checkBridgeDiscovery(dt);
    this._updateCamera(dt);
    this.ui.update?.(dt, this);
    this._spawnWorldEnemies(dt);
    this._respawnCampEnemies(dt);
    this._runDeferredInitialSpawn(dt);
    this._cleanupFarEntities(dt);

    this._safetyCheckT -= dt;
    if (this._safetyCheckT <= 0) {
      this._safetyCheckT = 0.4;
      this._ensureHeroSafe(false);
    }

    this._autosaveT -= dt;
    if (this._autosaveT <= 0) {
      this._autosaveT = 8;
      this._saveGame();
    }

    this.input.endFrame();
    this.mouse.clicked = false;
  }

  draw() {
    const ctx = this.ctx;
    if (!ctx) return;
    const renderWorld = this.renderMode !== "ui-only";

    ctx.clearRect(0, 0, this.w, this.h);

    if (renderWorld) {
      ctx.save();
      ctx.translate(
        this.w * 0.5 - this.camera.x + this.camera.sx,
        this.h * 0.5 - this.camera.y + this.camera.sy
      );

      if (this.dungeon.active) this._drawDungeonRoom(ctx);
      else this.world.draw(ctx, this.camera, this.hero);

      for (const l of this.loot) {
        if (!this._isVisibleWorldPoint(l?.x, l?.y, 80)) continue;
        if (l?.alive) l.draw(ctx);
      }

      for (const p of this.projectiles) {
        if (!this._isVisibleWorldPoint(p?.x, p?.y, 120)) continue;
        if (p?.alive) p.draw(ctx);
      }

      for (const e of this.enemies) {
        if (!this._isVisibleWorldPoint(e?.x, e?.y, 150)) continue;
        if (!e?.alive) continue;
        const d2 = dist2(e.x, e.y, this.hero.x, this.hero.y);
        if (!this.dungeon.active && d2 > 340 * 340) this._drawEnemyProxy(ctx, e);
        else e.draw(ctx);
      }

      this.hero.draw(ctx);
      this._drawFloatingTexts(ctx);

      ctx.restore();
    }

    this._drawScreenEffects(ctx);
    this.ui.draw(ctx, this);
  }

  _isVisibleWorldPoint(x, y, margin = 96) {
    if (this.dungeon.active) return true;
    if (!Number.isFinite(x) || !Number.isFinite(y)) return false;
    const halfW = (this.w || 960) * 0.5 + margin;
    const halfH = (this.h || 540) * 0.5 + margin;
    return x >= this.camera.x - halfW && x <= this.camera.x + halfW &&
      y >= this.camera.y - halfH && y <= this.camera.y + halfH;
  }

  _drawScreenEffects(ctx) {
    ctx.save();

    if (this._killFlashT > 0) {
      ctx.fillStyle = `rgba(255,255,255,${0.22 * this._killFlashT})`;
      ctx.fillRect(0, 0, this.w, this.h);
    }

    const hpFrac = clamp((this.hero.hp || 0) / Math.max(1, this.hero.maxHp || 100), 0, 1);
    if (hpFrac < 0.32 && !this.dev?.godMode) {
      ctx.fillStyle = `rgba(120, 10, 24, ${(0.32 - hpFrac) * 0.34})`;
      ctx.fillRect(0, 0, this.w, this.h);
    }

    const hurtT = this.hero?.state?.hurtT || 0;
    if (hurtT > 0) {
      ctx.fillStyle = `rgba(255,120,120,${hurtT * 0.18})`;
      ctx.fillRect(0, 0, this.w, this.h);
    }

    const poisonT = this.hero?.state?.poisonT || 0;
    if (poisonT > 0) {
      ctx.fillStyle = `rgba(110,205,120,${Math.min(0.12, poisonT * 0.08)})`;
      ctx.fillRect(0, 0, this.w, this.h);
    }

    const dashT = this.hero?.state?.dashT || 0;
    if (dashT > 0) {
      const dir = this.hero?.aimDir || this.hero?.lastMove || { x: 1, y: 0 };
      const angle = Math.atan2(dir.y || 0, dir.x || 1);
      ctx.translate(this.w * 0.5, this.h * 0.5);
      ctx.rotate(angle);
      ctx.fillStyle = `rgba(255,211,110,${Math.min(0.16, dashT * 0.18)})`;
      ctx.fillRect(-this.w * 0.18, -18, this.w * 0.36, 36);
      ctx.setTransform(1, 0, 0, 1, 0, 0);
    }

    this._drawCachedScreenVignette(ctx);

    ctx.restore();
  }

  _drawEnemyProxy(ctx, e) {
    const r = Math.max(5, Math.min(12, (e.radius || e.r || 10) * 0.65));
    ctx.save();
    ctx.translate(e.x, e.y);
    ctx.fillStyle = "rgba(0,0,0,0.16)";
    ctx.beginPath();
    ctx.ellipse(0, r + 2, r * 0.95, Math.max(3, r * 0.28), 0, 0, Math.PI * 2);
    ctx.fill();

    ctx.fillStyle = e.colorB || "#5b6470";
    ctx.beginPath();
    ctx.arc(0, 0, r, 0, Math.PI * 2);
    ctx.fill();

    ctx.fillStyle = e.colorA || "#d95b5b";
    ctx.beginPath();
    ctx.arc(0, -1, r * 0.76, 0, Math.PI * 2);
    ctx.fill();

    if (e.elite || e.boss) {
      ctx.strokeStyle = e.boss ? "rgba(255,150,150,0.48)" : "rgba(255,226,130,0.42)";
      ctx.lineWidth = e.boss ? 2.4 : 1.6;
      ctx.beginPath();
      ctx.arc(0, 0, r + 3, 0, Math.PI * 2);
      ctx.stroke();
    }
    ctx.restore();
  }

  _drawCachedScreenVignette(ctx) {
    const key = `${this.w}x${this.h}:${this.dev?.godMode ? 1 : 0}`;
    let cache = this._screenFxCache;
    if (!cache || cache.key !== key) {
      const canvas = typeof document !== "undefined" ? document.createElement("canvas") : null;
      if (!canvas) return;
      canvas.width = Math.max(1, this.w | 0);
      canvas.height = Math.max(1, this.h | 0);
      const fx = canvas.getContext("2d");
      if (!fx) return;
      const grd = fx.createRadialGradient(
        this.w * 0.5,
        this.h * 0.48,
        Math.min(this.w, this.h) * 0.18,
        this.w * 0.5,
        this.h * 0.5,
        Math.max(this.w, this.h) * 0.62
      );
      grd.addColorStop(0, "rgba(255,255,255,0)");
      grd.addColorStop(1, this.dev?.godMode ? "rgba(120,190,255,0.12)" : "rgba(0,0,0,0.22)");
      fx.fillStyle = grd;
      fx.fillRect(0, 0, canvas.width, canvas.height);
      cache = this._screenFxCache = { key, canvas };
    }
    ctx.drawImage(cache.canvas, 0, 0, this.w, this.h);
  }

  _bindMouse() {
    const onMove = (ev) => {
      const rect = this.canvas.getBoundingClientRect();
      const sx = (ev.clientX - rect.left) * (this.w / rect.width);
      const sy = (ev.clientY - rect.top) * (this.h / rect.height);
      const moved = Math.abs(this.mouse.x - sx) + Math.abs(this.mouse.y - sy) > 1.25;
      this.mouse.x = sx;
      this.mouse.y = sy;
      if (moved) {
        this.mouse.aimRecentT = 0.75;
        this.mouse.moved = true;
      }
    };

    this.canvas.addEventListener("mousemove", onMove);
    this.canvas.addEventListener("mousedown", (ev) => {
      this.mouse.down = true;
      this.mouse.clicked = true;
      onMove(ev);
    });
    window.addEventListener("mouseup", () => {
      this.mouse.down = false;
    });
    this.canvas.addEventListener("wheel", (ev) => {
      if (this.menu.open === "inventory") {
        const inv = this.hero.inventory || [];
        if (inv.length <= 1) return;
        ev.preventDefault();
        const dir = ev.deltaY > 0 ? 1 : -1;
        this.invIndex = clamp((this.invIndex || 0) + dir, 0, inv.length - 1);
        return;
      }

      if (this.menu.open !== "map") return;
      ev.preventDefault();
      this._setMapZoom(ev.deltaY < 0 ? "in" : "out");
    }, { passive: false });

    const toCanvasPoint = (ev) => {
      const rect = this.canvas.getBoundingClientRect();
      return {
        x: (ev.clientX - rect.left) * (this.w / rect.width),
        y: (ev.clientY - rect.top) * (this.h / rect.height),
      };
    };
    const isTouch = (ev) => ev.pointerType === "touch" || ev.pointerType === "pen";
    const resetTouchButton = (id) => {
      if (!this.touch?.buttons) return;
      for (const key of Object.keys(this.touch.buttons)) {
        if (this.touch.buttons[key] === id) delete this.touch.buttons[key];
      }
    };

    this.canvas.addEventListener("pointerdown", (ev) => {
      if (!isTouch(ev)) return;
      ev.preventDefault();
      this.canvas.setPointerCapture?.(ev.pointerId);
      const p = toCanvasPoint(ev);
      this.touch.enabled = true;
      this.touch.recentT = 4;

      const button = this._touchButtonAt(p.x, p.y);
      if (button) {
        this.touch.buttons[button] = ev.pointerId;
        this._triggerTouchButton(button);
        return;
      }

      if (p.x < this.w * 0.48 && p.y > this.h * 0.42 && this.touch.moveId == null) {
        this.touch.moveId = ev.pointerId;
        this.touch.baseX = p.x;
        this.touch.baseY = p.y;
        this.touch.x = p.x;
        this.touch.y = p.y;
        this.touch.mx = 0;
        this.touch.my = 0;
        return;
      }

      this.touch.aimId = ev.pointerId;
      this.mouse.x = p.x;
      this.mouse.y = p.y;
      this.mouse.down = true;
      this.mouse.clicked = true;
      this.mouse.aimRecentT = 0.9;
      this.mouse.moved = true;
    }, { passive: false });

    this.canvas.addEventListener("pointermove", (ev) => {
      if (!isTouch(ev)) return;
      ev.preventDefault();
      const p = toCanvasPoint(ev);
      this.touch.enabled = true;
      this.touch.recentT = 4;

      if (ev.pointerId === this.touch.moveId) {
        const dx = p.x - this.touch.baseX;
        const dy = p.y - this.touch.baseY;
        const max = 54;
        const d = Math.hypot(dx, dy) || 0.001;
        const k = Math.min(1, d / max);
        this.touch.mx = (dx / d) * k;
        this.touch.my = (dy / d) * k;
        this.touch.x = this.touch.baseX + (dx / d) * Math.min(max, d);
        this.touch.y = this.touch.baseY + (dy / d) * Math.min(max, d);
      } else if (ev.pointerId === this.touch.aimId) {
        const moved = Math.abs(this.mouse.x - p.x) + Math.abs(this.mouse.y - p.y) > 1.25;
        this.mouse.x = p.x;
        this.mouse.y = p.y;
        if (moved) {
          this.mouse.aimRecentT = 0.9;
          this.mouse.moved = true;
        }
      }
    }, { passive: false });

    const endPointer = (ev) => {
      if (!isTouch(ev)) return;
      ev.preventDefault();
      if (ev.pointerId === this.touch.moveId) {
        this.touch.moveId = null;
        this.touch.mx = 0;
        this.touch.my = 0;
      }
      if (ev.pointerId === this.touch.aimId) {
        this.touch.aimId = null;
        this.mouse.down = false;
      }
      resetTouchButton(ev.pointerId);
    };
    this.canvas.addEventListener("pointerup", endPointer, { passive: false });
    this.canvas.addEventListener("pointercancel", endPointer, { passive: false });
  }

  _touchButtonLayout() {
    const compact = this.w < 720 || this.h < 500;
    const r = compact ? 24 : 27;
    const gap = compact ? 9 : 12;
    const right = this.w - (compact ? 28 : 34);
    const bottom = this.h - (compact ? 142 : 132);
    return {
      q: { x: right - (r * 2 + gap) * 1.5, y: bottom - r - gap, r },
      w: { x: right - (r * 2 + gap) * 0.5, y: bottom - r - gap, r },
      e: { x: right - (r * 2 + gap) * 1.5, y: bottom + r + gap, r },
      r: { x: right - (r * 2 + gap) * 0.5, y: bottom + r + gap, r },
      f: { x: right - (r * 2 + gap) * 2.6, y: bottom + r + gap, r: 24 },
      b: { x: right - (r * 2 + gap) * 2.6, y: bottom - r - gap, r: 24 },
    };
  }

  _touchButtonAt(x, y) {
    for (const [key, b] of Object.entries(this._touchButtonLayout())) {
      const dx = x - b.x;
      const dy = y - b.y;
      if (dx * dx + dy * dy <= b.r * b.r) return key;
    }
    return "";
  }

  _triggerTouchButton(key) {
    if (key === "q") this._castSpark();
    else if (key === "w") this._castNova();
    else if (key === "e") this._castBlink();
    else if (key === "r") this._castOrb();
    else if (key === "f" && this._interactCd <= 0 && !this.menu.open) {
      this._interactCd = 0.18;
      this._interact();
    } else if (key === "b" && this._dockToggleCd <= 0 && !this.menu.open) {
      this._dockToggleCd = 0.18;
      this._toggleDockingOrSailing();
    }
  }

  _clearTouchState() {
    if (!this.touch) return;
    this.touch.moveId = null;
    this.touch.aimId = null;
    this.touch.mx = 0;
    this.touch.my = 0;
    this.touch.buttons = {};
    this.mouse.down = false;
  }

  _updateMouseWorld() {
    const aimPoint = this.getAimWorldPoint?.(this.mouse, this);
    if (Number.isFinite(aimPoint?.x) && Number.isFinite(aimPoint?.y)) {
      this.mouse.worldX = aimPoint.x;
      this.mouse.worldY = aimPoint.y;
    } else {
      this.mouse.worldX = this.mouse.x - this.w * 0.5 + this.camera.x;
      this.mouse.worldY = this.mouse.y - this.h * 0.5 + this.camera.y;
    }

    const dx = this.mouse.worldX - this.hero.x;
    const dy = this.mouse.worldY - this.hero.y;
    const a = norm(dx, dy);
    this.hero.aimDir.x = a.x;
    this.hero.aimDir.y = a.y;
    if (!this.hero.faceDir) this.hero.faceDir = { x: a.x, y: a.y };
    if ((this.mouse.aimRecentT || 0) > 0.02) {
      this.hero.faceDir.x = a.x;
      this.hero.faceDir.y = a.y;
    }
  }

  _tickMessages(dt) {
    this.msgT = Math.max(0, this.msgT - dt);
    if (this.msgT <= 0) this.msg = "";

    this.zoneMsgT = Math.max(0, this.zoneMsgT - dt);
    if (this.zoneMsgT <= 0) this.zoneMsg = "";
  }

  _tickCooldowns(dt) {
    for (const k of Object.keys(this.cooldowns)) {
      this.cooldowns[k] = Math.max(0, this.cooldowns[k] - dt);
    }
  }

  _tickVisualEffects(dt) {
    this._killFlashT = Math.max(0, (this._killFlashT || 0) - dt * 2.4);

    for (const f of this.floatingTexts) {
      f.vy = Number.isFinite(f.vy) ? f.vy : -21;
      f.life = Number.isFinite(f.life) ? f.life : Math.max(0.01, (f.a || 1) / 0.9);
      f.y += f.vy * dt;
      f.a = clamp((f.a ?? 1) - dt * 0.9, 0, 1);
      f.life = Math.max(0, f.life - dt);
    }

    this.floatingTexts = this.floatingTexts.filter((f) => (f.a || 0) > 0 && (f.life || 0) > 0);
  }

  _handleMenus() {
    if (this.menu.open === "class-select") {
      this._handleClassSelectInput();
      if (this.menu.open) this._clearTouchState();
      return;
    }

    if (this.input.wasPressed("m") || this.input.wasPressed("M")) {
      this.menu.open = this.menu.open === "map" ? null : "map";
    }

    if (this.menu.open === "map") this._handleMapInput();
    if (this.menu.open === "quests") this._handleQuestInput();

    if (this.input.wasPressed("i") || this.input.wasPressed("I")) {
      this.menu.open = this.menu.open === "inventory" ? null : "inventory";
      this.invIndex = clamp(this.invIndex || 0, 0, Math.max(0, (this.hero.inventory?.length || 1) - 1));
    }

    if (this.input.wasPressed("k") || this.input.wasPressed("K")) {
      this.menu.open = this.menu.open === "skills" ? null : "skills";
    }

    if (this.input.wasPressed("j") || this.input.wasPressed("J")) {
      this.menu.open = this.menu.open === "quests" ? null : "quests";
    }

    if (this.input.wasPressed("o") || this.input.wasPressed("O")) {
      this.menu.open = this.menu.open === "options" ? null : "options";
    }

    if (this.input.wasPressed("g") || this.input.wasPressed("G")) {
      this.menu.open = this.menu.open === "dev" ? null : "dev";
    }

    if (this.input.wasPressed("F4")) this.toggleMode();

    if (this.input.wasPressed("F1")) {
      this._toggleSpikeMonitor();
    }

    if (this.input.wasPressed("F2")) {
      this._toggleProfiler();
    }

    if (this.input.wasPressed("Escape")) {
      if (this.menu.open) {
        this.menu.open = null;
        this._townServiceFocus = "";
      } else if (this.dungeon.active) {
        this._leaveDungeon();
      }
    }

    if (this.menu.open && this.menu.open !== "editor") this._clearTouchState();
    if (this.menu.open === "dev") this._handleDevToolsInput();
    if (this.menu.open === "editor") this._handleEditorInput();
  }

  enterBuildMode() {
    if (!this._editorBaseCaptured) {
      this.world?.captureEditorSessionBase?.();
      this._editorBaseCaptured = true;
    }
    if (this.world) this.world.suppressEditorRiverCarve = true;
    this.mode = "build";
    this.menu.open = "editor";
    this._townServiceFocus = "";
    this.editor.playMode = false;
    this.onEditorWorldChanged?.("terrain");
    this._msg("Build mode: world forge open", 1.0);
  }

  enterPlayMode() {
    if (this.world) this.world.suppressEditorRiverCarve = false;
    this.mode = "play";
    if (this.menu.open === "editor") this.menu.open = null;
    this.editor.dragging = false;
    this.editor.stroke = [];
    this._flushEditorTerrainBatch();
    this.onEditorWorldChanged?.("terrain");
    this._msg("Play mode", 0.9);
  }

  toggleMode() {
    if (this.mode === "build") this.enterPlayMode();
    else this.enterBuildMode();
  }

  _notifyEditorWorldChanged() {
    this.onEditorWorldChanged?.("terrain");
    this._requestEditorAutosave();
  }

  _notifyEditorDetailChanged() {
    this.onEditorWorldChanged?.("detail");
    this._requestEditorAutosave();
  }

  _requestEditorAutosave(delay = 420) {
    if (this._editorAutosaveTimer) clearTimeout(this._editorAutosaveTimer);
    this.editor.lastStatus = "Unsaved changes";
    this._editorAutosaveTimer = setTimeout(() => {
      this._editorAutosaveTimer = null;
      const ok = this.world?.saveEditorData?.();
      if (ok) this.editor.lastStatus = "Autosaved";
    }, delay);
  }

  _queueEditorTerrainStamp(stamp) {
    if (!stamp) return;
    this.editor.pendingTerrainStamps.push(stamp);
  }

  _flushEditorTerrainBatch(force = false) {
    const batch = this.editor.pendingTerrainStamps || [];
    if (!batch.length) return false;
    if (!force && (this.editor.terrainFlushT || 0) > 0) return false;
    const ok = this.world?.addEditorTerrainStampBatch?.(batch);
    this.editor.pendingTerrainStamps = [];
    this.editor.terrainFlushT = 0.06;
    if (ok) this._notifyEditorWorldChanged();
    return !!ok;
  }

  _editorToolName(tool = this.editor?.tool) {
    const names = {
      road: "Road",
      river: "River Section",
      bridge: "Bridge",
      dock: "Dock",
      raise: "Raise Land",
      lower: "Lower Land",
      water: "Water Carve",
      erase: "Erase",
      flatten: "Flatten",
      smooth: "Smooth",
      tree: "Tree",
      rock: "Rock",
      clutter: "Clutter",
      camp: "Camp",
      town: "Town",
      dungeon: "Dungeon",
      shrine: "Shrine",
      cache: "Cache",
      secret: "Secret",
      dragon: "Dragon Lair",
      waystone: "Waystone",
      herb: "Herb",
    };
    return names[tool] || "Editor";
  }

  _editorToolHotkey(tool) {
    const map = {
      road: "1",
      river: "2",
      bridge: "3",
      dock: "4",
      raise: "5",
      lower: "6",
      water: "7",
      erase: "8",
      flatten: "T",
      smooth: "Y",
      tree: "Q",
      rock: "W",
      clutter: "E",
      camp: "A",
      town: "S",
      dungeon: "D",
      shrine: "Z",
      cache: "X",
      secret: "C",
      dragon: "V",
      waystone: "B",
      herb: "H",
    };
    return map[tool] || "";
  }

  _editorToolShortLabel(tool = this.editor?.tool) {
    const map = {
      road: "Road",
      river: "River Seg",
      bridge: "Bridge",
      dock: "Dock",
      raise: "Raise",
      lower: "Lower",
      water: "Water",
      erase: "Erase",
      flatten: "Flatten",
      smooth: "Smooth",
      tree: "Tree",
      rock: "Rock",
      clutter: "Clutter",
      camp: "Camp",
      town: "Town",
      dungeon: "Crypt",
      shrine: "Shrn",
      cache: "Cache",
      secret: "Hidden",
      dragon: "Lair",
      waystone: "Stone",
      herb: "Herb",
    };
    return map[tool] || this._editorToolName(tool);
  }

  _simplifyEditorStroke(points, minStep = 48) {
    if (!Array.isArray(points) || points.length < 3) return points || [];
    const simplified = [points[0]];
    let last = points[0];
    for (let i = 1; i < points.length - 1; i++) {
      const p = points[i];
      if (!p) continue;
      if (Math.hypot(p.x - last.x, p.y - last.y) < minStep) continue;
      simplified.push(p);
      last = p;
    }
    const end = points[points.length - 1];
    if (simplified[simplified.length - 1] !== end) simplified.push(end);
    return simplified;
  }

  _setEditorTool(tool) {
    if (!EDITOR_TOOL_IDS.includes(tool)) return;
    if (this.worldVariant === "river-build" && !["river", "erase", "flatten", "smooth", "lower", "water"].includes(tool)) return;
    this.editor.tool = tool;
    this.editor.dragging = false;
    this.editor.stroke = [];
    this._msg(`Editor: ${this._editorToolName(tool)}`, 0.8);
  }

  _isMouseOverEditorHud() {
    const mx = this.mouse.x;
    const my = this.mouse.y;
    if (!Number.isFinite(mx) || !Number.isFinite(my)) return false;
    const { x, y, w, h } = this.getEditorPanelLayout();
    return mx >= x && mx <= x + w && my >= y && my <= y + h;
  }

  _handleEditorInput() {
    const toolKeys = ["1", "2", "3", "4", "5", "6", "7", "8", "t", "y", "q", "w", "e", "a", "s", "d", "z", "x", "c", "v", "b", "h"];
    for (let i = 0; i < toolKeys.length; i++) {
      if (this.input.wasPressed(toolKeys[i])) this._setEditorTool(EDITOR_TOOL_IDS[i]);
      if (this.input.wasPressed(toolKeys[i].toUpperCase?.() || toolKeys[i])) this._setEditorTool(EDITOR_TOOL_IDS[i]);
    }
    const usedPanelButton = this._handleEditorPanelButtons();
    const overHud = this._isMouseOverEditorHud();
    if (this.input.wasPressed("[")) {
      this.editor.brushSize = Math.max(36, this.editor.brushSize - 20);
      this.editor.strokeWidth = Math.max(24, this.editor.strokeWidth - 10);
      this.editor.propScale = Math.max(0.4, this.editor.propScale - 0.1);
    }
    if (this.input.wasPressed("]")) {
      this.editor.brushSize = Math.min(520, this.editor.brushSize + 20);
      this.editor.strokeWidth = Math.min(220, this.editor.strokeWidth + 10);
      this.editor.propScale = Math.min(3.2, this.editor.propScale + 0.1);
    }
    if (this.input.wasPressed("-") || this.input.wasPressed("_")) {
      this.editor.terrainPower = Math.max(4, this.editor.terrainPower - 2);
    }
    if (this.input.wasPressed("=") || this.input.wasPressed("+")) {
      this.editor.terrainPower = Math.min(80, this.editor.terrainPower + 2);
    }
    if (this.input.wasPressed("u") || this.input.wasPressed("U")) {
      const undone = this.world?.undoEditorAction?.();
      if (undone) this._notifyEditorWorldChanged();
      this._msg(undone ? "Editor: undid last change" : "Editor: nothing to undo", 0.9);
    }
    if (this.input.wasPressed("p") || this.input.wasPressed("P")) {
      this.editor.showGameHud = !this.editor.showGameHud;
      this._msg(this.editor.showGameHud ? "Editor: gameplay HUD ON" : "Editor: gameplay HUD OFF", 0.9);
    }
    if (this.input.wasPressed("9")) {
      this._saveEditorWorld(false);
    }
    if (this.input.wasPressed("0")) {
      this._importEditorFromClipboard();
    }
    if (this.input.wasPressed("Backspace")) {
      const cleared = this.world?.eraseEditorAt?.(this.mouse.worldX, this.mouse.worldY, this.editor.brushSize);
      if (cleared) this._notifyEditorWorldChanged();
      this._msg(cleared ? "Editor: erased nearby authored changes" : "Editor: nothing nearby to erase", 0.8);
    }
    if (overHud) {
      if (!this.mouse.down) {
        if (this.editor.dragging) {
          if (this.editor.tool === "bridge") this._commitEditorBridgeStroke();
          else if (this.editor.tool === "road" || this.editor.tool === "river") this._commitEditorStroke(this.editor.tool);
        }
        this._flushEditorTerrainBatch(true);
        this.editor.lastPaintX = NaN;
        this.editor.lastPaintY = NaN;
      }
      return;
    }
    if (!usedPanelButton) this._handleEditorMouseTool();
  }

  _handleEditorPanelButtons() {
    if (!this.mouse.clicked) return false;
    const mx = this.mouse.x;
    const my = this.mouse.y;
    for (const button of this.getEditorButtonRects()) {
      if (mx < button.x || mx > button.x + button.w || my < button.y || my > button.y + button.h) continue;
      if (button.action?.startsWith?.("tool:")) {
        this._setEditorTool(button.action.slice(5));
      } else if (button.action?.startsWith?.("river-piece:")) {
        this.editor.riverPiece = "straight";
        this.editor.tool = "river";
        this._msg("Editor: straight river section", 0.8);
      } else if (button.action === "river-rot-left") {
        this.editor.riverAngle -= Math.PI / 72;
        this._msg(`Editor: river rotation ${Math.round((((this.editor.riverAngle || 0) * 180) / Math.PI) % 360)}deg`, 0.8);
      } else if (button.action === "river-rot-right") {
        this.editor.riverAngle += Math.PI / 72;
        this._msg(`Editor: river rotation ${Math.round((((this.editor.riverAngle || 0) * 180) / Math.PI) % 360)}deg`, 0.8);
      } else if (button.action === "undo") {
        this.editor.lastStatus = "Undoing...";
        const undone = this.world?.undoEditorAction?.();
        if (undone) this._notifyEditorWorldChanged();
        this._msg(undone ? "Editor: undid last change" : "Editor: nothing to undo", 0.9);
      } else if (button.action === "revert-base") {
        this.editor.lastStatus = "Reverting base map...";
        const ok = this.world?.revertEditorToSessionBase?.();
        if (ok) this.onEditorWorldChanged?.("terrain");
        this._msg(ok ? "Editor: reverted to base map" : "Editor: no base map captured yet", 1.0);
      } else if (button.action === "repair-paths") {
        this.editor.lastStatus = "Repairing paths...";
        const ok = this.world?.rebuildEditorTravelFromBase?.();
        if (ok) this.onEditorWorldChanged?.("terrain");
        this._msg(ok ? "Editor: rebuilt roads, rivers, bridges, and docks from the base world" : "Editor: path rebuild failed", 1.2);
      } else if (button.action === "bake-rivers") {
        this.editor.lastStatus = "Baking rivers...";
        const ok = this.world?.bakeEditorRiversToTerrain?.();
        if (ok) this.onEditorWorldChanged?.("terrain");
        this._msg(ok ? "Editor: baked riverbeds into terrain" : "Editor: no rivers to bake", 1.1);
      } else if (button.action === "save") this._saveEditorWorld(false);
      else if (button.action === "save-play") this._saveEditorWorld(true);
      else if (button.action === "play") this.enterPlayMode();
      else if (button.action === "build") this.enterBuildMode();
      else if (button.action === "hud") {
        this.editor.showGameHud = !this.editor.showGameHud;
        this._msg(this.editor.showGameHud ? "Editor: gameplay HUD ON" : "Editor: gameplay HUD OFF", 0.9);
      } else if (button.action === "brush-down") {
        this.editor.brushSize = Math.max(36, this.editor.brushSize - 20);
      } else if (button.action === "brush-up") {
        this.editor.brushSize = Math.min(520, this.editor.brushSize + 20);
      } else if (button.action === "width-down") {
        this.editor.strokeWidth = Math.max(24, this.editor.strokeWidth - 10);
      } else if (button.action === "width-up") {
        this.editor.strokeWidth = Math.min(220, this.editor.strokeWidth + 10);
      } else if (button.action === "power-down") {
        this.editor.terrainPower = Math.max(4, this.editor.terrainPower - 2);
      } else if (button.action === "power-up") {
        this.editor.terrainPower = Math.min(80, this.editor.terrainPower + 2);
      } else if (button.action === "scale-down") {
        this.editor.propScale = Math.max(0.4, this.editor.propScale - 0.1);
      } else if (button.action === "scale-up") {
        this.editor.propScale = Math.min(3.2, this.editor.propScale + 0.1);
      } else if (button.action === "export") {
        this.editor.exportText = this.world?.exportEditorData?.() || "";
        this._copyTextToClipboard(this.editor.exportText, "Editor: export copied", "Editor: export ready in panel");
      } else if (button.action === "import") {
        this.editor.lastStatus = "Importing...";
        this._importEditorFromClipboard();
      } else if (button.action === "clear") {
        this.editor.lastStatus = "Clearing...";
        this.world?.clearEditorData?.();
        this.onEditorWorldChanged?.("terrain");
        this._msg("Editor: cleared authored changes", 1.0);
      }
      return true;
    }
    return false;
  }

  _saveEditorWorld(andPlay = false) {
    const ok = this.world?.saveEditorData?.();
    this.editor.lastStatus = ok ? "Saved authored world data locally" : "Save failed";
    this._msg(ok ? (andPlay ? "Editor: saved world, back to play" : "Editor: world saved") : "Editor: save failed", 1.1);
    if (andPlay && ok) {
      this.enterPlayMode();
      this.editor.playMode = true;
    }
  }

  _handleEditorMouseTool() {
    const tool = this.editor.tool;
    const x = this.mouse.worldX;
    const y = this.mouse.worldY;
    if (!Number.isFinite(x) || !Number.isFinite(y)) return;

    if (tool === "river" && this.mouse.clicked) {
      try {
        const ok = this.worldVariant === "river-build"
          ? this.world?.addEditorRiverCutSectionAt?.(
              x,
              y,
              this.editor.riverAngle || 0,
              Math.max(56, this.editor.strokeWidth * 0.95),
            )
          : this.world?.addEditorRiverPieceAt?.(
              x,
              y,
              "straight",
              this.editor.riverAngle || 0,
              Math.max(56, this.editor.strokeWidth * 0.95),
            );
        if (ok) {
          this.editor.lastStatus = this.worldVariant === "river-build" ? "Placed river trench cut" : "Placed straight river section";
          this._notifyEditorWorldChanged();
          this._msg(this.worldVariant === "river-build" ? "Editor: river trench placed" : "Editor: straight river placed", 0.8);
        }
      } catch (err) {
        console.error("Editor river placement failed", err);
        this.editor.lastStatus = "River placement failed";
        this._msg("Editor: river placement failed", 1.2);
      }
      return;
    }

    if (tool === "road" || tool === "bridge") {
      if (this.mouse.clicked && !this.editor.dragging) {
        this.editor.dragging = true;
        this.editor.stroke = [{ x, y, sx: this.mouse.x, sy: this.mouse.y }];
      } else if (this.mouse.down && this.editor.dragging) {
        const last = this.editor.stroke[this.editor.stroke.length - 1];
        const step =
          tool === "road"
            ? Math.max(16, this.editor.brushSize * 0.1)
            : Math.max(24, this.editor.brushSize * 0.18);
        if (!last || Math.hypot(last.x - x, last.y - y) >= step) {
          this.editor.stroke.push({ x, y, sx: this.mouse.x, sy: this.mouse.y });
        }
      } else if (!this.mouse.down && this.editor.dragging) {
        if (tool === "bridge") this._commitEditorBridgeStroke();
        else this._commitEditorStroke(tool);
      }
      return;
    }

    if ((tool === "raise" || tool === "lower" || tool === "water" || tool === "erase" || tool === "flatten" || tool === "smooth") && this.mouse.down) {
      const dist = Math.hypot((this.editor.lastPaintX || 0) - x, (this.editor.lastPaintY || 0) - y);
      if (!Number.isFinite(this.editor.lastPaintX) || dist >= Math.max(28, this.editor.brushSize * 0.18)) {
        if (tool === "erase") {
          this.world?.eraseEditorAt?.(x, y, this.editor.brushSize);
          this._notifyEditorWorldChanged();
        } else {
          this._queueEditorTerrainStamp({
            mode: tool,
            x,
            y,
            radius: this.editor.brushSize,
            power: this.editor.terrainPower,
          });
        }
        this.editor.lastPaintX = x;
        this.editor.lastPaintY = y;
      }
      this._flushEditorTerrainBatch(false);
      return;
    }

    if (this.mouse.clicked && (tool === "tree" || tool === "rock" || tool === "clutter")) {
      this.world?.addEditorPropAt?.(x, y, tool, this.editor.propScale);
      this._notifyEditorDetailChanged();
      this._msg(`Editor: ${this._editorToolName(tool).toLowerCase()} placed`, 0.8);
      return;
    }

    if (this.mouse.clicked && ["camp", "town", "dungeon", "shrine", "cache", "secret", "dragon", "waystone", "herb"].includes(tool)) {
      this.world?.addEditorPoiAt?.(x, y, tool);
      this._notifyEditorDetailChanged();
      this._msg(`Editor: ${this._editorToolName(tool).toLowerCase()} placed`, 0.8);
      return;
    }

    if (!this.mouse.down) {
      this._flushEditorTerrainBatch(true);
      this.editor.lastPaintX = NaN;
      this.editor.lastPaintY = NaN;
    }

    if (this.mouse.clicked && (tool === "bridge" || tool === "dock")) {
      if (tool === "dock") {
        this.world?.addEditorDockAt?.(x, y);
        this._notifyEditorDetailChanged();
        this._msg("Editor: dock placed", 0.8);
      }
    }
  }

  _commitEditorStroke(tool) {
    const points = this.editor.stroke || [];
    this.editor.dragging = false;
    this.editor.stroke = [];
    if (points.length < 2) return;
    if (tool === "road") {
      const sampled = this._simplifyEditorStroke(points, Math.max(32, this.editor.strokeWidth * 0.45));
      this.editor.lastStatus = "Applying road...";
      this.world?.addEditorRoadStroke?.(sampled, this.editor.strokeWidth);
      this._notifyEditorWorldChanged();
      this._msg(`Editor: road stroke saved (${sampled.length} pts)`, 0.9);
    } else if (tool === "river") {
      const start = points[0];
      const end = points[points.length - 1];
      const dx = (end?.x || 0) - (start?.x || 0);
      const dy = (end?.y || 0) - (start?.y || 0);
      const len = Math.hypot(dx, dy);
      if (len < 40) return;
      const steps = Math.max(8, Math.ceil(len / 36));
      const sampled = [];
      for (let i = 0; i <= steps; i++) {
        const t = i / steps;
        sampled.push({
          x: start.x + dx * t,
          y: start.y + dy * t,
        });
      }
      this.editor.lastStatus = "Applying river...";
      this.world?.addEditorRiverStroke?.(sampled, Math.max(72, this.editor.strokeWidth * 1.2));
      this._notifyEditorWorldChanged();
      this._msg(`Editor: river section saved (${Math.round(len)})`, 0.9);
    }
  }

  _commitEditorBridgeStroke() {
    const points = this.editor.stroke || [];
    this.editor.dragging = false;
    this.editor.stroke = [];
    if (points.length < 2) return;
    const start = points[0];
    const end = points[points.length - 1];
    const dx = end.x - start.x;
    const dy = end.y - start.y;
    const length = Math.hypot(dx, dy);
    if (length < 40) return;
    this.world?.addEditorBridgeAt?.((start.x + end.x) * 0.5, (start.y + end.y) * 0.5, {
      angle: Math.atan2(dy, dx),
      length: clamp(length, 60, 560),
      width: clamp(this.editor.strokeWidth * 0.52, 24, 140),
    });
    this._notifyEditorDetailChanged();
    this._msg(`Editor: bridge placed (${Math.round(length)})`, 0.9);
  }

  _copyTextToClipboard(text, successMsg, fallbackMsg) {
    if (!text) {
      this._msg("Editor: nothing to copy", 0.8);
      return;
    }
    const clip = globalThis?.navigator?.clipboard;
    if (clip?.writeText) {
      clip.writeText(text)
        .then(() => this._msg(successMsg, 0.9))
        .catch(() => this._msg(fallbackMsg, 1.0));
    } else {
      this._msg(fallbackMsg, 1.0);
    }
  }

  _importEditorFromClipboard() {
    const clip = globalThis?.navigator?.clipboard;
    if (!clip?.readText) {
      this._msg("Editor: clipboard import unavailable here", 1.0);
      return;
    }
    clip.readText()
      .then((text) => {
        const ok = this.world?.importEditorData?.(text);
        this.editor.importedAt = ok ? Date.now() : 0;
        this._msg(ok ? "Editor: imported world forge data" : "Editor: import failed", 1.1);
      })
      .catch(() => this._msg("Editor: clipboard import failed", 1.0));
  }

  _handleClassSelectInput() {
    const choices = ["knight", "ranger", "arcanist", "raider"];
    for (let i = 0; i < choices.length; i++) {
      if (this.input.wasPressed(String(i + 1))) {
        this._chooseClass(choices[i]);
        return;
      }
    }
    if (!this.mouse.clicked) return;
    const layout = this.getClassPanelLayout();
    const mx = this.mouse.x;
    const my = this.mouse.y;
    for (let i = 0; i < choices.length; i++) {
      const card = layout.cards[i];
      if (mx >= card.x && mx <= card.x + card.w && my >= card.y && my <= card.y + card.h) {
        this._chooseClass(choices[i]);
        return;
      }
    }
  }

  _handleQuestInput() {
    this._handleQuestMouse();
    for (const [key, track] of QUEST_TRACKS) {
      if (!this.input.wasPressed(key)) continue;
      this._setTrackedObjective(track);
    }
  }

  _handleQuestMouse() {
    if (!this.mouse.clicked) return;
    const { w, h, rows } = this.getQuestPanelLayout();
    const x = ((this.w - w) / 2) | 0;
    const y = ((this.h - h) / 2) | 0;
    const mx = this.mouse.x;
    const my = this.mouse.y;

    for (const row of rows) {
      const rowY = y + row.y;
      if (my < rowY || my > rowY + 18 || mx < x + 170 || mx > x + w - 18) continue;
      const slotW = (w - 194) / row.tracks.length;
      const idx = clamp(Math.floor((mx - (x + 176)) / slotW), 0, row.tracks.length - 1);
      this._setTrackedObjective(row.tracks[idx]);
      return;
    }
  }

  getQuestPanelLayout() {
    return {
      w: Math.min(Math.max(this.w - 120, 430), 560),
      h: QUEST_PANEL_HEIGHT,
      rows: [
        { y: 62, tracks: QUEST_TRACK_ROWS[0] },
        { y: 78, tracks: QUEST_TRACK_ROWS[1] },
      ],
    };
  }

  _setTrackedObjective(track, message) {
    const map = {
      story: "Tracking story",
      bounty: "Tracking bounty",
      town: "Tracking nearest town",
      dungeon: "Tracking dungeon",
      dragon: "Tracking dragon",
      treasure: "Tracking treasure",
      secret: "Tracking secrets",
    };
    this.trackedObjective = track;
    if (message !== null) this._msg(message || map[track] || `Tracking ${this._titleCase(track)}`, 0.9);
  }

  getQuestTrackHintLines() {
    const first = QUEST_TRACKS.slice(0, 4).map(([key, track]) => `${key} ${this._titleCase(track)}`);
    const second = QUEST_TRACKS.slice(4).map(([key, track]) => `${key} ${track === "secret" ? "Secrets" : this._titleCase(track)}`);
    return [
      first.join("  "),
      `${second.join("  ")}  (click to track)`,
    ];
  }

  getJournalStats() {
    return {
      towns: this.progress.visitedTowns?.size || 0,
      townsTotal: this.world.towns?.length || 0,
      waystones: this.progress.discoveredWaystones?.size || 0,
      waystonesTotal: this.world.waystones?.length || 0,
      bridges: this.progress.crossedBridges?.size || 0,
      bridgesTotal: this.world.bridges?.length || 0,
      dungeons: this.progress.dungeonBest || 0,
      dragons: this.progress.defeatedDragons?.size || 0,
      dragonsTotal: this.world.dragonLairs?.length || 0,
      secrets: this.progress.discoveredSecrets?.size || 0,
      secretsTotal: this.world.secrets?.length || 0,
    };
  }

  _handleMapInput() {
    const zoomIn = this.input.wasPressed("+") || this.input.wasPressed("=") || this.input.wasPressed("Add");
    const zoomOut = this.input.wasPressed("-") || this.input.wasPressed("_") || this.input.wasPressed("Subtract");
    const reset = this.input.wasPressed("0");

    if (zoomIn) {
      this._setMapZoom("in");
    } else if (zoomOut) {
      this._setMapZoom("out");
    } else if (reset) {
      this._setMapZoom("reset");
    }
  }

  _setMapZoom(mode) {
    const current = clamp(this.menu.mapZoom || 1, 1, 8);
    const next =
      mode === "in" ? Math.min(8, current * 2) :
      mode === "out" ? Math.max(1, current / 2) :
      1;
    if (next === current && mode !== "reset") return;
    this.menu.mapZoom = next;
    this._msg(mode === "reset" ? "Map zoom reset" : `Map zoom ${next}x`, 0.7);
  }

  _handleDevToolsInput() {
    this._handleDevToolsMouse();
    const keys = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"];
    for (let i = 0; i < DEV_TOOL_ACTION_COUNT; i++) {
      if (keys[i] && this.input.wasPressed(keys[i])) this._runDevToolAction(i + 1);
    }
    if (this.input.wasPressed("h") || this.input.wasPressed("H")) this._runDevToolAction(11);
  }

  _handleDevToolsMouse() {
    if (!this.mouse.clicked) return;
    const { w, x, y, rowStart, rowStep, rowInset } = this.getDevPanelLayout();
    const mx = this.mouse.x;
    const my = this.mouse.y;
    const row = Math.floor((my - (y + rowStart)) / rowStep);
    if (mx < x + rowInset || mx > x + w - rowInset || row < 0 || row >= DEV_TOOL_ACTION_COUNT) return;
    this._runDevToolAction(row + 1);
  }

  _runDevToolAction(action) {
    if (action === 1) {
      this.hero.hp = this.hero.maxHp || 100;
      this.hero.mana = this.hero.maxMana || 60;
      this._msg("Dev: healed", 0.9);
    }
    if (action === 2) {
      this.hero.gold += 250;
      this._msg("Dev: +250 gold", 0.9);
    }
    if (action === 3) {
      this.hero.giveXP?.(this.hero.nextXp || 25);
      this._msg("Dev: level boost", 0.9);
    }
    if (action === 4) {
      this.world.revealAll?.();
      this._msg("Dev: map revealed", 0.9);
    }
    if (action === 5) {
      const dungeon = this._nearest(this.world.dungeons);
      if (dungeon) {
        this.hero.x = dungeon.x;
        this.hero.y = dungeon.y + 72;
        this.camera.x = this.hero.x;
        this.camera.y = this.hero.y;
        this._msg("Dev: nearest dungeon", 0.9);
      }
    }
    if (action === 6) {
      const dock = this._nearest(this.world.docks);
      if (dock) {
        this.hero.x = dock.x - 56;
        this.hero.y = dock.y + 18;
        this.camera.x = this.hero.x;
        this.camera.y = this.hero.y;
        this._msg("Dev: nearest port", 0.9);
      }
    }
    if (action === 7) {
      this.dev.godMode = !this.dev.godMode;
      if (this.dev.godMode) {
        this.hero.hp = this.hero.maxHp || 100;
        this.hero.mana = this.hero.maxMana || 60;
      }
      this._msg(this.dev.godMode ? "Dev: god mode ON" : "Dev: god mode OFF", 1.1);
    }
    if (action === 8) {
      this._devEquipBestGear();
    }
    if (action === 9) {
      if (!this._isDevResetConfirmLive()) {
        this._devResetConfirmAt = Date.now();
        this._msg("Dev: press 9 again to reset", 1.4);
        return;
      }
      this._devResetConfirmAt = 0;
      this._devResetGame();
    }
    if (action === 10) {
      this._toggleProfiler();
    }
    if (action === 11) {
      this._toggleSpikeMonitor();
    }
  }

  _toggleProfiler() {
    this.dev.showProfiler = !this.dev.showProfiler;
    this._msg(this.dev.showProfiler ? "Dev: profiler ON" : "Dev: profiler OFF", 1.0);
  }

  _toggleSpikeMonitor() {
    this.dev.showSpikeMonitor = !this.dev.showSpikeMonitor;
    this._msg(this.dev.showSpikeMonitor ? "Dev: hitch monitor ON" : "Dev: hitch monitor OFF", 1.0);
  }

  getDevToolLines() {
    const perf = this.getPerfSnapshot?.() || {};
    return [
      "1 heal HP and mana",
      "2 add 250 gold",
      "3 grant one level worth of XP",
      "4 reveal entire world map",
      "5 teleport near closest dungeon",
      "6 teleport near closest port",
      `7 god mode ${this.dev?.godMode ? "ON" : "OFF"}`,
      "8 equip mythic best gear",
      this._isDevResetConfirmLive() ? "9 reset to a new game (press again now)" : "9 reset to a new game (confirm)",
      `0 profiler ${this.dev?.showProfiler ? "ON" : "OFF"} (F2 quick toggle)`,
      `H hitch monitor ${this.dev?.showSpikeMonitor ? "ON" : "OFF"} (F1 quick toggle)`,
      `FPS ${Math.round(perf.fps || 0)} | Frame ${(perf.frameMs || 0).toFixed(1)}ms | Jank ${(perf.frameJank || 0).toFixed(1)}ms`,
      `Explored cells: ${this.world?.exportDiscovery?.()?.length || 0}`,
      `World span: ${((this.world?.mapHalfSize || 0) * 2).toLocaleString()} units`,
    ];
  }

  getDevActionCount() {
    return DEV_TOOL_ACTION_COUNT;
  }

  getDevPanelLayout() {
    const w = Math.min(Math.max(this.w - 120, 430), 560);
    const lines = this.getDevToolLines?.() || [];
    const h = Math.min(this.h - 36, Math.max(362, 102 + lines.length * 22));
    const x = ((this.w - w) / 2) | 0;
    const y = ((this.h - h) / 2) | 0;
    return {
      w,
      h,
      x,
      y,
      rowStart: 70,
      rowStep: 22,
      rowInset: 20,
    };
  }

  getSkillPanelData() {
    const defs = this.skillDefs || {};
    const prog = this.skillProg || {};
    const cooldowns = this.cooldowns || {};
    const heroMana = this.hero?.mana || 0;
    const heroMaxMana = this.hero?.maxMana || 0;

    return {
      manaText: `Mana ${Math.round(heroMana)}/${Math.round(heroMaxMana)}`,
      legendText: "Green ready   amber cooling down   red low mana",
      oathText: `Oath: ${this._className?.() || "Knight"}`,
      rows: SKILL_PANEL_ORDER.map((key) => {
        const def = defs[key] || {};
        const s = prog[key] || { xp: 0, level: 1 };
        const need = 10 + ((s.level || 1) - 1) * 8;
        const xp = s.xp || 0;
        const remainingCd = Math.max(0, cooldowns[key] || 0);
        const baseCd = Math.max(0.01, +def.cd || 1);
        const affordable = heroMana >= (def.mana || 0);
        const statusText = remainingCd > 0.01 ? `${remainingCd.toFixed(1)}s left` : affordable ? "Ready" : "Low mana";
        const statusColor = remainingCd > 0.01 ? "#ffd98a" : affordable ? "#94e48d" : "#ff9c9c";
        return {
          key,
          name: def.name || "Skill",
          color: def.color || "#dbe7ff",
          manaCost: def.mana || 0,
          manaText: `Mana ${def.mana || 0}`,
          cooldownText: `Cooldown ${(+def.cd || 0).toFixed(1)}s`,
          cooldownValue: remainingCd,
          cooldownFrac: clamp(remainingCd / baseCd, 0, 1),
          levelText: `Level ${s.level || 1}`,
          statusText,
          statusColor,
          affordable,
          xpText: `XP ${xp} / ${need}`,
          infoText: this._skillUpgradeSummary?.(key, s.level || 1) || "Balanced scaling",
          xpFrac: clamp(xp / Math.max(1, need), 0, 1),
        };
      }),
    };
  }

  getSkillPanelLayout() {
    const w = Math.min(Math.max(this.w - 110, 520), 620);
    const h = Math.min(Math.max(this.h - 110, 388), 432);
    const x = ((this.w - w) / 2) | 0;
    const y = ((this.h - h) / 2) | 0;
    return {
      w,
      h,
      x,
      y,
      rowStart: 98,
      rowStep: 82,
      rowHeight: 66,
      rowInset: 18,
    };
  }

  getClassPanelLayout() {
    const w = Math.min(Math.max(this.w - 120, 640), 820);
    const h = Math.min(Math.max(this.h - 120, 360), 450);
    const x = ((this.w - w) / 2) | 0;
    const y = ((this.h - h) / 2) | 0;
    const gap = 16;
    const cardW = Math.floor((w - 36 - gap) / 2);
    const cardH = 124;
    return {
      w, h, x, y,
      cards: [
        { x: x + 18, y: y + 94, w: cardW, h: cardH },
        { x: x + 18 + cardW + gap, y: y + 94, w: cardW, h: cardH },
        { x: x + 18, y: y + 94 + cardH + gap, w: cardW, h: cardH },
        { x: x + 18 + cardW + gap, y: y + 94 + cardH + gap, w: cardW, h: cardH },
      ],
    };
  }

  getClassPanelData() {
    return [
      { id: "knight", key: "1", name: "Knight", color: "#8fd8ff", body: "Durable frontline fighter. Longer blink guard and steadier survivability.", perks: ["Higher armor feel", "Safer blink finish", "Balanced damage"] },
      { id: "ranger", key: "2", name: "Ranger", color: "#9fe48d", body: "Fast roaming skirmisher. Better spark speed and longer movement lines.", perks: ["Faster projectiles", "Longer blink distance", "Best travel tempo"] },
      { id: "arcanist", key: "3", name: "Arcanist", color: "#d8a8ff", body: "High-output caster. Bigger nova and stronger spell damage.", perks: ["Stronger spark/orb", "Largest nova radius", "Mana-heavy"] },
      { id: "raider", key: "4", name: "Raider", color: "#ffd38a", body: "Aggressive striker. Fast blink, fast orb, and sharp melee pacing.", perks: ["Longest blink", "Faster orb", "High pressure"] },
    ];
  }

  _chooseClass(classId) {
    this.hero.classId = classId || "knight";
    this.menu.open = null;
    this._msg(`${this._className(classId)} chosen`, 1.2);
  }

  getSpellBarLayout() {
    const box = 46;
    const gap = 10;
    const total = box * SKILL_PANEL_ORDER.length + gap * (SKILL_PANEL_ORDER.length - 1);
    return {
      box,
      gap,
      total,
      x: ((this.w - total) / 2) | 0,
      y: this.h - 62,
      inset: 5,
    };
  }

  _isDevResetConfirmLive() {
    return !!(this._devResetConfirmAt && Date.now() - this._devResetConfirmAt <= DEV_RESET_CONFIRM_MS);
  }

  _devEquipBestGear() {
    const slots = EQUIPMENT_SLOTS;
    const level = Math.max(18, (this.hero.level || 1) + 10);
    for (let i = 0; i < slots.length; i++) {
      const item = makeGear(slots[i], level, "epic", hash2(this.seed, i + 8800, level));
      item.name = `Mythic ${item.name}`;
      this.hero.equip[slots[i]] = item;
    }

    const stats = this.hero.getStats?.() || {};
    this.hero.maxHp = stats.maxHp || this.hero.maxHp || 100;
    this.hero.maxMana = stats.maxMana || this.hero.maxMana || 60;
    this.hero.hp = this.hero.maxHp;
    this.hero.mana = this.hero.maxMana;
    this._msg("Dev: mythic gear equipped", 1.2);
  }

  _devResetGame() {
    this.save.clear?.();
    this.seed = (Date.now() & 0x7fffffff) | 0;
    this.world = new World(this.seed, { viewW: this.w, viewH: this.h, variant: this.worldVariant });
    const start = this.world.getStarterPoint?.() || this.world.spawn || { x: 0, y: 0 };
    this.hero = new Hero(start.x, start.y);
    this.enemies = [];
    this.projectiles = [];
    this.loot = [];
    this.hitSparks = [];
    this.floatingTexts = [];
    this.cooldowns = { q: 0, w: 0, e: 0, r: 0 };
    this.skillProg = {
      q: { xp: 0, level: 1 },
      w: { xp: 0, level: 1 },
      e: { xp: 0, level: 1 },
      r: { xp: 0, level: 1 },
    };
    this.progress = {
      discoveredWaystones: new Set(),
      discoveredDocks: new Set(),
      dungeonBest: 0,
      visitedCamps: new Set(),
      eliteKills: 0,
      bountyCompletions: 0,
      campRenown: {},
      campRestBonusClaimed: {},
      claimedShrines: new Set(),
      openedCaches: new Set(),
      discoveredSecrets: new Set(),
      defeatedDragons: new Set(),
      relicShards: 0,
      storyMilestones: {},
      visitedTowns: new Set(),
      crossedBridges: new Set(),
      herbs: 0,
      pickedHerbs: new Set(),
      materials: { scrap: 0, ore: 0, hide: 0, essence: 0 },
    };
    this.hero.classId = "knight";
    this.dungeon = { active: false, kind: "depths", floor: 0, origin: null, lairId: null, room: null, roomIndex: 0, totalRooms: 0, roomRewarded: false, layout: null, currentRoomId: null, keys: 0, roomClearT: 0, hoardOpened: false };
    this.menu.open = "class-select";
    this.menu.mapZoom = 1;
    this.trackedObjective = "story";
    this._cachedNearbyCamp = null;
    this._cachedNearbyTown = null;
    this._cachedNearbyWaystone = null;
    this._cachedNearbyShrine = null;
    this._cachedNearbyCache = null;
    this._cachedNearbySecret = null;
    this._cachedNearbyDragonLair = null;
    this._cachedNearbyDungeon = null;
    this._cachedNearbyDock = null;
    this._cachedNearbyHerb = null;
    this.invIndex = 0;
    this.inventoryView = "list";
    this.quest = this._makeBountyQuest();
    this._lastHeroLevel = this.hero.level || 1;
    this.camera.x = this.hero.x;
    this.camera.y = this.hero.y;
    this._spawnInitialEnemies();
    this.world.revealAround?.(this.hero.x, this.hero.y, 900);
    this._saveGame();
    this._msg("Dev: new game reset", 1.3);
  }

  _handleMovement(dt) {
    let mx = 0;
    let my = 0;

    if (this.input.isDown("ArrowUp")) my -= 1;
    if (this.input.isDown("ArrowDown")) my += 1;
    if (this.input.isDown("ArrowLeft")) mx -= 1;
    if (this.input.isDown("ArrowRight")) mx += 1;
    if (this.touch?.moveId != null) {
      mx += this.touch.mx || 0;
      my += this.touch.my || 0;
    }

    const moveInput = { x: mx, y: my };
    const redirectedMove = this.getMoveIntent?.(moveInput, this);
    const move = norm(redirectedMove?.x ?? mx, redirectedMove?.y ?? my);
    if (Math.abs(mx) > 0.08 || Math.abs(my) > 0.08) this._noteMoveIntent(0.28);
    const speed = this._getHeroMoveSpeed();
    if (Math.abs(move.x) > 0.01 || Math.abs(move.y) > 0.01) {
      this.hero.lastMove.x = move.x;
      this.hero.lastMove.y = move.y;
      if ((this.mouse.aimRecentT || 0) <= 0.02) {
        if (!this.hero.faceDir) this.hero.faceDir = { x: move.x, y: move.y };
        this.hero.faceDir.x = move.x;
        this.hero.faceDir.y = move.y;
      }
    }

    this.hero.vx = move.x * speed;
    this.hero.vy = move.y * speed;

    const nx = this.hero.x + this.hero.vx * dt;
    const ny = this.hero.y + this.hero.vy * dt;

    if (this._canHeroMoveTo(nx, ny)) {
      this.hero.x = nx;
      this.hero.y = ny;
      return;
    }

    if (this._canHeroMoveTo(nx, this.hero.y)) this.hero.x = nx;
    if (this._canHeroMoveTo(this.hero.x, ny)) this.hero.y = ny;
  }

  _applyTerrainEffects(dt) {
    if (this.dungeon.active || !this.world || !this.hero) return;
    this._terrainFxT = Math.max(0, (this._terrainFxT || 0) - dt);
    if (this._terrainFxT > 0) return;
    this._terrainFxT = 0.42;

    const zone = String(this._heroTerrainSample?.zone || "").toLowerCase();
    if (!zone) return;

    if (zone === "meadow" || zone === "whisper grass" || zone === "old fields") {
      if ((this.hero.hp || 0) < (this.hero.maxHp || 0)) {
        this.hero.hp = Math.min(this.hero.maxHp || 0, (this.hero.hp || 0) + 1);
      }
    } else if (zone === "greenwood" || zone === "forest" || zone === "deep wilds") {
      if ((this.hero.mana || 0) < (this.hero.maxMana || 0)) {
        this.hero.mana = Math.min(this.hero.maxMana || 0, (this.hero.mana || 0) + 1);
      }
    }
  }

  _canHeroMoveTo(x, y) {
    if (this.dungeon.active) return this._canMoveInDungeon(x, y);
    return this.world.canWalk(x, y, this.hero);
  }

  _canMoveInDungeon(x, y) {
    const layout = this.dungeon?.layout;
    if (!layout) {
      const room = this.dungeon.room || { x: this.hero.x, y: this.hero.y, w: 760, h: 520 };
      return x > room.x - room.w * 0.5 + 42 &&
        x < room.x + room.w * 0.5 - 42 &&
        y > room.y - room.h * 0.5 + 42 &&
        y < room.y + room.h * 0.5 - 42;
    }

    const insideRect = (rect, inset = 0) =>
      x >= rect.x - rect.w * 0.5 + inset &&
      x <= rect.x + rect.w * 0.5 - inset &&
      y >= rect.y - rect.h * 0.5 + inset &&
      y <= rect.y + rect.h * 0.5 - inset;

    let walkable = false;
    for (const rect of layout.walkRects || []) {
      if (insideRect(rect, rect.kind === "room" ? 0 : 0)) {
        walkable = true;
        break;
      }
    }
    if (!walkable) return false;

    for (const rect of layout.blockedRects || []) {
      if (insideRect(rect, 0)) return false;
    }

    for (const door of layout.doors || []) {
      if (door.open) continue;
      if (insideRect(door.blocker, 2)) return false;
    }
    return true;
  }

  noteFrame(frameDt) {
    const dt = Math.max(0, frameDt || 0);
    if (!(dt > 0)) return;
    this._frameMs = dt * 1000;
    this._frameJank = Math.max(0, this._frameMs - 16.67);
    this._fpsAccum += dt;
    this._fpsFrames += 1;
    if (this._fpsAccum >= 0.25) {
      this._fps = this._fpsFrames / this._fpsAccum;
      this._fpsAccum = 0;
      this._fpsFrames = 0;
    }

    const now = (this.time || 0) + dt;
    const dxHero = (this.hero?.x || 0) - (this._perfLastHeroX || 0);
    const dyHero = (this.hero?.y || 0) - (this._perfLastHeroY || 0);
    const movedDist = Math.hypot(dxHero, dyHero);
    const moving =
      movedDist > 0.85 ||
      Math.hypot(this.hero?.vx || 0, this.hero?.vy || 0) > 12 ||
      Math.abs(this.touch?.mx || 0) > 0.08 ||
      Math.abs(this.touch?.my || 0) > 0.08 ||
      (this._moveIntentTimer || 0) > 0 ||
      !!this.hero?.state?.sailing;
    this._perfLastHeroX = this.hero?.x || 0;
    this._perfLastHeroY = this.hero?.y || 0;
    this._recentFrameSamples.push({ t: now, ms: this._frameMs, moving });
    const windowSec = this._spikeStats?.windowSec || 5;
    while (this._recentFrameSamples.length && now - this._recentFrameSamples[0].t > windowSec) {
      this._recentFrameSamples.shift();
    }
    let worstMs = 0;
    let hitch24 = 0;
    let hitch33 = 0;
    let hitch50 = 0;
    let moveWorstMs = 0;
    let moveHitches = 0;
    for (const sample of this._recentFrameSamples) {
      if (sample.ms > worstMs) worstMs = sample.ms;
      if (sample.ms >= 24) hitch24++;
      if (sample.ms >= 33.3) hitch33++;
      if (sample.ms >= 50) hitch50++;
      if (sample.moving) {
        if (sample.ms > moveWorstMs) moveWorstMs = sample.ms;
        if (sample.ms >= 24) moveHitches++;
      }
    }
    this._spikeStats = {
      worstMs,
      hitch24,
      hitch33,
      hitch50,
      moveWorstMs,
      moveHitches,
      windowSec,
    };
  }

  _getHeroMoveSpeed() {
    const st = this.hero.getStats();
    let speed = 150 + st.move * 160;
    if ((this.hero.state?.dashT || 0) > 0) speed *= 1.45;
    if (this.hero.state?.sailing) speed *= 1.18;
    speed *= this._heroTerrainSample?.moveModifier || 1;
    return speed;
  }

  _noteMoveIntent(dt = 0.12) {
    this._moveIntentTimer = Math.max(this._moveIntentTimer || 0, dt);
  }

  _updateHeroTerrainSample(dt) {
    this._heroTerrainSampleT -= dt;
    const sample = this._heroTerrainSample || {};
    const moved = Math.abs((this.hero.x || 0) - (sample.x || 0)) + Math.abs((this.hero.y || 0) - (sample.y || 0));
    if (this._heroTerrainSampleT > 0 && moved < 28) return;
    this._refreshHeroTerrainSample(false);
  }

  _refreshHeroTerrainSample(force = false) {
    if (!this.world || !this.hero) return;
    const zoneInfo = this.world.getZoneInfo?.(this.hero.x, this.hero.y);
    const moveModifier = this.world.getMoveModifier?.(this.hero.x, this.hero.y) ?? 1;
    this._heroTerrainSample = {
      moveModifier,
      zone: String(zoneInfo?.zone || zoneInfo?.name || ""),
      x: this.hero.x,
      y: this.hero.y,
    };
    this._heroTerrainSampleT = force ? 0.08 : 0.12;
  }

  getPerfSnapshot() {
    let visibleEnemies = 0;
    let visibleProjectiles = 0;
    let visibleLoot = 0;
    for (const e of this.enemies || []) {
      if (e?.alive && this._isVisibleWorldPoint(e.x, e.y, 150)) visibleEnemies++;
    }
    for (const p of this.projectiles || []) {
      if (p?.alive && this._isVisibleWorldPoint(p.x, p.y, 120)) visibleProjectiles++;
    }
    for (const l of this.loot || []) {
      if (l?.alive && this._isVisibleWorldPoint(l.x, l.y, 80)) visibleLoot++;
    }
    return {
      fps: this._fps || 0,
      frameMs: this._frameMs || 0,
      frameJank: this._frameJank || 0,
      spike: this._spikeStats || null,
      renderScale: this.renderScale || 1,
      enemies: this.enemies?.length || 0,
      visibleEnemies,
      activeEnemies: this._activeEnemies?.length || 0,
      projectiles: this.projectiles?.length || 0,
      visibleProjectiles,
      loot: this.loot?.length || 0,
      visibleLoot,
      floatingTexts: this.floatingTexts?.length || 0,
      world: this.world?.getPerfStats?.(this.camera) || null,
    };
  }

  getPerfSnapshotText() {
    const perf = this.getPerfSnapshot();
    const world = perf.world || {};
    return [
      `FPS ${Math.round(perf.fps || 0)}  Frame ${perf.frameMs.toFixed(1)}ms  Jank ${perf.frameJank.toFixed(1)}ms`,
      `Enemies visible/active/total ${perf.visibleEnemies}/${perf.activeEnemies}/${perf.enemies}`,
      `Projectiles visible/total ${perf.visibleProjectiles}/${perf.projectiles}`,
      `Loot visible/total ${perf.visibleLoot}/${perf.loot}  FloatingTexts ${perf.floatingTexts || 0}`,
      `Roads visible/total ${world.visibleRoads || 0}/${world.roads || 0}  RoadSegs ${world.roadSegments || 0}  RoadBuckets ${world.roadBuckets || 0}`,
      `Rivers ${world.rivers || 0}  RiverSegs ${world.riverSegments || 0}  RiverBuckets ${world.riverBuckets || 0}`,
      `Bridges visible/total ${world.visibleBridges || 0}/${world.bridges || 0}  Docks ${world.docks || 0}`,
      `Chunks terrain/props/bridge ${world.terrainChunks || 0}/${world.propChunks || 0}/${world.bridgeChunks || 0}`,
      `Props trees/rocks/clutter ${world.trees || 0}/${world.rocks || 0}/${world.clutter || 0}`,
      `Spikes worst ${((perf.spike?.worstMs) || 0).toFixed(1)}ms  move worst ${((perf.spike?.moveWorstMs) || 0).toFixed(1)}ms  h24 ${perf.spike?.hitch24 || 0}  h33 ${perf.spike?.hitch33 || 0}  h50 ${perf.spike?.hitch50 || 0}`,
      `Hero X ${Math.round(this.hero?.x || 0)}  Y ${Math.round(this.hero?.y || 0)}`,
    ].join("\n");
  }

  getHitchSnapshotText() {
    const spike = this._spikeStats || {};
    return [
      `Worst ${((spike.worstMs) || 0).toFixed(1)}ms/${spike.windowSec || 5}s`,
      `Move worst ${((spike.moveWorstMs) || 0).toFixed(1)}ms`,
      `Hitches 24/33/50 ${spike.hitch24 || 0}/${spike.hitch33 || 0}/${spike.hitch50 || 0}`,
      `Move hitches ${spike.moveHitches || 0}`,
    ].join("\n");
  }

  _runDeferredInitialSpawn(dt) {
    if (!this._needsInitialSpawn) return;
    this._startupSpawnT -= dt;
    if (this._startupSpawnT > 0) return;
    this._needsInitialSpawn = false;
    this._spawnInitialEnemies();
  }

  _updateActiveEnemySet(dt) {
    this._activeEnemyRefreshT -= dt;
    if (this._activeEnemyRefreshT > 0 && this._activeEnemies.length) return;
    this._activeEnemyRefreshT = this.dungeon.active ? 0.08 : 0.12;
    const logicD2 = this.dungeon.active ? Infinity : (this.perf.enemyLogicRadius || 720) ** 2;
    const updateD2 = this.dungeon.active ? Infinity : (this.perf.enemyUpdateRadius || 920) ** 2;
    const active = [];
    for (const e of this.enemies) {
      if (!e?.alive) continue;
      const d2 = dist2(e.x, e.y, this.hero.x, this.hero.y);
      if (d2 <= updateD2 || d2 <= logicD2) active.push(e);
    }
    this._activeEnemies = active;
  }

  _handleSkills() {
    if (this.input.wasPressed("1")) this._usePotion("hp");
    if (this.input.wasPressed("2")) this._usePotion("mana");

    if (this.input.wasPressed("q") || this.input.wasPressed("Q")) this._castSpark();
    if (this.input.wasPressed("w") || this.input.wasPressed("W")) this._castNova();
    if (this.input.wasPressed("e") || this.input.wasPressed("E")) this._castBlink();
    if (this.input.wasPressed("r") || this.input.wasPressed("R")) this._castOrb();

    if (this.mouse.down) this._castSpark();
    if (this.touch?.buttons?.q != null) this._castSpark();
  }

  _handleInteractShortcuts(dt) {
    this._dockToggleCd = Math.max(0, this._dockToggleCd - dt);
    this._interactCd = Math.max(0, this._interactCd - dt);

    if ((this.input.wasPressed("b") || this.input.wasPressed("B")) && this._dockToggleCd <= 0 && !this.menu.open) {
      this._dockToggleCd = 0.18;
      this._toggleDockingOrSailing();
    }

    if ((this.input.wasPressed("f") || this.input.wasPressed("F")) && this._interactCd <= 0 && !this.menu.open) {
      this._interactCd = 0.18;
      this._interact();
    }
  }

  _handleInventoryInput() {
    const entries = this.getInventoryEntries();

    if (this.input.wasPressed("v") || this.input.wasPressed("V")) {
      this.inventoryView = this.inventoryView === "grid" ? "list" : "grid";
      this._msg(this.inventoryView === "grid" ? "Inventory grid view" : "Inventory list view", 0.8);
    }

    if (this.input.wasPressed("b") || this.input.wasPressed("B")) {
      this._brewPotion("hp");
    }
    if (this.input.wasPressed("n") || this.input.wasPressed("N")) {
      this._brewPotion("mana");
    }

    if (entries.length <= 0) {
      this.invIndex = 0;
      return;
    }

    this._handleInventoryMouse(entries);

    if (this.inventoryView === "grid") {
      const cols = this.getInventoryGridLayout().cols;
      if (this.input.wasPressed("ArrowRight")) this.invIndex = Math.min(entries.length - 1, (this.invIndex || 0) + 1);
      if (this.input.wasPressed("ArrowLeft")) this.invIndex = Math.max(0, (this.invIndex || 0) - 1);
      if (this.input.wasPressed("ArrowDown")) this.invIndex = Math.min(entries.length - 1, (this.invIndex || 0) + cols);
      if (this.input.wasPressed("ArrowUp")) this.invIndex = Math.max(0, (this.invIndex || 0) - cols);
    } else {
      if (this.input.wasPressed("ArrowDown")) {
        this.invIndex = Math.min(entries.length - 1, (this.invIndex || 0) + 1);
      }

      if (this.input.wasPressed("ArrowUp")) {
        this.invIndex = Math.max(0, (this.invIndex || 0) - 1);
      }
    }

    const entry = entries[this.invIndex];

    if ((this.input.wasPressed("Enter") || this.input.wasPressed("e") || this.input.wasPressed("E")) && entry) {
      this._runInventoryAction("equip", this.invIndex);
    }

    if ((this.input.wasPressed("x") || this.input.wasPressed("X") || this.input.wasPressed("Backspace") || this.input.wasPressed("Delete")) && entry?.kind === "gear") {
      this._runInventoryAction("salvage", this.invIndex);
    }
  }

  _handleInventoryMouse(entries) {
    const layout = this.getInventoryPanelLayout();
    const leftX = layout.leftX;
    const leftY = layout.leftY;
    const leftW = layout.leftW;
    const leftH = layout.leftH;
    if (this.inventoryView === "grid") {
      const grid = this.getInventoryGridLayout();
      const selected = clamp(this.invIndex || 0, 0, Math.max(0, entries.length - 1));
      const maxRows = Math.max(1, Math.ceil(entries.length / grid.cols));
      const selectedRow = Math.floor(selected / grid.cols);
      const scrollRow = clamp(selectedRow - grid.rowsVisible + 1, 0, Math.max(0, maxRows - grid.rowsVisible));
      const mx = this.mouse.x;
      const my = this.mouse.y;
      if (mx < leftX + 8 || mx > leftX + leftW - 8 || my < leftY + 16 || my > leftY + leftH - 8) return;
      const localY = my - grid.startY + scrollRow * (grid.tileH + grid.gutter);
      const row = Math.floor(localY / (grid.tileH + grid.gutter));
      const localX = mx - grid.startX;
      const col = Math.floor(localX / (grid.tileW + grid.gutter));
      if (row < 0 || col < 0 || col >= grid.cols) return;
      const withinTileX = localX - col * (grid.tileW + grid.gutter);
      const withinTileY = localY - row * (grid.tileH + grid.gutter);
      if (withinTileX < 0 || withinTileX > grid.tileW || withinTileY < 0 || withinTileY > grid.tileH) return;
      const idx = row * grid.cols + col;
      if (idx < 0 || idx >= entries.length) return;
      if (this.mouse.clicked && idx === selected) {
        this._runInventoryAction("equip", idx);
        return;
      }
      this.invIndex = idx;
      if (this.mouse.clicked) this._msg(`${entries[idx]?.name || "Item"} selected`, 0.55);
      return;
    }

    const rowH = layout.rowH;
    const visible = Math.max(1, Math.floor((leftH - 40) / rowH));
    const selected = clamp(this.invIndex || 0, 0, Math.max(0, entries.length - 1));
    const scroll = clamp(selected - visible + 1, 0, Math.max(0, entries.length - visible));
    const mx = this.mouse.x;
    const my = this.mouse.y;
    const inList = mx >= leftX + 8 && mx <= leftX + leftW - 8 && my >= leftY + 16 && my <= leftY + leftH - 8;
    if (!inList) return;

    const row = Math.floor((my - (leftY + 18)) / rowH);
    const idx = scroll + row;
    if (idx < 0 || idx >= entries.length) return;

    if (this.mouse.clicked && idx === selected) {
      this._runInventoryAction("equip", idx);
      return;
    }

    this.invIndex = idx;
    if (this.mouse.clicked) this._msg(`${entries[idx]?.name || "Item"} selected`, 0.55);
  }

  _runInventoryAction(action, index) {
    const entry = this.getInventoryEntries()[index];
    if (!entry) return;
    if (action === "equip") {
      if (entry.kind === "recipe") this._craftRecipe(entry.recipeId);
      else if (entry.kind === "material") this._msg(`${entry.name} is stored for crafting`, 0.8);
      else this._equipInventoryItem(index);
    } else if (action === "salvage" && entry.kind === "gear") {
      this._salvageInventoryItem(index);
    }
  }

  getInventoryPanelText(hasItems = (this.hero?.inventory?.length || 0) > 0) {
    return {
      headerHint: hasItems ? "I or Esc close   V swap view   wheel/arrow select   Enter craft/equip   X salvage" : "I or Esc close   V swap view   Enter craft   B brew HP   N brew Mana",
      emptyBagTitle: "No gear in your bag yet.",
      emptyBagBody: "Clear camps, shops, contracts, and dungeons will start filling it.",
      emptyDetailTitle: "Item Details",
      emptyDetailBody: "Pick up gear to compare it here.",
      emptyDetailNote: "Your equipped kit will stay visible above while the bag is empty.",
      equipHint: "Enter/E or click again use/equip",
      salvageHint: "X/Delete salvage",
      brewHpHint: "B Brew health potion (3 herbs)",
      brewManaHint: "N Brew mana potion (4 herbs)",
    };
  }

  getMaterialCatalog() {
    return {
      herb: { label: "Wild Herb", color: "#8fe48d", desc: "Fresh greens used for brews, salves, and road remedies." },
      scrap: { label: "Metal Scrap", color: "#d1c0aa", desc: "Bent buckles, nails, and fittings salvaged from old gear." },
      ore: { label: "Ore Chunk", color: "#8ba9c8", desc: "Raw stone and iron ore fit for smelting or tool work." },
      hide: { label: "Tough Hide", color: "#b88c62", desc: "Animal and raider leathers used for stitched gear." },
      essence: { label: "Arcane Essence", color: "#c8a0ff", desc: "Residual energy gathered from occult threats and relic sites." },
    };
  }

  getCraftingRecipes() {
    const level = Math.max(1, this.hero?.level || 1);
    return [
      {
        id: "field-tonic",
        name: "Field Tonic",
        color: "#8fe48d",
        desc: "A simple restorative brew for surviving the road.",
        requires: { herb: 3 },
        resultText: "Crafts 1 health potion",
        craft: () => {
          this.hero.potions.hp = (this.hero.potions.hp || 0) + 1;
          this._spawnFloatingText(this.hero.x, this.hero.y - 26, "+Health potion", "#8fe48d");
          this._msg("Field tonic brewed", 1.0);
        },
      },
      {
        id: "focus-draught",
        name: "Focus Draught",
        color: "#88cfff",
        desc: "An herb-and-essence draught for restoring mana.",
        requires: { herb: 4, essence: 1 },
        resultText: "Crafts 1 mana potion",
        craft: () => {
          this.hero.potions.mana = (this.hero.potions.mana || 0) + 1;
          this._spawnFloatingText(this.hero.x, this.hero.y - 26, "+Mana potion", "#88cfff");
          this._msg("Focus draught brewed", 1.0);
        },
      },
      {
        id: "patchwork-armor",
        name: "Patchwork Armor",
        color: "#d5c1a2",
        desc: "Hide and scrap stitched into practical travel armor.",
        requires: { hide: 5, scrap: 3 },
        resultText: "Crafts 1 common armor",
        craft: () => {
          const item = makeGear("armor", Math.max(level, 2), "common", hash2(this.seed, level, this.time | 0, 201));
          item.name = "Patchwork Armor";
          item.affix = "stitched";
          this.hero.inventory.push(item);
          this._msg("Patchwork armor crafted", 1.2);
        },
      },
      {
        id: "iron-edge",
        name: "Iron Edge",
        color: "#dce8f6",
        desc: "A sturdier forged weapon made from ore and salvage.",
        requires: { scrap: 5, ore: 3 },
        resultText: "Crafts 1 uncommon weapon",
        craft: () => {
          const item = makeGear("weapon", Math.max(level, 2), "uncommon", hash2(this.seed, level, this.time | 0, 202));
          item.name = "Iron Edge";
          item.affix = "forged";
          this.hero.inventory.push(item);
          this._msg("Iron Edge forged", 1.2);
        },
      },
      {
        id: "trail-boots",
        name: "Trail Boots",
        color: "#d8c39c",
        desc: "Flexible boots made for long-distance travel.",
        requires: { hide: 4, scrap: 2 },
        resultText: "Crafts 1 uncommon boots",
        craft: () => {
          const item = makeGear("boots", Math.max(level, 2), "uncommon", hash2(this.seed, level, this.time | 0, 203));
          item.name = "Trail Boots";
          item.affix = "wayfarer";
          this.hero.inventory.push(item);
          this._msg("Trail boots crafted", 1.2);
        },
      },
      {
        id: "ward-charm",
        name: "Ward Charm",
        color: "#d3a9ff",
        desc: "A bound charm for safer spellwork and deeper delves.",
        requires: { essence: 3, hide: 2, scrap: 1 },
        resultText: "Crafts 1 uncommon trinket",
        craft: () => {
          const item = makeGear("trinket", Math.max(level, 2), "uncommon", hash2(this.seed, level, this.time | 0, 204));
          item.name = "Ward Charm";
          item.affix = "bound";
          this.hero.inventory.push(item);
          this._msg("Ward charm crafted", 1.2);
        },
      },
      {
        id: "hunter-wraps",
        name: "Hunter Wraps",
        color: "#d8b992",
        desc: "Leather wrappings that toughen long marches and quick turns.",
        requires: { hide: 6, herb: 2 },
        resultText: "Crafts 1 uncommon boots",
        craft: () => {
          const item = makeGear("boots", Math.max(level, 3), "uncommon", hash2(this.seed, level, this.time | 0, 205));
          item.name = "Hunter Wraps";
          item.affix = "scouted";
          this.hero.inventory.push(item);
          this._msg("Hunter wraps crafted", 1.2);
        },
      },
      {
        id: "quicksilver-ring",
        name: "Quicksilver Ring",
        color: "#dfe9ff",
        desc: "A light silver band that sharpens movement and critical timing.",
        requires: { ore: 3, essence: 2, scrap: 2 },
        resultText: "Crafts 1 uncommon ring",
        craft: () => {
          const item = makeGear("ring", Math.max(level, 3), "uncommon", hash2(this.seed, level, this.time | 0, 206));
          item.name = "Quicksilver Ring";
          item.affix = "nimble";
          this.hero.inventory.push(item);
          this._msg("Quicksilver ring crafted", 1.2);
        },
      },
      {
        id: "campfire-kit",
        name: "Campfire Kit",
        color: "#ffcb8e",
        desc: "Scrap and herb bundles packed into a quick field-rest supply.",
        requires: { herb: 2, scrap: 2, hide: 1 },
        resultText: "Grants 1 health potion and 1 mana potion",
        craft: () => {
          this.hero.potions.hp = (this.hero.potions.hp || 0) + 1;
          this.hero.potions.mana = (this.hero.potions.mana || 0) + 1;
          this._spawnFloatingText(this.hero.x, this.hero.y - 28, "Campfire kit", "#ffcb8e");
          this._msg("Campfire kit packed", 1.0);
        },
      },
      {
        id: "rune-lantern",
        name: "Rune Lantern",
        color: "#b9e5ff",
        desc: "A relic lamp for deeper delves and steadier dungeon footing.",
        requires: { essence: 4, ore: 2, hide: 2 },
        resultText: "Crafts 1 rare trinket",
        craft: () => {
          const item = makeGear("trinket", Math.max(level, 4), "rare", hash2(this.seed, level, this.time | 0, 207));
          item.name = "Rune Lantern";
          item.affix = "delver's";
          this.hero.inventory.push(item);
          this._msg("Rune lantern crafted", 1.2);
        },
      },
      {
        id: "surveyor-kit",
        name: "Surveyor Kit",
        color: "#9ad7ff",
        desc: "Charts the land ahead and uncovers a safer patch of the world map.",
        requires: { herb: 1, scrap: 2, ore: 1 },
        resultText: "Reveals the nearby map",
        craft: () => {
          this.world?.revealAround?.(this.hero.x, this.hero.y, 780);
          this._spawnFloatingText(this.hero.x, this.hero.y - 28, "Surveyed", "#9ad7ff");
          this._msg("Surveyor kit used", 1.0);
        },
      },
      {
        id: "brigandine",
        name: "Reinforced Brigandine",
        color: "#e1c9ab",
        desc: "A stronger field cuirass pieced together from hide, ore, and salvage.",
        requires: { hide: 7, ore: 3, scrap: 4 },
        resultText: "Crafts 1 uncommon armor",
        craft: () => {
          const item = makeGear("armor", Math.max(level, 4), "uncommon", hash2(this.seed, level, this.time | 0, 208));
          item.name = "Reinforced Brigandine";
          item.affix = "layered";
          this.hero.inventory.push(item);
          this._msg("Reinforced brigandine crafted", 1.2);
        },
      },
      {
        id: "wayfarer-ration",
        name: "Wayfarer Ration",
        color: "#f1d39c",
        desc: "Packed herbs and hide strips that steady you for the next hard march.",
        requires: { herb: 2, hide: 2 },
        resultText: "Restores health and mana",
        craft: () => {
          const hpGain = Math.max(16, Math.round((this.hero.maxHp || 100) * 0.18));
          const manaGain = Math.max(10, Math.round((this.hero.maxMana || 60) * 0.22));
          this.hero.hp = Math.min(this.hero.maxHp || 100, (this.hero.hp || 0) + hpGain);
          this.hero.mana = Math.min(this.hero.maxMana || 60, (this.hero.mana || 0) + manaGain);
          this._spawnFloatingText(this.hero.x, this.hero.y - 28, "Rations", "#f1d39c");
          this._msg("Wayfarer ration consumed", 1.0);
        },
      },
      {
        id: "river-knife",
        name: "River Knife",
        color: "#d9ebff",
        desc: "A slim blade balanced for quick cuts and clean finishing strikes.",
        requires: { scrap: 4, ore: 4, essence: 1 },
        resultText: "Crafts 1 uncommon weapon",
        craft: () => {
          const item = makeGear("weapon", Math.max(level, 4), "uncommon", hash2(this.seed, level, this.time | 0, 209));
          item.name = "River Knife";
          item.affix = "nimble";
          this.hero.inventory.push(item);
          this._msg("River Knife crafted", 1.2);
        },
      },
      {
        id: "warden-seal",
        name: "Warden Seal",
        color: "#d8d0ff",
        desc: "A stamped charm that hardens resolve for rough crossings and longer fights.",
        requires: { essence: 3, scrap: 2, ore: 2 },
        resultText: "Crafts 1 rare ring",
        craft: () => {
          const item = makeGear("ring", Math.max(level, 5), "rare", hash2(this.seed, level, this.time | 0, 210));
          item.name = "Warden Seal";
          item.affix = "steadfast";
          this.hero.inventory.push(item);
          this._msg("Warden seal crafted", 1.2);
        },
      },
      {
        id: "roadwarden-cloak",
        name: "Roadwarden Cloak",
        color: "#b8c7d8",
        desc: "A weathered mantle stitched for long roads, cold passes, and hard travel.",
        requires: { hide: 6, scrap: 3, herb: 2 },
        resultText: "Crafts 1 rare armor",
        craft: () => {
          const item = makeGear("armor", Math.max(level, 5), "rare", hash2(this.seed, level, this.time | 0, 211));
          item.name = "Roadwarden Cloak";
          item.affix = "waymarked";
          this.hero.inventory.push(item);
          this._msg("Roadwarden Cloak crafted", 1.2);
        },
      },
      {
        id: "tideglass-phial",
        name: "Tideglass Phial",
        color: "#9ddfff",
        desc: "A clear vessel tuned to riverlight and coastal fog, useful for deep travel and sharper recovery.",
        requires: { essence: 2, herb: 3, ore: 2 },
        resultText: "Grants 1 mana potion and reveals water crossings nearby",
        craft: () => {
          this.hero.potions.mana = (this.hero.potions.mana || 0) + 1;
          this.world?.revealAround?.(this.hero.x, this.hero.y, 520);
          this._spawnFloatingText(this.hero.x, this.hero.y - 28, "Tideglass", "#9ddfff");
          this._msg("Tideglass phial prepared", 1.0);
        },
      },
    ];
  }

  getEditorToolLines() {
    const snap = this.world?.getEditorSnapshot?.() || {};
    const status = this.editor.lastStatus ? `Status: ${this.editor.lastStatus}` : "World Forge ready";
    const riverPiece =
      this.editor.tool === "river"
        ? `  Straight  Rot ${Math.round((((this.editor.riverAngle || 0) * 180) / Math.PI) % 360)}deg`
        : "";
    if (this.worldVariant === "river-build") {
      return [
        `River Build  ${this._editorToolName()}${this.editor.dragging ? " (placing)" : ""}${riverPiece}`,
        `Flat sandbox. Click to stamp V-shaped trench cuts. Rotate the trench and judge the shape only.`,
        `Cuts ${snap.terrainStamps || 0}  ${status}`,
        `Brush ${Math.round(this.editor.brushSize)}  Width ${Math.round(this.editor.strokeWidth)}  Pow ${Math.round(this.editor.terrainPower)}`,
        `Mouse ${Math.round(this.mouse.worldX || 0)}, ${Math.round(this.mouse.worldY || 0)}`,
      ];
    }
    return [
      `${this.mode === "build" ? "Build" : "Play"}  ${this._editorToolName()}${this.editor.dragging ? " (drawing)" : ""}${riverPiece}`,
      `Road drag. River = click straight sections. Click props/places. WASD pan, wheel zoom, F center.`,
      `Roads ${snap.roads || 0}  Rivers ${snap.rivers || 0}  Bridges ${snap.bridges || 0}  Docks ${snap.docks || 0}`,
      `Props ${snap.props || 0}  POIs ${snap.pois || 0}  Terrain ${snap.terrainStamps || 0}  ${status}`,
      `Brush ${Math.round(this.editor.brushSize)}  Width ${Math.round(this.editor.strokeWidth)}  Pow ${Math.round(this.editor.terrainPower)}  Scale ${this.editor.propScale.toFixed(1)}`,
      `Mouse ${Math.round(this.mouse.worldX || 0)}, ${Math.round(this.mouse.worldY || 0)}`,
    ];
  }

  getEditorPanelLayout() {
    const w = Math.min(Math.max(this.w - 220, 640), 760);
    const lines = this.getEditorToolLines();
    const h = Math.min(this.h - 56, Math.max(690, 352 + lines.length * 16));
    return {
      w,
      h,
      x: 24,
      y: 24,
      rowStart: 548,
      rowStep: 16,
    };
  }

  getEditorButtonRects() {
    const { x, y, w, h } = this.getEditorPanelLayout();
    const buttons = [];
    const leftX = x + 18;
    const topY = y + 58;
    const gap = 10;
    const sectionGap = 14;
    const groupTitleH = 18;
    let cursorY = topY;
    const colW = 72;
    const toolH = 22;
    const toolGap = 4;
    const groupCols = [4, 3, 3, 4];

    const toolGroups = this.worldVariant === "river-build"
      ? [
          { label: "River", tools: ["river"] },
        ]
      : EDITOR_TOOL_GROUPS;

    for (let gi = 0; gi < toolGroups.length; gi++) {
      const group = toolGroups[gi];
      const cols = groupCols[gi] || 4;
      buttons.push({ action: `label:${group.label}`, label: group.label, x: leftX, y: cursorY, w: 160, h: groupTitleH, kind: "label" });
      cursorY += groupTitleH + 8;
      for (let i = 0; i < group.tools.length; i++) {
        const tool = group.tools[i];
        const row = Math.floor(i / cols);
        const col = i % cols;
        buttons.push({
          action: `tool:${tool}`,
          label: `${this._editorToolShortLabel(tool)}`,
          hotkey: this._editorToolHotkey(tool),
          x: leftX + col * (colW + toolGap),
          y: cursorY + row * (toolH + toolGap),
          w: colW,
          h: toolH,
          kind: "tool",
          active: this.editor.tool === tool,
        });
      }
      cursorY += Math.ceil(group.tools.length / cols) * (toolH + toolGap) + sectionGap;
    }

    if (this.worldVariant === "river-build") {
      buttons.push({
        action: "tool:river",
        label: "River Seg",
        hotkey: "2",
        x: leftX,
        y: cursorY,
        w: 284,
        h: 36,
        kind: "tool",
        active: this.editor.tool === "river",
      });
      cursorY += 46;
    } else {
      buttons.push({ action: "label:River Pieces", label: "River Pieces", x: leftX, y: cursorY, w: 160, h: groupTitleH, kind: "label" });
      cursorY += groupTitleH + 8;
      const riverPieceButtons = [
        { action: "river-piece:straight", piece: "straight", label: "Straight", x: leftX, y: cursorY, w: 284, h: 36 },
      ];
      for (const button of riverPieceButtons) {
        buttons.push({
          ...button,
          kind: "river-piece",
          active: this.editor.tool === "river" && this.editor.riverPiece === button.piece,
        });
      }
      cursorY += 46;
    }
    buttons.push({ action: "river-rot-left", label: "Rotate L", x: leftX, y: cursorY, w: 138, h: 24, kind: "control" });
    buttons.push({ action: "river-rot-right", label: "Rotate R", x: leftX + 146, y: cursorY, w: 138, h: 24, kind: "control" });

    const controlY = y + 58;
    const controlX = x + w - 156;
    const miniW = 24;
    const bigW = 68;
    const controlH = 22;
    const controlRows = [
      { label: "Brush", value: `${Math.round(this.editor.brushSize)}`, down: "brush-down", up: "brush-up" },
      { label: "Width", value: `${Math.round(this.editor.strokeWidth)}`, down: "width-down", up: "width-up" },
      { label: "Power", value: `${Math.round(this.editor.terrainPower)}`, down: "power-down", up: "power-up" },
      { label: "Scale", value: `${this.editor.propScale.toFixed(1)}`, down: "scale-down", up: "scale-up" },
    ];
    for (let i = 0; i < controlRows.length; i++) {
      const rowY = controlY + 16 + i * 28;
      const row = controlRows[i];
      buttons.push({ action: `label:${row.label}`, label: row.label, x: controlX, y: rowY - 18, w: 80, h: 16, kind: "label" });
      buttons.push({ action: row.down, label: "-", x: controlX, y: rowY, w: miniW, h: controlH, kind: "control" });
      buttons.push({ action: `value:${row.label}`, label: row.value, x: controlX + miniW + gap, y: rowY, w: bigW, h: controlH, kind: "value" });
      buttons.push({ action: row.up, label: "+", x: controlX + miniW + gap + bigW + gap, y: rowY, w: miniW, h: controlH, kind: "control" });
    }

    const modeY = controlY + 132;
    if (this.worldVariant !== "river-build") {
      buttons.push({ action: "play", label: "Play", x: controlX, y: modeY, w: 44, h: 22, kind: "mode", active: this.mode !== "build" });
      buttons.push({ action: "build", label: "Build", x: controlX + 48, y: modeY, w: 44, h: 22, kind: "mode", active: this.mode === "build" });
      buttons.push({ action: "hud", label: this.editor.showGameHud ? "HUD" : "NoHUD", x: controlX + 96, y: modeY, w: 54, h: 22, kind: "mode", active: this.editor.showGameHud });
    }

    const actionX = controlX;
    const actionW = 150;
    const actionH = 24;
    const actionTop = this.worldVariant === "river-build" ? modeY : modeY + 34;
    const actionButtons = this.worldVariant === "river-build"
      ? [
          { action: "undo", label: "Undo", kind: "action" },
          { action: "revert-base", label: "Revert", kind: "action-danger" },
          { action: "clear", label: "Clear", kind: "action-danger" },
          { action: "save", label: "Save", kind: "action" },
          { action: "export", label: "Export", kind: "action" },
          { action: "import", label: "Import", kind: "action" },
        ]
      : [
        { action: "undo", label: "Undo", kind: "action" },
        { action: "revert-base", label: "Revert", kind: "action-danger" },
        { action: "repair-paths", label: "Repair", kind: "action-primary" },
        { action: "bake-rivers", label: "Bake Rivers", kind: "action-primary" },
        { action: "clear", label: "Clear", kind: "action-danger" },
        { action: "save", label: "Save", kind: "action" },
        { action: "save-play", label: "Save + Play", kind: "action-primary" },
        { action: "export", label: "Export", kind: "action" },
        { action: "import", label: "Import", kind: "action" },
      ];
    for (let i = 0; i < actionButtons.length; i++) {
      buttons.push({
        ...actionButtons[i],
        x: actionX,
        y: actionTop + i * (actionH + 8),
        w: actionW,
        h: actionH,
      });
    }
    return buttons;
  }

  getInventoryEntries() {
    const gear = (this.hero.inventory || []).map((item, index) => ({
      kind: "gear",
      index,
      item,
      name: item?.name || "Unknown Gear",
      color: item?.color || "#d9dee8",
    }));
    const catalog = this.getMaterialCatalog();
    const materials = [];
    for (const [material, count] of [
      ["herb", this.progress.herbs || 0],
      ["scrap", this.progress.materials?.scrap || 0],
      ["ore", this.progress.materials?.ore || 0],
      ["hide", this.progress.materials?.hide || 0],
      ["essence", this.progress.materials?.essence || 0],
    ]) {
      if (!count) continue;
      const meta = catalog[material];
      materials.push({
        kind: "material",
        material,
        count,
        name: meta?.label || material,
        color: meta?.color || "#d9dee8",
        desc: meta?.desc || "",
      });
    }
    const recipes = this.getCraftingRecipes().map((recipe) => ({
      kind: "recipe",
      recipeId: recipe.id,
      name: recipe.name,
      color: recipe.color,
      recipe,
    }));
    return [...gear, ...materials, ...recipes];
  }

  getInventoryPanelLayout() {
    const panelW = Math.min(Math.max(this.w - 90, 700), 860);
    const panelH = Math.min(Math.max(this.h - 90, 430), 540);
    const x = ((this.w - panelW) / 2) | 0;
    const y = ((this.h - panelH) / 2) | 0;
    return {
      panelW,
      panelH,
      x,
      y,
      leftX: x + 18,
      leftY: y + 74,
      leftW: 370,
      leftH: panelH - 92,
      rowH: 28,
    };
  }

  getEquipmentSlots() {
    return EQUIPMENT_SLOTS;
  }

  _equipInventoryItem(index) {
    const entry = this.getInventoryEntries()[index];
    if (!entry || entry.kind !== "gear") return;
    const inv = this.hero.inventory || [];
    const item = inv[entry.index];
    if (!item?.slot) return;

    const prev = this.hero.equip?.[item.slot] || null;
    this.hero.equip[item.slot] = item;
    inv.splice(entry.index, 1);
    if (prev) inv.push(prev);

    this.invIndex = clamp(index, 0, Math.max(0, this.getInventoryEntries().length - 1));
    const delta = (item.score || 0) - (prev?.score || 0);
    const note = prev ? ` ${delta >= 0 ? "+" : ""}${delta} power` : "";
    this._msg(`Equipped ${item.name}${note}`, 1.6);
  }

  _salvageInventoryItem(index) {
    const entry = this.getInventoryEntries()[index];
    if (!entry || entry.kind !== "gear") return;
    const inv = this.hero.inventory || [];
    const item = inv[entry.index];
    if (!item) return;

    const rarityBonus =
      item.rarity === "epic" ? 28 :
      item.rarity === "rare" ? 14 :
      item.rarity === "uncommon" ? 7 : 0;

    const value = Math.max(4, 6 + (item.level || 1) * 3 + rarityBonus);
    const yieldMap = this._getSalvageYield(item);
    this.hero.gold += value;
    inv.splice(entry.index, 1);
    this._grantMaterials(yieldMap, false);

    this.invIndex = clamp(index, 0, Math.max(0, this.getInventoryEntries().length - 1));
    this._msg(`Salvaged for ${value}g and materials`, 1.4);
  }

  _getSalvageYield(item) {
    const slot = item?.slot || "trinket";
    const rarity = item?.rarity || "common";
    const tier = rarity === "epic" ? 3 : rarity === "rare" ? 2 : rarity === "uncommon" ? 1 : 0;
    const out = { scrap: 1 + tier, ore: 0, hide: 0, essence: 0 };
    if (slot === "weapon") {
      out.ore += 1 + (tier >= 1 ? 1 : 0);
    } else if (slot === "armor" || slot === "helm") {
      out.hide += 1 + tier;
      out.ore += tier >= 2 ? 1 : 0;
    } else if (slot === "boots") {
      out.hide += 2 + tier;
    } else if (slot === "ring" || slot === "trinket") {
      out.essence += 1 + tier;
      out.scrap += tier >= 2 ? 1 : 0;
    }
    return out;
  }

  _grantMaterials(amounts = {}, announce = true) {
    if (!this.progress.materials) this.progress.materials = { scrap: 0, ore: 0, hide: 0, essence: 0 };
    const parts = [];
    for (const key of ["scrap", "ore", "hide", "essence"]) {
      const amount = Math.max(0, Math.round(amounts[key] || 0));
      if (!amount) continue;
      this.progress.materials[key] = (this.progress.materials[key] || 0) + amount;
      parts.push(`+${amount} ${this.getMaterialCatalog()?.[key]?.label || key}`);
    }
    if (announce && parts.length) {
      this._spawnFloatingText(this.hero.x, this.hero.y - 24, "Materials", "#d5c1a2");
      this._msg(parts.join("  "), 1.2);
    }
  }

  _canCraftRecipe(recipe) {
    if (!recipe?.requires) return false;
    for (const [mat, need] of Object.entries(recipe.requires)) {
      const have = mat === "herb" ? (this.progress.herbs || 0) : (this.progress.materials?.[mat] || 0);
      if (have < need) return false;
    }
    return true;
  }

  _consumeRecipeMaterials(recipe) {
    for (const [mat, need] of Object.entries(recipe.requires || {})) {
      if (mat === "herb") this.progress.herbs = Math.max(0, (this.progress.herbs || 0) - need);
      else if (this.progress.materials) this.progress.materials[mat] = Math.max(0, (this.progress.materials[mat] || 0) - need);
    }
  }

  _craftRecipe(recipeId) {
    const recipe = this.getCraftingRecipes().find((entry) => entry.id === recipeId);
    if (!recipe) return false;
    if (!this._canCraftRecipe(recipe)) {
      this._msg(`${recipe.name} needs more materials`, 0.95);
      return false;
    }
    this._consumeRecipeMaterials(recipe);
    recipe.craft?.();
    return true;
  }

  getInventoryGridLayout() {
    const layout = this.getInventoryPanelLayout();
    const cols = 2;
    const tileW = 166;
    const tileH = 66;
    const gutter = 12;
    const startX = layout.leftX + 10;
    const startY = layout.leftY + 34;
    const rowsVisible = Math.max(1, Math.floor((layout.leftH - 48) / (tileH + gutter)));
    return { cols, tileW, tileH, gutter, startX, startY, rowsVisible };
  }

  _handleShopInput() {
    this._handleShopMouse();
    for (let i = 1; i <= SHOP_ACTION_COUNT; i++) {
      if (this.input.wasPressed(String(i))) this._runShopAction(i);
    }
  }

  _handleShopMouse() {
    if (!this.mouse.clicked) return;
    const layout = this.getShopPanelLayout();
    const w = layout.w;
    const x = layout.x;
    const y = layout.y;
    const mx = this.mouse.x;
    const my = this.mouse.y;
    if (mx < x + 16 || mx > x + w - 16) return;

    for (let i = 0; i < SHOP_ACTION_COUNT; i++) {
      const rowY = y + layout.rowStart + i * layout.rowStep;
      if (my >= rowY - 16 && my <= rowY + 16) {
        this._runShopAction(i + 1);
        return;
      }
    }
  }

  _runShopAction(action) {
    const index = (action | 0) - 1;
    if (index < 0 || index >= SHOP_ACTION_COUNT) return;
    this._buyShopItem(index);
  }

  _handleTownInput() {
    this._handleTownMouse();
    for (let i = 1; i <= TOWN_ACTION_COUNT; i++) {
      if (this.input.wasPressed(String(i))) this._runTownAction(i);
    }
  }

  _handleTownMouse() {
    if (!this.mouse.clicked) return;
    const layout = this.getTownPanelLayout();
    const w = layout.w;
    const x = layout.x;
    const y = layout.y;
    const mx = this.mouse.x;
    const my = this.mouse.y;
    if (mx < x + 18 || mx > x + w - 18 || my < y + layout.actionTop || my > y + layout.actionBottom) return;

    const row = Math.floor((my - (y + layout.rowStart)) / layout.rowStep);
    if (row >= 0 && row < TOWN_ACTION_COUNT) this._runTownAction(row + 1);
  }

  _runTownAction(action) {
    if (action === 1) this._townRest();
    else if (action === 2) this._townBuyPotion("hp");
    else if (action === 3) this._townBuyPotion("mana");
    else if (action === 4) this._townCommissionGear();
    else if (action === 5) this._townAskRumor();
    else if (action === 6) this._townCycleOath();
    else if (action === 7) this._townTakeContract();
    else if (action === 8) this._townBuyMapClue();
    else if (action === 9) this._townBuyPassage();
  }

  getTownMenuLines(town = this._cachedNearbyTown) {
    const npcs = town?.npcs || ["Warden", "Smith", "Archivist"];
    const visited = !!(town && this.progress?.visitedTowns?.has?.(String(town.id)));
    const restCost = Math.max(0, Math.min(28, 8 + (this.hero?.level || 1) * 2));
    const forgeCost = 58 + (this.hero?.level || 1) * 9;
    const clueCost = 36 + (this.hero?.level || 1) * 4;
    const passage = this._getTownPassageInfo(town);
    const focus = this.getTownServiceName();
    const focusHint = focus ? `${focus} service selected.` : "Move between town buildings for different services.";
    return {
      npcs,
      lines: [
        `1 Rest at inn (${restCost}g)`,
        "2 Buy health potion (18g)",
        "3 Buy mana potion (22g)",
        `4 Commission townforged gear (${forgeCost}g)`,
        "5 Ask for a rumor objective",
        "6 Change oath / class",
        "7 Take town contract",
        `8 Buy cartographer clue (${clueCost}g)`,
        passage.available
          ? `9 Pay passage to ${passage.destinationName} (${passage.cost}g)`
          : town?.coastal
            ? "9 Harbor route unavailable"
            : "9 No harbor in this town",
        visited ? `${npcs[0]}: Roads are safer when camps are cleared.` : `${npcs[0]}: First visit supplies were added.`,
      ],
      npcSummary: `${focusHint} ${npcs.join(", ")} are available. Current oath: ${this._className?.() || "Knight"}.${town?.coastal ? " Harbor passage is available here." : ""}`,
    };
  }

  getTownPanelLayout() {
    const w = Math.min(Math.max(this.w - 120, 430), 560);
    const h = 376;
    const x = ((this.w - w) / 2) | 0;
    const y = ((this.h - h) / 2) | 0;
    return {
      w,
      h,
      x,
      y,
      actionTop: 82,
      actionBottom: 304,
      rowStart: 91,
      rowStep: 21,
    };
  }

  _className(id = this.hero?.classId) {
    const names = { knight: "Knight", ranger: "Ranger", arcanist: "Arcanist", raider: "Raider" };
    return names[id] || "Knight";
  }

  _classSkillInfo(key, classId = this.hero?.classId || "knight") {
    const info = {
      knight: {
        w: "Nova radius +14%",
        e: "Blink grants longer guard",
      },
      ranger: {
        q: "Spark speed +14%",
        e: "Blink distance +18%",
      },
      arcanist: {
        q: "Spark damage +12%",
        w: "Nova radius +20%",
        r: "Orb damage +16%",
      },
      raider: {
        q: "Spark damage +8%",
        e: "Blink distance +24%",
        r: "Orb speed +12%",
      },
    };
    return info[classId]?.[key] || "Balanced scaling";
  }

  _skillUpgradeSummary(key, level = 1) {
    const lines = {
      q: [
        "Single bolt",
        "Single bolt",
        "Single bolt",
        "Single bolt",
        "Two-shot spread",
        "Two-shot spread",
        "Two-shot spread",
        "Two-shot spread",
        "Two-shot spread",
        "Three-shot spread",
      ],
      w: [
        "Close shock ring",
        "Close shock ring",
        "Close shock ring",
        "Close shock ring",
        "Slow shock ring",
        "Slow shock ring",
        "Slow shock ring",
        "Slow shock ring",
        "Slow shock ring",
        "Wide lingering shock ring",
      ],
      e: [
        "Short blink",
        "Short blink",
        "Short blink",
        "Short blink",
        "Long river blink",
        "Long river blink",
        "Long river blink",
        "Long river blink",
        "Long river blink",
        "Blink landing burst",
      ],
      r: [
        "Arcane orb",
        "Arcane orb",
        "Arcane orb",
        "Arcane orb",
        "Piercing orb",
        "Piercing orb",
        "Piercing orb",
        "Piercing orb",
        "Piercing orb",
        "Bursting orb",
      ],
    };
    const bucket = lines[key] || [];
    return bucket[Math.max(0, Math.min(bucket.length - 1, (level | 0) - 1))] || "Balanced scaling";
  }

  _usePotion(kind) {
    if (!this.hero?.potions) return false;
    if ((this.hero.potions[kind] || 0) <= 0) return false;

    if (kind === "hp") {
      if ((this.hero.hp || 0) >= (this.hero.maxHp || 1)) return false;
      this.hero.hp = Math.min(this.hero.maxHp, this.hero.hp + 38);
      this.hero.potions.hp -= 1;
      this._msg("Health potion", 1.1);
      return true;
    }

    if (kind === "mana") {
      if ((this.hero.mana || 0) >= (this.hero.maxMana || 1)) return false;
      this.hero.mana = Math.min(this.hero.maxMana, this.hero.mana + 30);
      this.hero.potions.mana -= 1;
      this._msg("Mana potion", 1.1);
      return true;
    }

    return false;
  }

  _castSpark() {
    if (this.cooldowns.q > 0) return;
    const def = this.skillDefs.q;
    if (!this.hero.spendMana(def.mana)) return;

    this.cooldowns.q = def.cd;

    const dir = norm(this.hero.aimDir?.x || 1, this.hero.aimDir?.y || 0);
    const sparkLevel = Math.max(1, this.skillProg.q?.level || 1);
    const hit = this._rollHeroDamage((this.hero.classId === "arcanist" ? 1.06 : this.hero.classId === "raider" ? 1.02 : 0.95));
    const sparkSpeed = (this.hero.classId === "ranger" ? 308 : 270) * (1 + Math.min(0.12, Math.floor((sparkLevel - 1) / 5) * 0.06));
    const pierce = sparkLevel >= 10 ? 1 : 0;
    const shotCount = sparkLevel >= 10 ? 3 : sparkLevel >= 5 ? 2 : 1;
    const angles = shotCount === 3 ? [0, -0.18, 0.18] : shotCount === 2 ? [-0.09, 0.09] : [0];

    for (const angleOffset of angles) {
      const ca = Math.cos(angleOffset);
      const sa = Math.sin(angleOffset);
      const vx = dir.x * ca - dir.y * sa;
      const vy = dir.x * sa + dir.y * ca;
      this.projectiles.push(
        new Projectile(
          this.hero.x + vx * 18,
          this.hero.y + vy * 18,
          vx * sparkSpeed,
          vy * sparkSpeed,
          hit.dmg,
          1.25 + (sparkLevel >= 10 ? 0.12 : 0),
          this.hero.level,
          { friendly: true, color: "rgba(148,225,255,0.95)", radius: 4, hitRadius: 15, pierce }
        )
      );
      this.projectiles[this.projectiles.length - 1].crit = hit.crit;
    }

    this.skillProg.q.xp += 1;
    this._checkSkillLevel("q");
  }

  _castNova() {
    if (this.cooldowns.w > 0) return;
    const def = this.skillDefs.w;
    if (!this.hero.spendMana(def.mana)) return;

    this.cooldowns.w = def.cd;

    const novaLevel = Math.max(1, this.skillProg.w?.level || 1);
    const hit = this._rollHeroDamage(this.hero.classId === "arcanist" ? 1.18 : 1.1);
    const baseRadius = this.hero.classId === "arcanist" ? 103 : this.hero.classId === "knight" ? 98 : 86;
    const novaRadius = baseRadius + (novaLevel >= 10 ? 34 : novaLevel >= 5 ? 16 : 0);
    const slow = novaLevel >= 10 ? 0.65 : novaLevel >= 5 ? 0.42 : 0;
    const novaLife = novaLevel >= 10 ? 0.6 : novaLevel >= 5 ? 0.5 : 0.45;
    const knockback = novaLevel >= 10 ? 96 : 0;

    this.projectiles.push(
      new Projectile(
        this.hero.x,
        this.hero.y,
        0,
        0,
        hit.dmg,
        novaLife,
        this.hero.level,
        {
          friendly: true,
          nova: true,
          color: "rgba(214,245,255,0.92)",
          radius: 14,
          hitRadius: novaRadius,
          ignoreWalls: true,
          slow,
          knockback,
        }
      )
    );
    this.projectiles[this.projectiles.length - 1].crit = hit.crit;

    this.skillProg.w.xp += 2;
    this._checkSkillLevel("w");
  }

  _castBlink() {
    if (this.cooldowns.e > 0) return;
    const def = this.skillDefs.e;
    if (!this.hero.spendMana(def.mana)) return;

    this.cooldowns.e = def.cd;

    const dir = norm(
      this.hero.aimDir?.x || this.hero.lastMove?.x || 1,
      this.hero.aimDir?.y || this.hero.lastMove?.y || 0
    );

    const blinkLevel = Math.max(1, this.skillProg.e?.level || 1);
    const classDashMul = this.hero.classId === "raider" ? 1.24 : this.hero.classId === "ranger" ? 1.18 : 1;
    const dashDist = (blinkLevel >= 10 ? 182 : blinkLevel >= 5 ? 122 : 68) * classDashMul;
    const tx = this.hero.x + dir.x * dashDist;
    const ty = this.hero.y + dir.y * dashDist;
    this._blinkLanding = null;

    if (this._canDashTo(tx, ty, dir, dashDist, blinkLevel)) {
      this.hero.x = this._blinkLanding?.x ?? tx;
      this.hero.y = this._blinkLanding?.y ?? ty;
      if (blinkLevel >= 5 && !this.dungeon.active) this._spawnFloatingText(this.hero.x, this.hero.y - 28, "River blink", "#ffd36e");
      if (blinkLevel >= 10) {
        const burstDmg = Math.max(1, Math.round((this.hero.getStats?.().dmg || 8) * 0.8));
        this._spawnSpellBurst(this.hero.x, this.hero.y, 72, burstDmg, "rgba(255,211,110,0.88)", {
          life: 0.26,
          slow: 0.35,
        });
      }
    }
    this._blinkLanding = null;

    this.hero.state.dashT = (0.20 + Math.min(0.18, (blinkLevel - 1) * 0.02)) + (this.hero.classId === "knight" ? 0.08 : 0);
    this.skillProg.e.xp += 2;
    this._checkSkillLevel("e");
  }

  _canDashTo(tx, ty, dir, dashDist, dashLevel) {
    if (this.dungeon.active) return this._canMoveInDungeon(tx, ty);

    const canCrossWater = dashLevel >= 5;
    const steps = Math.max(2, Math.ceil(dashDist / 22));
    for (let i = 1; i <= steps; i++) {
      const px = this.hero.x + dir.x * dashDist * (i / steps);
      const py = this.hero.y + dir.y * dashDist * (i / steps);
      const s = this.world._sampleCell?.(px, py);
      if (!s) return false;
      if (s.isWater && !s.bridge && !canCrossWater) return false;
      if (!s.isWater && !this.world.canWalk(px, py, this.hero)) return false;
    }

    if (this.world.canWalk(tx, ty, this.hero)) return true;
    if (canCrossWater && this.world?._findSafeLandPatchNear) {
      const safe = this.world._findSafeLandPatchNear(tx, ty, 72);
      if (safe && this.world.canWalk(safe.x, safe.y, this.hero)) {
        tx = safe.x;
        ty = safe.y;
        this._blinkLanding = safe;
        return true;
      }
    }
    return false;
  }

  _drawDungeonRoom(ctx) {
    const layout = this.dungeon.layout;
    const room = this._getDungeonRoom() || { x: this.hero.x, y: this.hero.y, w: 780, h: 540, type: "hall" };
    const theme = this._dungeonTheme(Math.max(1, this.dungeon.floor || 1));
    const aliveCount = this._dungeonHasLivingEnemies(room.id) ? this.enemies.filter((e) => e?.alive && e.dungeonRoomId === room.id).length : 0;
    const currentClear = room.cleared || aliveCount <= 0;

    ctx.save();
    ctx.fillStyle = "#0d1015";
    ctx.fillRect(this.hero.x - 1800, this.hero.y - 1400, 3600, 2800);

    for (const rect of layout?.corridors || []) {
      const gx = rect.x - rect.w * 0.5;
      const gy = rect.y - rect.h * 0.5;
      this._drawDungeonStoneFloor(ctx, gx, gy, rect.w, rect.h, theme, rect, rect.orientation === "h" ? 0.92 : 0.88);
      this._drawDungeonCorridorWalls(ctx, rect, theme);
      this._drawDungeonGrime(ctx, gx, gy, rect.w, rect.h, rect.seed || rect.id || `${rect.x}|${rect.y}`);
      this._drawDungeonDecor(ctx, rect.decor, theme);
    }

    for (const r of layout?.rooms || []) {
      const gx = r.x - r.w * 0.5;
      const gy = r.y - r.h * 0.5;
      const bossRoom = r.type === "boss";
      this._drawDungeonStoneFloor(ctx, gx, gy, r.w, r.h, theme, r, bossRoom ? 1.02 : r === room ? 0.96 : 0.90);
      this._drawDungeonGrime(ctx, gx, gy, r.w, r.h, r.id || `${r.x}|${r.y}`);

      this._drawDungeonDecor(ctx, r.decor, theme);
      this._drawDungeonRoomWalls(ctx, r, theme, r === room);

      ctx.strokeStyle = r === room ? "rgba(182,144,96,0.24)" : bossRoom ? "rgba(255,138,92,0.24)" : "rgba(255,255,255,0.04)";
      ctx.lineWidth = r === room ? 3 : 2;
      ctx.strokeRect(gx + 8, gy + 8, r.w - 16, r.h - 16);

      ctx.fillStyle = "rgba(233,223,206,0.84)";
      ctx.font = "bold 11px Arial";
      ctx.textAlign = "left";
      ctx.fillText(this._titleCase(r.type), gx + 28, gy + 28);

      if (r.type !== "start" && !r.cacheOpened && ["loot", "key", "shrine"].includes(r.type)) {
        const cache = this._getDungeonRoomCacheAnchor(r);
        ctx.fillStyle = r.type === "key" ? "rgba(139,233,255,0.18)" : r.type === "loot" ? "rgba(255,214,110,0.18)" : "rgba(160,255,176,0.16)";
        ctx.fillRect(cache.x - 18, cache.y - 12, 36, 24);
        ctx.strokeStyle = r.type === "key" ? "#d7c18a" : r.type === "loot" ? "#ffd86e" : "#b8f59e";
        ctx.lineWidth = 2;
        ctx.strokeRect(cache.x - 17.5, cache.y - 11.5, 35, 23);
        ctx.fillStyle = "#f4fbff";
        ctx.font = "bold 10px Arial";
        ctx.textAlign = "center";
        ctx.fillText(r.type === "key" ? "KEY" : r.type === "loot" ? "CACHE" : "RELIC", cache.x, cache.y + 4);
      }
    }

    for (const door of layout?.doors || []) {
      const blocker = door.blocker || { x: door.x, y: door.y, w: 16, h: 16 };
      const frameW = door.vertical ? 28 : Math.max(22, (door.frameSpan || blocker.w || 22) + 12);
      const frameH = door.vertical ? Math.max(22, (door.frameSpan || blocker.h || 58) + 12) : 28;
      const leafW = door.vertical ? 16 : Math.max(18, frameW - 14);
      const leafH = door.vertical ? Math.max(18, frameH - 14) : 16;
      const frameX = door.vertical ? blocker.x : door.x;
      const frameY = door.vertical ? door.y : blocker.y;
      ctx.fillStyle = "rgba(18,13,20,0.98)";
      ctx.fillRect(frameX - frameW * 0.5, frameY - frameH * 0.5, frameW, frameH);
      ctx.strokeStyle = door.locked === "key" ? "#ffd86e" : door.open ? "#caa46b" : "#9a8674";
      ctx.lineWidth = 2.5;
      ctx.strokeRect(frameX - frameW * 0.5 + 0.5, frameY - frameH * 0.5 + 0.5, frameW - 1, frameH - 1);
      ctx.fillStyle = "rgba(74,56,39,0.96)";
      if (door.vertical) {
        ctx.fillRect(frameX - frameW * 0.5 + 4, frameY - frameH * 0.5, 5, frameH);
        ctx.fillRect(frameX + frameW * 0.5 - 9, frameY - frameH * 0.5, 5, frameH);
      } else {
        ctx.fillRect(frameX - frameW * 0.5, frameY - frameH * 0.5 + 4, frameW, 5);
        ctx.fillRect(frameX - frameW * 0.5, frameY + frameH * 0.5 - 9, frameW, 5);
      }

      if (!door.open) {
        ctx.fillStyle = door.locked === "key" ? "rgba(126,84,26,0.95)" : "rgba(83,56,38,0.95)";
        ctx.fillRect(blocker.x - blocker.w * 0.5, blocker.y - blocker.h * 0.5, blocker.w, blocker.h);
        ctx.strokeStyle = door.locked === "key" ? "#ffd86e" : "#c8a27d";
        ctx.lineWidth = 1.5;
        ctx.strokeRect(blocker.x - blocker.w * 0.5 + 0.5, blocker.y - blocker.h * 0.5 + 0.5, blocker.w - 1, blocker.h - 1);
        if (door.vertical) {
          ctx.beginPath();
          ctx.moveTo(blocker.x, blocker.y - blocker.h * 0.5 + 3);
          ctx.lineTo(blocker.x, blocker.y + blocker.h * 0.5 - 3);
          ctx.stroke();
        } else {
          ctx.beginPath();
          ctx.moveTo(blocker.x - blocker.w * 0.5 + 3, blocker.y);
          ctx.lineTo(blocker.x + blocker.w * 0.5 - 3, blocker.y);
          ctx.stroke();
        }
      } else {
        ctx.fillStyle = "rgba(212,182,128,0.07)";
        ctx.fillRect(blocker.x - blocker.w * 0.5, blocker.y - blocker.h * 0.5, blocker.w, blocker.h);
      }

      ctx.fillStyle = door.open ? "rgba(244,226,188,0.76)" : door.locked === "key" ? "#ffe6a8" : "#d8c2b0";
      ctx.font = "bold 9px Arial";
      ctx.textAlign = "center";
      const labelY = door.vertical ? frameY - frameH * 0.5 - 8 : frameY - 13;
      ctx.fillText(door.open ? "OPEN" : door.locked === "key" ? "KEY" : "SEALED", frameX, labelY);
    }

    const ret = layout?.returnStair;
    if (ret) {
      ctx.fillStyle = "rgba(137,206,255,0.16)";
      ctx.beginPath();
      ctx.arc(ret.x, ret.y, 28, 0, Math.PI * 2);
      ctx.fill();
      ctx.strokeStyle = "#8be9ff";
      ctx.lineWidth = 2;
      ctx.beginPath();
      ctx.arc(ret.x, ret.y, 16, 0, Math.PI * 2);
      ctx.stroke();
      ctx.fillStyle = "#f0fbff";
      ctx.font = "bold 10px Arial";
      ctx.textAlign = "center";
      ctx.fillText("OUT", ret.x, ret.y + 3);
    }

    const exit = layout?.exitStair;
    if (exit) {
      ctx.fillStyle = currentClear && room.type === "boss" ? "rgba(255,211,110,0.20)" : "rgba(44,34,24,0.85)";
      ctx.beginPath();
      ctx.arc(exit.x, exit.y, 30, 0, Math.PI * 2);
      ctx.fill();
      ctx.strokeStyle = currentClear && room.type === "boss" ? "#ffd86e" : "rgba(255,255,255,0.12)";
      ctx.lineWidth = 2;
      ctx.beginPath();
      ctx.arc(exit.x, exit.y, 18, 0, Math.PI * 2);
      ctx.stroke();
      ctx.fillStyle = currentClear && room.type === "boss" ? "#fff1c8" : "#7f8a97";
      ctx.font = "bold 10px Arial";
      ctx.textAlign = "center";
      ctx.fillText("DOWN", exit.x, exit.y + 3);
    }

    ctx.fillStyle = "rgba(240,226,255,0.90)";
    ctx.font = "bold 13px Arial";
    ctx.textAlign = "center";
    ctx.fillText(`${theme.name}  Floor ${this.dungeon.floor}  Keys ${this.dungeon.keys || 0}`, room.x, room.y + room.h * 0.5 - 18);
    ctx.font = "11px Arial";
    ctx.fillStyle = "rgba(214,225,239,0.78)";
    const detail = !currentClear
      ? `${aliveCount} enemies remain in this room`
      : room.type === "boss"
      ? "Boss room cleared. Use DOWN to go deeper or OUT to leave."
      : "Room clear. Search caches and open doors.";
    ctx.fillText(detail, room.x, room.y + room.h * 0.5 - 36);
    ctx.restore();
  }

  _dungeonTheme(floor = 1) {
    const themes = [
      {
        name: "Ash Crypt",
        floor0: "#28262b",
        floor1: "#1d1d23",
        floor2: "#12151b",
        haze: "rgba(255,137,86,0.038)",
        accent: "rgba(255,152,104,0.28)",
        propA: "#4e3f3b",
        propB: "#35363f",
        enemies: ["ashling", "brute", "wisp", "sentinel"],
      },
      {
        name: "Moon Vault",
        floor0: "#202a38",
        floor1: "#171e2d",
        floor2: "#101722",
        haze: "rgba(126,224,255,0.04)",
        accent: "rgba(126,224,255,0.30)",
        propA: "#38465a",
        propB: "#263140",
        enemies: ["wisp", "caster", "duelist", "mender"],
      },
      {
        name: "Root Hall",
        floor0: "#253225",
        floor1: "#19251c",
        floor2: "#111914",
        haze: "rgba(128,218,91,0.04)",
        accent: "rgba(143,222,122,0.28)",
        propA: "#3e5638",
        propB: "#2f3e32",
        enemies: ["thorn", "wolf", "mender", "stalker"],
      },
      {
        name: "Iron Sepulcher",
        floor0: "#2a2d33",
        floor1: "#1d2027",
        floor2: "#12161d",
        haze: "rgba(200,192,162,0.035)",
        accent: "rgba(200,192,162,0.30)",
        propA: "#4b5260",
        propB: "#343a44",
        enemies: ["sentinel", "brute", "duelist", "caster"],
      },
    ];
    return themes[Math.abs((floor | 0) - 1) % themes.length];
  }

  _castOrb() {
    if (this.cooldowns.r > 0) return;
    const def = this.skillDefs.r;
    if (!this.hero.spendMana(def.mana)) return;

    this.cooldowns.r = def.cd;

    const orbLevel = Math.max(1, this.skillProg.r?.level || 1);
    const dir = norm(this.hero.aimDir?.x || 1, this.hero.aimDir?.y || 0);
    const hit = this._rollHeroDamage(this.hero.classId === "arcanist" ? 1.92 : 1.65);
    const orbSpeed = (this.hero.classId === "raider" ? 196 : 175) + (orbLevel >= 10 ? 28 : orbLevel >= 5 ? 14 : 0);
    const orbPierce = orbLevel >= 10 ? 2 : orbLevel >= 5 ? 1 : 0;
    const burstRadius = orbLevel >= 10 ? 72 : orbLevel >= 5 ? 0 : 0;

    this.projectiles.push(
      new Projectile(
        this.hero.x + dir.x * 22,
        this.hero.y + dir.y * 22,
        dir.x * orbSpeed,
        dir.y * orbSpeed,
        hit.dmg,
        1.7 + (orbLevel >= 3 ? 0.18 : 0),
        this.hero.level,
        {
          friendly: true,
          color: "rgba(198,140,255,0.95)",
          radius: 8 + (orbLevel >= 5 ? 1 : 0),
          hitRadius: 20 + (orbLevel >= 5 ? 4 : 0),
          pierce: orbPierce,
          burstRadius,
          burstColor: "rgba(214,176,255,0.92)",
          burstSlow: orbLevel >= 10 ? 0.55 : 0.35,
        }
      )
    );
    this.projectiles[this.projectiles.length - 1].crit = hit.crit;

    this.skillProg.r.xp += 3;
    this._checkSkillLevel("r");
  }

  _spawnSpellBurst(x, y, hitRadius, dmg, color, opts = {}) {
    this.projectiles.push(
      new Projectile(
        x,
        y,
        0,
        0,
        dmg,
        opts.life || 0.32,
        this.hero.level,
        {
          friendly: true,
          nova: true,
          color: color || "rgba(214,245,255,0.92)",
          radius: opts.radius || 12,
          hitRadius,
          ignoreWalls: true,
          slow: opts.slow || 0,
        }
      )
    );
  }

  _rollHeroDamage(mult = 1) {
    const stats = this.hero.getStats?.() || {};
    const crit = Math.random() < clamp(stats.crit || 0.05, 0, 0.85);
    const critMult = crit ? Math.max(1.1, stats.critMult || 1.6) : 1;
    return {
      dmg: Math.max(1, Math.round((stats.dmg || 8) * mult * critMult)),
      crit,
    };
  }

  _checkSkillLevel(key) {
    const s = this.skillProg[key];
    if (!s) return;
    const need = 10 + (s.level - 1) * 8;
    if (s.xp >= need) {
      s.xp -= need;
      s.level += 1;
      const name = this.skillDefs[key]?.name || "Skill";
      this._spawnFloatingText(this.hero.x, this.hero.y - 54, `${name} Lv ${s.level}`, this.skillDefs[key]?.color || "#b7ceff");
      this._msg(`${name} upgraded to Lv ${s.level}`, 1.5);
    }
  }

  _checkHeroLevelFeedback() {
    const level = this.hero.level || 1;
    const prev = this._lastHeroLevel || level;
    if (level <= prev) {
      this._lastHeroLevel = level;
      return;
    }

    this._lastHeroLevel = level;
    this._killFlashT = Math.max(this._killFlashT || 0, 0.5);
    this._spawnFloatingText(this.hero.x, this.hero.y - 72, `LEVEL ${level}`, "#ffd86e");
    this._msg(`Level up! Lv ${level} - HP and Mana restored`, 2.2);
  }

  _spawnInitialEnemies() {
    const camps = (this.world.camps || [])
      .map((camp) => ({ camp, d: dist2(this.hero.x, this.hero.y, camp.x, camp.y) }))
      .filter((v) => v.d > 560 * 560)
      .sort((a, b) => a.d - b.d)
      .slice(0, 3)
      .map((v) => v.camp);

    for (const camp of camps) {
      for (let i = 0; i < 3; i++) {
        const enemy = this._spawnEnemyNearCamp(camp, i);
        if (enemy) this.enemies.push(enemy);
      }
    }

    const pool = ["wolf", "scout", "thorn", "duelist"];
    for (let i = 0; i < 5; i++) {
      const ang = (i / 5) * Math.PI * 2;
      const rr = 860 + (i % 3) * 90;
      const x = this.hero.x + Math.cos(ang) * rr;
      const y = this.hero.y + Math.sin(ang) * rr;

      if (!this.world.canWalk(x, y)) continue;

      const kind = pool[i % pool.length];
      const enemy = new Enemy(x, y, Math.max(1, this.hero.level), kind, hash2(x | 0, y | 0, this.seed), false, false);
      this.enemies.push(enemy);
    }
  }

  _pickEnemyKind(zone) {
    const z = String(zone || "").toLowerCase();
    if (z.includes("dungeon")) {
      const pool = ["stalker", "caster", "brute", "ashling", "wolf", "wisp", "duelist", "sentinel", "mender"];
      return pool[Math.floor(Math.random() * pool.length)] || "stalker";
    }
    if (z.includes("wild")) return this._pickFrom(["wolf", "stalker", "thorn", "duelist"]);
    if (z.includes("stone")) return this._pickFrom(["brute", "sentinel", "blob", "wisp"]);
    if (z.includes("ash")) return this._pickFrom(["ashling", "brute", "wisp", "sentinel"]);
    if (z.includes("shore")) return this._pickFrom(["scout", "caster", "wisp", "thorn"]);
    if (z.includes("forest") || z.includes("greenwood")) return this._pickFrom(["wolf", "scout", "thorn", "mender"]);

    const pool = ["blob", "wolf", "stalker", "scout", "caster", "brute", "wisp", "thorn", "duelist"];
    return pool[(Math.random() * pool.length) | 0];
  }

  _pickFrom(pool) {
    return pool[(Math.random() * pool.length) | 0] || pool[0] || "blob";
  }

  _campEnemyPool(camp) {
    const type = String(camp?.type || "").toLowerCase();
    if (type === "bandit") return ["scout", "duelist", "caster", "brute", "mender"];
    if (type === "beast") return ["wolf", "stalker", "thorn", "wisp"];
    if (type === "cult") return ["ashling", "caster", "wisp", "mender", "brute"];
    if (type === "wild") return ["thorn", "wolf", "scout", "mender"];
    if (type === "stone") return ["sentinel", "brute", "wisp", "caster"];
    return ["scout", "wolf", "thorn", "duelist", "mender", "sentinel", "caster"];
  }

  _spawnWorldEnemies(dt) {
    this._spawnTimer -= dt;
    if (this._spawnTimer > 0) return;
    this._spawnTimer = 1.25;

    if (this.enemies.length >= this.perf.maxEnemies) return;
    if (this.dungeon.active) return;
    if (Math.random() > 0.34) return;

    const camp = this._nearest(this.world.camps, (p) => {
      const d2 = dist2(this.hero.x, this.hero.y, p.x, p.y);
      return d2 > 520 * 520 && d2 < 1800 * 1800;
    });
    if (!camp) {
      const roaming = this._spawnRoamingEnemyNearHero();
      if (roaming) this.enemies.push(roaming);
      return;
    }

    let tries = 0;
    while (tries++ < 5 && this.enemies.length < this.perf.maxEnemies) {
      const e = this._spawnEnemyNearCamp(camp, tries);
      if (!e) continue;
      this.enemies.push(e);
      break;
    }
  }

  _respawnCampEnemies(dt) {
    this._campRespawnT -= dt;
    if (this._campRespawnT > 0) return;
    this._campRespawnT = 5.5;

    const campCounts = this._countEnemiesNearCamps(260);

    for (const camp of this.world.camps || []) {
      if (this.enemies.length >= this.perf.maxEnemies) return;
      const heroD2 = dist2(this.hero.x, this.hero.y, camp.x, camp.y);
      if (heroD2 < 360 * 360 || heroD2 > 2200 * 2200) continue;

      const nearCount = campCounts.get(camp) || 0;
      const targetCount = heroD2 < 1200 * 1200 ? 4 : 2;
      if (nearCount >= targetCount) continue;

      const e = this._spawnEnemyNearCamp(camp, nearCount);
      if (e) {
        this.enemies.push(e);
        campCounts.set(camp, nearCount + 1);
      }
    }
  }

  _countEnemiesNearCamps(radius = 260) {
    const camps = this.world?.camps || [];
    const counts = new Map();
    if (!camps.length || !this.enemies.length) return counts;

    const r2 = radius * radius;
    for (const e of this.enemies) {
      if (!e?.alive) continue;
      for (const camp of camps) {
        if (dist2(e.x, e.y, camp.x, camp.y) <= r2) {
          counts.set(camp, (counts.get(camp) || 0) + 1);
          break;
        }
      }
    }
    return counts;
  }

  _spawnEnemyNearCamp(camp, salt = 0) {
    if (!camp) return null;

    const kinds = this._campEnemyPool(camp);
    for (let tries = 0; tries < 8; tries++) {
      const ang = Math.random() * Math.PI * 2;
      const rr = 125 + Math.random() * 150;
      const x = camp.x + Math.cos(ang) * rr;
      const y = camp.y + Math.sin(ang) * rr;
      if (!this.world.canWalk?.(x, y)) continue;
      if (dist2(x, y, this.world.spawn?.x || 0, this.world.spawn?.y || 0) < this.perf.worldSpawnSafeRadius ** 2) continue;

      const areaLevel = this.world.getDangerLevel?.(x, y) || 1;
      const kind = kinds[(Math.abs(hash2(camp.id || 0, salt + tries, this.seed)) % kinds.length)] || "scout";
      const elite = Math.random() < 0.06;
      const level = Math.max(1, (this.hero.level || 1) + areaLevel - 1);
      return this._applyEnemyAffix(
        new Enemy(x, y, level, kind, hash2(x | 0, y | 0, this.seed + salt), elite, false)
      );
    }

    return null;
  }

  _spawnRoamingEnemyNearHero() {
    const minDist = this.perf.spawnMinDistance || 840;
    const maxDist = this.perf.spawnMaxDistance || 1360;
    const enemySpacing2 = 170 * 170;
    for (let tries = 0; tries < 10; tries++) {
      const ang = Math.random() * Math.PI * 2;
      const rr = minDist + Math.random() * (maxDist - minDist);
      const x = this.hero.x + Math.cos(ang) * rr;
      const y = this.hero.y + Math.sin(ang) * rr;
      if (!this.world.canWalk?.(x, y)) continue;
      if (dist2(x, y, this.world.spawn?.x || 0, this.world.spawn?.y || 0) < this.perf.worldSpawnSafeRadius ** 2) continue;
      let tooClose = false;
      for (const e of this.enemies) {
        if (!e?.alive) continue;
        if (dist2(x, y, e.x, e.y) < enemySpacing2) {
          tooClose = true;
          break;
        }
      }
      if (tooClose) continue;
      const zone = this.world.getZoneName?.(x, y) || this.world.getZoneInfo?.(x, y)?.name || "";
      const areaLevel = this.world.getDangerLevel?.(x, y) || 1;
      const kind = this._pickEnemyKind(zone);
      const eliteChance = areaLevel >= 4 ? 0.08 : areaLevel >= 3 ? 0.05 : 0.03;
      const elite = Math.random() < eliteChance;
      const level = Math.max(1, (this.hero.level || 1) + areaLevel - 1);
      return this._applyEnemyAffix(
        new Enemy(x, y, level, kind, hash2(x | 0, y | 0, this.seed + 911 + tries), elite, false)
      );
    }
    return null;
  }

  _applyEnemyAffix(e) {
    if (!e?.elite && !e?.boss) return e;

    const affixes = [
      { name: "Ironhide", color: "#d6c48a", hp: 1.22, speed: 0.92, touch: 1.08 },
      { name: "Bloodbound", color: "#ff6f86", hp: 1.10, speed: 1.08, touch: 1.18 },
      { name: "Stormmarked", color: "#87d8ff", hp: 1.04, speed: 1.20, touch: 1.04 },
      { name: "Gilded", color: "#ffd76a", hp: 1.14, speed: 1.00, touch: 1.10, loot: 6 },
    ];
    const affix = affixes[Math.abs(e.seed || 0) % affixes.length];

    e.affix = affix.name;
    e.colorA = affix.color;
    e.hp = Math.round(e.hp * affix.hp);
    e.maxHp = e.hp;
    e.moveSpeed = Math.max(16, Math.round(e.moveSpeed * affix.speed));
    e.speed = e.moveSpeed;
    e.touchDps = Math.max(1, Math.round(e.touchDps * affix.touch));
    e.extraLoot = affix.loot || 0;
    return e;
  }

  _updateEnemies(dt) {
    this._touchDamageCd = Math.max(0, this._touchDamageCd - dt);
    const updateD2 = this.dungeon.active ? Infinity : (this.perf.enemyUpdateRadius || 1200) ** 2;
    const logicD2 = this.dungeon.active ? Infinity : (this.perf.enemyLogicRadius || 720) ** 2;
    const closeD2 = this.dungeon.active ? Infinity : 220 ** 2;
    const crowdHeavy = this.enemies.length > 16;

    for (let idx = 0; idx < this.enemies.length; idx++) {
      const e = this.enemies[idx];
      if (!e?.alive) continue;
      const heroD2 = dist2(e.x, e.y, this.hero.x, this.hero.y);
      if (heroD2 > updateD2) continue;
      if (heroD2 > logicD2) {
        e.attackCd = Math.max(0, (e.attackCd || 0) - dt);
        e.rangedCd = Math.max(0, (e.rangedCd || 0) - dt);
        e.lungeT = Math.max(0, (e.lungeT || 0) - dt);
        e.recoverT = Math.max(0, (e.recoverT || 0) - dt);
        e.specialCd = Math.max(0, (e.specialCd || 0) - dt);
        e.hitFlashT = Math.max(0, (e.hitFlashT || 0) - dt);
        e.staggerT = Math.max(0, (e.staggerT || 0) - dt);
        e.slowT = Math.max(0, (e.slowT || 0) - dt);
        e.alertT = Math.max(0, (e.alertT || 0) - dt);
        e.contactCd = Math.max(0, (e.contactCd || 0) - dt);
        e.patrolTimer = Math.max(-0.5, (e.patrolTimer || 0) - dt);
        continue;
      }
      if (!this.dungeon.active && heroD2 > closeD2) {
        const midSkip = ((idx + this._simPhase) & 1) !== 0;
        const farSkip = ((idx + this._simPhase) & 3) !== 0;
        const shouldSkip =
          heroD2 > logicD2 * 0.58
            ? farSkip
            : crowdHeavy && midSkip;
        if (shouldSkip) {
          e.attackCd = Math.max(0, (e.attackCd || 0) - dt);
          e.rangedCd = Math.max(0, (e.rangedCd || 0) - dt);
          e.lungeT = Math.max(0, (e.lungeT || 0) - dt);
          e.recoverT = Math.max(0, (e.recoverT || 0) - dt);
          e.specialCd = Math.max(0, (e.specialCd || 0) - dt);
          e.hitFlashT = Math.max(0, (e.hitFlashT || 0) - dt);
          e.staggerT = Math.max(0, (e.staggerT || 0) - dt);
          e.slowT = Math.max(0, (e.slowT || 0) - dt);
          e.alertT = Math.max(0, (e.alertT || 0) - dt);
          e.contactCd = Math.max(0, (e.contactCd || 0) - dt);
          continue;
        }
      }
      if (crowdHeavy && heroD2 > 180 * 180 && ((idx + this._simPhase) & 1) !== 0) {
        e.attackCd = Math.max(0, (e.attackCd || 0) - dt);
        e.rangedCd = Math.max(0, (e.rangedCd || 0) - dt);
        e.lungeT = Math.max(0, (e.lungeT || 0) - dt);
        e.recoverT = Math.max(0, (e.recoverT || 0) - dt);
        e.specialCd = Math.max(0, (e.specialCd || 0) - dt);
        e.hitFlashT = Math.max(0, (e.hitFlashT || 0) - dt);
        e.staggerT = Math.max(0, (e.staggerT || 0) - dt);
        e.slowT = Math.max(0, (e.slowT || 0) - dt);
        e.alertT = Math.max(0, (e.alertT || 0) - dt);
        e.contactCd = Math.max(0, (e.contactCd || 0) - dt);
        continue;
      }
      e.update?.(dt, this.hero, this.world, this);
      this._resolveEnemyHeroHitbox(e);
      e.contactCd = Math.max(0, (e.contactCd || 0) - dt);

      const rr = (this.hero.radius || this.hero.r || 12) + (e.radius || e.r || 12);
      if (dist2(this.hero.x, this.hero.y, e.x, e.y) <= rr * rr) {
        const meleeActive = (e.kind === "caster" || e.kind === "dragon") || (e.lungeT || 0) > 0 || (e.attackCd || 0) <= 0.04;
        if (meleeActive && this._touchDamageCd <= 0 && (e.contactCd || 0) <= 0) {
          const hurt = this._damageHero(e.touchDps || 1);
          if (hurt) e.contactCd = e.boss ? 0.28 : e.elite ? 0.42 : 0.56;
          this._touchDamageCd = this.perf.touchDamageTick;
        }
      }
    }

    this._enemyCrowdResolveT -= dt;
    if (this._enemyCrowdResolveT <= 0) {
      this._enemyCrowdResolveT = this.enemies.length > 14 ? 0.18 : 0.12;
      this._resolveEnemyCrowding();
    }

    let write = 0;
    for (let i = 0; i < this.enemies.length; i++) {
      const e = this.enemies[i];
      if (!e?.alive) continue;
      this.enemies[write++] = e;
    }
    this.enemies.length = write;
  }

  _resolveEnemyHeroHitbox(e) {
    if (!e?.alive || !this.hero) return;
    const hr = this.hero.radius || this.hero.r || 12;
    const er = e.radius || e.r || 12;
    const minD = Math.max(16, hr + er - 3);
    const dx = e.x - this.hero.x;
    const dy = e.y - this.hero.y;
    const d = Math.hypot(dx, dy) || 0.001;
    if (d >= minD) return;

    const push = (minD - d) * 0.72;
    const nx = dx / d;
    const ny = dy / d;
    const tx = e.x + nx * push;
    const ty = e.y + ny * push;

    if (this._entityCanMoveTo(tx, e.y)) e.x = tx;
    if (this._entityCanMoveTo(e.x, ty)) e.y = ty;
  }

  _resolveEnemyCrowding() {
    const alive = this._activeEnemies?.length ? this._activeEnemies : this.enemies.filter((e) => e?.alive);
    const limit = Math.min(alive.length, 34);
    for (let i = 0; i < limit; i++) {
      const a = alive[i];
      for (let j = i + 1; j < limit; j++) {
        const b = alive[j];
        const ar = a.radius || a.r || 12;
        const br = b.radius || b.r || 12;
        const minD = Math.max(14, (ar + br) * 0.72);
        const dx = b.x - a.x;
        const dy = b.y - a.y;
        const d2 = dx * dx + dy * dy;
        if (d2 <= 0.001 || d2 >= minD * minD) continue;

        const d = Math.sqrt(d2);
        const push = (minD - d) * 0.18;
        const nx = dx / d;
        const ny = dy / d;
        const ax = a.x - nx * push;
        const ay = a.y - ny * push;
        const bx = b.x + nx * push;
        const by = b.y + ny * push;

        if (this._entityCanMoveTo(ax, ay)) {
          a.x = ax;
          a.y = ay;
        }
        if (this._entityCanMoveTo(bx, by)) {
          b.x = bx;
          b.y = by;
        }
      }
    }
  }

  _entityCanMoveTo(x, y) {
    if (this.dungeon.active) return this._canMoveInDungeon(x, y);
    return this.world?.canWalk?.(x, y);
  }

  _handleHeroDeath(dt) {
    this._deathCd = Math.max(0, (this._deathCd || 0) - dt);
    if (this.dev?.godMode && (this.hero.hp || 0) <= 0) {
      this.hero.hp = this.hero.maxHp || 100;
      this.hero.mana = this.hero.maxMana || 60;
      return;
    }
    if ((this.hero.hp || 0) > 0 || this._deathCd > 0) return;

    this._deathCd = 2.5;
    const lostGold = Math.min(this.hero.gold || 0, Math.max(0, Math.floor((this.hero.gold || 0) * 0.12)));
    this.hero.gold -= lostGold;

    const safe = this.world._findSafeLandPatchNear?.(this.world.spawn?.x || 0, this.world.spawn?.y || 0, 340) ||
      this.world.spawn ||
      { x: 0, y: 0 };

    this.hero.x = safe.x;
    this.hero.y = safe.y;
    this.hero.vx = 0;
    this.hero.vy = 0;
    this.hero.hp = Math.max(1, Math.round((this.hero.maxHp || 100) * 0.55));
    this.hero.mana = Math.round((this.hero.maxMana || 60) * 0.55);
    this.hero.state.sailing = false;
    this.hero.state.dashT = 0;
    this.hero.state.hurtT = 0.6;
    this.dungeon.active = false;
    this.dungeon.room = null;
    this.camera.x = this.hero.x;
    this.camera.y = this.hero.y;

    this._msg(lostGold > 0 ? `Recovered at camp -${lostGold}g` : "Recovered at camp", 1.8);
  }

  _updateProjectiles(dt) {
    const updateD2 = this.dungeon.active ? Infinity : (this.perf.projectileUpdateRadius || 1400) ** 2;
    const logicD2 = this.dungeon.active ? Infinity : (this.perf.projectileLogicRadius || 900) ** 2;
    const targetEnemies = this._activeEnemies?.length ? this._activeEnemies : this.enemies;
    for (let idx = 0; idx < this.projectiles.length; idx++) {
      const p = this.projectiles[idx];
      if (!p?.alive) continue;
      const heroD2 = dist2(p.x, p.y, this.hero.x, this.hero.y);
      if (heroD2 > updateD2) {
        p.life -= dt;
        if (p.life <= 0) p.alive = false;
        continue;
      }
      if (!this.dungeon.active && heroD2 > logicD2 * 0.8 && ((idx + this._simPhase) & 1) !== 0) {
        p.life -= dt;
        if (p.life <= 0) p.alive = false;
        continue;
      }

      p.update?.(dt, this.world);
      if (!p.alive) {
        if (p.friendly && p.burstRadius && !p._burstDone) {
          p._burstDone = true;
          this._spawnSpellBurst(p.x, p.y, p.burstRadius, Math.max(1, Math.round((p.dmg || 1) * 0.55)), p.burstColor, {
            life: 0.24,
            slow: p.burstSlow || 0,
          });
        }
        continue;
      }

      if (heroD2 > logicD2) continue;

      if (p.friendly) {
        if (p.nova && !p._hitEnemies) p._hitEnemies = new Set();

        for (const e of targetEnemies) {
          if (!e?.alive) continue;
          if (p.nova && p._hitEnemies.has(e)) continue;
          if (Math.abs(e.x - p.x) > 140 || Math.abs(e.y - p.y) > 140) continue;

          const rr = (p.hitRadius || p.radius || 4) + (e.radius || e.r || 12);
          if (dist2(p.x, p.y, e.x, e.y) <= rr * rr) {
            if (p.nova) p._hitEnemies.add(e);
            e.takeDamage?.(p.dmg || 1);
            if (p.slow) e.slowT = Math.max(e.slowT || 0, p.slow);
            if (p.knockback) {
              const away = norm(e.x - p.x, e.y - p.y);
              e.vx = (e.vx || 0) + away.x * p.knockback;
              e.vy = (e.vy || 0) + away.y * p.knockback;
            }
            this._spawnFloatingText(e.x, e.y - 12, p.crit ? `CRIT ${p.dmg || 1}` : `${p.dmg || 1}`, p.crit ? "#ffd86e" : "#ffffff");
            if (!p.nova) {
              if ((p.pierce || 0) > 0) {
                p.pierce -= 1;
              } else {
                p.alive = false;
                if (p.burstRadius) {
                  this._spawnSpellBurst(p.x, p.y, p.burstRadius, Math.max(1, Math.round((p.dmg || 1) * 0.55)), p.burstColor, {
                    life: 0.24,
                    slow: p.burstSlow || 0,
                  });
                }
              }
            }

            if (!e.alive) {
              this.hero.giveXP?.(e.xpValue?.() || 4);
              if (e.kind === "dragon" && e.progressId) {
                this.progress.defeatedDragons.add(e.progressId);
                this.hero.gold += 150 + (e.level || 1) * 12;
                this._awardRelicShards(4, "dragon");
                this._spawnFloatingText(e.x, e.y - 36, "Dragon slain", "#ffb06e");
                this._msg("Dragon slain: legend grows", 2.2);
              }
              this._advanceBounty(e);
              this._dropEnemyLoot(e);
              this._killFlashT = 0.22;
            }
            if (!p.nova && !p.alive) break;
          }
        }
      } else {
        const rr = (p.hitRadius || p.radius || 4) + (this.hero.radius || this.hero.r || 12);
        if (dist2(p.x, p.y, this.hero.x, this.hero.y) <= rr * rr) {
          this._damageHero(p.dmg || 1);
          p.alive = false;
        }
      }
    }

    let write = 0;
    for (let i = 0; i < this.projectiles.length; i++) {
      const p = this.projectiles[i];
      if (!p?.alive) continue;
      this.projectiles[write++] = p;
    }
    this.projectiles.length = write;
  }

  _dropEnemyLoot(e) {
    const goldAmt = Math.max(2, 3 + Math.round((e.level || 1) * 0.8) + (e.lootBonus?.() || 0) + (e.extraLoot || 0));
    this.loot.push(new Loot(e.x, e.y, "gold", { amount: goldAmt }));
    const matYield = { scrap: 0, ore: 0, hide: 0, essence: 0 };
    const kind = String(e.kind || "").toLowerCase();
    if (["wolf", "stalker", "thorn"].includes(kind)) matYield.hide += e.elite ? 2 : 1;
    if (["wisp", "caster", "ashling", "dragon"].includes(kind)) matYield.essence += e.boss ? 3 : e.elite ? 2 : 1;
    if (["brute", "duelist", "sentinel", "scout"].includes(kind)) matYield.scrap += e.elite ? 2 : 1;
    if (["sentinel", "dragon", "brute"].includes(kind)) matYield.ore += e.boss ? 2 : e.elite ? 1 : 0;
    this._grantMaterials(matYield, false);

    const hasLockedKeyDoor = !!this.dungeon?.active && (this.dungeon?.layout?.doors || []).some((door) => !door.open && door.locked === "key");
    if (e?.dungeonRoomId && hasLockedKeyDoor) {
      const keyDropChance = e.boss ? 1 : e.elite ? 0.45 : 0.14;
      if (Math.random() < keyDropChance) {
        this.loot.push(new Loot(e.x + 4, e.y - 6, "key", { label: "Dungeon Key" }));
      }
    }

    if (e.boss || Math.random() < (e.elite ? 0.24 : 0.14)) {
      this.loot.push(new Loot(e.x + 8, e.y, "potion", { potionType: Math.random() < 0.35 ? "mana" : "hp" }));
    }

    if (e.boss || Math.random() < (e.elite ? 0.34 : 0.10)) {
      const slots = EQUIPMENT_SLOTS;
      const slot = slots[(Math.random() * slots.length) | 0];
      const rarity = e.boss
        ? (Math.random() < 0.45 ? "epic" : "rare")
        : e.elite
        ? (Math.random() < 0.12 ? "epic" : Math.random() < 0.52 ? "rare" : "uncommon")
        : (Math.random() < 0.18 ? "rare" : "uncommon");

      const item = makeGear(slot, Math.max(1, e.level || 1), rarity, hash2(e.x | 0, e.y | 0, this.time | 0));
      if (e.boss) item.name = `Boss-Taken ${item.name}`;
      else if (e.elite) item.name = `Elite ${item.name}`;
      this.loot.push(new Loot(e.x - 8, e.y, "gear", item));
    }
  }

  _damageHero(amount) {
    if (this.dev?.godMode) {
      this.hero.hp = this.hero.maxHp || 100;
      this.hero.mana = Math.max(this.hero.mana || 0, Math.min(this.hero.maxMana || 60, this.hero.mana || 0));
      return false;
    }
    const dmg = Math.max(1, Math.round(amount || 1));
    this.hero.takeDamage?.(dmg);
    const state = this.hero.state || (this.hero.state = {});
    state.hurtT = Math.max(state.hurtT || 0, 0.22);
    if (this.time - (this._lastHeroDamageTextT || 0) > 0.28) {
      this._spawnFloatingText(this.hero.x, this.hero.y - 32, `-${dmg}`, "#ff8fa0");
      this._lastHeroDamageTextT = this.time;
    }
    return true;
  }

  _brewPotion(kind) {
    const cost = kind === "mana" ? 4 : 3;
    const label = kind === "mana" ? "mana" : "health";
    if ((this.progress.herbs || 0) < cost) {
      this._msg(`${cost} herbs needed for a ${label} potion`, 0.95);
      return false;
    }
    this.progress.herbs = Math.max(0, (this.progress.herbs || 0) - cost);
    this.hero.potions[kind] = (this.hero.potions[kind] || 0) + 1;
    this._spawnFloatingText(this.hero.x, this.hero.y - 28, kind === "mana" ? "+Mana potion" : "+Health potion", kind === "mana" ? "#88cfff" : "#ff8fa0");
    this._msg(`${label === "mana" ? "Mana" : "Health"} potion brewed`, 1.0);
    return true;
  }

  _updateLoot(dt) {
    const updateD2 = this.dungeon.active ? Infinity : (this.perf.lootUpdateRadius || 820) ** 2;
    for (const l of this.loot) {
      if (!l?.alive) continue;
      if (dist2(l.x, l.y, this.hero.x, this.hero.y) > updateD2) continue;

      const wasAlive = l.alive;
      l.update?.(dt, this.hero);

      if (wasAlive && !l.alive) {
        this._pickupLoot(l);
      }
    }

    let write = 0;
    for (let i = 0; i < this.loot.length; i++) {
      const l = this.loot[i];
      if (!l?.alive) continue;
      this.loot[write++] = l;
    }
    this.loot.length = write;
  }

  _pickupLoot(l) {
    if (l.kind === "gold") {
      this.hero.gold += l.data?.amount || 1;
      this._spawnFloatingText(this.hero.x, this.hero.y - 28, `+${l.data?.amount || 1}g`, "#ffd86e");
      return;
    }

    if (l.kind === "potion") {
      const pt = l.data?.potionType === "mana" ? "mana" : "hp";
      this.hero.potions[pt] = (this.hero.potions[pt] || 0) + 1;
      this._spawnFloatingText(this.hero.x, this.hero.y - 28, pt === "mana" ? "+Mana potion" : "+Health potion", pt === "mana" ? "#88cfff" : "#ff8fa0");
      return;
    }

    if (l.kind === "key") {
      this.dungeon.keys = (this.dungeon.keys || 0) + 1;
      this._spawnFloatingText(this.hero.x, this.hero.y - 28, "+Dungeon key", "#8be9ff");
      this._msg("Dungeon key picked up", 0.95);
      return;
    }

    if (l.kind === "gear" && l.data) {
      this.hero.inventory.push(l.data);
      const power = l.data.score ? ` PWR ${l.data.score}` : "";
      const rarity = l.data.rarity ? `${this._titleCase(l.data.rarity)} ` : "";
      this._spawnFloatingText(this.hero.x, this.hero.y - 34, `+${rarity}Gear${power}`, l.data.color || "#d9dee8");
      this._msg(`Picked up ${l.data.name}${power}`, l.data.rarity === "epic" ? 2.0 : 1.25);
    }
  }

  _updateCamera(dt) {
    const follow = Math.min(1, dt * 8);
    this.camera.x = this.camera.x + (this.hero.x - this.camera.x) * follow;
    this.camera.y = this.camera.y + (this.hero.y - this.camera.y) * follow;
  }

  _updateNearbyPOIs(dt) {
    this._nearbyPoiTimer -= dt;
    if (this._nearbyPoiTimer > 0) return;
    this._nearbyPoiTimer = 0.22;

    this._cachedNearbyCamp = null;
    this._cachedNearbyDock = null;
    this._cachedNearbyWaystone = null;
    this._cachedNearbyDungeon = null;
    this._cachedNearbyShrine = null;
    this._cachedNearbyCache = null;
    this._cachedNearbyHerb = null;
    this._cachedNearbyTownDoor = null;

    const check = (arr, r, predicate = null) => {
      const r2 = r * r;
      for (const p of arr || []) {
        if (predicate && !predicate(p)) continue;
        if (dist2(this.hero.x, this.hero.y, p.x, p.y) <= r2) return p;
      }
      return null;
    };

    this._cachedNearbyCamp = check(this.world.camps, 84);
    this._cachedNearbyDock = check(this.world.docks, 64);
    this._cachedNearbyWaystone = check(this.world.waystones, 70);
    this._cachedNearbyDungeon = check(this.world.dungeons, 74);
    this._cachedNearbyShrine = check(this.world.shrines, 72);
    this._cachedNearbyCache = check(this.world.caches, 58);
    this._cachedNearbyHerb = check(this.world.herbs, 54, (h) => !h.picked);
    this._cachedNearbySecret = check(this.world.secrets, 62);
    this._cachedNearbyTown = check([this.world.startTown, ...(this.world.towns || [])], 128);
    this._cachedNearbyTownDoor = this._findNearbyTownDoor(this._cachedNearbyTown || this.world.startTown, 62);
    this._cachedNearbyDragonLair = check(this.world.dragonLairs, 110);
    if (this._cachedNearbySecret) this._discoverSecret(this._cachedNearbySecret);
  }

  _toggleDockingOrSailing() {
    const dock = this._cachedNearbyDock;
    if (!dock) return;

    this.hero.state.sailing = !this.hero.state.sailing;
    this._rememberProgressId(this.progress.discoveredDocks, dock);
    this._msg(this.hero.state.sailing ? "Sailing" : "Docked", 0.9);
  }

  _interact() {
    if (this.dungeon.active) {
      const room = this._getDungeonRoom(this.dungeon.currentRoomId);
      const currentClear = room ? !this._dungeonHasLivingEnemies(room.id) : !this._dungeonHasLivingEnemies();
      if (this.dungeon.kind === "dragon-lair" && this._isHeroNearDragonHoard()) {
        if (!currentClear) {
          this._msg("The dragon guards the hoard", 1.0);
        } else if (this.dungeon.hoardOpened) {
          this._msg("The hoard is already open", 0.8);
        } else {
          this._openDragonHoard();
        }
        return;
      }
      const cacheRoom = this._getDungeonNearbyCacheRoom();
      if (cacheRoom) {
        if (!cacheRoom.cleared) {
          this._msg("Clear the room first", 0.9);
        } else if (cacheRoom.cacheOpened) {
          this._msg("Already looted", 0.8);
        } else {
          this._openDungeonCache(cacheRoom);
        }
        return;
      }

      const door = this._getNearbyDungeonDoor();
      if (door) {
        const doorUnlocked = this._isDungeonDoorUnlocked(door, room);
        if (door.open) {
          this._msg("Door is open", 0.7);
        } else if (door.locked === "clear" && !doorUnlocked && !currentClear) {
          this._msg(door.locked === "clear" ? "Clear the room to unseal the door" : "The door is sealed", 0.9);
        } else if (door.locked === "clear" && !doorUnlocked) {
          this._msg("The door is still sealed", 0.9);
        } else if (door.locked === "key" && (this.dungeon.keys || 0) <= 0) {
          this._msg("You need a dungeon key", 1.0);
        } else {
          this._openDungeonDoor(door);
        }
        return;
      }

      if (this._isHeroNearDungeonReturn()) {
        this._leaveDungeon();
        return;
      }

      if (this._isHeroNearDungeonExitStair()) {
        if (!currentClear) {
          this._msg("The way deeper is sealed", 0.9);
        } else {
          this._descendDungeon();
        }
        return;
      }

      this._msg(currentClear ? "Search caches, unlock doors, or use the stairs" : "Clear the room first", 1.0);
      return;
    }

    if (this._cachedNearbyTownDoor) {
      this._enterTownService(this._cachedNearbyTownDoor);
      return;
    }

    if (this._cachedNearbyCamp) {
      this._openShop(this._cachedNearbyCamp);
      return;
    }

    if (this._cachedNearbyHerb) {
      this._collectHerb(this._cachedNearbyHerb);
      return;
    }

    if (this._cachedNearbyTown) {
      this._enterTown(this._cachedNearbyTown);
      return;
    }

    if (this._cachedNearbyWaystone) {
      this._discoverWaystone(this._cachedNearbyWaystone);
      return;
    }

    if (this._cachedNearbyShrine) {
      this._claimShrine(this._cachedNearbyShrine);
      return;
    }

    if (this._cachedNearbyCache) {
      this._openCache(this._cachedNearbyCache);
      return;
    }

    if (this._cachedNearbyDragonLair) {
      this._enterDragonLair(this._cachedNearbyDragonLair);
      return;
    }

    if (this._cachedNearbyDungeon) {
      this._enterDungeon(this._cachedNearbyDungeon);
    }
  }

  _findNearbyTownDoor(town, radius = 62) {
    if (!town?.buildings?.length) return null;
    const r2 = radius * radius;
    let best = null;
    let bestD2 = Infinity;
    for (const building of town.buildings) {
      const doorX = town.x + (building.x || 0) + (building.w || 0) * 0.5;
      const doorY = town.y + (building.y || 0) + (building.h || 0) - 8;
      const d2 = dist2(this.hero.x, this.hero.y, doorX, doorY);
      if (d2 > r2 || d2 >= bestD2) continue;
      bestD2 = d2;
      best = {
        town,
        building,
        service: building.service || "",
        name: building.name || "Door",
        x: doorX,
        y: doorY,
      };
    }
    return best;
  }

  _enterTownService(door) {
    if (!door?.town) return;
    this._townServiceFocus = door.service || "";
    if (door.service === "vendor") {
      this._openTownVendor();
      return;
    }
    this._enterTown(door.town, door.service || "");
    this._msg(`${door.name}`, 0.9);
  }

  _collectHerb(herb) {
    if (!herb || herb.picked) return;
    herb.picked = true;
    this.progress.herbs = (this.progress.herbs || 0) + 1;
    if (!this.progress.pickedHerbs) this.progress.pickedHerbs = new Set();
    this.progress.pickedHerbs.add(herb.id);
    this._cachedNearbyHerb = null;
    this._spawnFloatingText(this.hero.x, this.hero.y - 24, "+1 Herb", "#8fe48d");
    this._msg("Wild herbs gathered", 0.8);
  }

  _openShop(camp, opts = {}) {
    this.shop.campId = camp.id;
    if (!opts.skipCampProgress) {
      this._rememberProgressId(this.progress.visitedCamps, camp);
      this._claimCampRestBonus(camp);
    }
    this.shop.discount = opts.discount ?? this._shopDiscount(camp);
    this.shop.items = opts.items || this._buildShopForCamp(camp);
    this.menu.open = "shop";
  }

  _enterTown(town, focus = "") {
    const id = this._progressId(town);
    this._rememberProgressId(this.progress.visitedTowns, town);
    this._townServiceFocus = focus || "";

    if (!this.progress.storyMilestones[`town_${id}`]) {
      this.progress.storyMilestones[`town_${id}`] = true;
      const notes = [
        "The Warden marks a safer road on your map.",
        "The Smith names a forge worth remembering.",
        "The Archivist whispers about hidden lore stones.",
      ];
      const note = notes[Math.abs(hash2(this.seed, town?.x | 0, town?.y | 0)) % notes.length];
      this.hero.potions.hp = (this.hero.potions.hp || 0) + 1;
      this.hero.potions.mana = (this.hero.potions.mana || 0) + 1;
      this.hero.gold += 15;
      this._spawnFloatingText(town.x, town.y - 42, "+Supplies", "#8be9ff");
      this._msg(`${town.name || "Town"} welcomed you. ${note}`, 2.1);
    } else {
      this._msg(`${town.name || "Town"}`, 0.9);
    }

    this.menu.open = "town";
  }

  _primeDungeonStartDoors() {
    const startId = this.dungeon?.layout?.startRoomId;
    if (!startId) return;
    for (const door of this.dungeon?.layout?.doors || []) {
      if ((door.a === startId || door.b === startId) && door.locked === "clear") {
        door.unlocked = true;
        door.open = true;
      }
    }
  }

  _openTownVendor() {
    const town = this._cachedNearbyTown || this.world.startTown;
    if (!town) return;
    const merchantNode = { id: `town-vendor-${this._progressId(town)}`, x: town.x, y: town.y, type: town.coastal ? "bandit" : "wild" };
    const items = this._buildShopForCamp(merchantNode);
    items.push({
      kind: "material",
      name: "Wild Herb Bundle",
      price: 16,
      data: { material: "herb", amount: 3 },
    });
    items.push({
      kind: "material",
      name: "Forge Scrap",
      price: 24,
      data: { material: "scrap", amount: 2 },
    });
    items.push({
      kind: "material",
      name: "Ore Satchel",
      price: 30,
      data: { material: "ore", amount: 2 },
    });
    items.push({
      kind: "material",
      name: "Tanner Hide Roll",
      price: 28,
      data: { material: "hide", amount: 2 },
    });
    items.push({
      kind: "material",
      name: "Essence Phial",
      price: 42,
      data: { material: "essence", amount: 1 },
    });
    this._openShop(merchantNode, { items, discount: 0, skipCampProgress: true });
  }

  _townRest() {
    const cost = Math.max(0, Math.min(28, 8 + (this.hero.level || 1) * 2));
    if ((this.hero.hp || 0) >= (this.hero.maxHp || 1) && (this.hero.mana || 0) >= (this.hero.maxMana || 1)) {
      this._msg("Already rested", 0.8);
      return;
    }
    if ((this.hero.gold || 0) < cost) {
      this._msg(`Rest costs ${cost}g`, 0.9);
      return;
    }
    this.hero.gold -= cost;
    this.hero.hp = this.hero.maxHp || 100;
    this.hero.mana = this.hero.maxMana || 60;
    this._msg(`Rested -${cost}g`, 1.0);
  }

  _townBuyPotion(kind) {
    const cost = kind === "mana" ? 22 : 18;
    if ((this.hero.gold || 0) < cost) {
      this._msg(`${kind === "mana" ? "Mana" : "Health"} potion costs ${cost}g`, 0.9);
      return;
    }
    this.hero.gold -= cost;
    this.hero.potions[kind] = (this.hero.potions[kind] || 0) + 1;
    this._msg(`${kind === "mana" ? "Mana" : "Health"} potion bought`, 1.0);
  }

  _townCommissionGear() {
    const cost = 58 + (this.hero.level || 1) * 9;
    if ((this.hero.gold || 0) < cost) {
      this._msg(`Smith needs ${cost}g`, 0.9);
      return;
    }
    const slots = EQUIPMENT_SLOTS;
    const slot = slots[Math.abs(hash2(this.seed, this.hero.gold, this.time | 0)) % slots.length];
    const rarity = (this.hero.level || 1) >= 6 ? "rare" : "uncommon";
    const item = makeGear(slot, Math.max(1, this.hero.level || 1), rarity, hash2(this.seed, slot.length, this.hero.gold, this.time | 0));
    item.name = `Townforged ${item.name}`;
    this.hero.gold -= cost;
    this.hero.inventory.push(item);
    this._msg(`Forged ${item.name}`, 1.4);
  }

  getTownServiceName(service = this._townServiceFocus) {
    const names = {
      inn: "Inn",
      forge: "Forge",
      vendor: "Vendor",
      stable: "Stable",
      healer: "Healer",
      cartography: "Cartography",
      guild: "Guildhall",
      sanctum: "Sanctum",
    };
    return names[service] || "";
  }

  _townAskRumor() {
    const order = ["secret", "treasure", "town", "dungeon", "dragon", "bounty"];
    const current = order.indexOf(this.trackedObjective);
    const next = order[(current + 1 + order.length) % order.length];
    this._setTrackedObjective(next, `Rumor tracked: ${this._titleCase(next)}`);
  }

  _townCycleOath() {
    const order = ["knight", "ranger", "arcanist", "raider"];
    const current = Math.max(0, order.indexOf(this.hero.classId || "knight"));
    const next = order[(current + 1) % order.length];
    const free = !this.progress.storyMilestones?.oathChosen;
    const cost = free ? 0 : 90 + (this.hero.level || 1) * 12;
    if ((this.hero.gold || 0) < cost) {
      this._msg(`Oath change costs ${cost}g`, 1.0);
      return;
    }

    this.hero.gold -= cost;
    this.hero.classId = next;
    this.progress.storyMilestones.oathChosen = true;
    const stats = this.hero.getStats?.() || {};
    this.hero.maxHp = stats.maxHp || this.hero.maxHp;
    this.hero.maxMana = stats.maxMana || this.hero.maxMana;
    this.hero.hp = Math.min(this.hero.maxHp, Math.max(this.hero.hp || 1, Math.round(this.hero.maxHp * 0.72)));
    this.hero.mana = Math.min(this.hero.maxMana, Math.max(this.hero.mana || 1, Math.round(this.hero.maxMana * 0.72)));
    this._msg(`Oath: ${this._className(next)}`, 1.3);
  }

  _townTakeContract() {
    const town = this._cachedNearbyTown;
    const id = this._progressId(town || { id: "town" });
    const done = this.progress.storyMilestones || (this.progress.storyMilestones = {});
    const key = `contract_${id}`;
    const options = ["secret", "treasure", "town", "dungeon", "dragon", "bounty"];
    const pick = options[Math.abs(hash2(this.seed, town?.x | 0, town?.y | 0, this.progress.bountyCompletions || 0)) % options.length];
    this._setTrackedObjective(pick, null);

    if (!done[key]) {
      done[key] = true;
      const slots = EQUIPMENT_SLOTS;
      const rewardSlot = slots[Math.abs(hash2(id.length, this.seed, this.hero.level || 1)) % slots.length];
      const reward = makeGear(rewardSlot, Math.max(1, this.hero.level || 1), "uncommon", hash2(this.seed, town?.x | 0, town?.y | 0, 77));
      reward.name = `Town-Writ ${reward.name}`;
      this.hero.gold += 20;
      this.hero.giveXP?.(8);
      this.hero.inventory.push(reward);
      this._msg(`Town contract: ${this._titleCase(pick)} +20g and gear`, 1.4);
    } else {
      this._msg(`Contract tracked: ${this._titleCase(pick)}`, 1.0);
    }
  }

  _townBuyMapClue() {
    const cost = 36 + (this.hero.level || 1) * 4;
    if ((this.hero.gold || 0) < cost) {
      this._msg(`Map clue costs ${cost}g`, 0.9);
      return;
    }

    const candidates = [
      {
        mode: "secret",
        label: "hidden lore",
        target: this._nearest(this.world.secrets, (p) => !this.progress.discoveredSecrets.has(this._progressId(p))),
      },
      {
        mode: "treasure",
        label: "treasure cache",
        target: this._nearest(this.world.caches, (p) => !this.progress.openedCaches.has(this._progressId(p))),
      },
      {
        mode: "town",
        label: "unvisited town",
        target: this._nearest(this.world.towns, (p) => !this.progress.visitedTowns.has(this._progressId(p))),
      },
      {
        mode: "dungeon",
        label: "dungeon gate",
        target: this._nearest(this.world.dungeons),
      },
      {
        mode: "dragon",
        label: "dragon lair",
        target: this._nearest(this.world.dragonLairs, (p) => !this.progress.defeatedDragons.has(this._progressId(p))),
      },
    ].filter((v) => v.target);

    if (!candidates.length) {
      this._msg("No useful map clues left", 1.0);
      return;
    }

    candidates.sort((a, b) => dist2(this.hero.x, this.hero.y, a.target.x, a.target.y) - dist2(this.hero.x, this.hero.y, b.target.x, b.target.y));
    const clue = candidates[0];
    this.hero.gold -= cost;
    this._setTrackedObjective(clue.mode, null);
    this.world?.revealAround?.(clue.target.x, clue.target.y, 520);
    this._spawnFloatingText(this.hero.x, this.hero.y - 42, "Map clue", "#8be9ff");
    this._msg(`Cartographer marked ${clue.label} -${cost}g`, 1.6);
  }

  _getTownPassageInfo(town = this._cachedNearbyTown) {
    if (!town?.coastal || !town?.linkedDockId) {
      return { available: false, destination: null, destinationName: "", cost: 0 };
    }

    const coastalTowns = (this.world?.towns || [])
      .filter((t) => t?.coastal && t.id !== town.id && t.linkedDockId);
    if (!coastalTowns.length) {
      return { available: false, destination: null, destinationName: "", cost: 0 };
    }

    const unvisited = coastalTowns.filter((t) => !this.progress?.visitedTowns?.has?.(String(t.id)));
    const pool = unvisited.length ? unvisited : coastalTowns;
    pool.sort((a, b) => dist2(town.x, town.y, a.x, a.y) - dist2(town.x, town.y, b.x, b.y));
    const destination = pool[0];
    const travelDist = Math.sqrt(dist2(town.x, town.y, destination.x, destination.y));
    const cost = Math.max(18, Math.min(90, 12 + Math.round(travelDist / 220)));
    return {
      available: true,
      destination,
      destinationName: destination.name || "Harbor town",
      cost,
    };
  }

  _townBuyPassage() {
    const town = this._cachedNearbyTown;
    const passage = this._getTownPassageInfo(town);
    if (!passage.available || !passage.destination) {
      this._msg(town?.coastal ? "No ship is sailing right now" : "This town has no harbor passage", 1.0);
      return;
    }
    if ((this.hero.gold || 0) < passage.cost) {
      this._msg(`Passage costs ${passage.cost}g`, 0.9);
      return;
    }

    const destination = passage.destination;
    const dock = (this.world?.docks || []).find((d) => d.id === destination.linkedDockId);
    const arrival = dock || destination;

    this.hero.gold -= passage.cost;
    this.hero.state.sailing = false;
    this.hero.x = arrival.x;
    this.hero.y = arrival.y;
    this.hero.vx = 0;
    this.hero.vy = 0;
    this.camera.x = this.hero.x;
    this.camera.y = this.hero.y;

    if (dock) this._rememberProgressId(this.progress.discoveredDocks, dock);
    this._rememberProgressId(this.progress.visitedTowns, destination);
    this.world?.revealAround?.(arrival.x, arrival.y, 760);
    this._setTrackedObjective("town", null);
    this.menu.open = null;
    this._spawnFloatingText(this.hero.x, this.hero.y - 42, "Passage booked", "#8be9ff");
    this._msg(`Sailed to ${destination.name} -${passage.cost}g`, 1.5);
  }

  _claimCampRestBonus(camp) {
    const id = this._progressId(camp);
    if (this.progress.campRestBonusClaimed[id]) return;

    this.progress.campRestBonusClaimed[id] = true;
    this.progress.campRenown[id] = (this.progress.campRenown[id] || 0) + 1;
    this.hero.hp = Math.min(this.hero.maxHp || 100, (this.hero.hp || 0) + Math.round((this.hero.maxHp || 100) * 0.35));
    this.hero.mana = Math.min(this.hero.maxMana || 60, (this.hero.mana || 0) + Math.round((this.hero.maxMana || 60) * 0.45));
    this.hero.potions.hp = (this.hero.potions.hp || 0) + 1;
    this._msg("Camp rest: refreshed", 1.4);
  }

  _buildShopForCamp(camp) {
    const rng = new RNG(hash2(camp.x | 0, camp.y | 0, this.seed));
    const items = [];
    const discount = this._shopDiscount(camp);

    items.push({
      kind: "potion",
      name: "Health Potion",
      price: this._shopPrice(12, discount),
      data: { potionType: "hp" },
    });

    items.push({
      kind: "potion",
      name: "Mana Potion",
      price: this._shopPrice(13, discount),
      data: { potionType: "mana" },
    });

    const slots = EQUIPMENT_SLOTS;
    for (let i = 0; i < 4; i++) {
      const slot = slots[(rng.int(0, slots.length - 1) + i) % slots.length];
      const rarityRoll = rng.float();
      const rarity =
        rarityRoll > 0.9 ? "rare" :
        rarityRoll > 0.56 ? "uncommon" :
        "common";

      const gear = makeGear(
        slot,
        Math.max(1, this.hero.level),
        rarity,
        hash2(camp.x | 0, camp.y | 0, i + (this.time | 0))
      );

      items.push({
        kind: "gear",
        name: gear.name,
        price: this._shopPrice(rarity === "rare" ? 80 : rarity === "uncommon" ? 42 : 24, discount),
        data: gear,
      });
    }

    return items.slice(0, 4);
  }

  _shopDiscount(camp) {
    const id = this._progressId(camp);
    const renown = this.progress.campRenown[id] || 0;
    return clamp((this.progress.bountyCompletions || 0) * 0.01 + renown * 0.03, 0, 0.18);
  }

  _shopPrice(base, discount) {
    return Math.max(1, Math.round(base * (1 - discount)));
  }

  getShopPanelMeta() {
    const discount = Math.round((this.shop?.discount || 0) * 100);
    return {
      hint: "1-4 or click buy - Esc close",
      goldText: `Gold: ${this.hero?.gold || 0}`,
      discountText: discount > 0 ? `Renown discount: ${discount}%` : "",
    };
  }

  getShopPanelLayout() {
    const w = 430;
    const h = 260;
    const x = ((this.w - w) / 2) | 0;
    const y = ((this.h - h) / 2) | 0;
    return {
      w,
      h,
      x,
      y,
      rowStart: 70,
      rowStep: 42,
    };
  }

  _buyShopItem(index) {
    const item = this.shop.items[index];
    if (!item) return;

    if ((this.hero.gold || 0) < item.price) {
      this._msg("Not enough gold", 0.9);
      return;
    }

    this.hero.gold -= item.price;

    if (item.kind === "potion") {
      const pt = item.data?.potionType === "mana" ? "mana" : "hp";
      this.hero.potions[pt] = (this.hero.potions[pt] || 0) + 1;
    } else if (item.kind === "material") {
      const material = item.data?.material || "scrap";
      const amount = Math.max(1, item.data?.amount || 1);
      if (material === "herb") {
        this.progress.herbs = (this.progress.herbs || 0) + amount;
      } else {
        this._grantMaterials({ [material]: amount }, false);
      }
    } else if (item.kind === "gear") {
      this.hero.inventory.push(item.data);
    }

    this.shop.items.splice(index, 1);
    this._msg(`Bought ${item.name}`, 1.0);
  }

  _discoverWaystone(w) {
    const id = this._progressId(w);
    if (this.progress.discoveredWaystones.has(id)) {
      this._msg("Waystone already known", 0.8);
      return;
    }

    this.progress.discoveredWaystones.add(id);
    this._msg("Waystone discovered", 1.0);
  }

  _claimShrine(shrine) {
    const id = this._progressId(shrine);
    if (this.progress.claimedShrines.has(id)) {
      this._msg("Shrine already claimed", 0.9);
      return;
    }

    this.progress.claimedShrines.add(id);
    const roll = hash2(shrine.x | 0, shrine.y | 0, this.seed) % 3;

    if (roll === 0) {
      this._grantPermanentStats({ hp: 8 });
      this.hero.hp = Math.min(this.hero.maxHp, (this.hero.hp || 0) + 24);
      this._spawnFloatingText(shrine.x, shrine.y - 22, "+Max HP", "#ff8fa0");
      this._msg("Shrine of Vitality claimed", 1.5);
    } else if (roll === 1) {
      this._grantPermanentStats({ mana: 6 });
      this.hero.mana = Math.min(this.hero.maxMana, (this.hero.mana || 0) + 22);
      this._spawnFloatingText(shrine.x, shrine.y - 22, "+Max Mana", "#88cfff");
      this._msg("Shrine of Focus claimed", 1.5);
    } else {
      this.hero.giveXP?.(18 + Math.max(0, (this.hero.level || 1) - 1) * 5);
      this.hero.gold += 14 + (this.hero.level || 1) * 3;
      this._spawnFloatingText(shrine.x, shrine.y - 22, "+XP +Gold", "#ffd86e");
      this._msg("Shrine of Fortune claimed", 1.5);
    }

    for (const key of ["q", "w", "e", "r"]) {
      if (this.skillProg[key]) this.skillProg[key].xp += 1;
      this._checkSkillLevel(key);
    }
    this._awardRelicShards(1, "shrine");
  }

  _grantPermanentStats(stats = {}) {
    if (!this.hero.bonusStats) this.hero.bonusStats = { hp: 0, mana: 0 };
    this.hero.bonusStats.hp = Math.max(0, (this.hero.bonusStats.hp || 0) + (stats.hp || 0));
    this.hero.bonusStats.mana = Math.max(0, (this.hero.bonusStats.mana || 0) + (stats.mana || 0));

    const current = this.hero.getStats?.() || {};
    this.hero.maxHp = current.maxHp || this.hero.maxHp || 100;
    this.hero.maxMana = current.maxMana || this.hero.maxMana || 60;
  }

  _openCache(cache) {
    const id = this._progressId(cache);
    if (this.progress.openedCaches.has(id)) {
      this._msg("Cache already opened", 0.8);
      return;
    }

    this.progress.openedCaches.add(id);
    const level = Math.max(1, this.world.getDangerLevel?.(cache.x, cache.y) || this.hero.level || 1);
    const gold = 18 + level * 7 + (hash2(cache.x | 0, cache.y | 0, this.seed) % 14);

    this.loot.push(new Loot(cache.x - 10, cache.y, "gold", { amount: gold }));
    this.loot.push(new Loot(cache.x + 10, cache.y + 2, "potion", { potionType: level >= 3 ? "mana" : "hp" }));

    if (level >= 2) {
      const slots = EQUIPMENT_SLOTS;
      const slot = slots[Math.abs(hash2(cache.x | 0, cache.y | 0, level)) % slots.length];
      const rarity = level >= 5 ? "rare" : "uncommon";
      const item = makeGear(slot, Math.max(level, this.hero.level || 1), rarity, hash2(this.seed, cache.x | 0, cache.y | 0));
      item.name = `Cache-Sealed ${item.name}`;
      this.loot.push(new Loot(cache.x, cache.y - 12, "gear", item));
    }

    this._grantMaterials({
      scrap: 1 + Math.floor(level / 3),
      ore: level >= 3 ? 1 + Math.floor(level / 4) : 0,
      hide: level >= 2 ? 1 : 0,
      essence: level >= 4 ? 1 : 0,
    }, false);

    this._spawnFloatingText(cache.x, cache.y - 22, "Cache opened", "#ffe19a");
    this._msg("Treasure cache opened", 1.4);
    this._awardRelicShards(level >= 4 ? 2 : 1, "cache");
  }

  _discoverSecret(secret) {
    const id = this._progressId(secret);
    if (this.progress.discoveredSecrets?.has(id)) return;
    this.progress.discoveredSecrets.add(id);

    const bonus = 10 + Math.max(1, this.hero.level || 1) * 3;
    this.hero.gold += bonus;
    this.hero.giveXP?.(6 + Math.max(1, this.hero.level || 1));
    this._spawnFloatingText(secret.x, secret.y - 24, "Secret found", "#ffeaa8");
    this._msg(`Lore found: ${secret.name || "Hidden marker"} +${bonus}g`, 1.7);

    if ((this.progress.discoveredSecrets.size || 0) % 3 === 0) {
      this._awardRelicShards(1, "secret");
    }
  }

  _challengeDragon(lair) {
    const id = this._progressId(lair);
    if (this.progress.defeatedDragons.has(id)) {
      this._msg("This dragon is already defeated", 1.0);
      return;
    }

    const nearby = this.enemies.some((e) => e?.alive && e.boss && e.kind === "dragon" && dist2(e.x, e.y, lair.x, lair.y) < 700 * 700);
    if (nearby) {
      this._msg("The dragon is awake", 1.0);
      return;
    }

    const level = Math.max(8, (this.hero.level || 1) + (this.world.getDangerLevel?.(lair.x, lair.y) || 5) + 3);
    this._spawnDragonBoss(lair.x, lair.y, level, "Ancient Dragon", id);
    this._msg("Ancient Dragon awakened", 2.0);
  }

  _enterDragonLair(lair) {
    if (this.dungeon.active || !lair) return;
    const id = this._progressId(lair);
    if (this.progress.defeatedDragons.has(id)) {
      this._msg("This dragon lair is already broken", 1.0);
      return;
    }

    this.dungeon.active = true;
    this.dungeon.kind = "dragon-lair";
    this.dungeon.floor = Math.max(8, (this.hero.level || 1) + (this.world.getDangerLevel?.(lair.x, lair.y) || 5) + 3);
    this.dungeon.origin = { x: lair.x, y: lair.y };
    this.dungeon.lairId = id;
    this.dungeon.layout = this._buildDragonLair(lair);
    this.dungeon.roomIndex = 1;
    this.dungeon.totalRooms = 1;
    this.dungeon.roomRewarded = false;
    this.dungeon.keys = 0;
    this.dungeon.roomClearT = 0;
    this.dungeon.spawnQueue = [];
    this.dungeon.hoardOpened = false;
    this.dungeon.currentRoomId = this.dungeon.layout?.startRoomId || null;
    this.dungeon.room = this._getDungeonRoom(this.dungeon.currentRoomId);
    this._primeDungeonStartDoors();
    const start = this.dungeon.layout?.returnStair || { x: this.dungeon.room.x, y: this.dungeon.room.y + 150 };
    this.hero.x = start.x;
    this.hero.y = start.y;
    this.hero.vx = 0;
    this.hero.vy = 0;
    this.hero.state.sailing = false;
    this.camera.x = this.hero.x;
    this.camera.y = this.hero.y;
    this.enemies = [];
    this.projectiles = [];
    this.loot = [];
    this._msg("Dragon lair entered", 1.4);
    this._updateDungeonState(0);
  }

  _spawnDragonBoss(x, y, level, name = "Dragon", progressId = null) {
    const dragon = new Enemy(x, y, level, "dragon", hash2(x | 0, y | 0, this.seed), false, true);
    dragon.name = name;
    dragon.progressId = progressId;
    dragon.affix = name;
    dragon.extraLoot = 18;
    this.enemies.push(dragon);
    return dragon;
  }

  _enterDungeon(dungeonPoi) {
    if (this.dungeon.active) return;

    this.dungeon.active = true;
    this.dungeon.kind = "depths";
    this.dungeon.floor = Math.max(1, (this.progress.dungeonBest || 0) + 1);
    this.dungeon.origin = { x: dungeonPoi.x, y: dungeonPoi.y };
    this.dungeon.lairId = null;
    this.dungeon.layout = this._buildDungeonFloor();
    this.dungeon.roomIndex = 1;
    this.dungeon.totalRooms = this.dungeon.layout?.combatRooms || 1;
    this.dungeon.roomRewarded = false;
    this.dungeon.keys = 0;
    this.dungeon.roomClearT = 0;
    this.dungeon.spawnQueue = [];
    this.dungeon.hoardOpened = false;
    this.dungeon.currentRoomId = this.dungeon.layout?.startRoomId || null;
    this.dungeon.room = this._getDungeonRoom(this.dungeon.currentRoomId);
    this._primeDungeonStartDoors();
    const start = this.dungeon.layout?.returnStair || { x: this.dungeon.room.x, y: this.dungeon.room.y + 150 };
    this.hero.x = start.x;
    this.hero.y = start.y;
    this.hero.vx = 0;
    this.hero.vy = 0;
    this.hero.state.sailing = false;
    this.camera.x = this.hero.x;
    this.camera.y = this.hero.y;
    this.enemies = [];
    this.projectiles = [];
    this.loot = [];

    this._msg(`${this._dungeonTheme(this.dungeon.floor).name} - explore the floor`, 1.2);
    this._updateDungeonState(0);
  }

  _descendDungeon() {
    if (!this.dungeon.active) return;
    if (this.dungeon.kind === "dragon-lair") return;
    this.progress.dungeonBest = Math.max(this.progress.dungeonBest || 0, this.dungeon.floor || 0);
    this.dungeon.floor = Math.max(1, (this.dungeon.floor || 1) + 1);
    this.dungeon.layout = this._buildDungeonFloor();
    this.dungeon.roomIndex = 1;
    this.dungeon.totalRooms = this.dungeon.layout?.combatRooms || 1;
    this.dungeon.roomRewarded = false;
    this.dungeon.keys = 0;
    this.dungeon.roomClearT = 0;
    this.dungeon.spawnQueue = [];
    this.dungeon.hoardOpened = false;
    this.dungeon.currentRoomId = this.dungeon.layout?.startRoomId || null;
    this.dungeon.room = this._getDungeonRoom(this.dungeon.currentRoomId);
    this._primeDungeonStartDoors();
    const start = this.dungeon.layout?.returnStair || { x: this.dungeon.room.x, y: this.dungeon.room.y + this.dungeon.room.h * 0.28 };
    this.hero.x = start.x;
    this.hero.y = start.y;
    this.camera.x = this.hero.x;
    this.camera.y = this.hero.y;
    this.enemies = [];
    this.projectiles = [];
    this.loot = [];
    this.hero.hp = Math.min(this.hero.maxHp || 100, (this.hero.hp || 0) + 12);
    this.hero.mana = Math.min(this.hero.maxMana || 60, (this.hero.mana || 0) + 10);
    if (this.dungeon.floor % 3 === 0) this._awardRelicShards(1, "depths");
    this._updateDungeonState(0);
    this._msg(`Descended: ${this._dungeonTheme(this.dungeon.floor).name}`, 1.4);
  }

  _buildDragonLair(lair) {
    const originX = lair?.x || this.hero.x;
    const originY = lair?.y || this.hero.y;
    const rooms = [];
    const corridors = [];
    const doors = [];
    const walkRects = [];

    const makeRoom = (id, type, x, y, w, h) => {
      const room = {
        id,
        type,
        x,
        y,
        w,
        h,
        discovered: id === "start",
        spawned: false,
        cleared: id === "start",
        rewardClaimed: id === "start",
        cacheOpened: false,
        openings: [],
        decor: [],
      };
      rooms.push(room);
      walkRects.push({ x, y, w: Math.max(140, w - 40), h: Math.max(140, h - 40), kind: "room", roomId: id });
      return room;
    };

    const addOpening = (room, side, center, span) => room.openings.push({ side, center, span });
    const makeDoor = (a, b, x, y, vertical, locked, label, blockerW, blockerH, frameSpan) => ({
      id: `${a}_${b}`,
      a,
      b,
      x,
      y,
      vertical,
      open: locked === "none",
      unlocked: locked === "none" || locked === "clear",
      locked,
      label,
      blocker: { x, y, w: blockerW, h: blockerH },
      frameSpan,
    });

    const start = makeRoom("start", "start", originX, originY + 240, 760, 460);
    const hall = makeRoom("hall", "crypt", originX, originY - 120, 600, 380);
    const cache = makeRoom("loot", "loot", originX - 420, originY - 420, 480, 320);
    const keyRoom = makeRoom("key", "key", originX + 430, originY - 430, 500, 340);
    const antechamber = makeRoom("ante", "crypt", originX, originY - 760, 760, 420);
    const hoard = makeRoom("boss", "boss", originX, originY - 1360, 1120, 720);

    const verticalCorridor = (a, b, width = 108) => {
      const top = a.y < b.y ? a : b;
      const bottom = top === a ? b : a;
      const startY = top.y + top.h * 0.5 - 18;
      const endY = bottom.y - bottom.h * 0.5 + 18;
      const corridor = { x: top.x, y: (startY + endY) * 0.5, w: width, h: Math.max(44, endY - startY), kind: "corridor", rooms: [a.id, b.id], orientation: "v", decor: [] };
      corridors.push(corridor);
      walkRects.push(corridor);
      addOpening(top, "bottom", top.x, corridor.w + 4);
      addOpening(bottom, "top", bottom.x, corridor.w + 4);
      return corridor;
    };
    const horizontalCorridor = (a, b, height = 96) => {
      const left = a.x < b.x ? a : b;
      const right = left === a ? b : a;
      const startX = left.x + left.w * 0.5 - 18;
      const endX = right.x - right.w * 0.5 + 18;
      const corridor = { x: (startX + endX) * 0.5, y: left.y, w: Math.max(44, endX - startX), h: height, kind: "corridor", rooms: [a.id, b.id], orientation: "h", decor: [] };
      corridors.push(corridor);
      walkRects.push(corridor);
      addOpening(left, "right", left.y, corridor.h + 4);
      addOpening(right, "left", right.y, corridor.h + 4);
      return corridor;
    };

    const startHall = verticalCorridor(start, hall, 108);
    const hallAnte = verticalCorridor(hall, antechamber, 108);
    const anteBoss = verticalCorridor(antechamber, hoard, 120);
    const hallCache = horizontalCorridor(hall, cache, 92);
    const hallKey = horizontalCorridor(hall, keyRoom, 92);

    doors.push(
      makeDoor("start", "hall", start.x, start.y + start.h * 0.5 - 7, false, "clear", "Entry Gate", startHall.w + 8, 18, startHall.w - 10),
      makeDoor("hall", "cache", cache.x + cache.w * 0.5 - 7, cache.y, true, "clear", "Store Door", 18, hallCache.h + 8, hallCache.h - 10),
      makeDoor("hall", "key", hall.x + hall.w * 0.5 - 7, keyRoom.y, true, "clear", "Archive Gate", 18, hallKey.h + 8, hallKey.h - 10),
      makeDoor("hall", "ante", hall.x, hall.y + hall.h * 0.5 - 7, false, "clear", "Deep Gate", hallAnte.w + 8, 18, hallAnte.w - 10),
      makeDoor("ante", "boss", antechamber.x, antechamber.y + antechamber.h * 0.5 - 7, false, "key", "Dragon Seal", anteBoss.w + 8, 18, anteBoss.w - 10),
    );

    start.decor.push(
      { kind: "banner", x: start.x - start.w * 0.24, y: start.y - start.h * 0.28, sx: 1.1, sy: 1 },
      { kind: "banner", x: start.x + start.w * 0.24, y: start.y - start.h * 0.28, sx: 1.1, sy: 1 },
      { kind: "brazer", x: start.x - start.w * 0.26, y: start.y + start.h * 0.08, sx: 1, sy: 1 },
      { kind: "brazer", x: start.x + start.w * 0.26, y: start.y + start.h * 0.08, sx: 1, sy: 1 },
      { kind: "crate", x: start.x - 70, y: start.y + 46, sx: 1, sy: 1 },
    );
    hall.decor.push(
      { kind: "pillar", x: hall.x - hall.w * 0.26, y: hall.y - hall.h * 0.08, sx: 1.1, sy: 1.1 },
      { kind: "pillar", x: hall.x + hall.w * 0.26, y: hall.y - hall.h * 0.08, sx: 1.1, sy: 1.1 },
      { kind: "rubble", x: hall.x - 88, y: hall.y + 74, sx: 1.15, sy: 1 },
      { kind: "bones", x: hall.x + 96, y: hall.y + 58, sx: 1.1, sy: 1 },
    );
    cache.decor.push(
      { kind: "crate", x: cache.x - 60, y: cache.y + 26, sx: 1.1, sy: 1 },
      { kind: "crate", x: cache.x + 48, y: cache.y - 18, sx: 1, sy: 1 },
      { kind: "treasure", x: cache.x + 8, y: cache.y + 48, sx: 1, sy: 1 },
    );
    keyRoom.decor.push(
      { kind: "shelf", x: keyRoom.x - 96, y: keyRoom.y - 48, sx: 1.1, sy: 1 },
      { kind: "shelf", x: keyRoom.x + 96, y: keyRoom.y - 48, sx: 1.1, sy: 1 },
      { kind: "table", x: keyRoom.x, y: keyRoom.y + 24, sx: 1.1, sy: 1 },
    );
    antechamber.decor.push(
      { kind: "pillar", x: antechamber.x - antechamber.w * 0.26, y: antechamber.y - 12, sx: 1.2, sy: 1.2 },
      { kind: "pillar", x: antechamber.x + antechamber.w * 0.26, y: antechamber.y - 12, sx: 1.2, sy: 1.2 },
      { kind: "brazer", x: antechamber.x - antechamber.w * 0.28, y: antechamber.y + antechamber.h * 0.16, sx: 1, sy: 1 },
      { kind: "brazer", x: antechamber.x + antechamber.w * 0.28, y: antechamber.y + antechamber.h * 0.16, sx: 1, sy: 1 },
      { kind: "stalagmite", x: antechamber.x, y: antechamber.y - 82, sx: 1.1, sy: 1.1 },
    );
    hoard.decor.push(
      { kind: "dais", x: hoard.x, y: hoard.y + hoard.h * 0.1, sx: 2.4, sy: 1.4 },
      { kind: "pillar", x: hoard.x - hoard.w * 0.24, y: hoard.y - hoard.h * 0.06, sx: 1.2, sy: 1.2 },
      { kind: "pillar", x: hoard.x + hoard.w * 0.24, y: hoard.y - hoard.h * 0.06, sx: 1.2, sy: 1.2 },
      { kind: "banner", x: hoard.x - hoard.w * 0.28, y: hoard.y - hoard.h * 0.3, sx: 1.25, sy: 1.1 },
      { kind: "banner", x: hoard.x + hoard.w * 0.28, y: hoard.y - hoard.h * 0.3, sx: 1.25, sy: 1.1 },
      { kind: "bones", x: hoard.x - 120, y: hoard.y + 96, sx: 1.2, sy: 1.2 },
      { kind: "lava", x: hoard.x + 180, y: hoard.y + 110, sx: 1.3, sy: 1.1 },
      { kind: "treasure", x: hoard.x + 32, y: hoard.y + 84, sx: 1.2, sy: 1.2 },
    );
    startHall.decor.push(
      { kind: "sconce", x: startHall.x - startHall.w * 0.22, y: startHall.y - startHall.h * 0.2, sx: 0.9, sy: 1 },
      { kind: "sconce", x: startHall.x - startHall.w * 0.22, y: startHall.y + startHall.h * 0.2, sx: 0.9, sy: 1 }
    );
    hallAnte.decor.push(
      { kind: "sconce", x: hallAnte.x - hallAnte.w * 0.22, y: hallAnte.y - hallAnte.h * 0.26, sx: 0.9, sy: 1 },
      { kind: "sconce", x: hallAnte.x - hallAnte.w * 0.22, y: hallAnte.y + hallAnte.h * 0.26, sx: 0.9, sy: 1 },
      { kind: "rubble", x: hallAnte.x + 18, y: hallAnte.y + 12, sx: 1, sy: 1 }
    );
    anteBoss.decor.push(
      { kind: "sconce", x: anteBoss.x - anteBoss.w * 0.22, y: anteBoss.y - anteBoss.h * 0.28, sx: 0.9, sy: 1 },
      { kind: "sconce", x: anteBoss.x - anteBoss.w * 0.22, y: anteBoss.y + anteBoss.h * 0.28, sx: 0.9, sy: 1 },
      { kind: "bones", x: anteBoss.x + 10, y: anteBoss.y + 62, sx: 1.1, sy: 1 }
    );

    const blockedRects = this._buildDungeonBlockedRects({ rooms, corridors });
    const returnStair = { x: start.x, y: start.y + start.h * 0.5 - 78 };
    const hoardPoint = { x: hoard.x, y: hoard.y + hoard.h * 0.12 };

    return {
      seed: hash2(this.seed, originX | 0, originY | 0, 9917),
      rooms,
      corridors,
      doors,
      walkRects,
      blockedRects,
      startRoomId: "start",
      bossRoomId: "boss",
      currentRoomId: "start",
      combatRooms: rooms.filter((r) => r.type !== "start").length,
      returnStair,
      exitStair: null,
      hoard: hoardPoint,
    };
  }

  _buildDungeonFloor() {
    const floor = Math.max(1, this.dungeon.floor || 1);
    const seed = hash2(this.seed, floor, 4117);
    const rng = new RNG(seed);
    const originX = this.dungeon.origin?.x || this.hero.x;
    const originY = this.dungeon.origin?.y || this.hero.y;
    const layoutHash = Math.abs(hash2(originX | 0, originY | 0, floor, 9173));
    const cellX = 360;
    const cellY = 260;
    const rooms = [];
    const corridors = [];
    const doors = [];
    const walkRects = [];

    const makeRoom = (id, type, gx, gy, baseW, baseH) => {
      const room = {
        id,
        type,
        x: originX + gx * cellX,
        y: originY + gy * cellY,
        w: baseW + rng.range(-32, 32),
        h: baseH + rng.range(-26, 26),
        discovered: id === "start",
        spawned: false,
        cleared: id === "start",
        rewardClaimed: id === "start",
        cacheOpened: false,
        openings: [],
        decor: [],
      };
      rooms.push(room);
      walkRects.push({
        x: room.x,
        y: room.y,
        w: Math.max(120, room.w - 40),
        h: Math.max(120, room.h - 40),
        kind: "room",
        roomId: id,
      });
      return room;
    };

    const addOpening = (room, side, center, span) => {
      room.openings.push({ side, center, span });
    };

    const connect = (a, b, locked = "none", label = "") => {
      let corridor;
      let door;
      if (Math.abs(a.y - b.y) < 20) {
        const left = a.x < b.x ? a : b;
        const right = left === a ? b : a;
        const startX = left.x + left.w * 0.5 - 18;
        const endX = right.x - right.w * 0.5 + 18;
        corridor = { x: (startX + endX) * 0.5, y: left.y, w: Math.max(44, endX - startX), h: 82, kind: "corridor", rooms: [a.id, b.id] };
        door = {
          id: `${a.id}_${b.id}`,
          a: a.id,
          b: b.id,
          x: left.x + left.w * 0.5 - 7,
          y: left.y,
          vertical: true,
          open: locked === "none",
          unlocked: locked === "none" || (locked === "clear" && (a.id === "start" || b.id === "start")),
          locked,
          label,
          blocker: { x: left.x + left.w * 0.5 - 7, y: left.y, w: 18, h: corridor.h + 8 },
          frameSpan: corridor.h - 10,
        };
        addOpening(left, "right", left.y, corridor.h + 2);
        addOpening(right, "left", right.y, corridor.h + 2);
      } else {
        const top = a.y < b.y ? a : b;
        const bottom = top === a ? b : a;
        const startY = top.y + top.h * 0.5 - 18;
        const endY = bottom.y - bottom.h * 0.5 + 18;
        corridor = { x: top.x, y: (startY + endY) * 0.5, w: 82, h: Math.max(44, endY - startY), kind: "corridor", rooms: [a.id, b.id] };
        door = {
          id: `${a.id}_${b.id}`,
          a: a.id,
          b: b.id,
          x: top.x,
          y: top.y + top.h * 0.5 - 7,
          vertical: false,
          open: locked === "none",
          unlocked: locked === "none" || (locked === "clear" && (a.id === "start" || b.id === "start")),
          locked,
          label,
          blocker: { x: top.x, y: top.y + top.h * 0.5 - 7, w: corridor.w + 8, h: 18 },
          frameSpan: corridor.w - 10,
        };
        addOpening(top, "bottom", top.x, corridor.w + 2);
        addOpening(bottom, "top", bottom.x, corridor.w + 2);
      }
      corridor.orientation = door.vertical ? "h" : "v";
      corridor.decor = [];
      corridors.push(corridor);
      walkRects.push(corridor);
      doors.push(door);
      return door;
    };

    const templates = [
      {
        name: "forked-depths",
        rooms: [
          ["start", "start", 0, 0, 680, 460],
          ["loot", "loot", -1.1, -0.95, 560, 320],
          ["key", "key", 1.08, -1.08, 500, 360],
          ["crypt", "crypt", 0.12, -1.04, 700, 430],
          ["boss", "boss", -0.06, -2.18, 900, 540],
        ],
        links: [
          ["start", "loot", "clear", "Loot Door"],
          ["start", "key", "clear", "Key Door"],
          ["start", "crypt", "clear", "Crypt Gate"],
          ["crypt", "boss", "key", "Boss Gate"],
          ["loot", "crypt", "clear", "Stone Door"],
          ["key", "crypt", "clear", "Stone Door"],
        ],
      },
      {
        name: "long-spine",
        rooms: [
          ["start", "start", 0, 0, 650, 450],
          ["shrine", "shrine", -1.12, -0.96, 540, 360],
          ["key", "key", 1.02, -1.06, 500, 320],
          ["crypt", "crypt", 0.08, -1.02, 620, 450],
          ["boss", "boss", 0, -2.2, 820, 580],
        ],
        links: [
          ["start", "shrine", "clear", "Shrine Door"],
          ["start", "key", "clear", "Key Door"],
          ["start", "crypt", "clear", "Crypt Gate"],
          ["crypt", "boss", "key", "Boss Gate"],
          ["shrine", "crypt", "clear", "Stone Door"],
          ["key", "crypt", "clear", "Iron Gate"],
        ],
      },
      {
        name: "ring-vault",
        rooms: [
          ["start", "start", 0, 0, 660, 450],
          ["armory", "armory", -1.08, -1.02, 560, 340],
          ["key", "key", 1.12, -0.9, 500, 340],
          ["crypt", "crypt", 0, -1.08, 680, 410],
          ["boss", "boss", 0.04, -2.1, 880, 500],
        ],
        links: [
          ["start", "armory", "clear", "Armory Door"],
          ["start", "key", "clear", "Archive Door"],
          ["start", "crypt", "clear", "Crypt Gate"],
          ["armory", "crypt", "clear", "Stone Door"],
          ["key", "crypt", "clear", "Iron Gate"],
          ["crypt", "boss", "key", "Boss Gate"],
        ],
      },
      {
        name: "switchback-descent",
        rooms: [
          ["start", "start", 0, 0, 660, 430],
          ["loot", "loot", -1.14, -0.9, 540, 300],
          ["key", "key", 1.05, -1.12, 500, 360],
          ["crypt", "crypt", -0.08, -1.06, 700, 360],
          ["boss", "boss", 0.1, -2.16, 840, 560],
        ],
        links: [
          ["start", "loot", "clear", "Loot Door"],
          ["start", "key", "clear", "Archive Door"],
          ["start", "crypt", "clear", "Crypt Door"],
          ["loot", "crypt", "clear", "Stone Gate"],
          ["key", "crypt", "clear", "Iron Gate"],
          ["crypt", "boss", "key", "Boss Gate"],
        ],
      },
      {
        name: "cathedral-run",
        rooms: [
          ["start", "start", 0, 0, 700, 460],
          ["shrine", "shrine", -1.06, -0.92, 520, 380],
          ["key", "key", 1.08, -1.06, 540, 320],
          ["apse", "crypt", 0, -1.02, 760, 420],
          ["boss", "boss", 0, -2.18, 980, 540],
        ],
        links: [
          ["start", "shrine", "clear", "West Door"],
          ["start", "key", "clear", "East Door"],
          ["start", "apse", "clear", "Apse Gate"],
          ["apse", "boss", "key", "Boss Gate"],
          ["shrine", "apse", "clear", "Stone Door"],
          ["key", "apse", "clear", "Stone Door"],
        ],
      },
    ];

    const template = templates[layoutHash % templates.length];
    const roomById = new Map();
    for (const [id, type, gx, gy, w, h] of template.rooms) {
      roomById.set(id, makeRoom(id, type, gx, gy, w, h));
    }
    for (const [aId, bId, locked, label] of template.links) {
      connect(roomById.get(aId), roomById.get(bId), locked, label);
    }

    this._populateDungeonDecor({ rooms, corridors }, this._dungeonTheme(floor), rng);
    const blockedRects = this._buildDungeonBlockedRects({ rooms, corridors });
    const start = roomById.get("start");
    const boss = roomById.get("boss");
    const returnStair = { x: start.x, y: start.y + start.h * 0.5 - 78 };
    const exitStair = { x: boss.x, y: boss.y - boss.h * 0.5 + 92 };

    return {
      seed,
      rooms,
      corridors,
      doors,
      walkRects,
      blockedRects,
      startRoomId: "start",
      bossRoomId: "boss",
      currentRoomId: "start",
      combatRooms: rooms.filter((r) => r.type !== "start").length,
      returnStair,
      exitStair,
    };
  }

  _populateDungeonDecor(layout, theme, rng) {
    const addRoomProp = (room, kind, x, y, sx = 1, sy = 1) => {
      room.decor.push({ kind, x, y, sx, sy });
    };
    const addCorridorProp = (corridor, kind, x, y, sx = 1, sy = 1) => {
      corridor.decor.push({ kind, x, y, sx, sy });
    };

    for (const room of layout.rooms || []) {
      const insetX = room.w * 0.34;
      const insetY = room.h * 0.28;
      if (room.type === "start") {
        addRoomProp(room, "banner", room.x - room.w * 0.24, room.y - room.h * 0.34, 1.1, 1);
        addRoomProp(room, "banner", room.x + room.w * 0.24, room.y - room.h * 0.34, 1.1, 1);
        addRoomProp(room, "brazer", room.x - room.w * 0.26, room.y + room.h * 0.12, 1, 1);
        addRoomProp(room, "brazer", room.x + room.w * 0.26, room.y + room.h * 0.12, 1, 1);
      } else if (room.type === "boss") {
        addRoomProp(room, "dais", room.x, room.y + room.h * 0.08, 1.8, 1.15);
        addRoomProp(room, "banner", room.x - room.w * 0.28, room.y - room.h * 0.34, 1.2, 1.1);
        addRoomProp(room, "banner", room.x + room.w * 0.28, room.y - room.h * 0.34, 1.2, 1.1);
        addRoomProp(room, "pillar", room.x - room.w * 0.22, room.y - room.h * 0.05, 1.1, 1.1);
        addRoomProp(room, "pillar", room.x + room.w * 0.22, room.y - room.h * 0.05, 1.1, 1.1);
      } else if (room.type === "loot") {
        addRoomProp(room, "crate", room.x - insetX * 0.6, room.y + insetY * 0.18, 1.05, 1);
        addRoomProp(room, "crate", room.x + insetX * 0.5, room.y - insetY * 0.24, 0.95, 0.95);
      } else if (room.type === "key") {
        addRoomProp(room, "shelf", room.x - insetX * 0.72, room.y - insetY * 0.34, 1.15, 1);
        addRoomProp(room, "shelf", room.x + insetX * 0.68, room.y - insetY * 0.34, 1.15, 1);
        addRoomProp(room, "table", room.x, room.y + insetY * 0.06, 1.1, 1);
      } else if (room.type === "shrine") {
        addRoomProp(room, "pool", room.x, room.y, 1.2, 1);
        addRoomProp(room, "brazer", room.x - insetX * 0.78, room.y + insetY * 0.2, 0.9, 0.9);
        addRoomProp(room, "brazer", room.x + insetX * 0.78, room.y + insetY * 0.2, 0.9, 0.9);
      } else {
        const pillarCount = room.type === "hall" ? 4 : 2;
        for (let i = 0; i < pillarCount; i++) {
          const px = room.x + ((i % 2 === 0 ? -1 : 1) * insetX * (0.48 + (i % 3) * 0.06));
          const py = room.y + (Math.floor(i / 2) - 0.5) * insetY * 1.05;
          addRoomProp(room, "pillar", px, py, 1, 1);
        }
        addRoomProp(room, "rubble", room.x - insetX * 0.58, room.y + insetY * 0.52, 1.2, 1);
        addRoomProp(room, "rubble", room.x + insetX * 0.55, room.y - insetY * 0.52, 1, 0.9);
      }
    }

    for (const corridor of layout.corridors || []) {
      if (corridor.orientation === "h") {
        addCorridorProp(corridor, "sconce", corridor.x - corridor.w * 0.24, corridor.y - corridor.h * 0.28, 0.9, 1);
        addCorridorProp(corridor, "sconce", corridor.x + corridor.w * 0.24, corridor.y - corridor.h * 0.28, 0.9, 1);
      } else {
        addCorridorProp(corridor, "sconce", corridor.x - corridor.w * 0.28, corridor.y - corridor.h * 0.22, 0.9, 1);
        addCorridorProp(corridor, "sconce", corridor.x - corridor.w * 0.28, corridor.y + corridor.h * 0.22, 0.9, 1);
      }

      if (rng.next() < 0.75) {
        addCorridorProp(
          corridor,
          "rubble",
          corridor.x + rng.range(-corridor.w * 0.22, corridor.w * 0.22),
          corridor.y + rng.range(-corridor.h * 0.22, corridor.h * 0.22),
          0.95,
          0.9
        );
      }
    }
  }

  _buildDungeonBlockedRects(layout) {
    const blocked = [];
    const addRect = (x, y, w, h) => {
      if (w > 6 && h > 6) blocked.push({ x, y, w, h });
    };

    for (const room of layout.rooms || []) {
      const left = room.x - room.w * 0.5;
      const right = room.x + room.w * 0.5;
      const top = room.y - room.h * 0.5;
      const bottom = room.y + room.h * 0.5;
      const wall = 5;
      const openingsBySide = { top: [], right: [], bottom: [], left: [] };
      for (const opening of room.openings || []) openingsBySide[opening.side].push(opening);

      const addHorizontalSegments = (side) => {
        const y = side === "top" ? top + wall * 0.5 : bottom - wall * 0.5;
        const openings = openingsBySide[side].slice().sort((a, b) => a.center - b.center);
        let cursor = left;
        for (const opening of openings) {
          const gapLeft = Math.max(left, opening.center - opening.span * 0.5);
          const gapRight = Math.min(right, opening.center + opening.span * 0.5);
          if (gapLeft > cursor) addRect((cursor + gapLeft) * 0.5, y, gapLeft - cursor, wall);
          cursor = Math.max(cursor, gapRight);
        }
        if (cursor < right) addRect((cursor + right) * 0.5, y, right - cursor, wall);
      };

      const addVerticalSegments = (side) => {
        const x = side === "left" ? left + wall * 0.5 : right - wall * 0.5;
        const openings = openingsBySide[side].slice().sort((a, b) => a.center - b.center);
        let cursor = top;
        for (const opening of openings) {
          const gapTop = Math.max(top, opening.center - opening.span * 0.5);
          const gapBottom = Math.min(bottom, opening.center + opening.span * 0.5);
          if (gapTop > cursor) addRect(x, (cursor + gapTop) * 0.5, wall, gapTop - cursor);
          cursor = Math.max(cursor, gapBottom);
        }
        if (cursor < bottom) addRect(x, (cursor + bottom) * 0.5, wall, bottom - cursor);
      };

      addHorizontalSegments("top");
      addHorizontalSegments("bottom");
      addVerticalSegments("left");
      addVerticalSegments("right");
    }

    for (const corridor of layout.corridors || []) {
      const wall = 3;
      const trim = 54;
      if (corridor.orientation === "h") {
        addRect(corridor.x, corridor.y - corridor.h * 0.5 + wall * 0.5, Math.max(10, corridor.w - trim * 2), wall);
        addRect(corridor.x, corridor.y + corridor.h * 0.5 - wall * 0.5, Math.max(10, corridor.w - trim * 2), wall);
      } else {
        addRect(corridor.x - corridor.w * 0.5 + wall * 0.5, corridor.y, wall, Math.max(10, corridor.h - trim * 2));
        addRect(corridor.x + corridor.w * 0.5 - wall * 0.5, corridor.y, wall, Math.max(10, corridor.h - trim * 2));
      }
    }

    return blocked;
  }

  _drawDungeonStoneFloor(ctx, gx, gy, w, h, theme, seedRef, tone = 0.92) {
    const g = ctx.createLinearGradient(gx, gy, gx, gy + h);
    g.addColorStop(0, this._shadeHex(theme.floor0 || "#252830", 0.02 * tone));
    g.addColorStop(0.55, this._shadeHex(theme.floor1 || "#1a1f27", -0.01));
    g.addColorStop(1, this._shadeHex(theme.floor2 || "#12161d", -0.04));
    ctx.fillStyle = g;
    ctx.fillRect(gx, gy, w, h);

    const seed = typeof seedRef === "string" ? seedRef.length * 97 : ((seedRef?.x || 0) ^ (seedRef?.y || 0) ^ (seedRef?.w || 0));
    for (let yy = gy + 16; yy < gy + h - 12; yy += 24) {
      for (let xx = gx + 16; xx < gx + w - 12; xx += 28) {
        const jitter = hash2(seed, xx | 0, yy | 0);
        const rw = 18 + (Math.abs(jitter) % 12);
        const rh = 10 + (Math.abs(jitter >> 2) % 8);
        const jx = (jitter & 15) - 7;
        const jy = ((jitter >> 4) & 15) - 7;
        ctx.fillStyle = (jitter & 1) ? "rgba(255,255,255,0.025)" : "rgba(0,0,0,0.08)";
        ctx.fillRect(xx + jx, yy + jy, rw, rh);
      }
    }
  }

  _drawDungeonGrime(ctx, gx, gy, w, h, seedRef) {
    const seed = typeof seedRef === "string" ? seedRef.length * 131 : ((seedRef?.x || 0) ^ (seedRef?.y || 0));
    ctx.fillStyle = "rgba(0,0,0,0.16)";
    ctx.fillRect(gx, gy, w, 10);
    ctx.fillRect(gx, gy + h - 12, w, 12);
    ctx.fillRect(gx, gy, 10, h);
    ctx.fillRect(gx + w - 12, gy, 12, h);
    for (let i = 0; i < 5; i++) {
      const px = gx + 36 + (Math.abs(hash2(seed, i, 17)) % Math.max(24, Math.round(w - 72)));
      const py = gy + 32 + (Math.abs(hash2(seed, i, 41)) % Math.max(24, Math.round(h - 64)));
      ctx.fillStyle = i % 2 === 0 ? "rgba(255,255,255,0.03)" : "rgba(0,0,0,0.10)";
      ctx.beginPath();
      ctx.ellipse(px, py, 24 + (i % 3) * 10, 10 + (i % 2) * 5, (i * 0.45) % Math.PI, 0, Math.PI * 2);
      ctx.fill();
    }
  }

  _shadeHex(hex, amount = 0) {
    const raw = String(hex || "#000000").replace("#", "");
    const full = raw.length === 3 ? raw.split("").map((c) => c + c).join("") : raw;
    const n = Number.parseInt(full, 16);
    if (!Number.isFinite(n)) return hex || "#000000";
    const shift = Math.round(clamp(amount, -0.5, 0.5) * 255);
    const r = clamp(((n >> 16) & 255) + shift, 0, 255) | 0;
    const g = clamp(((n >> 8) & 255) + shift, 0, 255) | 0;
    const b = clamp((n & 255) + shift, 0, 255) | 0;
    return `rgb(${r},${g},${b})`;
  }

  _getDungeonRoom(id = this.dungeon.currentRoomId) {
    return this.dungeon?.layout?.rooms?.find((room) => room.id === id) || null;
  }

  _drawDungeonRoomWalls(ctx, room, theme, active = false) {
    const left = room.x - room.w * 0.5;
    const right = room.x + room.w * 0.5;
    const top = room.y - room.h * 0.5;
    const bottom = room.y + room.h * 0.5;
    const wall = 14;
    const edge = active ? "rgba(215,184,126,0.56)" : "rgba(112,88,61,0.48)";
    const face = room.type === "boss" ? "rgba(24,14,18,0.96)" : "rgba(20,17,15,0.94)";

    const openingsBySide = { top: [], right: [], bottom: [], left: [] };
    for (const opening of room.openings || []) openingsBySide[opening.side].push(opening);

    const drawHorizontal = (y, side) => {
      const span = side === "top" ? top : bottom - wall;
      const openings = openingsBySide[side].slice().sort((a, b) => a.center - b.center);
      let cursor = left;
      for (const opening of openings) {
        const gapLeft = Math.max(left, opening.center - opening.span * 0.5);
        const gapRight = Math.min(right, opening.center + opening.span * 0.5);
        if (gapLeft > cursor) {
          ctx.fillStyle = face;
          ctx.fillRect(cursor, span, gapLeft - cursor, wall);
        }
        cursor = Math.max(cursor, gapRight);
      }
      if (cursor < right) {
        ctx.fillStyle = face;
        ctx.fillRect(cursor, span, right - cursor, wall);
      }
      ctx.strokeStyle = edge;
      ctx.lineWidth = 3;
      ctx.beginPath();
      ctx.moveTo(left + 2, side === "top" ? top + 1.5 : bottom - 1.5);
      ctx.lineTo(right - 2, side === "top" ? top + 1.5 : bottom - 1.5);
      ctx.stroke();
    };

    const drawVertical = (x, side) => {
      const span = side === "left" ? left : right - wall;
      const openings = openingsBySide[side].slice().sort((a, b) => a.center - b.center);
      let cursor = top;
      for (const opening of openings) {
        const gapTop = Math.max(top, opening.center - opening.span * 0.5);
        const gapBottom = Math.min(bottom, opening.center + opening.span * 0.5);
        if (gapTop > cursor) {
          ctx.fillStyle = face;
          ctx.fillRect(span, cursor, wall, gapTop - cursor);
        }
        cursor = Math.max(cursor, gapBottom);
      }
      if (cursor < bottom) {
        ctx.fillStyle = face;
        ctx.fillRect(span, cursor, wall, bottom - cursor);
      }
      ctx.strokeStyle = edge;
      ctx.lineWidth = 3;
      ctx.beginPath();
      ctx.moveTo(side === "left" ? left + 1.5 : right - 1.5, top + 2);
      ctx.lineTo(side === "left" ? left + 1.5 : right - 1.5, bottom - 2);
      ctx.stroke();
    };

    drawHorizontal(top, "top");
    drawHorizontal(bottom, "bottom");
    drawVertical(left, "left");
    drawVertical(right, "right");
  }

  _drawDungeonCorridorWalls(ctx, rect, theme) {
    const gx = rect.x - rect.w * 0.5;
    const gy = rect.y - rect.h * 0.5;
    const wall = 10;
    const face = "rgba(22,18,15,0.95)";

    if (rect.orientation === "h") {
      ctx.fillStyle = face;
      ctx.fillRect(gx, gy, rect.w, wall);
      ctx.fillRect(gx, gy + rect.h - wall, rect.w, wall);
      ctx.strokeStyle = "rgba(120,92,64,0.44)";
      ctx.lineWidth = 2;
      ctx.beginPath();
      ctx.moveTo(gx + 4, gy + 1.5);
      ctx.lineTo(gx + rect.w - 4, gy + 1.5);
      ctx.moveTo(gx + 4, gy + rect.h - 1.5);
      ctx.lineTo(gx + rect.w - 4, gy + rect.h - 1.5);
      ctx.stroke();
    } else {
      ctx.fillStyle = face;
      ctx.fillRect(gx, gy, wall, rect.h);
      ctx.fillRect(gx + rect.w - wall, gy, wall, rect.h);
      ctx.strokeStyle = "rgba(120,92,64,0.44)";
      ctx.lineWidth = 2;
      ctx.beginPath();
      ctx.moveTo(gx + 1.5, gy + 4);
      ctx.lineTo(gx + 1.5, gy + rect.h - 4);
      ctx.moveTo(gx + rect.w - 1.5, gy + 4);
      ctx.lineTo(gx + rect.w - 1.5, gy + rect.h - 4);
      ctx.stroke();
    }
  }

  _drawDungeonDecor(ctx, items, theme) {
    for (const item of items || []) {
      const sx = item.sx || 1;
      const sy = item.sy || 1;
      ctx.save();
      ctx.translate(item.x, item.y);
      ctx.scale(sx, sy);
      switch (item.kind) {
        case "pillar":
          ctx.fillStyle = theme.propB;
          ctx.fillRect(-12, -16, 24, 34);
          ctx.fillStyle = theme.propA;
          ctx.fillRect(-16, -22, 32, 10);
          ctx.fillRect(-16, 12, 32, 8);
          break;
        case "rubble":
          ctx.fillStyle = theme.propB;
          for (let i = 0; i < 4; i++) {
            ctx.beginPath();
            ctx.ellipse(-16 + i * 10, -2 + (i % 2) * 6, 7 + (i % 2) * 3, 5 + ((i + 1) % 2) * 3, i * 0.25, 0, Math.PI * 2);
            ctx.fill();
          }
          break;
        case "crate":
          ctx.fillStyle = "#5a4632";
          ctx.fillRect(-18, -14, 36, 28);
          ctx.strokeStyle = "#8a6b4a";
          ctx.lineWidth = 2;
          ctx.strokeRect(-17, -13, 34, 26);
          ctx.beginPath();
          ctx.moveTo(-18, 0);
          ctx.lineTo(18, 0);
          ctx.moveTo(0, -14);
          ctx.lineTo(0, 14);
          ctx.stroke();
          break;
        case "table":
          ctx.fillStyle = "#61462f";
          ctx.fillRect(-26, -10, 52, 20);
          ctx.fillStyle = "#3b2a1e";
          ctx.fillRect(-22, 10, 6, 12);
          ctx.fillRect(16, 10, 6, 12);
          ctx.fillRect(-22, -22, 6, 12);
          ctx.fillRect(16, -22, 6, 12);
          break;
        case "shelf":
          ctx.fillStyle = "#3a2f24";
          ctx.fillRect(-30, -12, 60, 24);
          ctx.fillStyle = "#71573b";
          ctx.fillRect(-30, -12, 60, 5);
          ctx.fillRect(-30, 1, 60, 5);
          break;
        case "banner":
          ctx.fillStyle = "#3f2636";
          ctx.fillRect(-5, -24, 10, 12);
          ctx.fillStyle = "#7a4da0";
          ctx.beginPath();
          ctx.moveTo(-18, -12);
          ctx.lineTo(18, -12);
          ctx.lineTo(12, 18);
          ctx.lineTo(0, 9);
          ctx.lineTo(-12, 18);
          ctx.closePath();
          ctx.fill();
          break;
        case "brazer":
        case "sconce":
          ctx.fillStyle = "#584b3a";
          ctx.beginPath();
          ctx.arc(0, 8, 9, 0, Math.PI * 2);
          ctx.fill();
          ctx.fillStyle = "#ffbd64";
          ctx.beginPath();
          ctx.ellipse(0, -4, 10, 16, 0, 0, Math.PI * 2);
          ctx.fill();
          ctx.fillStyle = "rgba(255,200,96,0.18)";
          ctx.beginPath();
          ctx.arc(0, -2, item.kind === "sconce" ? 24 : 30, 0, Math.PI * 2);
          ctx.fill();
          break;
        case "pool":
          ctx.fillStyle = "rgba(100,196,255,0.18)";
          ctx.beginPath();
          ctx.ellipse(0, 0, 38, 22, 0, 0, Math.PI * 2);
          ctx.fill();
          ctx.strokeStyle = "rgba(160,232,255,0.46)";
          ctx.lineWidth = 2;
          ctx.stroke();
          break;
        case "dais":
          ctx.fillStyle = "#463027";
          ctx.fillRect(-52, -12, 104, 24);
          ctx.fillStyle = "#6a4938";
          ctx.fillRect(-40, -22, 80, 18);
          break;
      }
      ctx.restore();
    }
  }

  _findDungeonRoomAt(x, y, inset = 0) {
    const rooms = this.dungeon?.layout?.rooms || [];
    return rooms.find((room) =>
      x >= room.x - room.w * 0.5 + inset &&
      x <= room.x + room.w * 0.5 - inset &&
      y >= room.y - room.h * 0.5 + inset &&
      y <= room.y + room.h * 0.5 - inset
    ) || null;
  }

  _getNearbyDungeonDoor(radius = 104) {
    if (!this.dungeon.active) return null;
    const rectDist2 = (rect) => {
      const dx = Math.max(Math.abs(this.hero.x - rect.x) - rect.w * 0.5, 0);
      const dy = Math.max(Math.abs(this.hero.y - rect.y) - rect.h * 0.5, 0);
      return dx * dx + dy * dy;
    };
    const roomId = this.dungeon.currentRoomId;
    let best = null;
    let bestD2 = radius * radius;
    for (const door of this.dungeon?.layout?.doors || []) {
      if (roomId && door.a !== roomId && door.b !== roomId) continue;
      const d2 = rectDist2(door.blocker || { x: door.x, y: door.y, w: 16, h: 16 });
      if (d2 <= bestD2) {
        best = door;
        bestD2 = d2;
      }
    }
    return best;
  }

  _getDungeonNearbyCacheRoom(radius = 78) {
    if (!this.dungeon.active) return null;
    const room = this._getDungeonRoom();
    if (!room || room.type === "start" || room.type === "boss" || room.cacheOpened) return null;
    const cache = this._getDungeonRoomCacheAnchor(room);
    return dist2(this.hero.x, this.hero.y, cache.x, cache.y) <= radius * radius ? room : null;
  }

  _getDungeonRoomCacheAnchor(room) {
    return {
      x: room.x + (room.type === "key" ? room.w * 0.18 : room.type === "loot" ? -room.w * 0.18 : room.type === "shrine" ? -room.w * 0.16 : room.w * 0.12),
      y: room.y - room.h * 0.10,
    };
  }

  _isHeroNearDungeonReturn(radius = 92) {
    const p = this.dungeon?.layout?.returnStair;
    return !!p && dist2(this.hero.x, this.hero.y, p.x, p.y) <= radius * radius;
  }

  _isHeroNearDungeonExitStair(radius = 92) {
    const p = this.dungeon?.layout?.exitStair;
    return !!p && dist2(this.hero.x, this.hero.y, p.x, p.y) <= radius * radius;
  }

  _openDungeonDoor(door) {
    if (!door || door.open) return;
    if (door.locked === "key") {
      this.dungeon.keys = Math.max(0, (this.dungeon.keys || 0) - 1);
    }
    door.open = true;
    this._spawnFloatingText(door.x, door.y - 18, door.locked === "key" ? "Unlocked" : "Opened", "#8be9ff");
    this._msg(door.locked === "key" ? "Dungeon key used" : "Door opened", 1.0);
  }

  _isDungeonDoorUnlocked(door, room = this._getDungeonRoom(this.dungeon?.currentRoomId)) {
    if (!door) return false;
    if (door.open || door.locked === "none") return true;
    if (door.locked === "key") return (this.dungeon?.keys || 0) > 0;
    if (door.locked !== "clear") return !!door.unlocked;
    if (door.unlocked) return true;
    if (!room) return false;
    if ((door.a === room.id || door.b === room.id) && room.id === this.dungeon?.layout?.startRoomId) return true;
    return !!room.cleared;
  }

  _dungeonHasLivingEnemies(roomId = this.dungeon.currentRoomId) {
    return this.enemies.some((e) => e?.alive && (!roomId || e.dungeonRoomId === roomId));
  }

  _claimDungeonClearReward(room = this._getDungeonRoom()) {
    if (!room || room.rewardClaimed) return;
    room.rewardClaimed = true;
    const floor = Math.max(1, this.dungeon.floor || 1);
    const roomBonus =
      room.type === "boss" ? 34 :
      room.type === "hall" ? 22 :
      room.type === "shrine" ? 18 :
      14;
    const gold = roomBonus + floor * 5 + Math.round((this.hero.level || 1) * 1.8);
    this.hero.gold += gold;
    this.hero.giveXP?.(6 + floor * 2 + (room.type === "boss" ? 10 : 0));

    if (room.type !== "boss" && floor % 2 === 0) {
      const potionType = room.type === "shrine" || floor % 4 === 0 ? "mana" : "hp";
      this.hero.potions[potionType] = (this.hero.potions[potionType] || 0) + 1;
    }

    if (room.type === "key" && !room.cacheOpened) {
      room.cacheOpened = true;
      this.dungeon.keys = (this.dungeon.keys || 0) + 1;
      this._spawnFloatingText(this.hero.x, this.hero.y - 52, "Dungeon Key", "#8be9ff");
      this._msg("Key room cleared", 1.0);
    }

    if (room.type === "boss") {
      const slots = EQUIPMENT_SLOTS;
      const slot = slots[Math.abs(hash2(this.seed, floor, this.hero.level || 1)) % slots.length];
      const rarity = floor >= 9 ? "epic" : floor >= 5 ? "rare" : "uncommon";
      const gear = makeGear(slot, Math.max(1, (this.hero.level || 1) + Math.floor(floor / 2)), rarity, hash2(this.seed, floor, slot.length));
      gear.name = `Depth-Forged ${gear.name}`;
      this.hero.inventory.push(gear);
      this._spawnFloatingText(this.hero.x, this.hero.y - 58, `Gear PWR ${gear.score || "-"}`, gear.color || "#dc7cff");
      const done = this.progress.storyMilestones || (this.progress.storyMilestones = {});
      if (!done.mountainPassAccess) {
        done.mountainPassAccess = true;
        this.hero.state.mountainPassAccess = true;
        this._spawnFloatingText(this.hero.x, this.hero.y - 74, "Pass Sigil", "#8be9ff");
        this._msg("Dungeon reward: mountain passes can now be crossed on foot", 2.0);
      }
    }

    this._spawnFloatingText(this.hero.x, this.hero.y - 38, `${room.type === "boss" ? "Boss room" : "Room clear"} +${gold}g`, "#ffd86e");
  }

  _spawnDungeonWave(room = this._getDungeonRoom()) {
    const enemies = this._makeDungeonWaveEnemies(room);
    if (enemies.length) this.enemies.push(...enemies);
  }

  _makeDungeonWaveEnemies(room = this._getDungeonRoom()) {
    if (!room || room.type === "start") return [];
    if (this.dungeon.kind === "dragon-lair") {
      if (room.type !== "boss") return [];
      const level = Math.max(10, this.dungeon.floor || this.hero.level || 1);
      const dragon = new Enemy(room.x, room.y - 24, level, "dragon", hash2(room.x | 0, room.y | 0, this.seed, level), false, true);
      dragon.name = "Ancient Dragon";
      dragon.progressId = this.dungeon.lairId || null;
      dragon.affix = dragon.name;
      dragon.dungeonRoomId = room.id;
      dragon.extraLoot = 40;
      dragon.hp = Math.round((dragon.hp || dragon.maxHp || 100) * 1.25);
      dragon.maxHp = dragon.hp;
      return [dragon];
    }
    const floor = Math.max(1, this.dungeon.floor || 1);
    const theme = this._dungeonTheme(floor);
    const roomSeed = hash2(this.seed, floor, room.id.length, room.x | 0, room.y | 0);
    const rng = new RNG(roomSeed);
    const enemies = [];

    const addEnemy = (kind, elite = false, boss = false, px = null, py = null) => {
      const x = px ?? rng.range(room.x - room.w * 0.28, room.x + room.w * 0.28);
      const y = py ?? rng.range(room.y - room.h * 0.20, room.y + room.h * 0.20);
      const enemy = new Enemy(x, y, Math.max(1, (this.hero.level || 1) + floor - 1), kind, hash2(x | 0, y | 0, roomSeed), elite, boss);
      enemy.dungeonRoomId = room.id;
      enemies.push(this._applyEnemyAffix(enemy));
    };

    if (room.type === "boss") {
      addEnemy(theme.enemies[0], false, true, room.x, room.y - 40);
      for (let i = 0; i < Math.min(2, 1 + Math.floor(floor / 6)); i++) {
        addEnemy(this._pickFrom(theme.enemies.slice(1)), i === 1 && floor >= 6, false);
      }
    } else {
      const baseCount =
        room.type === "hall" ? 1 + Math.min(1, Math.floor(floor / 7)) :
        room.type === "shrine" ? 1 :
        room.type === "armory" || room.type === "crypt" ? 2 :
        1;
      for (let i = 0; i < baseCount; i++) {
        addEnemy(this._pickFrom(theme.enemies), room.type === "hall" && i === baseCount - 1 && floor >= 4, false);
      }
    }

    return enemies;
  }

  _queueDungeonWave(room = this._getDungeonRoom()) {
    const enemies = this._makeDungeonWaveEnemies(room);
    if (!enemies?.length) return;
    if (this.dungeon.kind === "dragon-lair") {
      this.enemies.push(...enemies);
      return;
    }
    let delay = 0;
    for (const enemy of enemies) {
      this.dungeon.spawnQueue.push({ enemy, delay, roomId: room.id });
      delay += enemy?.boss ? 0.12 : 0.05;
    }
  }

  _processDungeonSpawnQueue(dt) {
    const queue = this.dungeon?.spawnQueue;
    if (!this.dungeon?.active || !queue?.length) return;
    let spawned = 0;
    for (let i = 0; i < queue.length && spawned < 2;) {
      queue[i].delay -= dt;
      if (queue[i].delay > 0) {
        i++;
        continue;
      }
      this.enemies.push(queue[i].enemy);
      queue.splice(i, 1);
      spawned++;
    }
  }

  _updateDungeonState(dt) {
    if (!this.dungeon.active || !this.dungeon.layout) return;
    this._processDungeonSpawnQueue(dt);

    const roomAtHero = this._findDungeonRoomAt(this.hero.x, this.hero.y, 18);
    if (roomAtHero && roomAtHero.id !== this.dungeon.currentRoomId) {
      this.dungeon.currentRoomId = roomAtHero.id;
      roomAtHero.discovered = true;
      this.dungeon.room = roomAtHero;
      this._msg(`${this._titleCase(roomAtHero.type)} room`, 0.8);
    } else if (roomAtHero) {
      this.dungeon.room = roomAtHero;
    }

    const room = this._getDungeonRoom();
    if (!room) return;
    room.discovered = true;

    if (!room.spawned) {
      room.spawned = true;
      this._queueDungeonWave(room);
    }

    const alive = this._dungeonHasLivingEnemies(room.id);
    if (!alive && !room.cleared) {
      room.cleared = true;
      this._claimDungeonClearReward(room);
      for (const door of this.dungeon.layout.doors || []) {
        if (!door.open && door.locked === "clear" && (door.a === room.id || door.b === room.id)) door.unlocked = true;
      }
    }

    const visitedCombat = this.dungeon.layout.rooms.filter((r) => r.cleared && r.type !== "start").length;
    this.dungeon.roomIndex = Math.max(1, visitedCombat);
  }

  _openDungeonCache(room) {
    if (!room || room.cacheOpened) return;
    room.cacheOpened = true;
    const floor = Math.max(1, this.dungeon.floor || 1);
    if (room.type === "key") {
      this.dungeon.keys = (this.dungeon.keys || 0) + 1;
      this._spawnFloatingText(this.hero.x, this.hero.y - 30, "Dungeon Key", "#8be9ff");
      this._msg("A heavy key clinks into your palm", 1.2);
      return;
    }

    if (room.type === "loot") {
      const slots = EQUIPMENT_SLOTS;
      const slot = slots[Math.abs(hash2(this.seed, floor, room.x | 0)) % slots.length];
      const rarity = floor >= 7 ? "rare" : "uncommon";
      const gear = makeGear(slot, Math.max(1, (this.hero.level || 1) + Math.floor(floor / 2)), rarity, hash2(this.seed, floor, room.y | 0));
      gear.name = `Vault ${gear.name}`;
      this.hero.inventory.push(gear);
      this.hero.gold += 20 + floor * 4;
      this._spawnFloatingText(this.hero.x, this.hero.y - 30, gear.name, gear.color || "#dc7cff");
      this._msg("You found a sealed cache", 1.2);
      return;
    }

    this.hero.potions.hp = (this.hero.potions.hp || 0) + 1;
    this.hero.potions.mana = (this.hero.potions.mana || 0) + 1;
    this._awardRelicShards(1, "depths");
    this._spawnFloatingText(this.hero.x, this.hero.y - 30, "Sanctum cache", "#c8ff9a");
    this._msg("The cache restores your reserves", 1.2);
  }

  _isHeroNearDragonHoard(radius = 110) {
    const p = this.dungeon?.layout?.hoard;
    return !!p && dist2(this.hero.x, this.hero.y, p.x, p.y) <= radius * radius;
  }

  _openDragonHoard() {
    if (!this.dungeon?.active || this.dungeon.kind !== "dragon-lair" || this.dungeon.hoardOpened) return;
    const hoard = this.dungeon?.layout?.hoard;
    if (!hoard) return;
    this.dungeon.hoardOpened = true;
    const level = Math.max(8, this.dungeon.floor || this.hero.level || 1);
    const gold = 260 + level * 22;
    this.loot.push(new Loot(hoard.x - 28, hoard.y + 8, "gold", { amount: Math.round(gold * 0.45) }));
    this.loot.push(new Loot(hoard.x + 24, hoard.y + 10, "gold", { amount: Math.round(gold * 0.55) }));
    this.loot.push(new Loot(hoard.x - 12, hoard.y - 18, "potion", { potionType: "hp" }));
    this.loot.push(new Loot(hoard.x + 10, hoard.y - 18, "potion", { potionType: "mana" }));
    const slots = ["weapon", "armor", "helm", "boots"];
    for (let i = 0; i < 2; i++) {
      const slot = slots[Math.abs(hash2(this.seed, level, i, hoard.x | 0, hoard.y | 0)) % slots.length];
      const rarity = i === 0 || level >= 12 ? "epic" : "rare";
      const item = makeGear(slot, Math.max(level, this.hero.level || 1), rarity, hash2(this.seed, slot.length, i, level));
      item.name = `Hoard-Kept ${item.name}`;
      this.loot.push(new Loot(hoard.x + (i === 0 ? -6 : 16), hoard.y - 28 - i * 6, "gear", item));
    }
    this.hero.giveXP?.(18 + level * 3);
    this._awardRelicShards(3, "dragon-hoard");
    this._spawnFloatingText(hoard.x, hoard.y - 34, "Dragon hoard claimed", "#ffd36e");
    this._msg("The hoard spills open", 1.8);
  }

  _leaveDungeon() {
    if (!this.dungeon.active) return;

    const out = this.dungeon.origin || this.world.spawn || { x: 0, y: 0 };
    const safe = this.world._findSafeLandPatchNear?.(out.x, out.y, 140) || this.world.spawn || out;

    this.hero.x = safe.x;
    this.hero.y = safe.y;
    this.hero.vx = 0;
    this.hero.vy = 0;
    this.hero.state.sailing = false;
    if (this.dungeon.kind !== "dragon-lair") {
      this.progress.dungeonBest = Math.max(this.progress.dungeonBest || 0, this.dungeon.floor || 0);
    }
    this.dungeon.active = false;
    this.dungeon.kind = "depths";
    this.dungeon.room = null;
    this.dungeon.lairId = null;
    this.dungeon.roomIndex = 0;
    this.dungeon.totalRooms = 0;
    this.dungeon.roomRewarded = false;
    this.dungeon.layout = null;
    this.dungeon.currentRoomId = null;
    this.dungeon.keys = 0;
    this.dungeon.roomClearT = 0;
    this.dungeon.spawnQueue = [];
    this.dungeon.hoardOpened = false;

    this.camera.x = this.hero.x;
    this.camera.y = this.hero.y;

    this._msg("Left dungeon", 1.0);
  }

  _updateZoneMessage(dt) {
    this._zoneSampleT -= dt;
    if (this._zoneSampleT > 0) return;
    this._zoneSampleT = 0.2;

    const zone = this.dungeon.active
      ? "Dungeon"
      : (this._heroTerrainSample?.zone || this.world.getZoneName?.(this.hero.x, this.hero.y) || "");

    if (zone && zone !== this._lastZoneName) {
      this._lastZoneName = zone;
      this.zoneMsg = zone;
      this.zoneMsgT = 1.1;
    }
  }

  _checkBridgeDiscovery(dt) {
    if (this.dungeon.active) return;
    this._bridgeDiscoveryT = Math.max(0, (this._bridgeDiscoveryT || 0) - dt);
    if (this._bridgeDiscoveryT > 0) return;
    this._bridgeDiscoveryT = 0.32;

    const bridge = this.world?.getBridgeAt?.(this.hero.x, this.hero.y);
    if (!bridge) return;

    const id = `${bridge.cx | 0},${bridge.cy | 0}`;
    if (this.progress.crossedBridges?.has?.(id)) return;
    this.progress.crossedBridges.add(id);

    const gold = 6 + Math.max(1, this.world.getDangerLevel?.(bridge.cx, bridge.cy) || 1) * 3;
    this.hero.gold += gold;
    this.hero.giveXP?.(4);
    this.world?.revealAround?.(bridge.cx, bridge.cy, 620);
    this._spawnFloatingText(this.hero.x, this.hero.y - 34, `Bridge found +${gold}g`, "#ffd86e");
    this._msg(`Bridge route charted (${this.progress.crossedBridges.size})`, 1.1);
  }

  _makeBountyQuest(seedOffset = 0) {
    const targets = ["wolf", "stalker", "scout", "caster", "brute", "ashling", "wisp", "sentinel", "thorn", "duelist", "mender"];
    const target = targets[Math.abs(hash2(this.seed, this.hero.level + seedOffset)) % targets.length];
    const needed = 4 + Math.min(5, Math.floor((this.hero.level || 1) / 2));
    return {
      type: "bounty",
      target,
      needed,
      count: 0,
      rewardGold: 18 + (this.hero.level || 1) * 6,
      rewardXp: 10 + (this.hero.level || 1) * 4,
    };
  }

  _awardRelicShards(amount = 1, source = "relic") {
    const gain = Math.max(0, amount | 0);
    if (!gain) return;

    this.progress.relicShards = Math.max(0, (this.progress.relicShards || 0) + gain);
    this._spawnFloatingText(this.hero.x, this.hero.y - 44, `+${gain} relic`, "#c9a7ff");
    this._checkStoryMilestones(source);
  }

  _checkStoryMilestones(source = "") {
    const shards = this.progress.relicShards || 0;
    const done = this.progress.storyMilestones || (this.progress.storyMilestones = {});
    const milestones = [
      { at: 3, id: "spark", text: "Story: the Ash Crown stirs", hp: 6, mana: 4, gold: 40 },
      { at: 7, id: "ember", text: "Story: ember oath awakened", hp: 8, mana: 6, xp: 45 },
      { at: 12, id: "crown", text: "Story: crown shard restored", hp: 10, mana: 8, gold: 90, xp: 80 },
      { at: 20, id: "dragon", text: "Story: dragon paths revealed", hp: 14, mana: 10, gold: 150, xp: 130 },
    ];

    for (const m of milestones) {
      if (shards < m.at || done[m.id]) continue;
      done[m.id] = true;
      this._grantPermanentStats({ hp: m.hp || 0, mana: m.mana || 0 });
      this.hero.hp = this.hero.maxHp;
      this.hero.mana = this.hero.maxMana;
      this.hero.gold += m.gold || 0;
      if (m.xp) this.hero.giveXP?.(m.xp);
      this._msg(m.text, 2.0);
      this._spawnFloatingText(this.hero.x, this.hero.y - 60, "Milestone", "#c9a7ff");
    }
  }

  _advanceBounty(enemy) {
    if (enemy?.elite) this.progress.eliteKills = (this.progress.eliteKills || 0) + 1;
    if (!this.quest || this.quest.type !== "bounty") this.quest = this._makeBountyQuest();
    if (this.quest.target !== enemy?.kind) return;

    this.quest.count = Math.min(this.quest.needed, (this.quest.count || 0) + 1);
    if (this.quest.count < this.quest.needed) return;

    this._completeBounty();
  }

  _completeBounty() {
    const q = this.quest || this._makeBountyQuest();
    this.progress.bountyCompletions = (this.progress.bountyCompletions || 0) + 1;
    this.hero.gold += q.rewardGold || 0;
    this.hero.giveXP?.(q.rewardXp || 0);

    const slots = EQUIPMENT_SLOTS;
    const slot = slots[this.progress.bountyCompletions % slots.length];
    const rarity = this.progress.bountyCompletions % 4 === 0 ? "rare" : "uncommon";
    const reward = makeGear(slot, Math.max(1, this.hero.level), rarity, hash2(this.seed, this.progress.bountyCompletions));
    reward.name = `Bounty-Marked ${reward.name}`;
    this.hero.inventory.push(reward);

    this._spawnFloatingText(this.hero.x, this.hero.y - 46, `Gear PWR ${reward.score || "-"}`, reward.color || "#ffd86e");
    this._msg(`Bounty complete: +${q.rewardGold}g and ${reward.name}`, 2.0);
    this.quest = this._makeBountyQuest(this.progress.bountyCompletions + 7);
  }

  getObjective() {
    if (this.dungeon.active) {
      const floor = this.dungeon.floor || 1;
      const room = this._getDungeonRoom();
      const alive = room ? this.enemies.reduce((n, e) => n + (e?.alive && e.dungeonRoomId === room.id ? 1 : 0), 0) : this.enemies.reduce((n, e) => n + (e?.alive ? 1 : 0), 0);
      const theme = this.dungeon.kind === "dragon-lair" ? { name: "Dragon Lair" } : this._dungeonTheme(floor);
      const lockedDoor = (this.dungeon?.layout?.doors || []).find((door) => !door.open && (door.a === room?.id || door.b === room?.id));
      const cacheRoom = room && !room.cacheOpened && ["loot", "key", "shrine"].includes(room.type) ? room : null;
      let detail = this.dungeon.kind === "dragon-lair"
        ? alive > 0
          ? "The dragon sits on the hoard. Slay it to claim the treasure."
          : !this.dungeon.hoardOpened
            ? "The dragon is dead. Press F at the hoard to claim it."
            : "Hoard claimed. Use the OUT sigil to leave."
        : alive > 0
        ? `${alive} enemies remain in the ${this._titleCase(room?.type || "room")}.`
        : cacheRoom
        ? "Room clear. Search the cache, then unlock the next door."
        : lockedDoor
        ? lockedDoor.locked === "key"
          ? (this.dungeon.keys > 0 ? "Room clear. Press F at the boss gate to unlock it." : "Room clear. Find a dungeon key to open the boss gate.")
          : "Room clear. Press F at the sealed door."
        : room?.type === "boss"
        ? "Boss defeated. Use the stairs to descend or the OUT sigil to leave."
        : "Room clear. Explore onward.";
      return this._objective(
        this.dungeon.kind === "dragon-lair" ? "Dragon Lair" : `${theme.name} Floor ${floor}`,
        detail,
        null,
        this.dungeon.kind === "dragon-lair" ? "#ff8a5c" : "#dc7cff"
      );
    }

    const tracked = this._getTrackedObjective();
    if (tracked) return tracked;

    const story = this._getStoryObjective();
    if (story) return story;

    if (this.quest?.type === "bounty" && (this.quest.count || 0) < (this.quest.needed || 1)) {
      return this._objective(
        `Bounty: ${this._titleCase(this.quest.target)}`,
        `${this.quest.count || 0}/${this.quest.needed || 1} defeated - press J for details.`,
        this._nearest(this.enemies, (e) => e.alive && e.kind === this.quest.target),
        "#ffd86e"
      );
    }

    if ((this.hero.inventory?.length || 0) > 0) {
      return this._objective(
        "Check your gear",
        "Press I, then Enter to equip or X to salvage.",
        null,
        "#88cfff"
      );
    }

    const unvisitedCamp = this._nearest(
      this.world.camps,
      (camp) => !this.progress.visitedCamps.has(this._progressId(camp))
    );
    if (unvisitedCamp) {
      return this._objective(
        "Find a camp",
        "Follow the marker, then press F for the shop.",
        unvisitedCamp,
        "#ffdc63"
      );
    }

    const unknownWaystone = this._nearest(
      this.world.waystones,
      (waystone) => !this.progress.discoveredWaystones.has(this._progressId(waystone))
    );
    if (unknownWaystone) {
      return this._objective(
        "Discover a waystone",
        "Press F near the blue marker to unlock it.",
        unknownWaystone,
        "#7fe8ff"
      );
    }

    const unclaimedShrine = this._nearest(
      this.world.shrines,
      (shrine) => !this.progress.claimedShrines.has(this._progressId(shrine))
    );
    if (unclaimedShrine) {
      return this._objective(
        "Claim a shrine",
        "Find the violet marker and press F.",
        unclaimedShrine,
        "#b77eff"
      );
    }

    const unopenedCache = this._nearest(
      this.world.caches,
      (cache) => !this.progress.openedCaches.has(this._progressId(cache))
    );
    if (unopenedCache) {
      return this._objective(
        "Open a treasure cache",
        "Look for the gold chest marker.",
        unopenedCache,
        "#ffe19a"
      );
    }

    const undiscoveredSecret = this._nearest(
      this.world.secrets,
      (secret) => !this.progress.discoveredSecrets.has(this._progressId(secret))
    );
    if (undiscoveredSecret) {
      return this._objective(
        "Find hidden lore",
        "Explore old markers for XP, gold, and relic shards.",
        undiscoveredSecret,
        "#ffeaa8"
      );
    }

    const dragonLair = this._nearest(
      this.world.dragonLairs,
      (lair) => !this.progress.defeatedDragons.has(this._progressId(lair))
    );
    if (dragonLair && (this.hero.level || 1) >= 5) {
      return this._objective(
        "Hunt an ancient dragon",
        "Far lairs hold the hardest bosses.",
        dragonLair,
        "#ff8a5c"
      );
    }

    const dungeon = this._nearest(this.world.dungeons);
    if (dungeon) {
      return this._objective(
        "Enter a dungeon",
        "Find the purple marker and press F.",
        dungeon,
        "#dc7cff"
      );
    }

    const enemy = this._nearest(this.enemies, (e) => e.alive);
    return this._objective(
      "Hunt monsters",
      "Use Q/W/E/R and collect dropped loot.",
      enemy,
      "#cf4d5f"
    );
  }

  getTrackedObjectiveSummary() {
    return this._getTrackedObjective() || this.getObjective();
  }

  _objective(title, detail, target, color) {
    return { title, detail, target, color };
  }

  _getTrackedObjective() {
    const mode = this.trackedObjective || "story";
    if (mode === "story") return null;

    if (mode === "bounty" && this.quest?.type === "bounty") {
      return this._objective(
        `Bounty: ${this._titleCase(this.quest.target)}`,
        `${this.quest.count || 0}/${this.quest.needed || 1} defeated - press J to change tracking.`,
        this._nearest(this.enemies, (e) => e.alive && e.kind === this.quest.target),
        "#ffd86e"
      );
    }

    if (mode === "town") {
      const town = this._nearest(this.world.towns, (p) => !this.progress.visitedTowns.has(this._progressId(p))) ||
        this._nearest(this.world.towns);
      if (town) return this._objective("Reach a town", "Find NPCs, supplies, and story hints.", town, "#8be9ff");
    }

    if (mode === "dungeon") {
      const dungeon = this._nearest(this.world.dungeons);
      if (dungeon) return this._objective("Enter a dungeon", "Press F inside the purple gate.", dungeon, "#dc7cff");
    }

    if (mode === "dragon") {
      const lair = this._nearest(this.world.dragonLairs, (p) => !this.progress.defeatedDragons.has(this._progressId(p)));
      if (lair) return this._objective("Hunt an ancient dragon", "Hard bosses guard the far lairs.", lair, "#ff8a5c");
    }

    if (mode === "treasure") {
      const cache = this._nearest(this.world.caches, (p) => !this.progress.openedCaches.has(this._progressId(p)));
      if (cache) return this._objective("Open a treasure cache", "Gold chests hide gear and relic shards.", cache, "#ffe19a");
    }

    if (mode === "secret") {
      const secret = this._nearest(this.world.secrets, (p) => !this.progress.discoveredSecrets.has(this._progressId(p)));
      if (secret) return this._objective("Find hidden lore", "Old markers grant XP, gold, and occasional relic shards.", secret, "#ffeaa8");
    }

    return null;
  }

  _getStoryObjective() {
    const shards = this.progress.relicShards || 0;
    const next = shards < 3 ? 3 : shards < 7 ? 7 : shards < 12 ? 12 : shards < 20 ? 20 : 0;
    if (!next) {
      const dragonLair = this._nearest(
        this.world.dragonLairs,
        (lair) => !this.progress.defeatedDragons.has(this._progressId(lair))
      );
      if (!dragonLair) return null;
      return this._objective("Break the dragon seals", "Hunt ancient dragons for legendary loot.", dragonLair, "#ff8a5c");
    }

    const target =
      this._nearest(this.world.shrines, (p) => !this.progress.claimedShrines.has(this._progressId(p))) ||
      this._nearest(this.world.caches, (p) => !this.progress.openedCaches.has(this._progressId(p))) ||
      this._nearest(this.world.secrets, (p) => !this.progress.discoveredSecrets.has(this._progressId(p))) ||
      this._nearest(this.world.dungeons);

    return this._objective(
      "Restore the Ash Crown",
      `Collect relic shards: ${shards}/${next}`,
      target,
      "#c9a7ff"
    );
  }

  getActiveBossState() {
    const hero = this.hero;
    if (!hero) return null;

    let best = null;
    let bestD2 = Infinity;
    for (const e of this.enemies || []) {
      if (!e?.alive || !e.boss) continue;
      const d2 = dist2(hero.x, hero.y, e.x, e.y);
      const visible = this._isVisibleWorldPoint(e.x, e.y, 240);
      const alert = (e.alertT || 0) > 0.08;
      const engageR = Math.max(760, (e.aggroRadius || 0) + 280);
      if (!this.dungeon?.active && !visible && !alert && d2 > engageR * engageR) continue;
      if (d2 < bestD2) {
        best = e;
        bestD2 = d2;
      }
    }

    if (!best) return null;

    const frac = clamp((best.hp || 0) / Math.max(1, best.maxHp || 1), 0, 1);
    const distance = Math.max(0, Math.round(Math.sqrt(bestD2) / 10) * 10);
    const isDragon = best.kind === "dragon";
    const name = best.name || (isDragon ? "Ancient Dragon" : `${this._titleCase(best.kind)} Boss`);
    const detail =
      isDragon ? "Ancient threat" :
      this.dungeon?.active ? `Dungeon floor ${this.dungeon.floor || 1} boss` :
      "Roaming boss";

    return {
      name,
      detail,
      kind: best.kind || "boss",
      level: best.level || 1,
      hp: Math.round(best.hp || 0),
      maxHp: Math.max(1, Math.round(best.maxHp || 1)),
      frac,
      distance,
      colorA: isDragon ? "#b53045" : "#a9852d",
      colorB: isDragon ? "#ff8a5c" : "#ffd36e",
      accent: isDragon ? "#ff8a5c" : "#ffd36e",
      alive: !!best.alive,
    };
  }

  _titleCase(text) {
    const s = String(text || "");
    return s ? s.charAt(0).toUpperCase() + s.slice(1) : "";
  }

  _nearest(arr, predicate = () => true) {
    let best = null;
    let bestD2 = Infinity;
    for (const p of arr || []) {
      if (!p || !predicate(p)) continue;
      const d = dist2(this.hero.x, this.hero.y, p.x, p.y);
      if (d < bestD2) {
        best = p;
        bestD2 = d;
      }
    }
    return best;
  }

  _drawFloatingTexts(ctx) {
    for (const f of this.floatingTexts) {
      if (!this._isVisibleWorldPoint(f.x, f.y, 80)) continue;
      ctx.save();
      ctx.globalAlpha = f.a;
      ctx.fillStyle = f.color || "#fff";
      ctx.font = "bold 13px Arial";
      ctx.textAlign = "center";
      ctx.fillText(f.text, f.x, f.y);
      ctx.restore();
    }
  }

  _spawnFloatingText(x, y, text, color = "#fff") {
    const cap = this.perf?.maxFloatingTexts || 48;
    if (this.floatingTexts.length >= cap) this.floatingTexts.splice(0, this.floatingTexts.length - cap + 1);
    this.floatingTexts.push({ x, y, text, color, a: 1, vy: -21, life: 1.1 });
  }

  _nearPointOfInterest(x, y, r) {
    const r2 = r * r;
    const check = (arr) => {
      for (const p of arr || []) {
        if (dist2(x, y, p.x, p.y) <= r2) return true;
      }
      return false;
    };

    return check(this.world.camps) ||
      check(this.world.docks) ||
      check(this.world.waystones) ||
      check(this.world.dungeons) ||
      check(this.world.shrines) ||
      check(this.world.caches) ||
      check(this.world.secrets) ||
      check(this.world.dragonLairs);
  }

  _progressId(p) {
    return p?.id != null ? String(p.id) : `${p?.x ?? 0},${p?.y ?? 0}`;
  }

  _rememberProgressId(set, p) {
    if (set?.add && p) set.add(this._progressId(p));
  }

  _cleanupFarEntities(dt = 0.016) {
    this.perf.cleanupTimer += dt;
    if (this.perf.cleanupTimer < this.perf.cleanupEvery) return;
    this.perf.cleanupTimer = 0;

    const maxEnemyD2 = (this.perf.enemyUpdateRadius + 560) ** 2;
    const maxLootD2 = (this.perf.lootUpdateRadius + 420) ** 2;
    const maxProjD2 = (this.perf.projectileUpdateRadius + 260) ** 2;

    let ew = 0;
    for (let i = 0; i < this.enemies.length; i++) {
      const e = this.enemies[i];
      if (!e?.alive || dist2(e.x, e.y, this.hero.x, this.hero.y) >= maxEnemyD2) continue;
      this.enemies[ew++] = e;
    }
    this.enemies.length = ew;

    let lw = 0;
    for (let i = 0; i < this.loot.length; i++) {
      const l = this.loot[i];
      if (!l?.alive || dist2(l.x, l.y, this.hero.x, this.hero.y) >= maxLootD2) continue;
      this.loot[lw++] = l;
    }
    this.loot.length = lw;

    let pw = 0;
    for (let i = 0; i < this.projectiles.length; i++) {
      const p = this.projectiles[i];
      if (!p?.alive || dist2(p.x, p.y, this.hero.x, this.hero.y) >= maxProjD2) continue;
      this.projectiles[pw++] = p;
    }
    this.projectiles.length = pw;
    if (this.loot.length > this.perf.maxLoot) this.loot.splice(0, this.loot.length - this.perf.maxLoot);
    if (this.projectiles.length > this.perf.maxProjectiles) this.projectiles.splice(0, this.projectiles.length - this.perf.maxProjectiles);
    if (this.floatingTexts.length > this.perf.maxFloatingTexts) this.floatingTexts.splice(0, this.floatingTexts.length - this.perf.maxFloatingTexts);
  }

  _ensureHeroSafe(showMsg = false) {
    const onSafeGround = this.world.canWalk?.(this.hero.x, this.hero.y, this.hero);

    if (onSafeGround) {
      return;
    }

    let safe = this.world._findSafeLandPatchNear?.(this.hero.x, this.hero.y, 260);
    if (!safe && this.world.spawn) {
      safe = this.world._findSafeLandPatchNear?.(this.world.spawn.x, this.world.spawn.y, 320);
    }
    if (!safe && this.world.spawn) {
      safe = { x: this.world.spawn.x, y: this.world.spawn.y };
    }
    if (!safe) {
      safe = { x: 0, y: 0 };
    }

    this.hero.x = safe.x;
    this.hero.y = safe.y;
    this.hero.vx = 0;
    this.hero.vy = 0;
    this.hero.state.sailing = false;
    this.hero.state.dashT = 0;
    this.hero.state.hurtT = 0;
    this.hero.state.slowT = 0;
    this.hero.state.poisonT = 0;

    this.camera.x = this.hero.x;
    this.camera.y = this.hero.y;

    if (showMsg) {
      this._msg("Recovered to safe ground", 1.0);
    }
  }

  _saveGame() {
    try {
      this.save.save({
        seed: this.seed,
        worldBuild: this.world?.buildId || "rpg-v109",
        hero: {
          x: this.hero.x,
          y: this.hero.y,
          level: this.hero.level,
          xp: this.hero.xp,
          nextXp: this.hero.nextXp,
          hp: this.hero.hp,
          maxHp: this.hero.maxHp,
          mana: this.hero.mana,
          maxMana: this.hero.maxMana,
          gold: this.hero.gold,
          classId: this.hero.classId || "knight",
          inventory: this.hero.inventory,
          equip: this.hero.equip,
          potions: this.hero.potions,
          bonusStats: this.hero.bonusStats || { hp: 0, mana: 0 },
          state: this.hero.state,
          lastMove: this.hero.lastMove,
          aimDir: this.hero.aimDir,
        },
        progress: {
          discoveredWaystones: Array.from(this.progress.discoveredWaystones || []),
          discoveredDocks: Array.from(this.progress.discoveredDocks || []),
          dungeonBest: this.progress.dungeonBest || 0,
          visitedCamps: Array.from(this.progress.visitedCamps || []),
          eliteKills: this.progress.eliteKills || 0,
          bountyCompletions: this.progress.bountyCompletions || 0,
          campRenown: this.progress.campRenown || {},
          campRestBonusClaimed: this.progress.campRestBonusClaimed || {},
          claimedShrines: Array.from(this.progress.claimedShrines || []),
          openedCaches: Array.from(this.progress.openedCaches || []),
          discoveredSecrets: Array.from(this.progress.discoveredSecrets || []),
          defeatedDragons: Array.from(this.progress.defeatedDragons || []),
          relicShards: this.progress.relicShards || 0,
          storyMilestones: this.progress.storyMilestones || {},
          visitedTowns: Array.from(this.progress.visitedTowns || []),
          crossedBridges: Array.from(this.progress.crossedBridges || []),
          herbs: this.progress.herbs || 0,
          pickedHerbs: Array.from(this.progress.pickedHerbs || []),
          materials: this.progress.materials || { scrap: 0, ore: 0, hide: 0, essence: 0 },
          exploredCells: this.world?.exportDiscovery?.() || [],
        },
        trackedObjective: this.trackedObjective,
        quest: this.quest,
        skillProg: this.skillProg,
        menu: this.menu,
        cooldowns: this.cooldowns,
        dungeon: this.dungeon,
      });
    } catch (err) {
      console.warn("Save failed", err);
    }
  }

  flushSave() {
    this._saveGame();
  }

  _loadGame() {
    try {
      const data = this._bootSaveData || this.save.load?.() || this.save.read?.() || this.save.get?.();
      this._bootSaveData = null;
      if (!data) return;

      const currentWorldBuild = this.world?.buildId || "rpg-v109";
      const needsWorldMigration = data.worldBuild !== currentWorldBuild;

      if (Number.isFinite(+data.seed) && (data.seed | 0) !== this.seed) {
        this.seed = data.seed | 0;
        this.world = new World(this.seed, { viewW: this.w, viewH: this.h, variant: this.worldVariant });
        this._rng = new RNG(hash2(this.seed, 9001));
      }

      if (data.hero) {
        const h = data.hero;
        this.hero.x = this._finiteOr(h.x, this.hero.x);
        this.hero.y = this._finiteOr(h.y, this.hero.y);
        this.hero.level = Math.max(1, this._finiteOr(h.level, this.hero.level));
        this.hero.xp = Math.max(0, this._finiteOr(h.xp, 0));
        this.hero.nextXp = Math.max(1, this._finiteOr(h.nextXp, this.hero.nextXp));
        this.hero.maxHp = Math.max(1, this._finiteOr(h.maxHp, this.hero.maxHp));
        this.hero.hp = clamp(this._finiteOr(h.hp, this.hero.hp), 0, this.hero.maxHp);
        this.hero.maxMana = Math.max(0, this._finiteOr(h.maxMana, this.hero.maxMana));
        this.hero.mana = clamp(this._finiteOr(h.mana, this.hero.mana), 0, this.hero.maxMana);
        this.hero.gold = Math.max(0, this._finiteOr(h.gold, 0));
        this.hero.classId = this._className(h.classId).toLowerCase();
        this.hero.inventory = Array.isArray(h.inventory) ? h.inventory : [];
        this.hero.equip = h.equip || this.hero.equip;
        this.hero.potions = h.potions || this.hero.potions;
        this.hero.bonusStats = { hp: 0, mana: 0 };
        const baseStats = this.hero.getStats?.() || {};
        this.hero.bonusStats = {
          hp: Math.max(h.bonusStats?.hp || 0, Math.round((h.maxHp || 0) - (baseStats.maxHp || 0))),
          mana: Math.max(h.bonusStats?.mana || 0, Math.round((h.maxMana || 0) - (baseStats.maxMana || 0))),
        };
        this.hero.state = h.state || this.hero.state;
        this.hero.lastMove = h.lastMove || this.hero.lastMove;
        this.hero.aimDir = h.aimDir || this.hero.aimDir;

        const stats = this.hero.getStats?.() || {};
        this.hero.maxHp = Math.max(1, stats.maxHp || this.hero.maxHp);
        this.hero.hp = clamp(this.hero.hp, 0, this.hero.maxHp);
        this.hero.maxMana = Math.max(0, stats.maxMana || this.hero.maxMana);
        this.hero.mana = clamp(this.hero.mana, 0, this.hero.maxMana);
      }

      this.hero.vx = 0;
      this.hero.vy = 0;
      this.hero.state.sailing = false;
      this.hero.state.dashT = 0;
      this.hero.state.hurtT = 0;
      this.hero.state.slowT = 0;
      this.hero.state.poisonT = 0;

      if (needsWorldMigration) {
        const start = this.world.getStarterPoint?.() || this.world.spawn || { x: 0, y: 0 };
        this.hero.x = start.x;
        this.hero.y = start.y;
        this.dungeon.active = false;
        this.dungeon.floor = 0;
        this.dungeon.origin = null;
        this._worldBuildMigrated = true;
        this._msg("New roads charted. Returned to the starter road.", 2.2);
      }

      if (data.progress) {
        this.progress.discoveredWaystones = new Set(data.progress.discoveredWaystones || []);
        this.progress.discoveredDocks = new Set(data.progress.discoveredDocks || []);
        this.progress.dungeonBest = data.progress.dungeonBest || 0;
        this.progress.visitedCamps = new Set(data.progress.visitedCamps || []);
        this.progress.eliteKills = data.progress.eliteKills || 0;
        this.progress.bountyCompletions = data.progress.bountyCompletions || 0;
        this.progress.campRenown = data.progress.campRenown || {};
        this.progress.campRestBonusClaimed = data.progress.campRestBonusClaimed || {};
        this.progress.claimedShrines = new Set(data.progress.claimedShrines || []);
        this.progress.openedCaches = new Set(data.progress.openedCaches || []);
        this.progress.discoveredSecrets = new Set(data.progress.discoveredSecrets || []);
        this.progress.defeatedDragons = new Set(data.progress.defeatedDragons || []);
        this.progress.relicShards = data.progress.relicShards || 0;
        this.progress.storyMilestones = data.progress.storyMilestones || {};
        this.progress.visitedTowns = new Set(data.progress.visitedTowns || []);
        this.progress.crossedBridges = new Set(data.progress.crossedBridges || []);
        this.progress.herbs = data.progress.herbs || 0;
        this.progress.pickedHerbs = new Set(data.progress.pickedHerbs || []);
        this.progress.materials = {
          scrap: data.progress.materials?.scrap || 0,
          ore: data.progress.materials?.ore || 0,
          hide: data.progress.materials?.hide || 0,
          essence: data.progress.materials?.essence || 0,
        };
        for (const herb of this.world.herbs || []) herb.picked = this.progress.pickedHerbs.has(herb.id);
        if (!needsWorldMigration) {
          this.world?.importDiscovery?.(data.progress.exploredCells || []);
        }
      }

      this.hero.state.mountainPassAccess = !!this.progress?.storyMilestones?.mountainPassAccess;

      if (typeof data.trackedObjective === "string") {
        this.trackedObjective = data.trackedObjective;
      }

      if (data.quest?.type === "bounty") {
        this.quest = {
          type: "bounty",
          target: data.quest.target || "blob",
          needed: Math.max(1, data.quest.needed || 4),
          count: clamp(data.quest.count || 0, 0, Math.max(1, data.quest.needed || 4)),
          rewardGold: Math.max(0, data.quest.rewardGold || 20),
          rewardXp: Math.max(0, data.quest.rewardXp || 10),
        };
      } else {
        this.quest = this._makeBountyQuest(this.progress.bountyCompletions || 0);
      }

      if (data.skillProg) {
        for (const k of ["q", "w", "e", "r"]) {
          if (data.skillProg[k]) {
            this.skillProg[k].xp = data.skillProg[k].xp || 0;
            this.skillProg[k].level = Math.max(1, data.skillProg[k].level || 1);
          }
        }
      }

      if (data.menu) {
        this.menu.open = data.menu.open || null;
        if (this.menu.open === "shop" || this.menu.open === "town") this.menu.open = null;
        this.menu.mapZoom = clamp(this._finiteOr(data.menu.mapZoom, this.menu.mapZoom || 1), 1, 8);
      }

      if (data.cooldowns) {
        this.cooldowns.q = data.cooldowns.q || 0;
        this.cooldowns.w = data.cooldowns.w || 0;
        this.cooldowns.e = data.cooldowns.e || 0;
        this.cooldowns.r = data.cooldowns.r || 0;
      }

      this.camera.x = this.hero.x;
      this.camera.y = this.hero.y;
      this._lastHeroLevel = this.hero.level || 1;
    } catch (err) {
      console.warn("Load failed", err);
    }
  }

  _finiteOr(value, fallback) {
    const n = Number(value);
    return Number.isFinite(n) ? n : fallback;
  }

  _msg(text, t = 1.0) {
    this.msg = text;
    this.msgT = t;
  }
}
