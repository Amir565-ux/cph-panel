#!/bin/bash

# =====================================================================
# CPH-Panel Installer Script
# =====================================================================

set -e

# Colors for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
WHITE='\033[1;37m'
DIM='\033[2;37m'
NC='\033[0m' # No Color

echo -e "${RED}"
echo "  ██████╗ ██████╗ ███████╗ █████╗ ██╗  ████████╗██╗███╗   ███╗███████╗"
echo "  ██╔════╝██╔═══██╗██╔════╝██╔══██╗██║ ╚══██╔══╝██║████╗ ████║██╔════╝"
echo "  ██║     ██║   ██║█████╗  ███████║██║    ██║   ██║██╔████╔██║█████╗  "
echo "  ██║     ██║   ██║██╔══╝  ██╔══██║██║    ██║   ██║██║╚██╔╝██║██╔══╝  "
echo "  ╚██████╗╚██████╔╝███████╗██║  ██║██║    ██║   ██║██║ ╚═╝ ██║███████╗"
echo "   ╚═════╝ ╚═════╝ ╚══════╝╚═╝  ╚═╝╚═╝    ╚═╝   ╚═╝╚═╝     ╚═╝╚══════╝"
echo -e "${NC}"
echo -e "${DIM}  VPS Hosting Management Panel Installer${NC}"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}[ERROR] Please run as root (sudo ./install.sh)${NC}"
    exit 1
fi

# Default values
INSTALL_DIR="/var/www/cph-panel"
DOMAIN=""
SETUP_SSL="n"
PORT=80

# Parse arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --domain) DOMAIN="$2"; shift ;;
        --dir) INSTALL_DIR="$2"; shift ;;
        --ssl) SETUP_SSL="y" ;;
        --port) PORT="$2"; shift ;;
        -h|--help)
            echo "Usage: sudo ./install.sh [options]"
            echo ""
            echo "Options:"
            echo "  --domain <domain>   Set domain for reverse proxy (e.g. panel.example.com)"
            echo "  --dir <path>        Installation directory (default: /var/www/cph-panel)"
            echo "  --ssl               Setup SSL with Let's Encrypt (requires --domain)"
            echo "  --port <port>       Port for standalone mode (default: 80)"
            echo "  -h, --help          Show this help message"
            echo ""
            echo "Examples:"
            echo "  sudo ./install.sh"
            echo "  sudo ./install.sh --domain panel.example.com --ssl"
            echo "  sudo ./install.sh --dir /opt/cph-panel --port 8080"
            exit 0
            ;;
        *) echo -e "${RED}[ERROR] Unknown option: $1${NC}"; exit 1 ;;
    esac
    shift
done

# -----------------------------------------------------------------
# Step 1: Detect OS and install dependencies
# -----------------------------------------------------------------
echo -e "${YELLOW}[1/6] Detecting OS and installing dependencies...${NC}"

if command -v apt-get &> /dev/null; then
    # Debian / Ubuntu
    PKG_MANAGER="apt-get"
    $PKG_MANAGER update -y
    $PKG_MANAGER install -y nginx curl wget unzip
elif command -v dnf &> /dev/null; then
    # RHEL / Fedora / CentOS Stream
    PKG_MANAGER="dnf"
    $PKG_MANAGER update -y
    $PKG_MANAGER install -y nginx curl wget unzip
elif command -v apk &> /dev/null; then
    # Alpine Linux
    PKG_MANAGER="apk"
    $PKG_MANAGER update
    $PKG_MANAGER add nginx curl wget unzip
else
    echo -e "${RED}[ERROR] Unsupported OS. Only Debian/Ubuntu, RHEL/Fedora, and Alpine are supported.${NC}"
    exit 1
fi

echo -e "${GREEN}  Dependencies installed.${NC}"

# -----------------------------------------------------------------
# Step 2: Create installation directory
# -----------------------------------------------------------------
echo -e "${YELLOW}[2/6] Setting up directory: ${INSTALL_DIR}${NC}"

mkdir -p "$INSTALL_DIR"

echo -e "${GREEN}  Directory created.${NC}"

# -----------------------------------------------------------------
# Step 3: Write the panel HTML file
# -----------------------------------------------------------------
echo -e "${YELLOW}[3/6] Generating panel files...${NC}"

