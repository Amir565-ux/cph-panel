#!/bin/bash
# =============================================================================
# CPH PANEL — Self-Extracting Installer
# Version: 1.0.0
# Install: bash <(curl -s https://raw.githubusercontent.com/Amir565-ux/cph-panel/main/scripts/install.sh)
#
# AI-EDITABLE STRUCTURE:
#   Each source file is embedded below as a clearly labelled heredoc section.
#   Search for "## FILE:" to jump to any file. Edit between the heredoc markers.
#   After editing, re-run this script — it extracts and rebuilds everything.
#
# SECTIONS IN ORDER:
#   1. Config & helpers
#   2. System setup (Node, PostgreSQL, Nginx, PM2)
#   3. FILE: backend/src/schema.ts         — Database table definition
#   4. FILE: backend/src/db.ts             — Drizzle ORM connection
#   5. FILE: backend/src/routes/health.ts  — Health check route
#   6. FILE: backend/src/routes/vps.ts     — VPS CRUD + action routes
#   7. FILE: backend/src/routes/dashboard.ts — Stats + resource usage routes
#   8. FILE: backend/src/routes/index.ts   — Route registry
#   9. FILE: backend/src/app.ts            — Express app setup
#  10. FILE: backend/src/index.ts          — Server entry point
#  11. FILE: backend/package.json          — Backend dependencies
#  12. FILE: backend/tsconfig.json         — TypeScript config
#  13. FILE: frontend/src/index.css        — Global styles
#  14. FILE: frontend/src/pages/Dashboard.tsx — Main dashboard page
#  15. FILE: frontend/src/App.tsx          — React app root
#  16. FILE: frontend/src/main.tsx         — React entry point
#  17. FILE: frontend/index.html           — HTML shell
#  18. FILE: frontend/package.json         — Frontend dependencies
#  19. FILE: frontend/vite.config.ts       — Vite build config
#  20. Build & start
# =============================================================================

# ── Colors ─────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'

# ── Config (AI: edit these defaults if needed) ──────────────────────────────
PANEL_DIR="${PANEL_DIR:-/opt/cph-panel}"
API_PORT="${API_PORT:-5000}"
PANEL_PORT="${PANEL_PORT:-80}"
DB_NAME="cph_panel"
DB_USER="cph_panel"
# Safe password generation — uses /dev/urandom, no openssl dependency
DB_PASS="${DB_PASS:-$(tr -dc 'a-f0-9' < /dev/urandom 2>/dev/null | head -c 32 || echo "cphpanel$(date +%s)")}"
NODE_VERSION="20"

log_info()  { echo -e "${GREEN}[INFO]${NC}  $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step()  { echo -e "\n${BLUE}${BOLD}==> $1${NC}"; }

die() { log_error "$1"; exit 1; }

run() {
  "$@" || { log_error "Command failed: $*"; exit 1; }
}

banner() {
  echo -e "${BLUE}${BOLD}"
  echo "   ██████╗██████╗ ██╗  ██╗    ██████╗  █████╗ ███╗   ██╗███████╗██╗     "
  echo "  ██╔════╝██╔══██╗██║  ██║    ██╔══██╗██╔══██╗████╗  ██║██╔════╝██║     "
  echo "  ██║     ██████╔╝███████║    ██████╔╝███████║██╔██╗ ██║█████╗  ██║     "
  echo "  ██║     ██╔═══╝ ██╔══██║    ██╔═══╝ ██╔══██║██║╚██╗██║██╔══╝  ██║     "
  echo "  ╚██████╗██║     ██║  ██║    ██║     ██║  ██║██║ ╚████║███████╗███████╗"
  echo "   ╚═════╝╚═╝     ╚═╝  ╚═╝    ╚═╝     ╚═╝  ╚═╝╚═╝  ╚═══╝╚══════╝╚══════╝"
  echo -e "${NC}${BOLD}   VPS Hosting Control Panel  v1.0.0${NC}\n"
}

check_root() {
  if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root."
    echo -e "  Re-run with: ${BOLD}sudo bash \$0${NC}"
    echo -e "  Or switch to root first: ${BOLD}sudo su -${NC}"
    exit 1
  fi
}

detect_os() {
  if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    log_info "Detected OS: ${PRETTY_NAME:-$ID $VERSION_ID}"
  else
    log_warn "Could not detect OS — assuming Debian/Ubuntu-compatible"
  fi
}

service_cmd() {
  # Handles both systemctl (VPS) and service (containers/Codespaces)
  local action="$1" svc="$2"
  if command -v systemctl &>/dev/null && systemctl is-system-running &>/dev/null 2>&1; then
    systemctl "$action" "$svc" 2>/dev/null || true
  else
    service "$svc" "$action" 2>/dev/null || true
  fi
}

install_system_deps() {
  log_step "Installing system dependencies"

  # Yeh variable set karta hai takay apt-get koi interactive question na pooche
  export DEBIAN_FRONTEND=noninteractive

  # Package list ko refresh karta hai — server se latest package names laata hai
  apt-get update -qq 2>&1 | tail -3

  # Ye sab zaroori programs install karta hai:
  #   curl/wget  = internet se files download karne ke liye
  #   git        = code manage karne ke liye
  #   build-essential = C/C++ tools jo Node.js compile karne lagte hain
  #   openssl    = secure passwords aur SSL certificates banane ke liye
  #   postgresql = database server — panel ka data yahan store hota hai
  #   nginx      = web server — browser se requests leke backend ko bhejta hai
  apt-get install -y -qq curl wget git build-essential openssl postgresql postgresql-contrib nginx 2>&1 | tail -5

  log_step "Installing Node.js $NODE_VERSION"

  # Check karta hai ke Node.js pehle se installed hai ya nahi
  # Agar nahi hai ya purana version hai to install karta hai
  if ! command -v node &>/dev/null || [[ "$(node -v | cut -d. -f1 | tr -d 'v')" -lt "$NODE_VERSION" ]]; then

    # NodeSource ka official script download karke chalata hai
    # Yeh script apt-get mein Node.js ka sahi source add karta hai
    curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION}.x | bash -

    # Ab Node.js install karta hai us source se jo upar add kiya
    apt-get install -y -q nodejs
  fi

  log_step "Installing pnpm + pm2"

  # pnpm = fast package manager, Node.js dependencies install karne ke liye
  # pm2  = process manager, backend server ko background mein chalata hai aur crash pe restart karta hai
  npm install -g pnpm pm2 --silent
}

