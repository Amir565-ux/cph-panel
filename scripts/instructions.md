# CPH Panel — AI Modification Instructions

This document tells any AI exactly how to understand, modify, and extend CPH Panel.
All source code lives inside `scripts/install.sh` as heredoc blocks.

---

## How the panel works

```
User browser
    │
    ▼
Nginx (port 80)
    ├── /api/*  → Express backend (port 5000)
    │               └── PostgreSQL database
    └── /*      → React frontend (static files)
```

- **Frontend**: React + Vite + Recharts. Single page (Dashboard). No router needed.
- **Backend**: Express 5, TypeScript, Drizzle ORM, PostgreSQL.
- **Install**: One bash script extracts all source files, builds both apps, starts them.

---

## File map inside `install.sh`

Search for `## FILE:` in `scripts/install.sh` to jump to any file.

| Section label                          | What it does                                      |
|----------------------------------------|--------------------------------------------------|
| `## FILE: backend/src/schema.ts`       | PostgreSQL table definition (columns, types)      |
| `## FILE: backend/src/db.ts`           | Drizzle ORM connection setup                      |
| `## FILE: backend/src/routes/health.ts`| GET /api/healthz → `{ status: "ok" }`            |
| `## FILE: backend/src/routes/vps.ts`   | Full VPS CRUD + start/stop/suspend/reboot         |
| `## FILE: backend/src/routes/dashboard.ts` | GET stats, GET resource-usage history        |
| `## FILE: backend/src/routes/index.ts` | Registers all routers                             |
| `## FILE: backend/src/app.ts`          | Express middleware setup                          |
| `## FILE: backend/src/index.ts`        | Server entry (reads PORT env var)                 |
| `## FILE: backend/package.json`        | Backend npm dependencies                          |
| `## FILE: frontend/src/index.css`      | Global CSS (black background, white text)         |
| `## FILE: frontend/src/pages/Dashboard.tsx` | Entire dashboard UI                         |
| `## FILE: frontend/src/App.tsx`        | React root — renders Dashboard                    |
| `## FILE: frontend/src/main.tsx`       | React entry point                                 |
| `## FILE: frontend/index.html`         | HTML shell (change `<title>` here)                |
| `## FILE: frontend/package.json`       | Frontend npm dependencies                         |
| `## FILE: frontend/vite.config.ts`     | Vite config + /api proxy                          |
| `## FILE: ecosystem.config.cjs`        | PM2 process config                                |

---

## API endpoints

| Method   | Path                      | Description                          |
|----------|---------------------------|--------------------------------------|
| GET      | /api/healthz              | Health check                         |
| GET      | /api/vps                  | List all VPS instances               |
| POST     | /api/vps                  | Create a VPS                         |
| GET      | /api/vps/:id              | Get one VPS                          |
| PATCH    | /api/vps/:id              | Update VPS name/os/location          |
| DELETE   | /api/vps/:id              | Delete a VPS                         |
| POST     | /api/vps/:id/action       | Action: start / stop / suspend / reboot |
| GET      | /api/dashboard/stats      | Totals + status counts               |
| GET      | /api/dashboard/resource-usage | 10-point CPU/RAM history         |

### POST /api/vps body
```json
{ "name": "my-server", "cpuCores": 4, "ramGb": 8, "storageGb": 100, "os": "Ubuntu 22.04", "location": "US-East", "ipAddress": "10.0.0.5" }
```

### POST /api/vps/:id/action body
```json
{ "action": "start" }
```
Valid actions: `start` | `stop` | `suspend` | `reboot`

---

## Database schema

Table: **`vps`**

| Column       | Type      | Notes                                |
|--------------|-----------|--------------------------------------|
| id           | serial    | Primary key, auto-increment          |
| name         | text      | Display name of the VPS              |
| status       | text      | `running` / `stopped` / `suspended`  |
| cpu_cores    | integer   | Number of vCPU cores                 |
| ram_gb       | real      | RAM in gigabytes                     |
| storage_gb   | real      | Disk storage in gigabytes            |
| ip_address   | text      | IP address string                    |
| os           | text      | OS name (e.g. "Ubuntu 22.04")        |
| location     | text      | Optional datacenter location         |
| cpu_usage    | real      | CPU % (0–100), updated on actions    |
| ram_usage    | real      | RAM % (0–100), updated on actions    |
| created_at   | timestamp | Auto-set on insert                   |

---

## How to make common changes

### Change the panel name
1. In `install.sh`, find `## FILE: frontend/index.html`
2. Change `<title>CPH Panel</title>` to your name
3. Find `## FILE: frontend/src/pages/Dashboard.tsx`
4. Change the `CPH Panel` text in the navbar section