cat > "$INSTALL_DIR/index.html" << 'CPANEL_HTML'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>CPH-Panel</title>
    <link href="https://fonts.googleapis.com/css2?family=Space+Grotesk:wght@300;400;500;600;700&family=JetBrains+Mono:wght@400;500;600&display=swap" rel="stylesheet">
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.0/css/all.min.css">
    <script src="https://cdn.tailwindcss.com"><\/script>
    <script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.0/dist/chart.umd.min.js"><\/script>
    <script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2"><\/script>
    <script>
        tailwind.config={theme:{extend:{fontFamily:{display:['Space Grotesk','sans-serif'],mono:['JetBrains Mono','monospace']}}}}
    <\/script>
    <style>
        :root{
            --bg:#000;--bg2:#060606;--card:#0d0d0d;--card-b:#1a1a1a;--card-h:#111;
            --bdr:#1a1a1a;--bdr2:#222;--fg:#fff;--muted:#888;--dim:#555;
            --acc:#dc2626;--acc-h:#b91c1c;--acc-s:rgba(220,38,38,.08);--acc-g:rgba(220,38,38,.2);
            --grn:#22c55e;--grn-s:rgba(34,197,94,.08);--grn-b:rgba(34,197,94,.2);
            --ylw:#eab308;--ylw-s:rgba(234,179,8,.08);--ylw-b:rgba(234,179,8,.2);
            --gry:#6b7280;--gry-s:rgba(107,114,128,.08);--gry-b:rgba(107,114,128,.2);
            --red:#dc2626;--red-s:rgba(220,38,38,.08);
            --org:#f97316;--org-s:rgba(249,115,22,.08);
        }
        *{margin:0;padding:0;box-sizing:border-box}
        body{font-family:'Space Grotesk',sans-serif;background:var(--bg);color:var(--fg);min-height:100vh;overflow-x:hidden}
        ::-webkit-scrollbar{width:5px}::-webkit-scrollbar-track{background:transparent}::-webkit-scrollbar-thumb{background:#222;border-radius:3px}
        .auth-page{display:none;min-height:100vh;align-items:center;justify-content:center;position:relative;overflow:hidden}
        .auth-page.active{display:flex}
        .auth-bg{position:absolute;inset:0;background-image:linear-gradient(rgba(220,38,38,.03) 1px,transparent 1px),linear-gradient(90deg,rgba(220,38,38,.03) 1px,transparent 1px);background-size:60px 60px;pointer-events:none}
        .auth-glow{position:absolute;width:400px;height:400px;border-radius:50%;background:radial-gradient(circle,rgba(220,38,38,.1),transparent 70%);pointer-events:none}
        .auth-glow.g1{top:-100px;right:-100px}.auth-glow.g2{bottom:-150px;left:-100px}
        .auth-card{background:var(--card);border:1px solid var(--card-b);border-radius:16px;padding:40px;width:100%;max-width:420px;position:relative;z-index:2}
        .auth-logo{display:flex;align-items:center;gap:10px;margin-bottom:32px;justify-content:center}
        .auth-logo-icon{width:40px;height:40px;background:var(--acc);border-radius:10px;display:flex;align-items:center;justify-content:center;font-weight:700;font-size:14px;color:#fff}
        .auth-logo-text{font-weight:700;font-size:18px;letter-spacing:-.3px}.auth-logo-text span{color:var(--acc)}
        .auth-title{font-size:22px;font-weight:600;text-align:center;margin-bottom:6px}
        .auth-sub{font-size:13px;color:var(--muted);text-align:center;margin-bottom:28px}
        .fg{margin-bottom:18px}
        .fl{display:block;font-size:12px;font-weight:500;color:var(--muted);margin-bottom:6px;text-transform:uppercase;letter-spacing:.5px}
        .fi{width:100%;padding:11px 14px;background:var(--bg);border:1px solid var(--bdr);border-radius:8px;color:var(--fg);font-family:'Space Grotesk',sans-serif;font-size:14px;outline:none;transition:border-color .15s}
        .fi:focus{border-color:var(--acc)}.fi::placeholder{color:var(--dim)}
        .fe{font-size:11px;color:var(--red);margin-top:4px;display:none}.fe.show{display:block}
        .btn-r{width:100%;padding:12px;background:var(--acc);color:#fff;border:none;border-radius:8px;font-family:'Space Grotesk',sans-serif;font-size:14px;font-weight:500;cursor:pointer;transition:all .15s;display:flex;align-items:center;justify-content:center;gap:8px}
        .btn-r:hover{background:var(--acc-h);box-shadow:0 0 24px var(--acc-g)}
        .btn-r:active{transform:scale(.98)}.btn-r:disabled{opacity:.5;cursor:not-allowed;transform:none;box-shadow:none}
        .auth-footer{text-align:center;margin-top:20px;font-size:13px;color:var(--dim)}
        .auth-footer a{color:var(--acc);text-decoration:none;cursor:pointer;font-weight:500}.auth-footer a:hover{text-decoration:underline}
        .fr{display:grid;grid-template-columns:1fr 1fr;gap:12px}
        .panel-page{display:none;min-height:100vh}.panel-page.active{display:block}
        .sidebar{position:fixed;left:0;top:0;width:250px;height:100vh;background:var(--bg2);border-right:1px solid var(--bdr);display:flex;flex-direction:column;z-index:100;transition:transform .3s}
        .sidebar-logo{padding:20px;border-bottom:1px solid var(--bdr);display:flex;align-items:center;gap:10px}
        .sli{width:34px;height:34px;background:var(--acc);border-radius:8px;display:flex;align-items:center;justify-content:center;font-weight:700;font-size:13px;color:#fff;flex-shrink:0}
        .slt{font-weight:700;font-size:15px;letter-spacing:-.2px}.slt span{color:var(--acc)}
        .sidebar-nav{flex:1;padding:12px;overflow-y:auto}
        .ns{font-size:10px;font-weight:600;text-transform:uppercase;letter-spacing:1.1px;color:var(--dim);padding:10px 12px 6px}
        .ni{display:flex;align-items:center;gap:10px;padding:9px 12px;border-radius:8px;font-size:13px;color:var(--muted);cursor:pointer;transition:all .15s;text-decoration:none;margin-bottom:1px;position:relative}
        .ni:hover{background:var(--acc-s);color:var(--fg)}
        .ni.active{background:var(--acc-s);color:var(--acc);font-weight:500}
        .ni.active::before{content:'';position:absolute;left:-12px;top:50%;transform:translateY(-50%);width:3px;height:18px;background:var(--acc);border-radius:0 3px 3px 0}
        .ni i{width:18px;text-align:center;font-size:12px}
        .nb{margin-left:auto;background:var(--acc);color:#fff;font-size:10px;font-weight:600;padding:2px 7px;border-radius:10px;font-family:'JetBrains Mono',monospace}
        .sidebar-foot{padding:14px;border-top:1px solid var(--bdr)}
        .su{display:flex;align-items:center;gap:10px;padding:8px;border-radius:8px;cursor:pointer;transition:background .15s}
        .su:hover{background:var(--card)}
        .sua{width:32px;height:32px;border-radius:8px;background:var(--acc-s);border:1px solid var(--bdr2);display:flex;align-items:center;justify-content:center;font-size:11px;font-weight:600;color:var(--acc)}
        .sun{font-size:13px;font-weight:500}.sur{font-size:11px;color:var(--dim)}
        .main{margin-left:250px;min-height:100vh}
        .topbar{position:sticky;top:0;z-index:50;background:rgba(0,0,0,.85);backdrop-filter:blur(12px);border-bottom:1px solid var(--bdr);padding:0 28px;height:54px;display:flex;align-items:center;justify-content:space-between}
        .bc{display:flex;align-items:center;gap:8px;font-size:13px}
        .bcs{color:var(--dim);font-size:10px}.bcc{color:var(--fg);font-weight:500}.bcl{color:var(--dim);text-decoration:none;cursor:pointer}.bcl:hover{color:var(--fg)}
        .ta{display:flex;align-items:center;gap:8px}
        .tb{width:34px;height:34px;border-radius:8px;border:1px solid var(--bdr);background:0;color:var(--muted);display:flex;align-items:center;justify-content:center;cursor:pointer;transition:all .15s;font-size:12px;position:relative}
        .tb:hover{background:var(--card);color:var(--fg);border-color:var(--bdr2)}
        .tbd{position:absolute;top:7px;right:7px;width:5px;height:5px;background:var(--acc);border-radius:50%}
        .bsm{padding:8px 16px;background:var(--acc);color:#fff;border:none;border-radius:8px;font-family:'Space Grotesk',sans-serif;font-size:12.5px;font-weight:500;cursor:pointer;transition:all .15s;display:inline-flex;align-items:center;gap:6px}
        .bsm:hover{background:var(--acc-h);box-shadow:0 0 20px var(--acc-g)}.bsm:active{transform:scale(.97)}
        .bgst{padding:7px 14px;background:0;color:var(--muted);border:1px solid var(--bdr);border-radius:8px;font-family:'Space Grotesk',sans-serif;font-size:12px;cursor:pointer;transition:all .15s;display:inline-flex;align-items:center;gap:5px}
        .bgst:hover{border-color:var(--bdr2);color:var(--fg);background:var(--card)}
        .bdn{padding:7px 14px;background:var(--red-s);color:var(--red);border:1px solid rgba(220,38,38,.2);border-radius:8px;font-family:'Space Grotesk',sans-serif;font-size:12px;cursor:pointer;transition:all .15s;display:inline-flex;align-items:center;gap:5px}
        .bdn:hover{background:rgba(220,38,38,.15)}
        .page{padding:24px 28px 48px;max-width:1400px}
        .welcome h1{font-size:21px;font-weight:600;letter-spacing:-.3px;margin-bottom:3px}.welcome h1 .un{color:var(--acc)}.welcome p{font-size:13px;color:var(--muted)}
        .sr{display:grid;grid-template-columns:repeat(4,1fr);gap:14px;margin:22px 0 18px}
        .sc{background:var(--card);border:1px solid var(--card-b);border-radius:12px;padding:18px;transition:all .2s;position:relative;overflow:hidden}
        .sc::after{content:'';position:absolute;top:0;left:0;right:0;height:1px;background:linear-gradient(90deg,transparent,var(--acc-g),transparent);opacity:0;transition:opacity .3s}
        .sc:hover{border-color:var(--bdr2);background:var(--card-h)}.sc:hover::after{opacity:1}
        .sct{display:flex;align-items:center;justify-content:space-between;margin-bottom:12px}
        .scl{font-size:11px;font-weight:500;color:var(--muted);text-transform:uppercase;letter-spacing:.6px}
        .sci{width:32px;height:32px;border-radius:8px;display:flex;align-items:center;justify-content:center;font-size:12px}
        .scv{font-family:'JetBrains Mono',monospace;font-size:26px;font-weight:600;letter-spacing:-1px;line-height:1;margin-bottom:5px}
        .scv .u{font-size:14px;color:var(--muted);font-weight:400}
        .scs{font-size:11px;color:var(--dim);font-family:'JetBrains Mono',monospace}.scs .hl{color:var(--grn)}
        .br{display:grid;grid-template-columns:1fr 1fr;gap:14px;margin-bottom:18px}
        .bcc{background:var(--card);border:1px solid var(--card-b);border-radius:12px;padding:22px;transition:border-color .2s}
        .bcc:hover{border-color:var(--bdr2)}
        .bch{display:flex;align-items:center;justify-content:space-between;margin-bottom:20px}
        .bct{font-size:14px;font-weight:600;letter-spacing:-.2px}
        .bclnk{font-size:12px;color:var(--acc);cursor:pointer;display:flex;align-items:center;gap:4px}.bclnk:hover{opacity:.8}
        .vsi{display:flex;align-items:center;gap:12px;padding:12px 14px;border-radius:10px;border:1px solid var(--bdr);margin-bottom:10px;transition:background .15s}
        .vsi:hover{background:rgba(255,255,255,.02)}
        .vsd{width:9px;height:9px;border-radius:50%;flex-shrink:0}
        .vsd.green{background:var(--grn);box-shadow:0 0 8px rgba(34,197,94,.4);animation:pg 2s ease-in-out infinite}
        .vsd.yellow{background:var(--ylw);box-shadow:0 0 8px rgba(234,179,8,.4)}
        .vsd.grey{background:var(--gry);box-shadow:0 0 8px rgba(107,114,128,.3)}
        .vsif{flex:1}.vsin{font-size:13px;font-weight:500;margin-bottom:1px}.vsid{font-size:11px;color:var(--dim)}
        .vsic{font-family:'JetBrains Mono',monospace;font-size:20px;font-weight:600}
        .vsic.green{color:var(--grn)}.vsic.yellow{color:var(--ylw)}.vsic.grey{color:var(--gry)}
        .vpb{display:flex;height:5px;border-radius:3px;overflow:hidden;background:var(--bdr);margin-top:14px}
        .vpb div{height:100%;transition:width .6s}
        .vpb .bg{background:var(--grn)}.vpb .by{background:var(--ylw)}.vpb .brg{background:var(--gry)}
        .vpl{display:flex;gap:14px;margin-top:8px}
        .vli{display:flex;align-items:center;gap:5px;font-size:10px;color:var(--dim)}
        .vld{width:5px;height:5px;border-radius:50%}
        .cw{position:relative;width:100%;height:200px}
        .csrs{display:grid;grid-template-columns:repeat(3,1fr);gap:10px;margin-top:16px}
        .csb{padding:10px 12px;background:rgba(255,255,255,.02);border:1px solid var(--bdr);border-radius:8px}
        .csl{font-size:10px;color:var(--dim);margin-bottom:3px}
        .csv{font-family:'JetBrains Mono',monospace;font-size:15px;font-weight:600}
        .csv.red{color:var(--acc)}.csv.green{color:var(--grn)}.csv.yellow{color:var(--ylw)}
        .vt{width:100%;border-collapse:collapse}
        .vt th{text-align:left;font-size:11px;font-weight:500;color:var(--dim);text-transform:uppercase;letter-spacing:.5px;padding:10px 14px;border-bottom:1px solid var(--bdr)}
        .vt td{padding:14px;border-bottom:1px solid var(--bdr);font-size:13px}
        .vt tr:hover td{background:rgba(255,255,255,.01)}
        .sp{display:inline-flex;align-items:center;gap:5px;padding:3px 10px;border-radius:20px;font-size:11px;font-weight:500}
        .sp.green{background:var(--grn-s);color:var(--grn);border:1px solid var(--grn-b)}
        .sp.yellow{background:var(--ylw-s);color:var(--ylw);border:1px solid var(--ylw-b)}
        .sp.grey{background:var(--gry-s);color:var(--gry);border:1px solid var(--gry-b)}
        .sp .spd{width:5px;height:5px;border-radius:50%;background:currentColor}
        .vac{display:flex;gap:6px}
        .vab{width:30px;height:30px;border-radius:6px;border:1px solid var(--bdr);background:0;color:var(--muted);display:flex;align-items:center;justify-content:center;cursor:pointer;transition:all .15s;font-size:11px}
        .vab:hover{background:var(--card);color:var(--fg);border-color:var(--bdr2)}
        .vab.dng:hover{color:var(--red);border-color:rgba(220,38,38,.3);background:var(--red-s)}
        .asg{display:grid;grid-template-columns:repeat(5,1fr);gap:14px;margin:22px 0 18px}
        .abr{display:grid;grid-template-columns:2fr 1fr;gap:14px;margin-bottom:18px}
        .ur{display:flex;align-items:center;gap:10px;padding:12px 0;border-bottom:1px solid var(--bdr)}.ur:last-child{border-bottom:none}
        .ura{width:32px;height:32px;border-radius:8px;background:var(--acc-s);display:flex;align-items:center;justify-content:center;font-size:11px;font-weight:600;color:var(--acc);flex-shrink:0}
        .urn{font-size:13px;font-weight:500}.ure{font-size:11px;color:var(--dim)}
        .urrol{margin-left:auto;font-size:11px;padding:2px 8px;border-radius:6px;font-weight:500}
        .urrol.owner{background:var(--red-s);color:var(--acc);border:1px solid rgba(220,38,38,.2)}
        .urrol.admin{background:var(--org-s);color:var(--org);border:1px solid rgba(249,115,22,.2)}
        .urrol.user{background:var(--gry-s);color:var(--gry);border:1px solid var(--gry-b)}
        .nc{padding:14px;border:1px solid var(--bdr);border-radius:10px;margin-bottom:10px;transition:background .15px}.nc:hover{background:rgba(255,255,255,.02)}
        .ncn{font-size:13px;font-weight:600;margin-bottom:8px;display:flex;align-items:center;gap:8px}
        .od{width:7px;height:7px;border-radius:50%;background:var(--grn);box-shadow:0 0 6px rgba(34,197,94,.5)}
        .nsg{display:grid;grid-template-columns:repeat(4,1fr);gap:8px}
        .nsb{text-align:center;padding:8px;background:rgba(255,255,255,.02);border-radius:6px}
        .nsl{font-size:10px;color:var(--dim);margin-bottom:2px}.nsv{font-family:'JetBrains Mono',monospace;font-size:13px;font-weight:600}
        .mo{display:none;position:fixed;inset:0;background:rgba(0,0,0,.7);z-index:200;align-items:center;justify-content:center;backdrop-filter:blur(4px)}
        .mo.active{display:flex}
        .md{background:var(--card);border:1px solid var(--bdr);border-radius:14px;padding:28px;width:100%;max-width:460px;animation:fiu .25s ease}
        .mdt{font-size:17px;font-weight:600;margin-bottom:20px}
        .mda{display:flex;gap:8px;justify-content:flex-end;margin-top:22px}
        .setup-page{display:none;min-height:100vh;align-items:center;justify-content:center;position:relative;overflow:hidden}
        .setup-page.active{display:flex}
        #toasts{position:fixed;bottom:20px;right:20px;z-index:9999;display:flex;flex-direction:column;gap:8px}
        .toast{background:#111;border:1px solid #222;color:#fff;padding:11px 18px;border-radius:10px;font-size:13px;font