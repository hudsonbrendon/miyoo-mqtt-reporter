# Miyoo Mini Card (Home Assistant Lovelace) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a custom Lovelace card `miyoo-mini-card` that visually represents a Miyoo Mini Plus device on a Home Assistant dashboard, reading the live MQTT entities published by [`miyoo-mqtt-reporter`](https://github.com/hudsonbrendon/miyoo-mqtt-reporter) and displaying them on an inline SVG of the handheld, mirroring the look-and-feel of [`hudsonbrendon/nintendo-switch-card`](https://github.com/hudsonbrendon/nintendo-switch-card).

**Architecture:** TypeScript + Lit + Rollup web component, packaged for HACS. The card consumes Home Assistant entity states (not MQTT directly — HA Discovery already created the entities). It accepts an entity prefix (auto-resolves all 73 entities by suffix) or an explicit `entities:` map, and renders three regions: device SVG, state line (`mode` + `running game`), and a 4-cell stat grid.

**Tech Stack:** TypeScript 5, Lit 3, Rollup 4, Vitest, ESLint, HACS for distribution. New repo at `/Users/hudsonbrendon/Github/miyoo-mini-card/` → `github.com/hudsonbrendon/miyoo-mini-card`.

---

## Scope check

This plan is one self-contained project (the card). The MQTT daemon stays in its own repo. No back-and-forth coupling — the card only reads entity states by entity_id pattern.

## File structure

```
miyoo-mini-card/
├── .eslintrc.cjs
├── .github/workflows/release.yml      # GH Actions: build + attach dist on tag
├── .gitignore
├── LICENSE                            # MIT
├── README.md                          # install (HACS + manual), YAML samples
├── hacs.json                          # HACS manifest
├── package.json
├── package-lock.json                  # committed
├── rollup.config.mjs
├── tsconfig.json
├── vitest.config.ts
├── assets/
│   └── card-preview.png               # placeholder, replaced after first run
└── src/
    ├── const.ts                       # CARD_NAME, CARD_VERSION, EntityKey union
    ├── miyoo-mini-card.ts             # @customElement entrypoint
    ├── editor.ts                      # HA UI visual editor (stub)
    ├── styles.ts                      # css`...` block
    ├── types.ts                       # config + resolved-entity interfaces
    ├── assets/
    │   └── miyoo-svg.ts               # inline SVG of the Miyoo Mini Plus
    ├── helpers/
    │   ├── resolve-entities.ts        # prefix → entity_id map (+ overrides)
    │   ├── compute-state-line.ts      # mode + game → human string
    │   └── format-stat.ts             # value × multiply, precision, suffix
    └── localize/
        ├── index.ts                   # localize(key, lang) lookup
        ├── en.ts                      # English strings
        └── pt-BR.ts                   # Portuguese (Brazil) strings

tests/
├── compute-state-line.test.ts
├── format-stat.test.ts
└── resolve-entities.test.ts
```

**Decomposition notes:**
- Each helper file is one pure function — testable in isolation under Vitest's jsdom env.
- `assets/miyoo-svg.ts` is a single exported `svg` template — re-rendered with bound text nodes for the current game name.
- The main component reads entity states via the `hass.states[entity_id]` API that HA passes into Lovelace cards as a `@property`.
- Localize strings are tiny (~20 keys) — two files is enough; mirror the switch card if it grows.

---

### Task 1: Repository scaffold

**Files:**
- Create: `/Users/hudsonbrendon/Github/miyoo-mini-card/.gitignore`
- Create: `/Users/hudsonbrendon/Github/miyoo-mini-card/LICENSE`
- Create: `/Users/hudsonbrendon/Github/miyoo-mini-card/README.md` (placeholder header — final content in Task 14)

- [ ] **Step 1: Create the folder and init git**

```bash
mkdir -p /Users/hudsonbrendon/Github/miyoo-mini-card
cd /Users/hudsonbrendon/Github/miyoo-mini-card
git init
```

- [ ] **Step 2: Write `.gitignore`**

```gitignore
node_modules/
dist/
coverage/
*.tsbuildinfo
.DS_Store
.idea/
.vscode/
*.swp
*.log
.env
```

- [ ] **Step 3: Write `LICENSE` (MIT)**

```
MIT License

Copyright (c) 2026 Hudson Brendon

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
```

- [ ] **Step 4: Write a placeholder `README.md`**

```markdown
# miyoo-mini-card

Home Assistant Lovelace card for the Miyoo Mini Plus with OnionOS, paired
with [miyoo-mqtt-reporter](https://github.com/hudsonbrendon/miyoo-mqtt-reporter).

(Full README in Task 14.)
```

- [ ] **Step 5: Commit**

```bash
git add .gitignore LICENSE README.md
git commit -m "chore: bootstrap miyoo-mini-card repo"
```

---

### Task 2: Toolchain (package.json, tsconfig, rollup, vitest, eslint)

**Files:**
- Create: `package.json`
- Create: `tsconfig.json`
- Create: `rollup.config.mjs`
- Create: `vitest.config.ts`
- Create: `.eslintrc.cjs`

- [ ] **Step 1: Write `package.json`**

```json
{
  "name": "miyoo-mini-card",
  "version": "0.1.0",
  "description": "Lovelace card for Miyoo Mini Plus via miyoo-mqtt-reporter MQTT integration",
  "type": "module",
  "main": "dist/miyoo-mini-card.js",
  "scripts": {
    "build": "rollup -c rollup.config.mjs",
    "watch": "rollup -c rollup.config.mjs -w",
    "lint": "eslint 'src/**/*.ts' 'tests/**/*.ts'",
    "typecheck": "tsc --noEmit",
    "test": "vitest run",
    "test:watch": "vitest"
  },
  "keywords": ["home-assistant", "lovelace", "miyoo-mini", "onion-os", "mqtt", "hacs"],
  "license": "MIT",
  "dependencies": {
    "lit": "^3.1.0"
  },
  "devDependencies": {
    "@rollup/plugin-commonjs": "^25.0.7",
    "@rollup/plugin-json": "^6.1.0",
    "@rollup/plugin-node-resolve": "^15.2.3",
    "@rollup/plugin-terser": "^0.4.4",
    "@rollup/plugin-typescript": "^11.1.6",
    "@types/node": "^20.11.0",
    "@typescript-eslint/eslint-plugin": "^8.59.1",
    "@typescript-eslint/parser": "^8.59.1",
    "@vitest/ui": "^1.2.0",
    "eslint": "^8.56.0",
    "jsdom": "^24.0.0",
    "rollup": "^4.9.0",
    "tslib": "^2.6.2",
    "typescript": "^5.3.3",
    "vitest": "^1.2.0"
  }
}
```