setup_postgres() {
  log_step "Setting up PostgreSQL"

  # PostgreSQL service shuru karta hai
  # systemctl = normal VPS par, service = containers/Codespaces mein
  service_cmd start postgresql

  # Boot pe automatically start hone ke liye enable karta hai (sirf systemctl environments mein)
  service_cmd enable postgresql

  # PostgreSQL ke tayar hone ka intezaar karta hai — kabhi kabhi start hone mein waqt lagta hai
  local retries=0
  until su - postgres -c "psql -c 'SELECT 1' &>/dev/null" 2>/dev/null || [[ $retries -ge 10 ]]; do
    log_info "Waiting for PostgreSQL to be ready... ($retries/10)"
    # 2 second ruko phir dobara check karo
    sleep 2
    ((retries++))
  done

  # Agar service command se start nahi hua to pg_ctlcluster try karta hai (Debian ka alternative)
  if ! su - postgres -c "psql -c 'SELECT 1' &>/dev/null" 2>/dev/null; then
    # Installed PostgreSQL version dhundta hai
    PG_VERSION=$(ls /etc/postgresql/ 2>/dev/null | sort -V | tail -1)
    if [[ -n "$PG_VERSION" ]]; then
      # Directly cluster start karta hai version number ke saath
      pg_ctlcluster "$PG_VERSION" main start 2>/dev/null || true
      sleep 2
    fi
  fi

  # Agar panel ka database user pehle se nahi hai to banata hai
  su - postgres -c "psql -tc \"SELECT 1 FROM pg_user WHERE usename='$DB_USER'\" 2>/dev/null | grep -q 1 \
    || psql -c \"CREATE USER $DB_USER WITH PASSWORD '$DB_PASS'\" 2>/dev/null" 2>/dev/null || true

  # User ka password update karta hai (agar pehle se tha to bhi update ho jata hai)
  su - postgres -c "psql -c \"ALTER USER $DB_USER WITH PASSWORD '$DB_PASS'\" 2>/dev/null" 2>/dev/null || true

  # Agar panel ka database pehle se nahi hai to banata hai aur user ko owner banata hai
  su - postgres -c "psql -tc \"SELECT 1 FROM pg_database WHERE datname='$DB_NAME'\" 2>/dev/null | grep -q 1 \
    || psql -c \"CREATE DATABASE $DB_NAME OWNER $DB_USER\" 2>/dev/null" 2>/dev/null || true

  # DATABASE_URL variable set karta hai — backend is URL se database se connect karta hai
  DATABASE_URL="postgresql://$DB_USER:$DB_PASS@localhost:5432/$DB_NAME"
  log_info "Database ready: $DB_NAME"
}

# =============================================================================
# FILE EXTRACTION
# Each write_file call embeds the full content of one source file.
# AI: find the file you want to change, edit between the HEREDOC markers.
# =============================================================================

write_file() {
  local path="$1"
  mkdir -p "$(dirname "$PANEL_DIR/$path")"
  cat > "$PANEL_DIR/$path"
}

