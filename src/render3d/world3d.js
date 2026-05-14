import * as THREE from "three";
import { OrbitControls } from "three/addons/controls/OrbitControls.js";

import Save from "../save.js";
import World from "../world.js";
import { hash2 } from "../util.js";

const SAVE_KEY = "broke-knight-save-v106";
const TERRAIN_SIZE = 24000;
const TERRAIN_SEGMENTS = 168;
const RIVER_SAMPLE_STRIDE = 4;
const ROAD_SAMPLE_STRIDE = 3;
const WALK_SPEED = 560;
const RUN_SPEED = 920;
const FOLLOW_LERP = 0.16;
const ATTACK_RANGE = 145;
const ATTACK_ARC = Math.PI * 0.58;
const ATTACK_COOLDOWN = 0.38;
const ENEMY_ACTIVE_RADIUS = 1700;
const ENEMY_DESPAWN_RADIUS = 2600;
const MAX_ENEMIES = 18;

export default class World3DApp {
  constructor(canvas, ui = {}) {
    this.canvas = canvas;
    this.ui = ui;

    this.renderer = new THREE.WebGLRenderer({
      canvas,
      antialias: true,
      alpha: false,
      powerPreference: "high-performance",
    });
    this.renderer.outputColorSpace = THREE.SRGBColorSpace;
    this.renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 1.75));
    this.renderer.setSize(window.innerWidth, window.innerHeight, false);
    this.renderer.shadowMap.enabled = true;
    this.renderer.shadowMap.type = THREE.PCFSoftShadowMap;

    this.scene = new THREE.Scene();
    this.scene.background = new THREE.Color(0x0a1118);
    this.scene.fog = new THREE.FogExp2(0x0a1118, 0.00007);

    this.camera = new THREE.PerspectiveCamera(58, window.innerWidth / window.innerHeight, 8, 60000);
    this.controls = new OrbitControls(this.camera, this.renderer.domElement);
    this.controls.enableDamping = true;
    this.controls.dampingFactor = 0.08;
    this.controls.maxPolarAngle = Math.PI * 0.46;
    this.controls.minDistance = 260;
    this.controls.maxDistance = 7200;
    this.controls.screenSpacePanning = false;

    this.clock = new THREE.Clock();
    this.rafId = 0;
    this.world = null;
    this.save = new Save(SAVE_KEY);
    this.saveData = null;
    this.hero = { x: 0, y: 0 };
    this.heroMarker = null;
    this.heroHeading = 0;
    this.heroHp = 100;
    this.attackCooldown = 0;
    this.attackFlash = 0;
    this.enemies = [];
    this.enemyGroup = new THREE.Group();
    this.attackFxGroup = new THREE.Group();
    this.enemySpawnTimer = 0;
    this.enemySerial = 0;
    this.keys = new Set();
    this.lastSaveAt = 0;
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
  }

  start() {
    this.saveData = this.save.load() || null;
    const seed = Number.isFinite(+this.saveData?.seed) ? this.saveData.seed | 0 : (Date.now() & 0x7fffffff);

    this.world = new World(seed, {
      viewW: window.innerWidth,
      viewH: window.innerHeight,
    });

    this.hero.x = Number.isFinite(+this.saveData?.hero?.x) ? +this.saveData.hero.x : this.world.spawn.x;
    this.hero.y = Number.isFinite(+this.saveData?.hero?.y) ? +this.saveData.hero.y : this.world.spawn.y;

    this.buildScene();
    this.updateHud();
    this.recenter();

    window.addEventListener("resize", this.resize);
    window.addEventListener("keydown", this.onKeyDown);
    window.addEventListener("keyup", this.onKeyUp);
    window.addEventListener("blur", () => this.keys.clear());
    this.canvas.addEventListener("pointerdown", this.onPointerDown);
    this.ui.recenterBtn?.addEventListener("click", this.recenter);
    this.createDebugPanel();
    this.animate();
  }

  buildScene() {
    this.scene.clear();
    this.finishWorldWarmup();

    this.addLights();
    this.addSkyDome();
    this.addTerrain();
    this.addWater();
    this.addRoads();
    this.addRivers();
    this.addBridges();
    this.addDocks();
    this.addSettlements();
    this.addWorldProps();
    this.addLandmarks();
    this.addHeroMarker();
    this.scene.add(this.enemyGroup);
    this.scene.add(this.attackFxGroup);
    this.spawnEnemyPack(8, 520, 1200);
  }

  finishWorldWarmup() {
    let guard = 0;
    while (!this.world.isBootWarm?.() && guard < 8000) {
      this.world.update?.();
      guard++;
    }
  }

  addLights() {
    const ambient = new THREE.HemisphereLight(0xb7d7ff, 0x3a3024, 1.1);
    this.scene.add(ambient);

    const sun = new THREE.DirectionalLight(0xfff2d7, 2.15);
    sun.position.set(2600, 3800, 1400);
    sun.castShadow = true;
    sun.shadow.mapSize.set(2048, 2048);
    sun.shadow.camera.near = 400;
    sun.shadow.camera.far = 9000;
    sun.shadow.camera.left = -4200;
    sun.shadow.camera.right = 4200;
    sun.shadow.camera.top = 4200;
    sun.shadow.camera.bottom = -4200;
    this.scene.add(sun);
  }

  addSkyDome() {
    const skyGeo = new THREE.SphereGeometry(28000, 32, 18);
    const skyMat = new THREE.ShaderMaterial({
      side: THREE.BackSide,
      uniforms: {
        topColor: { value: new THREE.Color(0x24384f) },
        bottomColor: { value: new THREE.Color(0x091017) },
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
        uniform vec3 topColor;
        uniform vec3 bottomColor;
        varying vec3 vWorldPosition;
        void main() {
          float h = normalize(vWorldPosition + vec3(0.0, 2000.0, 0.0)).y;
          float t = clamp(pow(max(h, 0.0), 0.75), 0.0, 1.0);
          gl_FragColor = vec4(mix(bottomColor, topColor, t), 1.0);
        }
      `,
      depthWrite: false,
    });
    const sky = new THREE.Mesh(skyGeo, skyMat);
    this.scene.add(sky);
  }

  addTerrain() {
    const geometry = new THREE.PlaneGeometry(TERRAIN_SIZE, TERRAIN_SIZE, TERRAIN_SEGMENTS, TERRAIN_SEGMENTS);
    geometry.rotateX(-Math.PI * 0.5);
    const pos = geometry.attributes.position;
    const colors = [];

    for (let i = 0; i < pos.count; i++) {
      const x = pos.getX(i);
      const z = pos.getZ(i);
      const worldX = x;
      const worldY = z;
      const sample = this.world._sampleCell(worldX, worldY);
      const height = this.heightAt(worldX, worldY, sample);
      pos.setY(i, height);
      const color = this.colorForSample(sample);
      colors.push(color.r, color.g, color.b);
    }

    geometry.setAttribute("color", new THREE.Float32BufferAttribute(colors, 3));
    geometry.computeVertexNormals();

    const material = new THREE.MeshStandardMaterial({
      vertexColors: true,
      roughness: 0.96,
      metalness: 0.02,
      flatShading: false,
    });

    const terrain = new THREE.Mesh(geometry, material);
    terrain.receiveShadow = true;
    terrain.castShadow = false;
    this.scene.add(terrain);
    this.terrainMesh = terrain;
  }

  addWater() {
    const geo = new THREE.PlaneGeometry(TERRAIN_SIZE, TERRAIN_SIZE, 1, 1);
    geo.rotateX(-Math.PI * 0.5);
    const mat = new THREE.MeshStandardMaterial({
      color: 0x1b3f5f,
      transparent: true,
      opacity: 0.72,
      roughness: 0.18,
      metalness: 0.04,
    });
    const water = new THREE.Mesh(geo, mat);
    water.position.y = 8;
    this.scene.add(water);
  }

  addRoads() {
    const group = new THREE.Group();
    const baseMat = new THREE.MeshStandardMaterial({
      color: 0x6a5236,
      roughness: 1,
      metalness: 0.01,
      side: THREE.DoubleSide,
    });
    const wornMat = new THREE.MeshStandardMaterial({
      color: 0xa98a63,
      roughness: 0.95,
      metalness: 0,
      side: THREE.DoubleSide,
    });

    for (const road of this.world.roads || []) {
      const pts = this.samplePolyline(road.points || [], ROAD_SAMPLE_STRIDE);
      if (pts.length < 2) continue;
      const width = Math.max(18, (road.width || 28) * 0.82);
      const roadMesh = this.makePathRibbon(pts, width, 5.5, baseMat);
      if (roadMesh) {
        roadMesh.receiveShadow = true;
        group.add(roadMesh);
      }

      const wornMesh = this.makePathRibbon(pts, width * 0.42, 7, wornMat);
      if (wornMesh) group.add(wornMesh);
    }

    this.scene.add(group);
  }

  addRivers() {
    const group = new THREE.Group();
    const waterMat = new THREE.MeshStandardMaterial({
      color: 0x3c80c8,
      emissive: 0x173352,
      emissiveIntensity: 0.2,
      roughness: 0.22,
      metalness: 0.03,
      transparent: true,
      opacity: 0.9,
    });

    for (const band of this.world._riverBands || []) {
      const rawPath = this.world._riverPath(band) || [];
      const pts = this.samplePolyline(rawPath, RIVER_SAMPLE_STRIDE);
      if (pts.length < 2) continue;
      const curvePoints = pts.map((p) => this.toVec3(p.x, p.y, 12)).filter(Boolean);
      if (curvePoints.length < 2) continue;
      const curve = new THREE.CatmullRomCurve3(curvePoints);
      const width = Math.max(6, this.world._riverVisualWidth?.(band) ? this.world._riverVisualWidth(band) * 0.24 : 10);
      const mesh = new THREE.Mesh(
        new THREE.TubeGeometry(curve, Math.max(20, curvePoints.length * 3), width, 8, false),
        waterMat
      );
      mesh.receiveShadow = false;
      mesh.castShadow = false;
      group.add(mesh);
    }

    this.scene.add(group);
  }

  addBridges() {
    const group = new THREE.Group();
    const woodMat = new THREE.MeshStandardMaterial({
      color: 0x8c6943,
      roughness: 0.93,
      metalness: 0.02,
    });
    const railMat = new THREE.MeshStandardMaterial({
      color: 0x5b4127,
      roughness: 0.95,
      metalness: 0.03,
    });

    for (const bridge of this.world.bridges || []) {
      const length = Math.max(24, bridge.length || 80);
      const width = Math.max(16, (bridge.width || 34) * 0.4);
      const center = this.toVec3(bridge.cx, bridge.cy, 28);
      const angle = -(bridge.angle || 0);

      const deck = new THREE.Mesh(new THREE.BoxGeometry(length, 5, width), woodMat);
      deck.position.copy(center);
      deck.rotation.y = angle;
      deck.castShadow = true;
      deck.receiveShadow = true;
      group.add(deck);

      for (const side of [-1, 1]) {
        const rail = new THREE.Mesh(new THREE.BoxGeometry(length, 4, 2.2), railMat);
        rail.position.copy(center);
        rail.position.y += 5;
        rail.rotation.y = angle;
        const offset = new THREE.Vector3(0, 0, side * (width * 0.45));
        offset.applyAxisAngle(new THREE.Vector3(0, 1, 0), angle);
        rail.position.add(offset);
        group.add(rail);
      }
    }

    this.scene.add(group);
  }

  addDocks() {
    const group = new THREE.Group();
    const dockMat = new THREE.MeshStandardMaterial({
      color: 0x8a6b47,
      roughness: 0.95,
      metalness: 0.02,
    });
    const poleMat = new THREE.MeshStandardMaterial({
      color: 0x5d4228,
      roughness: 0.98,
      metalness: 0.02,
    });

    for (const dock of this.world.docks || []) {
      const pos = this.toVec3(dock.x, dock.y, 22);
      const deck = new THREE.Mesh(new THREE.BoxGeometry(44, 4, 26), dockMat);
      deck.position.copy(pos);
      deck.castShadow = true;
      group.add(deck);

      for (const side of [-1, 1]) {
        const post = new THREE.Mesh(new THREE.CylinderGeometry(1.8, 1.8, 10, 6), poleMat);
        post.position.set(pos.x + side * 18, pos.y - 3, pos.z + 9);
        group.add(post);
      }
    }

    this.scene.add(group);
  }

  addSettlements() {
    const group = new THREE.Group();
    const townMat = new THREE.MeshStandardMaterial({
      color: 0xc4b18c,
      roughness: 0.92,
      metalness: 0.01,
    });
    const roofMat = new THREE.MeshStandardMaterial({
      color: 0x5f4030,
      roughness: 0.96,
      metalness: 0.01,
    });
    const campMat = new THREE.MeshStandardMaterial({
      color: 0x7e674a,
      roughness: 0.96,
      metalness: 0.01,
    });

    const addHouse = (x, y, sx, sz, h) => {
      const body = new THREE.Mesh(new THREE.BoxGeometry(sx, h, sz), townMat);
      body.position.copy(this.toVec3(x, y, h * 0.5 + 14));
      body.castShadow = true;
      body.receiveShadow = true;
      group.add(body);

      const roof = new THREE.Mesh(new THREE.ConeGeometry(Math.max(sx, sz) * 0.7, h * 0.58, 4), roofMat);
      roof.position.copy(this.toVec3(x, y, h + 18));
      roof.rotation.y = Math.PI * 0.25;
      roof.castShadow = true;
      group.add(roof);
    };

    if (this.world.startTown) {
      addHouse(this.world.startTown.x, this.world.startTown.y, 120, 100, 58);
      for (const building of this.world.startTown.buildings || []) {
        addHouse(
          this.world.startTown.x + (building.x || 0),
          this.world.startTown.y + (building.y || 0),
          Math.max(26, (building.w || 40) * 0.85),
          Math.max(24, (building.h || 40) * 0.85),
          34
        );
      }
    }

    for (const town of this.world.towns || []) {
      addHouse(town.x, town.y, 70, 56, 38);
    }

    for (const camp of this.world.camps || []) {
      const tent = new THREE.Mesh(new THREE.ConeGeometry(14, 18, 4), campMat);
      tent.position.copy(this.toVec3(camp.x, camp.y, 18));
      tent.rotation.y = Math.PI * 0.25;
      tent.castShadow = true;
      group.add(tent);
    }

    this.scene.add(group);
  }

  addLandmarks() {
    const group = new THREE.Group();
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
        new THREE.MeshBasicMaterial({ color, transparent: true, opacity: 0.26, depthWrite: false })
      );
      beacon.position.copy(this.toVec3(x, y, height * 0.5 + 28));
      group.add(beacon);
    };

    for (const w of this.world.waystones || []) {
      const stone = new THREE.Mesh(new THREE.ConeGeometry(16, 58, 5), mats.waystone);
      stone.position.copy(this.toVec3(w.x, w.y, 42));
      stone.castShadow = true;
      group.add(stone);
      addBeacon(w.x, w.y, 0x7fe8ff, 180, 5);
    }

    for (const d of this.world.dungeons || []) {
      const gate = new THREE.Mesh(new THREE.TorusGeometry(32, 6, 10, 28), mats.dungeon);
      gate.position.copy(this.toVec3(d.x, d.y, 48));
      gate.rotation.x = Math.PI * 0.5;
      gate.castShadow = true;
      group.add(gate);
      addBeacon(d.x, d.y, 0xdc7cff, 210, 7);
    }

    for (const s of this.world.shrines || []) {
      const base = new THREE.Mesh(new THREE.CylinderGeometry(22, 28, 12, 8), mats.shrine);
      base.position.copy(this.toVec3(s.x, s.y, 18));
      base.castShadow = true;
      group.add(base);
      const pillar = new THREE.Mesh(new THREE.CylinderGeometry(8, 10, 48, 8), mats.shrine);
      pillar.position.copy(this.toVec3(s.x, s.y, 46));
      pillar.castShadow = true;
      group.add(pillar);
    }

    for (const c of this.world.caches || []) {
      const chest = new THREE.Mesh(new THREE.BoxGeometry(26, 18, 18), mats.cache);
      chest.position.copy(this.toVec3(c.x, c.y, 22));
      chest.castShadow = true;
      group.add(chest);
    }

    for (const herb of this.world.herbs || []) {
      const sprout = new THREE.Mesh(new THREE.ConeGeometry(8, 26, 5), mats.herb);
      sprout.position.copy(this.toVec3(herb.x, herb.y, 22));
      sprout.castShadow = true;
      group.add(sprout);
    }

    for (const s of this.world.secrets || []) {
      const marker = new THREE.Mesh(new THREE.OctahedronGeometry(14), mats.secret);
      marker.position.copy(this.toVec3(s.x, s.y, 32));
      marker.castShadow = true;
      group.add(marker);
    }

    for (const lair of this.world.dragonLairs || []) {
      const mound = new THREE.Mesh(new THREE.ConeGeometry(48, 70, 7), mats.dragon);
      mound.position.copy(this.toVec3(lair.x, lair.y, 46));
      mound.castShadow = true;
      group.add(mound);
      addBeacon(lair.x, lair.y, 0xff8a5c, 240, 9);
    }

    this.scene.add(group);
  }

  addWorldProps() {
    const group = new THREE.Group();
    const trunkMat = new THREE.MeshStandardMaterial({ color: 0x4c3523, roughness: 0.96 });
    const leafMat = new THREE.MeshStandardMaterial({ color: 0x355f35, roughness: 0.98 });
    const ashLeafMat = new THREE.MeshStandardMaterial({ color: 0x696363, roughness: 0.98 });
    const rockMat = new THREE.MeshStandardMaterial({ color: 0x7d817f, roughness: 0.94 });
    const brushMat = new THREE.MeshStandardMaterial({ color: 0x6b7b4b, roughness: 0.98 });

    for (const tree of this.world._trees || []) {
      const sample = this.world._sampleCell(tree.x, tree.y);
      const scale = Math.max(0.7, tree.scale || 1);
      const trunk = new THREE.Mesh(new THREE.CylinderGeometry(4 * scale, 6 * scale, 34 * scale, 6), trunkMat);
      trunk.position.copy(this.toVec3(tree.x, tree.y, 26 * scale));
      trunk.castShadow = true;
      group.add(trunk);

      const leaves = new THREE.Mesh(
        new THREE.ConeGeometry(20 * scale, 58 * scale, 8),
        sample.zone === "ashlands" || sample.zone === "ash fields" ? ashLeafMat : leafMat
      );
      leaves.position.copy(this.toVec3(tree.x, tree.y, 64 * scale));
      leaves.castShadow = true;
      group.add(leaves);
    }

    for (const rock of this.world._rocks || []) {
      const scale = Math.max(0.7, rock.scale || 1);
      const mesh = new THREE.Mesh(new THREE.DodecahedronGeometry(12 * scale, 0), rockMat);
      mesh.position.copy(this.toVec3(rock.x, rock.y, 16 * scale));
      mesh.rotation.set((rock.seed || 0) * 0.01, (rock.seed || 0) * 0.013, 0);
      mesh.castShadow = true;
      group.add(mesh);
    }

    for (const item of this.world._clutter || []) {
      const scale = Math.max(0.55, item.scale || 1);
      const mesh = new THREE.Mesh(new THREE.ConeGeometry(7 * scale, 18 * scale, 5), brushMat);
      mesh.position.copy(this.toVec3(item.x, item.y, 14 * scale));
      mesh.castShadow = true;
      group.add(mesh);
    }

    this.scene.add(group);
  }

  addHeroMarker() {
    const group = new THREE.Group();

    const body = new THREE.Mesh(
      new THREE.CapsuleGeometry(12, 30, 6, 12),
      new THREE.MeshStandardMaterial({
        color: 0xd9dde6,
        roughness: 0.6,
        metalness: 0.2,
      })
    );
    body.position.set(0, 30, 0);
    body.castShadow = true;
    group.add(body);

    const cloak = new THREE.Mesh(
      new THREE.ConeGeometry(12, 24, 6),
      new THREE.MeshStandardMaterial({
        color: 0x4c5f72,
        roughness: 0.94,
        metalness: 0,
      })
    );
    cloak.position.set(0, 24, -9);
    cloak.castShadow = true;
    group.add(cloak);

    const blade = new THREE.Mesh(
      new THREE.BoxGeometry(3, 34, 4),
      new THREE.MeshStandardMaterial({ color: 0xb8c4cf, roughness: 0.48, metalness: 0.36 })
    );
    blade.position.set(10, 30, -5);
    blade.rotation.z = -0.42;
    blade.castShadow = true;
    group.add(blade);

    group.position.copy(this.toVec3(this.hero.x, this.hero.y, 0));
    this.heroMarker = group;
    this.scene.add(group);
  }

  createEnemyMesh(kind = "blob") {
    const group = new THREE.Group();
    const palette = {
      blob: [0x668f54, 0x405c38],
      scout: [0x8d6b48, 0x60452e],
      brute: [0x8f5248, 0x5c332e],
      wisp: [0x7fe8ff, 0x265a72],
    };
    const colors = palette[kind] || palette.blob;
    const mat = new THREE.MeshStandardMaterial({
      color: colors[0],
      roughness: 0.8,
      metalness: 0.02,
      emissive: kind === "wisp" ? colors[1] : 0x000000,
      emissiveIntensity: kind === "wisp" ? 0.35 : 0,
    });
    const darkMat = new THREE.MeshStandardMaterial({ color: colors[1], roughness: 0.9 });

    const body =
      kind === "brute"
        ? new THREE.Mesh(new THREE.CapsuleGeometry(18, 36, 6, 10), mat)
        : kind === "scout"
          ? new THREE.Mesh(new THREE.CapsuleGeometry(12, 30, 5, 8), mat)
          : new THREE.Mesh(new THREE.SphereGeometry(kind === "wisp" ? 12 : 16, 14, 10), mat);
    body.position.y = kind === "brute" ? 42 : 30;
    body.castShadow = true;
    group.add(body);

    const head = new THREE.Mesh(new THREE.SphereGeometry(kind === "brute" ? 11 : 8, 10, 8), darkMat);
    head.position.set(0, kind === "brute" ? 68 : 52, -2);
    head.castShadow = true;
    group.add(head);

    const healthBack = new THREE.Mesh(
      new THREE.BoxGeometry(38, 3, 2),
      new THREE.MeshBasicMaterial({ color: 0x1b1512 })
    );
    healthBack.position.set(0, kind === "brute" ? 92 : 75, 0);
    group.add(healthBack);

    const health = new THREE.Mesh(
      new THREE.BoxGeometry(36, 4, 2.4),
      new THREE.MeshBasicMaterial({ color: 0xff6b5c })
    );
    health.position.set(0, kind === "brute" ? 92 : 75, 1);
    group.add(health);
    group.userData.health = health;

    return group;
  }

  spawnEnemyPack(count = 4, minDist = 460, maxDist = 1100) {
    for (let i = 0; i < count; i++) {
      this.spawnEnemyNearHero(minDist, maxDist, i);
    }
    this.updateDebugPanel();
  }

  spawnEnemyNearHero(minDist = 520, maxDist = 1400, salt = 0) {
    const kinds = ["blob", "scout", "blob", "brute", "wisp"];
    for (let tries = 0; tries < 36; tries++) {
      const seed = hash2((this.hero.x + salt * 97) | 0, (this.hero.y - tries * 131) | 0, this.world.seed);
      const angle = ((seed % 6283) / 1000) + tries * 0.71;
      const dist = minDist + ((Math.abs(seed >> 7) % 1000) / 1000) * (maxDist - minDist);
      const x = this.hero.x + Math.cos(angle) * dist;
      const y = this.hero.y + Math.sin(angle) * dist;
      if (!this.world.canWalk?.(x, y, { state: { mountainPassAccess: true } })) continue;

      const kind = kinds[Math.abs(seed) % kinds.length];
      const mesh = this.createEnemyMesh(kind);
      mesh.position.copy(this.toVec3(x, y, 0));
      this.enemyGroup.add(mesh);
      const maxHp = kind === "brute" ? 58 : kind === "wisp" ? 28 : kind === "scout" ? 34 : 38;
      const enemy = {
        id: ++this.enemySerial,
        kind,
        x,
        y,
        hp: maxHp,
        maxHp,
        speed: kind === "brute" ? 190 : kind === "wisp" ? 250 : kind === "scout" ? 280 : 220,
        damage: kind === "brute" ? 14 : kind === "wisp" ? 8 : 9,
        attackCd: 0.5,
        hitT: 0,
        mesh,
      };
      this.enemies.push(enemy);
      return enemy;
    }
    return null;
  }

  clearEnemies() {
    for (const enemy of this.enemies) {
      if (enemy.mesh) this.enemyGroup.remove(enemy.mesh);
    }
    this.enemies.length = 0;
    this.updateDebugPanel();
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

      const left = this.toVec3(here.x + nx * half, here.y + ny * half, lift);
      const right = this.toVec3(here.x - nx * half, here.y - ny * half, lift);
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
    const ridge = this.world._mountainInfluenceAt?.(x, y) || 0;
    const pass = this.world._mountainPassInfluenceAt?.(x, y) || 0;
    let h = Math.max(0, ground - 0.18) * 240;
    h += ridge * 260;
    h -= pass * 80;
    if (s.zone === "mountain") h += 180;
    if (s.zone === "stone flats") h += 70;
    if (s.isWater) h = Math.min(h, 4);
    return h;
  }

  toVec3(x, y, lift = 0) {
    return new THREE.Vector3(x, this.heightAt(x, y) + lift, y);
  }

  recenter() {
    const target = this.toVec3(this.hero.x, this.hero.y, 26);
    this.controls.target.copy(target);
    this.camera.position.set(target.x + 980, target.y + 760, target.z + 980);
    this.camera.lookAt(target);
    this.controls.update();
  }

  onKeyDown(event) {
    const key = this.normalizeKey(event);
    if (!key) return;
    if (key === "`" || key === "f3") {
      this.toggleDebug();
      event.preventDefault();
      return;
    }
    if (key === "f" || key === " ") {
      this.attack();
      event.preventDefault();
      return;
    }
    if (this.debug.enabled) {
      if (key === "p") {
        this.debug.paused = !this.debug.paused;
        this.updateDebugPanel();
        event.preventDefault();
        return;
      }
      if (key === "n") {
        this.spawnEnemyPack(1, 220, 520);
        event.preventDefault();
        return;
      }
      if (key === "c") {
        this.clearEnemies();
        event.preventDefault();
        return;
      }
      if (key === "v") {
        this.toggleWireframe();
        event.preventDefault();
        return;
      }
    }
    this.keys.add(key);
    if (["ArrowUp", "ArrowDown", "ArrowLeft", "ArrowRight", "Shift"].includes(key)) {
      event.preventDefault();
    }
  }

  onKeyUp(event) {
    const key = this.normalizeKey(event);
    if (!key) return;
    this.keys.delete(key);
  }

  normalizeKey(event) {
    if (!event) return "";
    if (event.code === "Space") return " ";
    if (event.key === "Shift") return "Shift";
    if (event.key?.startsWith("Arrow")) return event.key;
    return String(event.key || "").toLowerCase();
  }

  onPointerDown(event) {
    if (event.button !== 0) return;
    this.attack();
  }

  updateMovement(dt) {
    const forwardKey = this.keys.has("w") || this.keys.has("ArrowUp");
    const backKey = this.keys.has("s") || this.keys.has("ArrowDown");
    const leftKey = this.keys.has("a") || this.keys.has("ArrowLeft");
    const rightKey = this.keys.has("d") || this.keys.has("ArrowRight");
    const mx = (rightKey ? 1 : 0) - (leftKey ? 1 : 0);
    const mz = (forwardKey ? 1 : 0) - (backKey ? 1 : 0);
    if (!mx && !mz) return;

    const forward = new THREE.Vector3()
      .subVectors(this.controls.target, this.camera.position)
      .setY(0);
    if (forward.lengthSq() < 0.001) forward.set(0, 0, -1);
    forward.normalize();

    const right = new THREE.Vector3(-forward.z, 0, forward.x).normalize();
    const move = new THREE.Vector3()
      .addScaledVector(forward, mz)
      .addScaledVector(right, mx);
    if (move.lengthSq() < 0.0001) return;
    move.normalize();

    const modifier = this.world.getMoveModifier?.(this.hero.x, this.hero.y) || 1;
    const speed = (this.keys.has("Shift") ? RUN_SPEED : WALK_SPEED) * modifier;
    this.tryMove(move.x * speed * dt, move.z * speed * dt);
    this.heroHeading = Math.atan2(move.x, move.z);
    this.updateHeroMarker();
    this.updateFollowCamera();
    this.updateHud();
    this.saveHeroSoon();
  }

  tryMove(dx, dy) {
    const actor = { state: { mountainPassAccess: true } };
    const nextX = this.hero.x + dx;
    const nextY = this.hero.y + dy;
    if (this.world.canWalk?.(nextX, nextY, actor)) {
      this.hero.x = nextX;
      this.hero.y = nextY;
      return;
    }
    if (this.world.canWalk?.(nextX, this.hero.y, actor)) this.hero.x = nextX;
    if (this.world.canWalk?.(this.hero.x, nextY, actor)) this.hero.y = nextY;
  }

  updateHeroMarker() {
    if (!this.heroMarker) return;
    this.heroMarker.position.copy(this.toVec3(this.hero.x, this.hero.y, 0));
    this.heroMarker.rotation.y = this.heroHeading;
  }

  updateFollowCamera() {
    const desired = this.toVec3(this.hero.x, this.hero.y, 26);
    const before = this.controls.target.clone();
    this.controls.target.lerp(desired, FOLLOW_LERP);
    this.camera.position.add(new THREE.Vector3().subVectors(this.controls.target, before));
  }

  saveHeroSoon() {
    const now = performance.now();
    if (now - this.lastSaveAt < 900) return;
    this.lastSaveAt = now;
    const next = this.saveData || {};
    next.seed = this.world.seed;
    next.worldBuild = this.world.buildId || next.worldBuild || "";
    next.hero = {
      ...(next.hero || {}),
      x: this.hero.x,
      y: this.hero.y,
    };
    this.saveData = next;
    this.save.save(next);
  }

  attack() {
    if (this.attackCooldown > 0) return;
    this.attackCooldown = ATTACK_COOLDOWN;
    this.attackFlash = 0.18;

    const forward = this.heroForward2D();
    this.heroHeading = Math.atan2(forward.x, forward.y);
    this.updateHeroMarker();
    const hit = [];
    for (const enemy of this.enemies) {
      if (!enemy || enemy.hp <= 0) continue;
      const dx = enemy.x - this.hero.x;
      const dy = enemy.y - this.hero.y;
      const d = Math.hypot(dx, dy);
      if (d > ATTACK_RANGE) continue;
      const dot = d > 0 ? (dx / d) * forward.x + (dy / d) * forward.y : 1;
      const angle = Math.acos(Math.max(-1, Math.min(1, dot)));
      if (angle <= ATTACK_ARC * 0.5) hit.push(enemy);
    }

    for (const enemy of hit) {
      enemy.hp -= 22;
      enemy.hitT = 0.18;
      if (enemy.hp <= 0) this.killEnemy(enemy);
      else this.updateEnemyHealth(enemy);
    }

    this.addAttackArcMesh(hit.length > 0);
    this.updateDebugPanel();
  }

  heroForward2D() {
    const forward = new THREE.Vector3()
      .subVectors(this.controls.target, this.camera.position)
      .setY(0);
    if (forward.lengthSq() < 0.001) {
      return { x: Math.sin(this.heroHeading), y: Math.cos(this.heroHeading) };
    }
    forward.normalize();
    return { x: forward.x, y: forward.z };
  }

  addAttackArcMesh(didHit = false) {
    const shape = new THREE.Shape();
    const halfArc = ATTACK_ARC * 0.5;
    const forwardAngle = Math.atan2(Math.sin(this.heroHeading), Math.cos(this.heroHeading));
    shape.moveTo(0, 0);
    for (let i = 0; i <= 18; i++) {
      const a = forwardAngle - halfArc + (i / 18) * ATTACK_ARC;
      shape.lineTo(Math.sin(a) * ATTACK_RANGE, Math.cos(a) * ATTACK_RANGE);
    }
    shape.lineTo(0, 0);

    const geometry = new THREE.ShapeGeometry(shape);
    geometry.rotateX(-Math.PI * 0.5);
    const mesh = new THREE.Mesh(
      geometry,
      new THREE.MeshBasicMaterial({
        color: didHit ? 0xffdf8a : 0xb8d9ff,
        transparent: true,
        opacity: didHit ? 0.38 : 0.22,
        side: THREE.DoubleSide,
        depthWrite: false,
      })
    );
    mesh.position.copy(this.toVec3(this.hero.x, this.hero.y, 16));
    mesh.userData.life = 0.16;
    this.attackFxGroup.add(mesh);
  }

  killEnemy(enemy) {
    enemy.hp = 0;
    if (enemy.mesh) this.enemyGroup.remove(enemy.mesh);
    const index = this.enemies.indexOf(enemy);
    if (index >= 0) this.enemies.splice(index, 1);
  }

  updateEnemyHealth(enemy) {
    const health = enemy.mesh?.userData?.health;
    if (!health) return;
    const frac = Math.max(0, Math.min(1, enemy.hp / enemy.maxHp));
    health.scale.x = frac;
    health.position.x = -18 * (1 - frac);
  }

  updateCombat(dt) {
    this.attackCooldown = Math.max(0, this.attackCooldown - dt);
    this.attackFlash = Math.max(0, this.attackFlash - dt);
    this.enemySpawnTimer -= dt;

    if (!this.debug.paused) {
      if (this.enemySpawnTimer <= 0 && this.enemies.length < MAX_ENEMIES) {
        this.enemySpawnTimer = 1.8;
        this.spawnEnemyNearHero(760, 1500, this.enemies.length + this.enemySerial);
      }
      this.updateEnemies(dt);
    }

    this.updateAttackFx(dt);
    this.updateHeroCombatVisual();
  }

  updateEnemies(dt) {
    const actor = { state: { mountainPassAccess: true } };
    for (let i = this.enemies.length - 1; i >= 0; i--) {
      const enemy = this.enemies[i];
      const dx = this.hero.x - enemy.x;
      const dy = this.hero.y - enemy.y;
      const d = Math.hypot(dx, dy) || 1;
      enemy.attackCd = Math.max(0, enemy.attackCd - dt);
      enemy.hitT = Math.max(0, enemy.hitT - dt);

      if (d > ENEMY_DESPAWN_RADIUS) {
        this.killEnemy(enemy);
        continue;
      }

      if (d < ENEMY_ACTIVE_RADIUS && d > 42) {
        const step = enemy.speed * dt;
        const nx = enemy.x + (dx / d) * step;
        const ny = enemy.y + (dy / d) * step;
        if (this.world.canWalk?.(nx, ny, actor)) {
          enemy.x = nx;
          enemy.y = ny;
        }
      }

      if (d <= 58 && enemy.attackCd <= 0) {
        enemy.attackCd = enemy.kind === "brute" ? 1.1 : 0.78;
        this.heroHp = Math.max(0, this.heroHp - enemy.damage);
      }

      if (enemy.mesh) {
        enemy.mesh.position.copy(this.toVec3(enemy.x, enemy.y, 0));
        enemy.mesh.rotation.y = Math.atan2(dx, dy);
        const pulse = enemy.hitT > 0 ? 1.18 : 1;
        enemy.mesh.scale.setScalar(pulse);
      }
      this.updateEnemyHealth(enemy);
    }
  }

  updateAttackFx(dt) {
    for (let i = this.attackFxGroup.children.length - 1; i >= 0; i--) {
      const mesh = this.attackFxGroup.children[i];
      mesh.userData.life = (mesh.userData.life || 0) - dt;
      if (mesh.material) mesh.material.opacity = Math.max(0, mesh.userData.life / 0.16) * 0.38;
      if (mesh.userData.life <= 0) {
        this.attackFxGroup.remove(mesh);
        mesh.geometry?.dispose?.();
        mesh.material?.dispose?.();
      }
    }
  }

  updateHeroCombatVisual() {
    if (!this.heroMarker) return;
    const pulse = this.attackFlash > 0 ? 1.08 : 1;
    this.heroMarker.scale.setScalar(pulse);
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
      ["Spawn", () => this.spawnEnemyPack(3, 240, 720)],
      ["Clear", () => this.clearEnemies()],
      ["Pause AI", () => { this.debug.paused = !this.debug.paused; this.updateDebugPanel(); }],
      ["Wireframe", () => this.toggleWireframe()],
      ["Recenter", () => this.recenter()],
      ["Heal", () => { this.heroHp = 100; this.updateDebugPanel(); }],
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

  updateDebugPanel() {
    if (!this.debug.body || !this.debug.enabled) return;
    const zone = this.world?.getZoneName?.(this.hero.x, this.hero.y) || "-";
    const rendererInfo = this.renderer.info;
    const nearest = this.enemies.reduce((best, enemy) => {
      const d = Math.hypot(enemy.x - this.hero.x, enemy.y - this.hero.y);
      return d < best ? d : best;
    }, Infinity);
    this.debug.body.textContent = [
      `fps ${this.debug.fps.toFixed(1)} | frame ${this.debug.frameMs.toFixed(1)}ms`,
      `hero ${Math.round(this.hero.x)}, ${Math.round(this.hero.y)} | hp ${Math.round(this.heroHp)}/100`,
      `zone ${zone}`,
      `enemies ${this.enemies.length}/${MAX_ENEMIES} | nearest ${Number.isFinite(nearest) ? Math.round(nearest) : "-"}`,
      `draw calls ${rendererInfo.render.calls} | tris ${rendererInfo.render.triangles}`,
      `ai ${this.debug.paused ? "paused" : "live"} | wire ${this.debug.wireframe ? "on" : "off"}`,
      "",
      "F / Space / click: attack",
      "N: spawn | C: clear | P: pause AI | V: wireframe",
    ].join("\n");
  }

  updateHud() {
    if (this.ui.summaryEl) {
      this.ui.summaryEl.textContent =
        "3D world is live: same seed, roads, rivers, bridges, towns, camps, dungeons, shrines, caches, herbs, secrets, and dragon lairs.";
    }
    if (this.ui.seedEl) this.ui.seedEl.textContent = String(this.world.seed);
    if (this.ui.heroEl) this.ui.heroEl.textContent = `${Math.round(this.hero.x)}, ${Math.round(this.hero.y)}`;
    if (this.ui.roadsEl) this.ui.roadsEl.textContent = `${this.world.roads?.length || 0} paths`;
    if (this.ui.riversEl) this.ui.riversEl.textContent = `${this.world._riverBands?.length || 0} rivers`;
    if (this.ui.bridgesEl) this.ui.bridgesEl.textContent = `${this.world.bridges?.length || 0} bridges / ${this.world.docks?.length || 0} docks`;
    const townCount = (this.world.towns?.length || 0) + (this.world.startTown ? 1 : 0);
    if (this.ui.townsEl) this.ui.townsEl.textContent = `${townCount} settlements`;
  }

  resize() {
    const w = window.innerWidth;
    const h = window.innerHeight;
    this.camera.aspect = w / h;
    this.camera.updateProjectionMatrix();
    this.renderer.setSize(w, h, false);
  }

  animate() {
    this.rafId = requestAnimationFrame(this.animate);
    const dt = this.clock.getDelta();
    this.world.update?.();
    const step = Math.min(dt, 0.05);
    this.updateDebugStats(step);
    this.updateMovement(step);
    this.updateCombat(step);
    this.controls.update(dt);
    this.renderer.render(this.scene, this.camera);
    this.updateDebugPanel();
  }
}