- [ ] **Step 2: Write `tsconfig.json`**

```json
{
  "compilerOptions": {
    "target": "ES2020",
    "module": "ESNext",
    "moduleResolution": "Bundler",
    "lib": ["ES2020", "DOM", "DOM.Iterable"],
    "experimentalDecorators": true,
    "useDefineForClassFields": false,
    "strict": true,
    "noUnusedLocals": true,
    "noUnusedParameters": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true,
    "declaration": false,
    "sourceMap": false,
    "outDir": "dist"
  },
  "include": ["src/**/*", "tests/**/*"]
}
```

- [ ] **Step 3: Write `rollup.config.mjs`**

```js
import typescript from "@rollup/plugin-typescript";
import resolve from "@rollup/plugin-node-resolve";
import commonjs from "@rollup/plugin-commonjs";
import json from "@rollup/plugin-json";
import terser from "@rollup/plugin-terser";

export default {
  input: "src/miyoo-mini-card.ts",
  output: {
    file: "dist/miyoo-mini-card.js",
    format: "es",
    sourcemap: false,
  },
  plugins: [resolve(), commonjs(), json(), typescript(), terser()],
};
```

- [ ] **Step 4: Write `vitest.config.ts`**

```ts
import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    environment: "jsdom",
    globals: true,
    include: ["tests/**/*.test.ts"],
  },
});
```

- [ ] **Step 5: Write `.eslintrc.cjs`**

```js
module.exports = {
  root: true,
  parser: "@typescript-eslint/parser",
  plugins: ["@typescript-eslint"],
  extends: ["eslint:recommended", "plugin:@typescript-eslint/recommended"],
  env: { browser: true, es2022: true, node: true },
  parserOptions: { ecmaVersion: 2022, sourceType: "module" },
  rules: {
    "@typescript-eslint/no-explicit-any": "off",
    "@typescript-eslint/no-unused-vars": ["error", { argsIgnorePattern: "^_" }],
  },
};
```

- [ ] **Step 6: Install dependencies**

```bash
cd /Users/hudsonbrendon/Github/miyoo-mini-card
npm install
```

Expected: `node_modules/` populated, `package-lock.json` created.

- [ ] **Step 7: Sanity check the toolchain**

```bash
npx tsc --version           # ≥ 5.3
npx vitest --version        # ≥ 1.2
npx rollup --version        # ≥ 4
```

- [ ] **Step 8: Commit**

```bash
git add package.json package-lock.json tsconfig.json rollup.config.mjs vitest.config.ts .eslintrc.cjs
git commit -m "chore: TypeScript + Lit + Rollup + Vitest + ESLint toolchain"
```

---

### Task 3: `src/const.ts` — card name, version, entity-key union

**Files:**
- Create: `src/const.ts`

- [ ] **Step 1: Write the file**

```ts
export const CARD_NAME = "miyoo-mini-card";
export const CARD_VERSION = "0.1.0";

// All the data points the card knows how to render. These are *logical*
// keys — the entity ID is derived from `<prefix>_<key>` (or overridden
// explicitly via config.entities). Names match miyoo-mqtt-reporter's
// discovery object_id fields.
export const ENTITY_KEYS = [
  // Required for any view
  "battery",        // sensor
  "charging",       // binary_sensor
  // Highly recommended
  "volume",
  "brightness",
  "temperature",
  "wifi_rssi",
  "ram",
  "cpu",
  "playtime_today_min",
  "playtime_total_hours",
  "uptime",
  "mode",
  "game",
  "core",
  "last_played",
  "most_played",
  "charging_source",
  "vbat",
  "ibat",
] as const;

export type EntityKey = (typeof ENTITY_KEYS)[number];
```

- [ ] **Step 2: Commit**

```bash
git add src/const.ts
git commit -m "feat(const): card name, version, entity key union"
```

---

### Task 4: `src/types.ts` — config + resolved-entity interfaces

**Files:**
- Create: `src/types.ts`

- [ ] **Step 1: Write the file**

```ts
import type { EntityKey } from "./const";

export interface StatConfig {
  entity: string;        // entity_id or one of EntityKey
  unit?: string;
  multiply?: number;
  precision?: number;
  suffix?: string;
  subtitle: string;
}

export interface MiyooMiniCardConfig {
  type: string;
  /** Entity-id prefix — e.g. "miyoo_mini_plus_miyoominiplus".
   *  When set the card auto-resolves `<prefix>_<key>` for every EntityKey. */
  entity?: string;
  /** Per-key overrides. Wins over the auto-resolved prefix. */
  entities?: Partial<Record<EntityKey, string>>;
  name?: string;
  language?: string;
  compact?: boolean;
  stats?: StatConfig[];   // up to 4
}

/** All entity ids after resolution. Missing keys remain `""`. */
export type ResolvedEntities = Record<EntityKey, string>;

/** Minimal subset of the HASS object the card actually touches. */
export interface HassState {
  state: string;
  attributes: Record<string, unknown>;
}
export interface HassObject {
  states: Record<string, HassState>;
  language?: string;
}
```

- [ ] **Step 2: Typecheck**

```bash
npx tsc --noEmit
```

Expected: no output (success).

- [ ] **Step 3: Commit**

```bash
git add src/types.ts
git commit -m "feat(types): config + resolved-entity interfaces"
```

---

### Task 5: `src/helpers/resolve-entities.ts` (TDD)

**Files:**
- Create: `tests/resolve-entities.test.ts`
- Create: `src/helpers/resolve-entities.ts`

- [ ] **Step 1: Write the failing test**