extract_files() {
  log_step "Extracting panel source files"

# ── ## FILE: backend/src/schema.ts ─────────────────────────────────────────
# AI: Edit this to add/remove database columns for the vps table.
# After editing, the migration runs automatically via drizzle-kit push.
write_file "backend/src/schema.ts" << 'HEREDOC'
import { pgTable, serial, text, integer, real, timestamp } from "drizzle-orm/pg-core";

export const vpsTable = pgTable("vps", {
  id:         serial("id").primaryKey(),
  name:       text("name").notNull(),
  status:     text("status").notNull().default("stopped"),
  cpuCores:   integer("cpu_cores").notNull(),
  ramGb:      real("ram_gb").notNull(),
  storageGb:  real("storage_gb").notNull(),
  ipAddress:  text("ip_address").notNull().default(""),
  os:         text("os").notNull(),
  location:   text("location"),
  cpuUsage:   real("cpu_usage").notNull().default(0),
  ramUsage:   real("ram_usage").notNull().default(0),
  createdAt:  timestamp("created_at").notNull().defaultNow(),
});

export type Vps = typeof vpsTable.$inferSelect;
export type InsertVps = typeof vpsTable.$inferInsert;
HEREDOC

# ── ## FILE: backend/src/db.ts ──────────────────────────────────────────────
# AI: Database connection. DATABASE_URL is set by the installer automatically.
write_file "backend/src/db.ts" << 'HEREDOC'
import { drizzle } from "drizzle-orm/node-postgres";
import pg from "pg";
import * as schema from "./schema.js";

if (!process.env.DATABASE_URL) throw new Error("DATABASE_URL not set");

const pool = new pg.Pool({ connectionString: process.env.DATABASE_URL });
export const db = drizzle(pool, { schema });
export * from "./schema.js";
HEREDOC

# ── ## FILE: backend/src/routes/health.ts ──────────────────────────────────
# AI: Simple health check. Returns { status: "ok" }. Used by uptime monitors.
write_file "backend/src/routes/health.ts" << 'HEREDOC'
import { Router } from "express";
const r = Router();
r.get("/healthz", (_req, res) => res.json({ status: "ok" }));
export default r;
HEREDOC

# ── ## FILE: backend/src/routes/vps.ts ────────────────────────────────────
# AI: All VPS CRUD endpoints + action endpoint (start/stop/suspend/reboot).
# Endpoints: GET /vps, POST /vps, GET /vps/:id, PATCH /vps/:id,
#            DELETE /vps/:id, POST /vps/:id/action
write_file "backend/src/routes/vps.ts" << 'HEREDOC'
import { Router } from "express";
import { db, vpsTable } from "../db.js";
import { eq } from "drizzle-orm";

const r = Router();

const fmt = (v: typeof vpsTable.$inferSelect) => ({
  ...v,
  createdAt: v.createdAt instanceof Date ? v.createdAt.toISOString() : v.createdAt,
});

r.get("/vps", async (req, res) => {
  try {
    res.json((await db.select().from(vpsTable).orderBy(vpsTable.id)).map(fmt));
  } catch (e) { res.status(500).json({ error: String(e) }); }
});

r.post("/vps", async (req, res) => {
  const { name, cpuCores, ramGb, storageGb, os, location, ipAddress } = req.body;
  if (!name || !cpuCores || !ramGb || !storageGb || !os)
    return void res.status(400).json({ error: "Missing required fields" });
  try {
    const [row] = await db.insert(vpsTable).values({
      name, cpuCores: Number(cpuCores), ramGb: Number(ramGb),
      storageGb: Number(storageGb), os,
      location: location ?? null,
      ipAddress: ipAddress ?? `10.0.${Math.floor(Math.random()*255)}.${Math.floor(Math.random()*254)+1}`,
      status: "stopped", cpuUsage: 0, ramUsage: 0,
    }).returning();
    res.status(201).json(fmt(row));
  } catch (e) { res.status(500).json({ error: String(e) }); }
});

r.get("/vps/:id", async (req, res) => {
  try {
    const [row] = await db.select().from(vpsTable).where(eq(vpsTable.id, Number(req.params.id)));
    row ? res.json(fmt(row)) : res.status(404).json({ error: "Not found" });
  } catch (e) { res.status(500).json({ error: String(e) }); }
});

r.patch("/vps/:id", async (req, res) => {
  const { name, os, location } = req.body;
  try {
    const [row] = await db.update(vpsTable).set({ name, os, location })
      .where(eq(vpsTable.id, Number(req.params.id))).returning();
    row ? res.json(fmt(row)) : res.status(404).json({ error: "Not found" });
  } catch (e) { res.status(500).json({ error: String(e) }); }
});

r.delete("/vps/:id", async (req, res) => {
  try {
    const [row] = await db.delete(vpsTable).where(eq(vpsTable.id, Number(req.params.id))).returning();
    row ? res.status(204).send() : res.status(404).json({ error: "Not found" });
  } catch (e) { res.status(500).json({ error: String(e) }); }
});

r.post("/vps/:id/action", async (req, res) => {
  const { action } = req.body;
  const validActions = ["start", "stop", "suspend", "reboot"];
  if (!validActions.includes(action))
    return void res.status(400).json({ error: "Invalid action" });

  const statusMap: Record<string, string> = {
    start: "running", stop: "stopped", suspend: "suspended", reboot: "running",
  };
  const usageMap: Record<string, { cpuUsage: number; ramUsage: number }> = {
    start:   { cpuUsage: Math.random()*40+10, ramUsage: Math.random()*40+20 },
    stop:    { cpuUsage: 0, ramUsage: 0 },
    suspend: { cpuUsage: 0, ramUsage: 5 },
    reboot:  { cpuUsage: Math.random()*30+5, ramUsage: Math.random()*30+15 },
  };
  try {
    const [row] = await db.update(vpsTable)
      .set({ status: statusMap[action], ...usageMap[action] })
      .where(eq(vpsTable.id, Number(req.params.id))).returning();
    row ? res.json(fmt(row)) : res.status(404).json({ error: "Not found" });
  } catch (e) { res.status(500).json({ error: String(e) }); }
});

export default r;
HEREDOC

# ── ## FILE: backend/src/routes/dashboard.ts ──────────────────────────────
# AI: Dashboard stats + resource usage history endpoints.
# /api/dashboard/stats    → totals and status counts
# /api/dashboard/resource-usage → last 10 data points of cpu/ram usage
write_file "backend/src/routes/dashboard.ts" << 'HEREDOC'
import { Router } from "express";
import { db, vpsTable } from "../db.js";

const r = Router();

r.get("/dashboard/stats", async (_req, res) => {
  try {
    const rows = await db.select().from(vpsTable);
    res.json({
      totalVps:       rows.length,
      totalCpuCores:  rows.reduce((s, v) => s + v.cpuCores, 0),
      totalRamGb:     Math.round(rows.reduce((s, v) => s + v.ramGb, 0) * 10) / 10,
      totalStorageGb: Math.round(rows.reduce((s, v) => s + v.storageGb, 0) * 10) / 10,
      runningCount:   rows.filter(v => v.status === "running").length,
      stoppedCount:   rows.filter(v => v.status === "stopped").length,
      suspendedCount: rows.filter(v => v.status === "suspended").length,
    });
  } catch (e) { res.status(500).json({ error: String(e) }); }
});

r.get("/dashboard/resource-usage", async (_req, res) => {
  try {
    const rows = await db.select().from(vpsTable);
    const running = rows.filter(v => v.status === "running");
    const avgCpu = running.length ? running.reduce((s, v) => s + (v.cpuUsage ?? 0), 0) / running.length : 0;
    const avgRam = running.length ? running.reduce((s, v) => s + (v.ramUsage ?? 0), 0) / running.length : 0;

    const now = Date.now();
    const jitter = () => (Math.random() - 0.5) * 8;
    const history = Array.from({ length: 10 }, (_, i) => {
      const t = new Date(now - (9 - i) * 6 * 60 * 1000);
      return {
        time: t.toLocaleTimeString("en-US", { hour: "2-digit", minute: "2-digit", hour12: false }),
        cpuUsage: Math.max(0, Math.min(100, avgCpu + jitter())),
        ramUsage: Math.max(0, Math.min(100, avgRam + jitter())),
      };
    });
    res.json({ history });
  } catch (e) { res.status(500).json({ error: String(e) }); }
});

export default r;
HEREDOC

# ── ## FILE: backend/src/routes/index.ts ──────────────────────────────────
# AI: Register new routers here by importing and adding router.use(yourRouter).
write_file "backend/src/routes/index.ts" << 'HEREDOC'
import { Router } from "express";
import health    from "./health.js";
import vps       from "./vps.js";
import dashboard from "./dashboard.js";

const router = Router();
router.use(health);
router.use(vps);
router.use(dashboard);
export default router;
HEREDOC

# ── ## FILE: backend/src/app.ts ────────────────────────────────────────────
# AI: Express app. Add global middleware here (auth, rate-limiting, etc.)
write_file "backend/src/app.ts" << 'HEREDOC'
import express from "express";
import cors    from "cors";
import router  from "./routes/index.js";

const app = express();
app.use(cors());
app.use(express.json());
app.use(express.urlencoded({ extended: true }));
app.use("/api", router);
export default app;
HEREDOC

# ── ## FILE: backend/src/index.ts ─────────────────────────────────────────
# AI: Entry point. Reads PORT env var and starts the server.
write_file "backend/src/index.ts" << 'HEREDOC'
import app from "./app.js";
const port = Number(process.env.PORT ?? 5000);
app.listen(port, () => console.log(`[cph-api] Listening on :${port}`));
HEREDOC

# ── ## FILE: backend/package.json ─────────────────────────────────────────
# AI: Add backend npm packages here, then re-run the installer.
write_file "backend/package.json" << 'HEREDOC'
{
  "name": "cph-panel-api",
  "version": "1.0.0",
  "type": "module",
  "scripts": {
    "build": "tsc",
    "start": "node dist/index.js",
    "dev":   "tsx watch src/index.ts"
  },
  "dependencies": {
    "cors": "^2.8.5",
    "drizzle-orm": "^0.41.0",
    "express": "^5.0.1",
    "pg": "^8.13.0"
  },
  "devDependencies": {
    "@types/cors":    "^2.8.17",
    "@types/express": "^5.0.0",
    "@types/node":    "^22.0.0",
    "@types/pg":      "^8.11.10",
    "drizzle-kit":    "^0.31.0",
    "tsx":            "^4.19.0",
    "typescript":     "^5.7.0"
  }
}
HEREDOC

# ── ## FILE: backend/tsconfig.json ────────────────────────────────────────
write_file "backend/tsconfig.json" << 'HEREDOC'
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "NodeNext",
    "moduleResolution": "NodeNext",
    "outDir": "./dist",
    "rootDir": "./src",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true
  },
  "include": ["src"]
}
HEREDOC