### Change colors
All colors are defined in one place in `Dashboard.tsx`:
```typescript
const CLR = { blue: "#2563eb", green: "#22c55e", grey: "#52525b", amber: "#f59e0b", cpu: "#3b82f6" };
```
Edit these hex values and all charts, badges, and status indicators update automatically.

### Add a new database column
1. Find `## FILE: backend/src/schema.ts`
2. Add the column using Drizzle syntax:
   ```typescript
   myNewField: text("my_new_field").default("value"),
   ```
3. Re-run `install.sh` — the migration runs automatically via `drizzle-kit push`

### Add a new API endpoint
1. Find `## FILE: backend/src/routes/vps.ts` (or create a new route file)
2. Add your route: `r.get("/vps/search", async (req, res) => { ... })`
3. If new file: register it in `## FILE: backend/src/routes/index.ts`

### Add a new npm package to the frontend
1. Find `## FILE: frontend/package.json`
2. Add to `"dependencies"`: `"my-package": "^1.0.0"`
3. Import it in `Dashboard.tsx` and use it

### Add a new npm package to the backend
1. Find `## FILE: backend/package.json`
2. Add to `"dependencies"`: `"my-package": "^1.0.0"`
3. Import it in the relevant route file

### Add a new page (e.g., VPS List page)
1. Find `## FILE: frontend/src/pages/Dashboard.tsx`
2. After that heredoc block, add a new one:
   ```bash
   write_file "frontend/src/pages/VpsList.tsx" << 'HEREDOC'
   export default function VpsList() { return <div>...</div>; }
   HEREDOC
   ```
3. Find `## FILE: frontend/src/App.tsx`
4. Add routing (install `wouter` in package.json first):
   ```typescript
   import { Switch, Route } from "wouter";
   import VpsList from "./pages/VpsList";
   export default function App() {
     return <Switch>
       <Route path="/" component={Dashboard} />
       <Route path="/vps" component={VpsList} />
     </Switch>;
   }
   ```

### Change the port numbers
At the top of `install.sh`, edit:
```bash
API_PORT="${API_PORT:-5000}"    # backend API port
PANEL_PORT="${PANEL_PORT:-80}"  # nginx/web port
```

---

## How the dashboard fetches data

The `Dashboard.tsx` uses plain `fetch()` — no external state library:

```typescript
useEffect(() => {
  Promise.all([
    fetch("/api/dashboard/stats").then(r => r.json()),
    fetch("/api/dashboard/resource-usage").then(r => r.json()),
  ]).then(([stats, usage]) => { ... });
}, []);
```

To add a new data source, add another `fetch()` call to the `Promise.all` array
and add a new `useState` for it.

---

## Deployment after editing

After editing `install.sh`:

```bash
# On the target VPS as root:
bash /path/to/install.sh

# Or pull latest from GitHub and re-install:
bash <(curl -s https://raw.githubusercontent.com/Amir565-ux/cph-panel/main/scripts/install.sh)
```

The script is idempotent — re-running it overwrites files, re-runs migrations (safe),
rebuilds both apps, and restarts PM2.

---

## Useful commands on the VPS after install

```bash
pm2 status                    # see if API is running
pm2 logs cph-panel-api        # live API logs
pm2 restart cph-panel-api     # restart API after manual code edits
pm2 stop cph-panel-api        # stop API

nginx -t                      # test nginx config
systemctl reload nginx        # reload nginx

psql -U cph_panel cph_panel   # connect to DB as panel user
\dt                           # list tables
SELECT * FROM vps;            # see all VPS rows
```

---

## Project structure on the VPS after install

```
/opt/cph-panel/
├── backend/
│   ├── src/
│   │   ├── schema.ts          ← DB table definition
│   │   ├── db.ts              ← DB connection
│   │   ├── app.ts             ← Express setup
│   │   ├── index.ts           ← Server entry
│   │   └── routes/
│   │       ├── health.ts
│   │       ├── vps.ts         ← VPS CRUD
│   │       ├── dashboard.ts   ← Stats + usage
│   │       └── index.ts       ← Route registry
│   ├── dist/                  ← Compiled JS (auto-generated)
│   ├── package.json
│   ├── tsconfig.json
│   └── drizzle.config.ts
├── frontend/
│   ├── src/
│   │   ├── pages/
│   │   │   └── Dashboard.tsx  ← Main UI
│   │   ├── App.tsx
│   │   ├── main.tsx
│   │   └── index.css
│   ├── dist/                  ← Built static files (served by nginx)
│   ├── index.html
│   ├── package.json
│   └── vite.config.ts
└── ecosystem.config.cjs       ← PM2 config
```