```ts
// tests/resolve-entities.test.ts
import { describe, it, expect } from "vitest";
import { resolveEntities } from "../src/helpers/resolve-entities";
import { ENTITY_KEYS } from "../src/const";

describe("resolveEntities", () => {
  it("derives every key from the prefix when no overrides are given", () => {
    const out = resolveEntities({ type: "x", entity: "miyoo_main" });
    for (const k of ENTITY_KEYS) {
      const expected = k === "charging" ? `binary_sensor.miyoo_main_${k}` : `sensor.miyoo_main_${k}`;
      expect(out[k]).toBe(expected);
    }
  });

  it("uses explicit overrides instead of the prefix", () => {
    const out = resolveEntities({
      type: "x",
      entity: "miyoo_main",
      entities: { battery: "sensor.custom_battery", game: "sensor.custom_game" },
    });
    expect(out.battery).toBe("sensor.custom_battery");
    expect(out.game).toBe("sensor.custom_game");
    expect(out.volume).toBe("sensor.miyoo_main_volume");
  });

  it("works with only overrides (no prefix)", () => {
    const out = resolveEntities({
      type: "x",
      entities: { battery: "sensor.b", charging: "binary_sensor.c" },
    });
    expect(out.battery).toBe("sensor.b");
    expect(out.charging).toBe("binary_sensor.c");
    expect(out.volume).toBe("");
  });
});
```

- [ ] **Step 2: Run — fail**

```bash
npx vitest run tests/resolve-entities.test.ts
```

Expected: FAIL `Cannot find module ... resolve-entities`.

- [ ] **Step 3: Implement**

```ts
// src/helpers/resolve-entities.ts
import { ENTITY_KEYS, type EntityKey } from "../const";
import type { MiyooMiniCardConfig, ResolvedEntities } from "../types";

const BINARY_KEYS = new Set<EntityKey>(["charging"]);

export function resolveEntities(config: MiyooMiniCardConfig): ResolvedEntities {
  const map = {} as ResolvedEntities;
  const overrides = config.entities ?? {};
  const prefix = config.entity?.trim() ?? "";

  for (const key of ENTITY_KEYS) {
    if (overrides[key]) {
      map[key] = overrides[key]!;
    } else if (prefix) {
      const domain = BINARY_KEYS.has(key) ? "binary_sensor" : "sensor";
      map[key] = `${domain}.${prefix}_${key}`;
    } else {
      map[key] = "";
    }
  }
  return map;
}
```

- [ ] **Step 4: Run — pass**

```bash
npx vitest run tests/resolve-entities.test.ts
```

Expected: 3 tests OK.

- [ ] **Step 5: Commit**

```bash
git add src/helpers/resolve-entities.ts tests/resolve-entities.test.ts
git commit -m "feat(helpers): resolveEntities — prefix + per-key overrides"
```

---

### Task 6: `src/helpers/format-stat.ts` (TDD)

**Files:**
- Create: `tests/format-stat.test.ts`
- Create: `src/helpers/format-stat.ts`

- [ ] **Step 1: Write the failing test**

```ts
// tests/format-stat.test.ts
import { describe, it, expect } from "vitest";
import { formatStat } from "../src/helpers/format-stat";

describe("formatStat", () => {
  it("returns em-dash for missing state", () => {
    expect(formatStat(undefined, { entity: "x", subtitle: "Battery" })).toBe("—");
    expect(formatStat({ state: "unknown" } as never, { entity: "x", subtitle: "Battery" })).toBe("—");
    expect(formatStat({ state: "unavailable" } as never, { entity: "x", subtitle: "Battery" })).toBe("—");
  });

  it("appends unit", () => {
    expect(formatStat({ state: "42" } as never, { entity: "x", subtitle: "S", unit: "%" })).toBe("42%");
  });

  it("multiplies before formatting", () => {
    expect(formatStat({ state: "1.5" } as never, { entity: "x", subtitle: "S", multiply: 60, unit: "min" })).toBe("90min");
  });

  it("respects precision", () => {
    expect(formatStat({ state: "3.14159" } as never, { entity: "x", subtitle: "S", precision: 2 })).toBe("3.14");
  });

  it("falls back to raw string for non-numeric state", () => {
    expect(formatStat({ state: "mainui" } as never, { entity: "x", subtitle: "Mode" })).toBe("mainui");
  });

  it("supports suffix on raw string fallback", () => {
    expect(formatStat({ state: "GBA" } as never, { entity: "x", subtitle: "Core", suffix: " core" })).toBe("GBA core");
  });
});
```

- [ ] **Step 2: Run — fail**

```bash
npx vitest run tests/format-stat.test.ts
```

Expected: FAIL — module not found.

- [ ] **Step 3: Implement**

```ts
// src/helpers/format-stat.ts
import type { StatConfig, HassState } from "../types";

const MISSING = "—";

export function formatStat(state: HassState | undefined, cfg: StatConfig): string {
  if (!state || state.state === "unknown" || state.state === "unavailable" || state.state === "") {
    return MISSING;
  }
  const raw = state.state;
  const asNum = Number(raw);
  if (Number.isFinite(asNum)) {
    const multiplied = asNum * (cfg.multiply ?? 1);
    const text =
      cfg.precision != null ? multiplied.toFixed(cfg.precision) : String(multiplied);
    return `${text}${cfg.unit ?? ""}${cfg.suffix ?? ""}`;
  }
  return `${raw}${cfg.suffix ?? ""}`;
}
```

- [ ] **Step 4: Run — pass**

```bash
npx vitest run tests/format-stat.test.ts
```

Expected: 6 tests OK.

- [ ] **Step 5: Commit**

```bash
git add src/helpers/format-stat.ts tests/format-stat.test.ts
git commit -m "feat(helpers): formatStat — unit / multiply / precision / suffix"
```

---

### Task 7: `src/helpers/compute-state-line.ts` (TDD)

**Files:**
- Create: `tests/compute-state-line.test.ts`
- Create: `src/helpers/compute-state-line.ts`

- [ ] **Step 1: Write the failing test**