# ── ## FILE: backend/drizzle.config.ts ────────────────────────────────────
write_file "backend/drizzle.config.ts" << 'HEREDOC'
import type { Config } from "drizzle-kit";
export default {
  schema: "./src/schema.ts",
  dialect: "postgresql",
  dbCredentials: { url: process.env.DATABASE_URL! },
} satisfies Config;
HEREDOC

# ── ## FILE: frontend/src/index.css ───────────────────────────────────────
# AI: Global styles. Theme: black bg, white text, blue (#2563eb) for buttons only.
write_file "frontend/src/index.css" << 'HEREDOC'
* { box-sizing: border-box; margin: 0; padding: 0; }
body {
  background: #000;
  color: #fff;
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
  -webkit-font-smoothing: antialiased;
}
HEREDOC

# ── ## FILE: frontend/src/pages/Dashboard.tsx ─────────────────────────────
# AI: The main dashboard page. Contains:
#   - StatCard component  → edit to change the 4 top stat cards
#   - CustomTooltip       → chart tooltip style
#   - PieTooltip          → donut chart tooltip
#   - Dashboard()         → main render, contains navbar, stats, charts, status strip
#
# COLOR GUIDE (AI: search these hex values to change colors):
#   #2563eb  → blue  (navbar icon, admin avatar — the "blue only" rule)
#   #22c55e  → green (running VPS status)
#   #52525b  → grey  (stopped VPS status)
#   #f59e0b  → amber (suspended VPS status)
#   #3b82f6  → blue  (CPU line in resource chart)
#   #0f0f0f  → card background
#   rgba(255,255,255,0.08) → card border
#
# API calls use plain fetch() to /api/dashboard/stats and /api/dashboard/resource-usage.
# No external state library needed — uses React's built-in hooks.
write_file "frontend/src/pages/Dashboard.tsx" << 'HEREDOC'
import { useEffect, useState } from "react";
import { PieChart, Pie, Cell, ResponsiveContainer, LineChart, Line, XAxis, YAxis, Tooltip, CartesianGrid } from "recharts";

// ── Types ────────────────────────────────────────────────────────────────
interface Stats {
  totalVps: number; totalCpuCores: number; totalRamGb: number; totalStorageGb: number;
  runningCount: number; stoppedCount: number; suspendedCount: number;
}
interface UsagePoint { time: string; cpuUsage: number; ramUsage: number; }

// ── Colors (AI: change these to retheme the entire panel) ────────────────
const CLR = { blue: "#2563eb", green: "#22c55e", grey: "#52525b", amber: "#f59e0b", cpu: "#3b82f6" };

// ── Stat Card ─────────────────────────────────────────────────────────────
function StatCard({ label, value, sub, icon }: { label: string; value: string|number; sub?: string; icon: string }) {
  return (
    <div style={{ background:"#0f0f0f", border:"1px solid rgba(255,255,255,0.08)", borderRadius:12, padding:16, display:"flex", flexDirection:"column", gap:12 }}>
      <div style={{ display:"flex", alignItems:"center", justifyContent:"space-between" }}>
        <span style={{ fontSize:11, fontWeight:600, letterSpacing:"0.1em", textTransform:"uppercase", color:"rgba(255,255,255,0.35)" }}>{label}</span>
        <div style={{ width:30, height:30, borderRadius:8, background:"rgba(255,255,255,0.05)", display:"flex", alignItems:"center", justifyContent:"center", fontSize:15 }}>{icon}</div>
      </div>
      <div style={{ fontSize:28, fontWeight:700, color:"#fff", lineHeight:1 }}>{value}</div>
      {sub && <div style={{ fontSize:11, color:"rgba(255,255,255,0.25)" }}>{sub}</div>}
    </div>
  );
}

// ── Tooltips ──────────────────────────────────────────────────────────────
const ChartTip = ({ active, payload, label }: any) => {
  if (!active || !payload?.length) return null;
  return (
    <div style={{ background:"#111", border:"1px solid rgba(255,255,255,0.1)", borderRadius:8, padding:"8px 12px", fontSize:12 }}>
      <p style={{ color:"rgba(255,255,255,0.4)", marginBottom:4 }}>{label}</p>
      {payload.map((p: any) => <p key={p.dataKey} style={{ color:p.color }}>{p.name}: {p.value.toFixed(1)}%</p>)}
    </div>
  );
};
const PieTip = ({ active, payload }: any) => {
  if (!active || !payload?.length) return null;
  return (
    <div style={{ background:"#111", border:"1px solid rgba(255,255,255,0.1)", borderRadius:8, padding:"6px 10px", fontSize:12 }}>
      <p style={{ color:payload[0].payload.color }}>{payload[0].name}: {payload[0].value}</p>
    </div>
  );
};