```ts
// tests/compute-state-line.test.ts
import { describe, it, expect } from "vitest";
import { computeStateLine } from "../src/helpers/compute-state-line";

const hass = (states: Record<string, string>) => ({
  states: Object.fromEntries(
    Object.entries(states).map(([k, v]) => [k, { state: v, attributes: {} }])
  ),
});

describe("computeStateLine", () => {
  it("shows game and core when in game mode", () => {
    const h = hass({
      "sensor.x_mode": "game",
      "sensor.x_game": "Pokemon FireRed",
      "sensor.x_core": "mgba",
    });
    expect(
      computeStateLine(h, {
        mode: "sensor.x_mode",
        game: "sensor.x_game",
        core: "sensor.x_core",
      } as never, "en")
    ).toBe("Playing Pokemon FireRed (mgba)");
  });

  it("shows mode label when not in game", () => {
    const h = hass({ "sensor.x_mode": "mainui" });
    expect(
      computeStateLine(h, { mode: "sensor.x_mode" } as never, "en")
    ).toBe("In menu");
  });

  it("falls back to standby for empty / unknown", () => {
    const h = hass({});
    expect(computeStateLine(h, { mode: "" } as never, "en")).toBe("Standby");
  });

  it("localizes to Portuguese", () => {
    const h = hass({
      "sensor.x_mode": "game",
      "sensor.x_game": "Mario",
      "sensor.x_core": "snes9x",
    });
    expect(
      computeStateLine(h, {
        mode: "sensor.x_mode",
        game: "sensor.x_game",
        core: "sensor.x_core",
      } as never, "pt-BR")
    ).toBe("Jogando Mario (snes9x)");
  });
});
```

- [ ] **Step 2: Run — fail**

```bash
npx vitest run tests/compute-state-line.test.ts
```

Expected: FAIL — module not found.

- [ ] **Step 3: Implement**

```ts
// src/helpers/compute-state-line.ts
import type { HassObject, ResolvedEntities } from "../types";
import { localize } from "../localize";

const KNOWN_MODES = ["mainui", "switcher", "apps", "advmenu", "drastic", "launching"];

export function computeStateLine(
  hass: HassObject,
  entities: ResolvedEntities,
  lang: string
): string {
  const modeState = entities.mode ? hass.states[entities.mode]?.state : undefined;
  const game = entities.game ? hass.states[entities.game]?.state : undefined;
  const core = entities.core ? hass.states[entities.core]?.state : undefined;

  if (modeState === "game" && game && game !== "unknown" && game !== "unavailable") {
    const coreSuffix = core && core !== "unknown" && core !== "unavailable" ? ` (${core})` : "";
    return `${localize("state.playing", lang)} ${game}${coreSuffix}`;
  }

  if (modeState && KNOWN_MODES.includes(modeState)) {
    return localize(`mode.${modeState}`, lang);
  }
  return localize("state.standby", lang);
}
```

- [ ] **Step 4: Run — fail (no localize module yet)**

```bash
npx vitest run tests/compute-state-line.test.ts
```

Expected: FAIL — `cannot find module './localize'`. That's Task 8.

- [ ] **Step 5: Commit (helper only, tests will go green after Task 8)**

```bash
git add src/helpers/compute-state-line.ts tests/compute-state-line.test.ts
git commit -m "feat(helpers): computeStateLine (tests pending Task 8 localize)"
```

---

### Task 8: `src/localize/` — en + pt-BR + lookup

**Files:**
- Create: `src/localize/en.ts`
- Create: `src/localize/pt-BR.ts`
- Create: `src/localize/index.ts`

- [ ] **Step 1: Write `en.ts`**

```ts
// src/localize/en.ts
export const en: Record<string, string> = {
  "state.playing": "Playing",
  "state.standby": "Standby",
  "mode.mainui": "In menu",
  "mode.switcher": "Game switcher",
  "mode.apps": "In an app",
  "mode.advmenu": "Advanced menu",
  "mode.drastic": "DraStic running",
  "mode.launching": "Launching",
  "stat.battery": "Battery",
  "stat.volume": "Volume",
  "stat.brightness": "Brightness",
  "stat.temperature": "Temperature",
  "stat.wifi": "Wi-Fi",
  "stat.playtime_today": "Today",
  "stat.ram": "RAM",
};
```

- [ ] **Step 2: Write `pt-BR.ts`**

```ts
// src/localize/pt-BR.ts
export const ptBR: Record<string, string> = {
  "state.playing": "Jogando",
  "state.standby": "Em standby",
  "mode.mainui": "No menu",
  "mode.switcher": "Game switcher",
  "mode.apps": "Em um app",
  "mode.advmenu": "Menu avançado",
  "mode.drastic": "Rodando DraStic",
  "mode.launching": "Carregando",
  "stat.battery": "Bateria",
  "stat.volume": "Volume",
  "stat.brightness": "Brilho",
  "stat.temperature": "Temperatura",
  "stat.wifi": "Wi-Fi",
  "stat.playtime_today": "Hoje",
  "stat.ram": "RAM",
};
```

- [ ] **Step 3: Write `index.ts`**

```ts
// src/localize/index.ts
import { en } from "./en";
import { ptBR } from "./pt-BR";

const TABLE: Record<string, Record<string, string>> = {
  en,
  "en-US": en,
  "en-GB": en,
  "pt-BR": ptBR,
  "pt": ptBR,
};

export function localize(key: string, lang?: string): string {
  const table = (lang && TABLE[lang]) || en;
  return table[key] ?? key;
}
```

- [ ] **Step 4: Run all helper tests — all 12+ should now pass**

```bash
npx vitest run
```

Expected: 3 test files, ~13 tests, all OK.

- [ ] **Step 5: Commit**

```bash
git add src/localize/
git commit -m "feat(localize): en + pt-BR string tables and lookup"
```

---

### Task 9: `src/styles.ts` — card CSS

**Files:**
- Create: `src/styles.ts`

- [ ] **Step 1: Write the file**