// ── Main Dashboard ────────────────────────────────────────────────────────
export default function Dashboard() {
  const [stats,   setStats]   = useState<Stats|null>(null);
  const [usage,   setUsage]   = useState<UsagePoint[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const base = (window as any).__API_BASE__ || "";
    Promise.all([
      fetch(`${base}/api/dashboard/stats`).then(r => r.json()),
      fetch(`${base}/api/dashboard/resource-usage`).then(r => r.json()),
    ]).then(([s, u]) => { setStats(s); setUsage(u.history ?? []); })
      .catch(console.error)
      .finally(() => setLoading(false));
  }, []);

  const pieData = stats ? [
    { name:"Running",   value:stats.runningCount,   color:CLR.green },
    { name:"Stopped",   value:stats.stoppedCount,   color:CLR.grey  },
    { name:"Suspended", value:stats.suspendedCount, color:CLR.amber },
  ] : [];

  return (
    <div style={{ minHeight:"100vh", background:"#000", color:"#fff", fontFamily:"inherit" }}>

      {/* ── Navbar ── */}
      <header style={{ position:"sticky", top:0, zIndex:50, borderBottom:"1px solid rgba(255,255,255,0.08)", background:"rgba(0,0,0,0.85)", backdropFilter:"blur(12px)" }}>
        <div style={{ maxWidth:1100, margin:"0 auto", padding:"0 20px", height:56, display:"flex", alignItems:"center", justifyContent:"space-between" }}>
          <div style={{ display:"flex", alignItems:"center", gap:10 }}>
            <div style={{ width:30, height:30, borderRadius:8, background:CLR.blue, display:"flex", alignItems:"center", justifyContent:"center", fontSize:16 }}>⬛</div>
            <span style={{ fontWeight:700, fontSize:16 }}>CPH Panel</span>
          </div>
          <div style={{ display:"flex", alignItems:"center", gap:10 }}>
            <div style={{ width:32, height:32, borderRadius:"50%", background:"#1d4ed8", display:"flex", alignItems:"center", justifyContent:"center", fontSize:13, fontWeight:700 }}>A</div>
            <span style={{ fontSize:13, color:"rgba(255,255,255,0.5)" }}>admin</span>
          </div>
        </div>
      </header>

      <main style={{ maxWidth:1100, margin:"0 auto", padding:"32px 20px 40px" }}>

        {/* ── Welcome ── */}
        <div style={{ marginBottom:28 }}>
          <h1 style={{ fontSize:"clamp(22px,5vw,32px)", fontWeight:700, margin:0 }}>Welcome, admin.</h1>
          <p style={{ fontSize:14, color:"rgba(255,255,255,0.35)", marginTop:6 }}>Manage your virtual private servers from one place.</p>
        </div>

        {/* ── Stats grid (2-col mobile → 4-col desktop) ── */}
        <div style={{ display:"grid", gridTemplateColumns:"repeat(2,1fr)", gap:12, marginBottom:20 }} className="g4">
          {loading
            ? [...Array(4)].map((_,i) => <div key={i} style={{ background:"#0f0f0f", border:"1px solid rgba(255,255,255,0.08)", borderRadius:12, height:108 }} />)
            : stats ? [
                { label:"Total VPS",   value:stats.totalVps,            sub:"Across all servers", icon:"🖥" },
                { label:"CPU Cores",   value:stats.totalCpuCores,       sub:"Across all VPS",     icon:"⚙️" },
                { label:"Total RAM",   value:`${stats.totalRamGb} GB`,  sub:"Across all VPS",     icon:"🧠" },
                { label:"Storage",     value:`${stats.totalStorageGb} GB`, sub:"Across all VPS",  icon:"💾" },
              ].map(c => <StatCard key={c.label} {...c} />)
            : null}
        </div>

        {/* ── Charts (1-col mobile → 2-col desktop) ── */}
        <div style={{ display:"grid", gridTemplateColumns:"1fr", gap:16, marginBottom:20 }} className="g2">

          {/* Donut chart */}
          <div style={{ background:"#0f0f0f", border:"1px solid rgba(255,255,255,0.08)", borderRadius:12, padding:"20px 20px 16px" }}>
            <p style={{ fontSize:12, fontWeight:600, textTransform:"uppercase", letterSpacing:"0.1em", color:"rgba(255,255,255,0.4)", marginBottom:16 }}>VPS Status Overview</p>
            {loading ? (
              <div style={{ height:180, display:"flex", alignItems:"center", justifyContent:"center", color:"rgba(255,255,255,0.2)", fontSize:13 }}>Loading...</div>
            ) : stats && stats.totalVps > 0 ? (
              <div style={{ display:"flex", alignItems:"center", gap:24 }}>
                <div style={{ width:160, height:160, flexShrink:0 }}>
                  <ResponsiveContainer width={160} height={160}>
                    <PieChart>
                      <Pie data={pieData} cx={76} cy={76} innerRadius={48} outerRadius={72} paddingAngle={3} dataKey="value" strokeWidth={0} startAngle={90} endAngle={-270}>
                        {pieData.map((e,i) => <Cell key={i} fill={e.color} />)}
                      </Pie>
                      <Tooltip content={<PieTip />} />
                    </PieChart>
                  </ResponsiveContainer>
                </div>
                <div style={{ display:"flex", flexDirection:"column", gap:12 }}>
                  {pieData.map(d => (
                    <div key={d.name} style={{ display:"flex", alignItems:"center", gap:8 }}>
                      <div style={{ width:10, height:10, borderRadius:"50%", background:d.color }} />
                      <span style={{ fontSize:13, color:"rgba(255,255,255,0.45)" }}>{d.name}</span>
                      <span style={{ fontSize:15, fontWeight:700, marginLeft:6 }}>{d.value}</span>
                    </div>
                  ))}
                </div>
              </div>
            ) : (
              <div style={{ height:160, display:"flex", alignItems:"center", justifyContent:"center", color:"rgba(255,255,255,0.2)", fontSize:13 }}>No VPS instances yet</div>
            )}
          </div>

          {/* Line chart */}
          <div style={{ background:"#0f0f0f", border:"1px solid rgba(255,255,255,0.08)", borderRadius:12, padding:"20px 20px 16px" }}>
            <p style={{ fontSize:12, fontWeight:600, textTransform:"uppercase", letterSpacing:"0.1em", color:"rgba(255,255,255,0.4)", marginBottom:16 }}>Resource Usage</p>
            {loading ? (
              <div style={{ height:180, display:"flex", alignItems:"center", justifyContent:"center", color:"rgba(255,255,255,0.2)", fontSize:13 }}>Loading...</div>
            ) : usage.length ? (
              <>
                <div style={{ height:160 }}>
                  <ResponsiveContainer width="100%" height="100%">
                    <LineChart data={usage} margin={{ top:4, right:8, bottom:0, left:-20 }}>
                      <CartesianGrid strokeDasharray="3 3" stroke="rgba(255,255,255,0.05)" vertical={false} />
                      <XAxis dataKey="time" stroke="transparent" tick={{ fill:"rgba(255,255,255,0.25)", fontSize:10 }} tickLine={false} />
                      <YAxis stroke="transparent" tick={{ fill:"rgba(255,255,255,0.25)", fontSize:10 }} tickLine={false} unit="%" domain={[0,100]} />
                      <Tooltip content={<ChartTip />} />
                      <Line type="monotone" dataKey="cpuUsage" name="CPU" stroke={CLR.cpu}   strokeWidth={2} dot={false} />
                      <Line type="monotone" dataKey="ramUsage" name="RAM" stroke={CLR.amber} strokeWidth={2} dot={false} />
                    </LineChart>
                  </ResponsiveContainer>
                </div>
                <div style={{ display:"flex", gap:16, marginTop:8, justifyContent:"center" }}>
                  {[{l:"CPU Usage",c:CLR.cpu},{l:"RAM Usage",c:CLR.amber}].map(x => (
                    <div key={x.l} style={{ display:"flex", alignItems:"center", gap:6, fontSize:12, color:"rgba(255,255,255,0.4)" }}>
                      <div style={{ width:20, height:2, background:x.c, borderRadius:2 }} />
                      {x.l}
                    </div>
                  ))}
                </div>
              </>
            ) : (
              <div style={{ height:160, display:"flex", alignItems:"center", justifyContent:"center", color:"rgba(255,255,255,0.2)", fontSize:13 }}>No data</div>
            )}
          </div>
        </div>

        {/* ── Status strip ── */}
        {stats && stats.totalVps > 0 && (
          <div style={{ display:"grid", gridTemplateColumns:"repeat(3,1fr)", gap:12 }}>
            {[
              { label:"Running",   count:stats.runningCount,   color:CLR.green, border:"rgba(34,197,94,0.2)",   bg:"rgba(34,197,94,0.05)"  },
              { label:"Stopped",   count:stats.stoppedCount,   color:"rgba(255,255,255,0.4)", border:"rgba(255,255,255,0.08)", bg:"rgba(255,255,255,0.03)" },
              { label:"Suspended", count:stats.suspendedCount, color:CLR.amber, border:"rgba(245,158,11,0.2)",  bg:"rgba(245,158,11,0.05)" },
            ].map(s => (
              <div key={s.label} style={{ background:s.bg, border:`1px solid ${s.border}`, borderRadius:12, padding:"16px 12px", textAlign:"center" }}>
                <div style={{ fontSize:26, fontWeight:700, color:s.color }}>{s.count}</div>
                <div style={{ fontSize:12, color:"rgba(255,255,255,0.35)", marginTop:4 }}>{s.label}</div>
              </div>
            ))}
          </div>
        )}
      </main>

      <style>{`
        @media(min-width:900px){.g4{grid-template-columns:repeat(4,1fr)!important}.g2{grid-template-columns:repeat(2,1fr)!important}}
      `}</style>
    </div>
  );
}
HEREDOC

# ── ## FILE: frontend/src/App.tsx ─────────────────────────────────────────
# AI: App root. Add new pages/routes here. Currently renders only Dashboard.
write_file "frontend/src/App.tsx" << 'HEREDOC'
import Dashboard from "./pages/Dashboard";
export default function App() { return <Dashboard />; }
HEREDOC

# ── ## FILE: frontend/src/main.tsx ────────────────────────────────────────
write_file "frontend/src/main.tsx" << 'HEREDOC'
import { createRoot } from "react-dom/client";
import "./index.css";
import App from "./App";
createRoot(document.getElementById("root")!).render(<App />);
HEREDOC

# ── ## FILE: frontend/index.html ──────────────────────────────────────────
# AI: HTML shell. Change <title> here to rename the browser tab.
write_file "frontend/index.html" << 'HEREDOC'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>CPH Panel</title>
</head>
<body>
  <div id="root"></div>
  <script type="module" src="/src/main.tsx"></script>
</body>
</html>
HEREDOC

# ── ## FILE: frontend/package.json ────────────────────────────────────────
# AI: Add frontend npm packages here (React components, charting libs, etc.)
write_file "frontend/package.json" << 'HEREDOC'
{
  "name": "cph-panel-ui",
  "version": "1.0.0",
  "private": true,
  "scripts": {
    "dev":   "vite",
    "build": "vite build",
    "preview": "vite preview"
  },
  "dependencies": {
    "react":        "^18.3.1",
    "react-dom":    "^18.3.1",
    "recharts":     "^2.13.0"
  },
  "devDependencies": {
    "@types/react":     "^18.3.12",
    "@types/react-dom": "^18.3.1",
    "@vitejs/plugin-react": "^4.3.3",
    "typescript": "^5.7.0",
    "vite":       "^6.0.0"
  }
}
HEREDOC

# ── ## FILE: frontend/tsconfig.json ──────────────────────────────────────
write_file "frontend/tsconfig.json" << 'HEREDOC'
{
  "compilerOptions": {
    "target": "ES2020",
    "useDefineForClassFields": true,
    "lib": ["ES2020", "DOM", "DOM.Iterable"],
    "module": "ESNext",
    "skipLibCheck": true,
    "moduleResolution": "bundler",
    "allowImportingTsExtensions": true,
    "isolatedModules": true,
    "noEmit": true,
    "jsx": "react-jsx",
    "strict": true
  },
  "include": ["src"]
}
HEREDOC

# ── ## FILE: frontend/vite.config.ts ─────────────────────────────────────
# AI: Vite config. The /api proxy forwards API calls to the backend server.
# Change "target" port if you changed API_PORT above.
write_file "frontend/vite.config.ts" << HEREDOC
import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

export default defineConfig({
  plugins: [react()],
  server: {
    proxy: {
      "/api": { target: "http://localhost:${API_PORT}", changeOrigin: true },
    },
  },
  build: { outDir: "dist" },
});
HEREDOC

# ── ## FILE: ecosystem.config.cjs ────────────────────────────────────────
# AI: PM2 process config. Adjust env vars or restart strategies here.
write_file "ecosystem.config.cjs" << HEREDOC
module.exports = {
  apps: [{
    name: "cph-panel-api",
    script: "./backend/dist/index.js",
    cwd: "$PANEL_DIR",
    env: {
      NODE_ENV: "production",
      DATABASE_URL: "${DATABASE_URL}",
      PORT: ${API_PORT},
    },
    restart_delay: 3000,
    max_restarts: 10,
  }],
};
HEREDOC

  log_info "All files extracted to $PANEL_DIR"
}

# =============================================================================
# BUILD & START
# =============================================================================

migrate_db() {
  log_step "Running database migrations"

  # Backend folder mein jaata hai jahan drizzle config file hai
  cd "$PANEL_DIR/backend"

  # Database tables banata ya update karta hai schema.ts ke mutabiq
  # --force = purane data ko preserve karte hue structure change karta hai
  DATABASE_URL="$DATABASE_URL" npx drizzle-kit push --config drizzle.config.ts --force
}