```ts
import { css } from "lit";

export const cardStyles = css`
  :host {
    --mmc-bg: var(--ha-card-background, var(--card-background-color, #1a1a1a));
    --mmc-fg: var(--primary-text-color, #fff);
    --mmc-muted: var(--secondary-text-color, #aaa);
    --mmc-accent: var(--accent-color, #38bdf8);
    display: block;
  }
  ha-card {
    padding: 16px;
    background: var(--mmc-bg);
    color: var(--mmc-fg);
  }
  .mmc-title {
    font-size: 1rem;
    font-weight: 600;
    margin-bottom: 6px;
  }
  .mmc-state-line {
    font-size: 0.92rem;
    color: var(--mmc-muted);
    margin-bottom: 12px;
    min-height: 1.2em;
  }
  .mmc-state-line .charging {
    color: var(--mmc-accent);
    margin-left: 6px;
  }
  .mmc-svg-wrap {
    display: flex;
    justify-content: center;
    margin: 6px 0 14px;
  }
  .mmc-svg-wrap svg {
    width: 100%;
    max-width: 360px;
    height: auto;
  }
  .mmc-stats {
    display: grid;
    grid-template-columns: repeat(4, 1fr);
    gap: 10px;
  }
  .mmc-stat {
    background: rgba(255, 255, 255, 0.04);
    border-radius: 10px;
    padding: 8px 6px;
    text-align: center;
  }
  .mmc-stat-val {
    font-size: 1rem;
    font-weight: 700;
  }
  .mmc-stat-sub {
    font-size: 0.72rem;
    color: var(--mmc-muted);
    margin-top: 2px;
  }
  .mmc-screen-text {
    font: 600 18px sans-serif;
    fill: #fff;
    text-anchor: middle;
    dominant-baseline: middle;
  }
  .mmc-screen-sub {
    font: 400 11px sans-serif;
    fill: #9aa;
    text-anchor: middle;
  }
`;
```

- [ ] **Step 2: Commit**

```bash
git add src/styles.ts
git commit -m "feat(styles): card CSS with HA theme variables"
```

---

### Task 10: `src/assets/miyoo-svg.ts` — Miyoo Mini Plus inline SVG

**Files:**
- Create: `src/assets/miyoo-svg.ts`

The SVG mirrors the layout of the nintendo-switch-card SVG: a stylized device with a screen area in the middle that displays the **current state line** (game name or mode). On the Miyoo Mini Plus the body is a single chunk (no detachable Joy-Cons), with a D-pad on the left and ABXY buttons on the right.

- [ ] **Step 1: Write the file**

```ts
// src/assets/miyoo-svg.ts
import { svg, type TemplateResult } from "lit";

export function miyooSvg(opts: {
  screenLine1: string;
  screenLine2: string;
  charging: boolean;
}): TemplateResult {
  return svg`
    <svg viewBox="0 0 360 220" xmlns="http://www.w3.org/2000/svg" aria-hidden="true">
      <defs>
        <linearGradient id="mmcBody" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stop-color="#2f343a"/>
          <stop offset="100%" stop-color="#15181c"/>
        </linearGradient>
        <linearGradient id="mmcScreen" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stop-color="#0d1117"/>
          <stop offset="100%" stop-color="#1f2937"/>
        </linearGradient>
        <radialGradient id="mmcDpad" cx="50%" cy="50%" r="60%">
          <stop offset="0%" stop-color="#3b4148"/>
          <stop offset="100%" stop-color="#0e1013"/>
        </radialGradient>
        <radialGradient id="mmcBtnA" cx="50%" cy="50%" r="60%">
          <stop offset="0%" stop-color="#ef4444"/>
          <stop offset="100%" stop-color="#7f1d1d"/>
        </radialGradient>
        <radialGradient id="mmcBtnB" cx="50%" cy="50%" r="60%">
          <stop offset="0%" stop-color="#fbbf24"/>
          <stop offset="100%" stop-color="#92400e"/>
        </radialGradient>
        <radialGradient id="mmcBtnX" cx="50%" cy="50%" r="60%">
          <stop offset="0%" stop-color="#38bdf8"/>
          <stop offset="100%" stop-color="#075985"/>
        </radialGradient>
        <radialGradient id="mmcBtnY" cx="50%" cy="50%" r="60%">
          <stop offset="0%" stop-color="#22c55e"/>
          <stop offset="100%" stop-color="#14532d"/>
        </radialGradient>
      </defs>
      <ellipse cx="180" cy="214" rx="160" ry="4" fill="#000" opacity="0.18"/>

      <!-- Body -->
      <rect x="14" y="18" width="332" height="184" rx="28" ry="28" fill="url(#mmcBody)" stroke="#000" stroke-width="0.5"/>

      <!-- Shoulder buttons -->
      <rect x="30" y="12" width="40" height="10" rx="4" fill="#1c2026"/>
      <rect x="290" y="12" width="40" height="10" rx="4" fill="#1c2026"/>

      <!-- Screen -->
      <rect x="98" y="34" width="164" height="124" rx="6" fill="url(#mmcScreen)" stroke="#000" stroke-width="0.5"/>
      <text x="180" y="92" class="mmc-screen-text">${opts.screenLine1}</text>
      <text x="180" y="118" class="mmc-screen-sub">${opts.screenLine2}</text>

      <!-- D-pad (left) -->
      <g transform="translate(56,114)">
        <rect x="-6" y="-22" width="12" height="44" rx="3" fill="url(#mmcDpad)"/>
        <rect x="-22" y="-6" width="44" height="12" rx="3" fill="url(#mmcDpad)"/>
      </g>

      <!-- ABXY (right, diamond) -->
      <g transform="translate(304,114)">
        <circle cx="0" cy="-18" r="9" fill="url(#mmcBtnX)"/>
        <circle cx="18" cy="0" r="9" fill="url(#mmcBtnA)"/>
        <circle cx="0" cy="18" r="9" fill="url(#mmcBtnB)"/>
        <circle cx="-18" cy="0" r="9" fill="url(#mmcBtnY)"/>
      </g>

      <!-- Select / Start / Menu under screen -->
      <rect x="124" y="170" width="22" height="6" rx="3" fill="#1c2026"/>
      <rect x="170" y="170" width="22" height="6" rx="3" fill="#1c2026"/>
      <rect x="214" y="170" width="22" height="6" rx="3" fill="#1c2026"/>

      <!-- Speaker grilles -->
      <g fill="#0e1013">
        <circle cx="48" cy="178" r="2"/>
        <circle cx="56" cy="178" r="2"/>
        <circle cx="64" cy="178" r="2"/>
        <circle cx="296" cy="178" r="2"/>
        <circle cx="304" cy="178" r="2"/>
        <circle cx="312" cy="178" r="2"/>
      </g>

      <!-- Charging LED -->
      ${opts.charging
        ? svg`<circle cx="180" cy="28" r="4" fill="#22c55e">
                <animate attributeName="opacity" values="0.4;1;0.4" dur="1.6s" repeatCount="indefinite"/>
              </circle>`
        : svg`<circle cx="180" cy="28" r="3" fill="#3a3f46"/>`}
    </svg>
  `;
}
```

- [ ] **Step 2: Typecheck**

```bash
npx tsc --noEmit
```

Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add src/assets/miyoo-svg.ts
git commit -m "feat(svg): inline Miyoo Mini Plus illustration with live screen text"
```

---

### Task 11: `src/miyoo-mini-card.ts` — main component

**Files:**
- Create: `src/miyoo-mini-card.ts`

- [ ] **Step 1: Write the component**

```ts
// src/miyoo-mini-card.ts
import { LitElement, html, nothing, type TemplateResult } from "lit";
import { customElement, property, state } from "lit/decorators.js";
import { CARD_NAME, CARD_VERSION } from "./const";
import { cardStyles } from "./styles";
import { miyooSvg } from "./assets/miyoo-svg";
import { resolveEntities } from "./helpers/resolve-entities";
import { computeStateLine } from "./helpers/compute-state-line";
import { formatStat } from "./helpers/format-stat";
import { localize } from "./localize";
import type {
  HassObject,
  MiyooMiniCardConfig,
  ResolvedEntities,
  StatConfig,
} from "./types";

console.info(
  `%c MIYOO-MINI-CARD %c v${CARD_VERSION} `,
  "color: white; background: #1f2937; font-weight: 700;",
  "color: white; background: #38bdf8; font-weight: 700;"
);

interface CustomCardWindow extends Window {
  customCards?: Array<{ type: string; name: string; description: string; preview: boolean }>;
}
const w = window as CustomCardWindow;
w.customCards = w.customCards || [];
w.customCards.push({
  type: CARD_NAME,
  name: "Miyoo Mini Card",
  description: "Card for Miyoo Mini Plus via miyoo-mqtt-reporter MQTT integration",
  preview: false,
});

const DEFAULT_STATS: StatConfig[] = [
  { entity: "battery", unit: "%", subtitle: "stat.battery" },
  { entity: "volume", unit: "%", subtitle: "stat.volume" },
  { entity: "temperature", unit: "°C", subtitle: "stat.temperature" },
  { entity: "playtime_today_min", unit: " min", subtitle: "stat.playtime_today" },
];

@customElement(CARD_NAME)
export class MiyooMiniCard extends LitElement {
  static styles = cardStyles;

  @property({ attribute: false }) hass?: HassObject;
  @state() private _config?: MiyooMiniCardConfig;

  setConfig(config: MiyooMiniCardConfig): void {
    if (!config) throw new Error("invalid_config: empty");
    const hasPrefix = typeof config.entity === "string" && config.entity.length > 0;
    const ents = config.entities ?? {};
    const hasMinEntities = !!ents.battery && !!ents.charging;
    if (!hasPrefix && !hasMinEntities) {
      throw new Error(
        "missing required entity: provide `entity:` prefix or `entities.battery` + `entities.charging`"
      );
    }
    if (config.stats && config.stats.length > 4) {
      throw new Error("invalid_config: stats can have at most 4 items");
    }
    this._config = config;
  }

  getCardSize(): number {
    return 5;
  }

  static getStubConfig(): MiyooMiniCardConfig {
    return { type: `custom:${CARD_NAME}`, entity: "miyoo_mini_plus_miyoominiplus" };
  }

  private _lang(): string {
    return this._config?.language ?? this.hass?.language ?? "en";
  }

  private _resolveStatEntity(id: string, resolved: ResolvedEntities): string {
    // If the stat config's `entity` is a logical EntityKey, map via resolved table.
    if (id in resolved) return resolved[id as keyof ResolvedEntities];
    return id;
  }

  render(): TemplateResult | typeof nothing {
    if (!this._config || !this.hass) return nothing;
    const resolved = resolveEntities(this._config);
    const lang = this._lang();

    const modeState = resolved.mode ? this.hass.states[resolved.mode]?.state : undefined;
    const chargingState = resolved.charging
      ? this.hass.states[resolved.charging]?.state
      : undefined;
    const isCharging = chargingState === "on" || chargingState === "ON";

    const stateLine = computeStateLine(this.hass, resolved, lang);

    const screenLine1 = modeState === "game" && resolved.game
      ? (this.hass.states[resolved.game]?.state || localize("state.standby", lang))
      : localize(`mode.${modeState ?? ""}`, lang) || localize("state.standby", lang);
    const screenLine2 = resolved.core && this.hass.states[resolved.core]?.state
      ? String(this.hass.states[resolved.core].state).toUpperCase()
      : "";

    const stats = (this._config.stats ?? DEFAULT_STATS).slice(0, 4);

    return html`
      <ha-card>
        ${this._config.name ? html`<div class="mmc-title">${this._config.name}</div>` : nothing}
        <div class="mmc-state-line">
          ${stateLine}
          ${isCharging ? html`<span class="charging">⚡</span>` : nothing}
        </div>
        <div class="mmc-svg-wrap">
          ${miyooSvg({ screenLine1, screenLine2, charging: isCharging })}
        </div>
        <div class="mmc-stats">
          ${stats.map((s) => {
            const id = this._resolveStatEntity(s.entity, resolved);
            const v = id ? this.hass!.states[id] : undefined;
            return html`
              <div class="mmc-stat">
                <div class="mmc-stat-val">${formatStat(v, s)}</div>
                <div class="mmc-stat-sub">${localize(s.subtitle, lang)}</div>
              </div>
            `;
          })}
        </div>
      </ha-card>
    `;
  }
}
```

- [ ] **Step 2: Typecheck + lint**

```bash
npx tsc --noEmit
npx eslint 'src/**/*.ts'
```

Expected: no errors.

- [ ] **Step 3: Build**

```bash
npm run build
ls -lh dist/miyoo-mini-card.js
```

Expected: `dist/miyoo-mini-card.js` exists, ~30-70 KB minified.

- [ ] **Step 4: Commit**

```bash
git add src/miyoo-mini-card.ts
git commit -m "feat: MiyooMiniCard component — state line, SVG, stat grid"
```

---

### Task 12: `src/editor.ts` — minimal config editor stub

A real visual editor needs ha-form. For v0.1.0 a textarea-style editor that just shows the YAML is fine — HACS users typically edit YAML by hand.

**Files:**
- Create: `src/editor.ts`
- Modify: `src/miyoo-mini-card.ts` (register `getConfigElement`)

- [ ] **Step 1: Write `src/editor.ts`**

```ts
// src/editor.ts
import { LitElement, html, type TemplateResult } from "lit";
import { customElement, property } from "lit/decorators.js";
import type { MiyooMiniCardConfig } from "./types";

@customElement("miyoo-mini-card-editor")
export class MiyooMiniCardEditor extends LitElement {
  @property({ attribute: false }) hass?: unknown;
  @property({ attribute: false }) _config?: MiyooMiniCardConfig;

  setConfig(config: MiyooMiniCardConfig): void {
    this._config = config;
  }

  render(): TemplateResult {
    return html`
      <div style="padding:12px;font-family:sans-serif;">
        <p>
          Edit YAML directly in the dashboard. Minimum config:
        </p>
        <pre style="background:#0a0a0a;color:#ccc;padding:10px;border-radius:6px;">
type: custom:miyoo-mini-card
entity: miyoo_mini_plus_miyoominiplus
name: My Miyoo</pre>
        <p>See the
          <a href="https://github.com/hudsonbrendon/miyoo-mini-card"
             target="_blank" rel="noreferrer">README</a>
          for all options.
        </p>
      </div>
    `;
  }
}
```

- [ ] **Step 2: Wire `getConfigElement` in the main component**

Edit `src/miyoo-mini-card.ts`. At the top, add the import:

```ts
import "./editor";
```

And add this static method inside the `MiyooMiniCard` class (right after `getCardSize`):

```ts
static getConfigElement(): HTMLElement {
  return document.createElement("miyoo-mini-card-editor");
}
```

- [ ] **Step 3: Typecheck + build**

```bash
npx tsc --noEmit
npm run build
```

Expected: clean.

- [ ] **Step 4: Commit**

```bash
git add src/editor.ts src/miyoo-mini-card.ts
git commit -m "feat(editor): minimal config-editor stub linking to README"
```

---

### Task 13: `hacs.json` — HACS manifest

**Files:**
- Create: `hacs.json`

- [ ] **Step 1: Write the file**

```json
{
  "name": "Miyoo Mini Card",
  "render_readme": true,
  "filename": "miyoo-mini-card.js",
  "homeassistant": "2024.1.0"
}
```

- [ ] **Step 2: Commit**

```bash
git add hacs.json
git commit -m "chore: HACS manifest"
```

---

### Task 14: `README.md` — installation + YAML samples

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Replace the placeholder with the full README**

```markdown
# miyoo-mini-card

Home Assistant Lovelace card for the **Miyoo Mini Plus** running
[OnionOS](https://onionui.github.io/), paired with
[`miyoo-mqtt-reporter`](https://github.com/hudsonbrendon/miyoo-mqtt-reporter).

Displays an inline SVG of the device with the currently running game on the
screen, a state line, and a 4-cell stat grid (battery / volume / temperature
/ playtime today by default — fully configurable).

![Card preview](assets/card-preview.png)

## Requirements

1. The companion daemon installed and publishing — see
   [miyoo-mqtt-reporter README](https://github.com/hudsonbrendon/miyoo-mqtt-reporter#readme).
2. Home Assistant **2024.1.0+** with the MQTT integration configured against
   the same broker the Miyoo publishes to.
3. After the daemon runs once, HA Discovery auto-creates 73 entities under
   the device `Miyoo Mini Plus (<device_id>)`.

## Installation

### HACS (recommended)

1. HACS → Frontend → **⋮ Custom repositories**
2. Repository: `https://github.com/hudsonbrendon/miyoo-mini-card`, Category: **Lovelace**
3. Install → Reload your browser cache (Ctrl+F5)

### Manual

1. Download `miyoo-mini-card.js` from the
   [latest release](https://github.com/hudsonbrendon/miyoo-mini-card/releases/latest)
2. Copy it into `<config>/www/`
3. Settings → Dashboards → ⋮ → **Resources** → Add resource:
   `URL: /local/miyoo-mini-card.js`, Type: **JavaScript Module**

## Usage

Minimum config — provide the device id prefix that HA derived from the
`DEVICE_ID` field in `mqtt.conf` (default `miyoominiplus`). The card auto-
resolves all entity ids by suffix:

```yaml
type: custom:miyoo-mini-card
entity: miyoo_mini_plus_miyoominiplus
name: My Miyoo
```

### Full config

```yaml
type: custom:miyoo-mini-card
entity: miyoo_mini_plus_miyoominiplus
name: Hudson's Miyoo
language: pt-BR          # en | pt-BR (default: HA language)
stats:                   # up to 4
  - entity: battery
    unit: "%"
    subtitle: stat.battery
  - entity: volume
    unit: "%"
    subtitle: stat.volume
  - entity: temperature
    unit: "°C"
    subtitle: stat.temperature
  - entity: playtime_today_min
    suffix: " min"
    subtitle: stat.playtime_today
# Optional per-entity overrides (when HA renamed something)
entities:
  battery: sensor.miyoo_main_battery
  charging: binary_sensor.miyoo_main_charging
```

### Stat entities supported

`battery, volume, brightness, temperature, wifi_rssi, ram, cpu,
playtime_today_min, playtime_total_hours, uptime, mode, game, core,
last_played, most_played, charging_source, vbat, ibat`.

The `stats[].entity` field accepts either one of the keys above (resolved
via the prefix) or a full entity id.

## Development

```bash
npm install
npm test         # vitest
npm run lint
npm run typecheck
npm run build    # dist/miyoo-mini-card.js
```

## License

MIT — see [LICENSE](LICENSE).
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: README with HACS + manual install and YAML samples"
```

---

### Task 15: GitHub Actions release workflow

**Files:**
- Create: `.github/workflows/release.yml`

- [ ] **Step 1: Create the workflow**

```yaml
name: Release
on:
  push:
    tags:
      - 'v*'

permissions:
  contents: write

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: '20'
          cache: 'npm'
      - run: npm ci
      - run: npm run typecheck
      - run: npm run lint
      - run: npm test
      - run: npm run build
      - uses: softprops/action-gh-release@v2
        with:
          files: dist/miyoo-mini-card.js
          generate_release_notes: true
```

- [ ] **Step 2: Commit**

```bash
git add .github/workflows/release.yml
git commit -m "ci: build + attach dist/miyoo-mini-card.js on tag push"
```

---

### Task 16: First local build + smoke check

- [ ] **Step 1: Full pipeline**

```bash
cd /Users/hudsonbrendon/Github/miyoo-mini-card
npm run lint
npm run typecheck
npm test
npm run build
```

Expected: lint clean, typecheck clean, 13+ tests pass, `dist/miyoo-mini-card.js` ~30-70 KB.

- [ ] **Step 2: Visual smoke check (cards render in a browser via a stub HASS)**

Optional but informative. Create a temporary `dev.html` in repo root:

```bash
cat > dev.html <<'EOF'
<!doctype html>
<html><body style="background:#0a0a0a;margin:0;padding:30px;">
<script type="module" src="./dist/miyoo-mini-card.js"></script>
<miyoo-mini-card id="card"></miyoo-mini-card>
<script>
  const el = document.getElementById('card');
  el.setConfig({
    type: 'custom:miyoo-mini-card',
    entity: 'demo',
    name: 'Demo Miyoo',
  });
  el.hass = {
    language: 'en',
    states: {
      'sensor.demo_battery': { state: '78', attributes: {} },
      'binary_sensor.demo_charging': { state: 'on', attributes: {} },
      'sensor.demo_volume': { state: '45', attributes: {} },
      'sensor.demo_temperature': { state: '52', attributes: {} },
      'sensor.demo_playtime_today_min': { state: '23', attributes: {} },
      'sensor.demo_mode': { state: 'game', attributes: {} },
      'sensor.demo_game': { state: 'Pokemon FireRed', attributes: {} },
      'sensor.demo_core': { state: 'mgba', attributes: {} },
    },
  };
</script>
</body></html>
EOF
python3 -m http.server 8765 &
sleep 1
open http://localhost:8765/dev.html
```

Visually verify the card renders: device SVG, "Playing Pokemon FireRed (mgba) ⚡", 4 stat tiles. Kill the server when done:

```bash
kill %1 2>/dev/null
rm dev.html
```

- [ ] **Step 3: Commit if anything changed**

```bash
git status
# If only dev.html appeared and was removed: nothing to commit. Skip.
```

---

### Task 17: Create GitHub repo + push + tag v0.1.0

- [ ] **Step 1: Create the public repo + push**

```bash
cd /Users/hudsonbrendon/Github/miyoo-mini-card
gh repo create miyoo-mini-card \
    --public \
    --source=. \
    --description "Home Assistant Lovelace card for Miyoo Mini Plus + miyoo-mqtt-reporter" \
    --push
```

Expected: prints `https://github.com/hudsonbrendon/miyoo-mini-card` and pushes `main`.

- [ ] **Step 2: Tag + push v0.1.0 to trigger the release workflow**

```bash
git tag v0.1.0
git push origin v0.1.0
```

Expected: GitHub Actions runs the `release` workflow; after ~1 minute, a Release with `miyoo-mini-card.js` attached appears at
`https://github.com/hudsonbrendon/miyoo-mini-card/releases/tag/v0.1.0`.

Verify:

```bash
gh release view v0.1.0 --json assets --jq '.assets[].name'
```

Expected: `miyoo-mini-card.js`.

- [ ] **Step 3: Confirm HACS will discover it**

`hacs.json`'s `filename` matches the release asset; that's all HACS needs. No further action.

---

### Task 18: Install in Home Assistant and screenshot

This task is manual hardware-style verification — no commits, no automation. Documents the steps the user takes to actually use the card.

- [ ] **Step 1: HACS → Frontend → Custom repositories**

Add `https://github.com/hudsonbrendon/miyoo-mini-card` as type **Lovelace**.

- [ ] **Step 2: Install + reload browser**

- [ ] **Step 3: Add to a dashboard**

Edit dashboard → Add card → search "Miyoo" → drop. Replace the auto-stub `entity:` with the real device prefix from your Miyoo (Settings → Devices → MQTT → the Miyoo device → look at the entity ids — strip the `sensor.` prefix and the trailing `_battery`, that's the prefix).

- [ ] **Step 4: Live verify**

The card should show the running game (if a ROM is loaded), animate the charging LED when plugged, and update every `INTERVAL` seconds.

- [ ] **Step 5: Capture a screenshot**

Save it to the card repo at `assets/card-preview.png` so the README image renders. Commit + push:

```bash
cd /Users/hudsonbrendon/Github/miyoo-mini-card
git add assets/card-preview.png
git commit -m "docs: add card preview screenshot"
git push origin main
```

---

## Self-Review

**Spec coverage**
- "Crie esse desenho igual o Nintendo Switch, mas do Mew Mini" → Task 10 builds the inline SVG with a Miyoo-shaped body, D-pad, ABXY, screen, charging LED. ✔
- "mostra esse card lá no Home Assistant" → Task 17 publishes the release HACS picks up; Task 18 documents the dashboard install. ✔
- "com as principais informações aí que a gente tem na integração do MQTT" → Task 11 wires battery + charging + state line + 4 default stats (battery / volume / temperature / playtime_today) from the 73 entities the daemon publishes. EntityKey union in Task 3 covers all the high-value fields; users can swap stats via YAML. ✔
- "crie um novo repositorio pra ele" → Task 17 runs `gh repo create --public --push`. ✔
- "uma nova pasta pra concentrar esse codigo aqui no meu mac" → Task 1 creates `/Users/hudsonbrendon/Github/miyoo-mini-card/` and inits git. ✔

**Placeholder scan** — every code step has full source. The only manual step is Task 18 (HA dashboard install + screenshot) which can't be automated from a Mac without the HA frontend.

**Type / name consistency**
- `CARD_NAME` defined in Task 3, used in Task 11 (`@customElement(CARD_NAME)`) and the editor in Task 12 — matches.
- `EntityKey` union (Task 3) used by `resolveEntities` (Task 5), `computeStateLine` (Task 7), `formatStat` indirectly (Task 6 via `StatConfig.entity`), and the main component (Task 11) — consistent.
- `MiyooMiniCardConfig.entities` is `Partial<Record<EntityKey, string>>` in Task 4, consumed the same way by Tasks 5 and 11.
- `miyooSvg({ screenLine1, screenLine2, charging })` signature defined in Task 10, called with exactly those keys in Task 11.
- `cardStyles` defined in Task 9, referenced as `static styles = cardStyles` in Task 11.
- `localize(key, lang?)` signature defined in Task 8, used in Tasks 7 and 11 with the same shape.

**No tests for the main component** is deliberate — Lit + jsdom DOM assertions add a lot of weight for what is essentially glue between the three already-tested helpers + a static SVG. The build + smoke check in Task 16 verifies the wiring.

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-05-13-miyoo-mini-card.md`. Two execution options:

**1. Subagent-Driven (recommended)** — I dispatch a fresh subagent per task, review between tasks, fast iteration.

**2. Inline Execution** — Execute tasks in this session using executing-plans, batch execution with checkpoints.

Which approach?