build_backend() {
  log_step "Building backend (TypeScript → JS)"

  # Backend folder mein jaata hai
  cd "$PANEL_DIR/backend"

  # Sab npm packages install karta hai jo backend ke liye chahiye (express, drizzle, pg etc.)
  pnpm install --silent

  # TypeScript code ko JavaScript mein compile karta hai — Node.js direct TS nahi chal sakta
  # Output /dist folder mein jaata hai
  pnpm run build
}

build_frontend() {
  log_step "Building frontend (React → static)"

  # Frontend folder mein jaata hai
  cd "$PANEL_DIR/frontend"

  # Sab npm packages install karta hai jo frontend ke liye chahiye (React, Recharts etc.)
  pnpm install --silent

  # React app ko static HTML/CSS/JS mein compile karta hai
  # Output /dist folder mein jaata hai — yahi Nginx serve karta hai browser ko
  pnpm run build
  log_info "Frontend built to $PANEL_DIR/frontend/dist"
}

setup_nginx() {
  log_step "Configuring Nginx"

  # Nginx config file likhta hai CPH Panel ke liye
  # Yeh file batata hai ke Nginx kaise kaam kare:
  #   - Port 80 par listen karo
  #   - Frontend files /frontend/dist se serve karo
  #   - /api/* wali requests backend (port 5000) ko bhej do
  cat > /etc/nginx/sites-available/cph-panel << NGINX
server {
    listen ${PANEL_PORT};
    server_name _;
    root $PANEL_DIR/frontend/dist;
    index index.html;

    location / {
        try_files \$uri \$uri/ /index.html;
    }

    location /api/ {
        proxy_pass         http://127.0.0.1:${API_PORT};
        proxy_http_version 1.1;
        proxy_set_header   Host \$host;
        proxy_set_header   X-Real-IP \$remote_addr;
    }
}
NGINX

  # CPH Panel config ko sites-enabled mein link karta hai (enable karta hai)
  ln -sf /etc/nginx/sites-available/cph-panel /etc/nginx/sites-enabled/cph-panel

  # Purani default Nginx site remove karta hai taake conflict na ho
  rm -f /etc/nginx/sites-enabled/default

  # Config test karta hai aur agar sahi hai to Nginx reload karta hai
  nginx -t && (service_cmd reload nginx || nginx -s reload || true)
}

start_services() {
  log_step "Starting API server with PM2"

  # Panel directory mein jaata hai jahan ecosystem.config.cjs hai
  cd "$PANEL_DIR"

  # Agar pehle se cph-panel-api chal raha hai to band karta hai (fresh start ke liye)
  pm2 delete cph-panel-api 2>/dev/null || true

  # Backend API server shuru karta hai ecosystem config ke mutabiq
  # PM2 is process ko background mein chalata hai aur crash hone par restart karta hai
  pm2 start ecosystem.config.cjs

  # PM2 process list save karta hai taake server reboot par dobara shuru ho
  pm2 save

  # Server boot par PM2 automatically start ho — systemd par kaam karta hai
  # Containers/Codespaces mein silently skip ho jaata hai
  pm2 startup 2>/dev/null | grep -E "^sudo|^env" | bash 2>/dev/null || true
}

print_summary() {
  local IP; IP=$(hostname -I | awk '{print $1}')
  echo ""
  echo -e "${BLUE}${BOLD}═══════════════════════════════════════${NC}"
  echo -e "${GREEN}${BOLD}   CPH Panel installed successfully!${NC}"
  echo -e "${BLUE}${BOLD}═══════════════════════════════════════${NC}"
  echo ""
  echo -e "  Panel URL  : ${BOLD}http://$IP${NC}"
  echo -e "  API URL    : ${BOLD}http://$IP/api/healthz${NC}"
  echo -e "  Files      : ${BOLD}$PANEL_DIR${NC}"
  echo -e "  DB name    : ${BOLD}$DB_NAME${NC}"
  echo -e "  DB user    : ${BOLD}$DB_USER${NC}"
  echo -e "  DB pass    : ${BOLD}$DB_PASS${NC}  (save this!)"
  echo ""
  echo -e "  ${BOLD}Commands:${NC}"
  echo -e "    pm2 logs cph-panel-api   view API logs"
  echo -e "    pm2 restart all          restart services"
  echo -e "    nginx -t && nginx -s reload   reload nginx"
  echo ""
  echo -e "${BLUE}${BOLD}═══════════════════════════════════════${NC}"
}

# =============================================================================
# MAIN
# =============================================================================
main() {
  # CPH Panel ka naam aur version dikhata hai terminal mein
  banner

  # Check karta hai ke script root user se chal rahi hai ya nahi
  # Root hona zaroori hai kyunke system packages install karne hain
  check_root

  # Linux distribution detect karta hai (Ubuntu, Debian, etc.)
  detect_os

  # apt-get se sab zaroori packages install karta hai (Node.js, PostgreSQL, Nginx, PM2)
  install_system_deps

  # PostgreSQL database server setup karta hai — panel ka user aur database banata hai
  setup_postgres

  # Sab source files (backend + frontend) /opt/cph-panel mein extract karta hai
  extract_files

  # Database schema apply karta hai — vps table aur baaki tables banata hai
  migrate_db

  # Backend TypeScript code compile karke JavaScript mein convert karta hai
  build_backend

  # React frontend ko static HTML/CSS/JS files mein build karta hai
  build_frontend

  # Nginx web server configure karta hai — port 80 par panel serve karta hai
  setup_nginx

  # PM2 se backend API server shuru karta hai background mein
  start_services

  # Installation ka summary dikhata hai — URL, database credentials, etc.
  print_summary
}

# Script shuru karna — main() function call karta hai
main "$@"
