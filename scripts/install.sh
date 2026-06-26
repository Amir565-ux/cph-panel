#!/bin/bash

# cph-panel Auto Installer
echo "========================================"
echo "      Installing cph-panel              "
echo "========================================"

# Check if Node.js is installed
if ! command -v node &> /dev/null; then
    echo "Node.js is not installed. Please install Node.js v18+ first."
    exit 1
fi

# Create Vite React project
echo "Creating Vite React project..."
npm create vite@latest cph-panel -- --template react
cd cph-panel

# Install dependencies
echo "Installing dependencies..."
npm install
npm install @supabase/supabase-js recharts
npm install -D tailwindcss postcss autoprefixer

# Initialize Tailwind CSS
echo "Configuring Tailwind CSS..."
npx tailwindcss init -p

# Configure Tailwind config
cat << 'EOF' > tailwind.config.js
/** @type {import('tailwindcss').Config} */
export default {
  content: [
    "./index.html",
    "./src/**/*.{js,ts,jsx,tsx}",
  ],
  theme: {
    extend: {},
  },
  plugins: [],
}
EOF

# Configure Global CSS
cat << 'EOF' > src/index.css
@tailwind base;
@tailwind components;
@tailwind utilities;

body {
  background-color: #000000;
  color: #ffffff;
}
EOF

# Create directories
mkdir -p src/lib
mkdir -p src/components

# Create Supabase Client (Dynamic to read from localStorage first, then .env)
cat << 'EOF' > src/lib/supabaseClient.js
import { createClient } from '@supabase/supabase-js';

const getSupabaseConfig = () => {
  // Check if keys were saved from the Admin Backend UI
  const localStorageUrl = localStorage.getItem('cph_supabase_url');
  const localStorageKey = localStorage.getItem('cph_supabase_anon_key');
  
  return {
    url: localStorageUrl || import.meta.env.VITE_SUPABASE_URL,
    key: localStorageKey || import.meta.env.VITE_SUPABASE_ANON_KEY
  };
};

let { url, key } = getSupabaseConfig();

// Fallback to prevent crash if not configured yet
export const supabase = createClient(url || 'https://placeholder.supabase.co', key || 'placeholder-anon-key');
EOF

# Create .env file placeholder (optional now, as it can be set via UI)
cat << 'EOF' > .env
# You can set keys here, OR directly in the Admin Backend UI of the panel
VITE_SUPABASE_URL=
VITE_SUPABASE_ANON_KEY=
EOF

# 1. Create Auth Component
cat << 'EOF' > src/components/Auth.jsx
import { useState } from 'react';
import { supabase } from '../lib/supabaseClient';

export default function Auth() {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [username, setUsername] = useState('');
  const [isLogin, setIsLogin] = useState(true);

  const handleAuth = async (e) => {
    e.preventDefault();
    if (isLogin) {
      const { error } = await supabase.auth.signInWithPassword({ email, password });
      if (error) alert(error.message);
    } else {
      const { error } = await supabase.auth.signUp({ 
        email, 
        password, 
        options: { data: { username } } 
      });
      if (error) alert(error.message);
    }
  };

  return (
    <div className="min-h-screen bg-black flex items-center justify-center">
      <div className="bg-zinc-900 p-8 rounded-lg w-96 border border-zinc-800">
        <h2 className="text-white text-2xl mb-6 text-center font-normal">
          {isLogin ? 'Login to cph-panel' : 'Sign up for cph-panel'}
        </h2>
        <form onSubmit={handleAuth} className="space-y-4">
          {!isLogin && (
            <input
              type="text"
              placeholder="Username"
              value={username}
              onChange={(e) => setUsername(e.target.value)}
              className="w-full bg-black text-white border border-zinc-700 p-2 rounded focus:border-blue-500 outline-none"
              required
            />
          )}
          <input
            type="email"
            placeholder="Email"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            className="w-full bg-black text-white border border-zinc-700 p-2 rounded focus:border-blue-500 outline-none"
            required
          />
          <input
            type="password"
            placeholder="Password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            className="w-full bg-black text-white border border-zinc-700 p-2 rounded focus:border-blue-500 outline-none"
            required
          />
          <button
            type="submit"
            className="w-full bg-blue-600 hover:bg-blue-700 text-white p-2 rounded transition-colors"
          >
            {isLogin ? 'Login' : 'Sign Up'}
          </button>
        </form>
        <button
          onClick={() => setIsLogin(!isLogin)}
          className="text-blue-500 mt-4 text-sm w-full text-center hover:underline"
        >
          {isLogin ? 'Need an account? Sign up' : 'Already have an account? Login'}
        </button>
      </div>
    </div>
  );
}
EOF

# 2. Create User Dashboard Component
cat << 'EOF' > src/components/UserDashboard.jsx
import { LineChart, Line, XAxis, YAxis, ResponsiveContainer, Tooltip } from 'recharts';

export default function UserDashboard({ user, vpsData }) {
  const totalVps = vpsData.length;
  const totalCpu = vpsData.reduce((sum, vps) => sum + vps.cpu_cores, 0);
  const totalRam = vpsData.reduce((sum, vps) => sum + vps.ram_mb, 0);
  const totalStorage = vpsData.reduce((sum, vps) => sum + vps.storage_gb, 0);
  const cpuGraphData = [{name: '1m', cpu: 20}, {name: '2m', cpu: 45}, {name: '3m', cpu: 30}, {name: '4m', cpu: 60}];

  return (
    <div className="p-6 bg-black text-white min-h-screen">
      <h1 className="text-3xl font-normal mb-8">Welcome {user?.username}</h1>
      
      <div className="grid grid-cols-1 md:grid-cols-4 gap-4 mb-8">
        <div className="bg-zinc-900 p-4 rounded-lg border border-zinc-800">
          <p className="text-zinc-400 text-sm">Total VPS</p>
          <p className="text-2xl">{totalVps}</p>
        </div>
        <div className="bg-zinc-900 p-4 rounded-lg border border-zinc-800">
          <p className="text-zinc-400 text-sm">CPU Cores</p>
          <p className="text-2xl">{totalCpu}</p>
        </div>
        <div className="bg-zinc-900 p-4 rounded-lg border border-zinc-800">
          <p className="text-zinc-400 text-sm">Total RAM</p>
          <p className="text-2xl">{totalRam} MB</p>
        </div>
        <div className="bg-zinc-900 p-4 rounded-lg border border-zinc-800">
          <p className="text-zinc-400 text-sm">Storage</p>
          <p className="text-2xl">{totalStorage} GB</p>
        </div>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
        <div className="bg-zinc-900 p-6 rounded-lg border border-zinc-800">
          <h3 className="text-xl mb-4 font-normal">VPS Status Overview</h3>
          <div className="flex justify-around items-center mt-8">
            <div className="text-center">
              <div className="w-4 h-4 bg-green-500 rounded-full mx-auto mb-2"></div>
              <p>Running: {vpsData.filter(v => v.status === 'running').length}</p>
            </div>
            <div className="text-center">
              <div className="w-4 h-4 bg-gray-500 rounded-full mx-auto mb-2"></div>
              <p>Stopped: {vpsData.filter(v => v.status === 'stopped').length}</p>
            </div>
            <div className="text-center">
              <div className="w-4 h-4 bg-yellow-500 rounded-full mx-auto mb-2"></div>
              <p>Suspended: {vpsData.filter(v => v.status === 'suspended').length}</p>
            </div>
          </div>
        </div>

        <div className="bg-zinc-900 p-6 rounded-lg border border-zinc-800">
          <h3 className="text-xl mb-4 font-normal">Resource Usage (CPU)</h3>
          <ResponsiveContainer width="100%" height={150}>
            <LineChart data={cpuGraphData}>
              <XAxis dataKey="name" stroke="#666" />
              <YAxis stroke="#666" />
              <Tooltip contentStyle={{ backgroundColor: '#000', border: '1px solid #333' }} />
              <Line type="monotone" dataKey="cpu" stroke="#3b82f6" strokeWidth={2} />
            </LineChart>
          </ResponsiveContainer>
        </div>
      </div>
    </div>
  );
}
EOF

# 3. Create My VPS Component
cat << 'EOF' > src/components/MyVps.jsx
import { useState } from 'react';

export default function MyVps({ vps }) {
  const [activeTab, setActiveTab] = useState('overview');
  const [status, setStatus] = useState(vps.status);

  const handleAction = (action) => {
    if (action === 'start') setStatus('running');
    if (action === 'stop') setStatus('stopped');
    if (action === 'restart') setStatus('running');
  };

  return (
    <div className="p-6 bg-black text-white min-h-screen">
      <div className="bg-zinc-900 p-4 rounded-lg border border-zinc-800 flex justify-between items-center mb-6">
        <div>
          <h2 className="text-xl font-normal">{vps.vps_name}</h2>
          <p className="text-zinc-400 text-sm">ID: {vps.id} | Created: {new Date(vps.created_at).toLocaleDateString()}</p>
        </div>
        <div className="space-x-2">
          {status === 'running' ? (
            <button onClick={() => handleAction('stop')} className="bg-blue-600 hover:bg-blue-700 px-4 py-2 rounded">Stop</button>
          ) : (
            <button onClick={() => handleAction('start')} className="bg-blue-600 hover:bg-blue-700 px-4 py-2 rounded">Start</button>
          )}
          <button onClick={() => handleAction('restart')} className="bg-blue-600 hover:bg-blue-700 px-4 py-2 rounded">Restart</button>
          <button className="bg-blue-600 hover:bg-blue-700 px-4 py-2 rounded">Console</button>
        </div>
      </div>

      <div className="grid grid-cols-2 md:grid-cols-4 gap-4 mb-6">
        <div className="bg-zinc-900 p-4 rounded border border-zinc-800">
          <p className="text-zinc-400 text-sm">CPU Cores</p>
          <p className="text-xl">{vps.cpu_cores}</p>
        </div>
        <div className="bg-zinc-900 p-4 rounded border border-zinc-800">
          <p className="text-zinc-400 text-sm">RAM Usage</p>
          <p className="text-xl">{vps.ram_mb} MB</p>
        </div>
        <div className="bg-zinc-900 p-4 rounded border border-zinc-800">
          <p className="text-zinc-400 text-sm">Storage Usage</p>
          <p className="text-xl">{vps.storage_gb} GB</p>
        </div>
        <div className="bg-zinc-900 p-4 rounded border border-zinc-800">
          <p className="text-zinc-400 text-sm">Network IP</p>
          <p className="text-xl">{vps.ip_address}</p>
        </div>
      </div>

      <div className="border-b border-zinc-800 mb-4">
        <nav className="flex space-x-4">
          {['overview', 'performance', 'backup', 'settings'].map(tab => (
            <button
              key={tab}
              onClick={() => setActiveTab(tab)}
              className={`py-2 px-4 capitalize ${activeTab === tab ? 'text-blue-500 border-b-2 border-blue-500' : 'text-zinc-400 hover:text-white'}`}
            >
              {tab}
            </button>
          ))}
        </nav>
      </div>

      <div className="bg-zinc-900 p-4 rounded border border-zinc-800 min-h-[200px]">
        {activeTab === 'overview' && <p>VPS Overview Details...</p>}
        {activeTab === 'performance' && <p>Performance Graphs...</p>}
        {activeTab === 'backup' && <p>Backup Management...</p>}
        {activeTab === 'settings' && <p>VPS Settings...</p>}
      </div>
    </div>
  );
}
EOF

# 4. Create Port Forwarding Component
cat << 'EOF' > src/components/PortForwarding.jsx
import { useState } from 'react';
import { supabase } from '../lib/supabaseClient';

export default function PortForwarding({ vpsId }) {
  const [ports, setPorts] = useState([]);
  const [external, setExternal] = useState('');
  const [internal, setInternal] = useState('');

  const addPort = async (e) => {
    e.preventDefault();
    const { data, error } = await supabase
      .from('port_forwarding')
      .insert({ vps_id: vpsId, external_port: external, internal_port: internal })
      .select();
    
    if (!error) setPorts([...ports, data[0]]);
    setExternal(''); setInternal('');
  };

  return (
    <div className="p-6 bg-black text-white min-h-screen">
      <h2 className="text-2xl font-normal mb-6">Port Forwarding</h2>
      
      <form onSubmit={addPort} className="bg-zinc-900 p-4 rounded-lg border border-zinc-800 mb-6 flex space-x-4">
        <input 
          type="number" 
          placeholder="External Port" 
          value={external}
          onChange={(e) => setExternal(e.target.value)}
          className="bg-black border border-zinc-700 p-2 rounded flex-1 outline-none focus:border-blue-500"
          required
        />
        <input 
          type="number" 
          placeholder="Internal Port" 
          value={internal}
          onChange={(e) => setInternal(e.target.value)}
          className="bg-black border border-zinc-700 p-2 rounded flex-1 outline-none focus:border-blue-500"
          required
        />
        <button type="submit" className="bg-blue-600 hover:bg-blue-700 px-6 py-2 rounded">Forward Port</button>
      </form>

      <div className="bg-zinc-900 p-4 rounded-lg border border-zinc-800">
        <table className="w-full text-left">
          <thead className="border-b border-zinc-800">
            <tr>
              <th className="py-2">External Port</th>
              <th className="py-2">Internal Port</th>
              <th className="py-2">Action</th>
            </tr>
          </thead>
          <tbody>
            {ports.length === 0 ? (
              <tr><td colSpan="3" className="py-4 text-center text-zinc-500">No ports forwarded yet.</td></tr>
            ) : (
              ports.map((p, i) => (
                <tr key={i} className="border-b border-zinc-800">
                  <td className="py-2">{p.external_port}</td>
                  <td className="py-2">{p.internal_port}</td>
                  <td><button className="text-red-500 hover:underline">Delete</button></td>
                </tr>
              ))
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}
EOF

# 5. Create Admin Dashboard Component
cat << 'EOF' > src/components/AdminDashboard.jsx
export default function AdminDashboard({ stats, health }) {
  return (
    <div className="p-6 bg-black text-white min-h-screen">
      <h1 className="text-3xl font-normal mb-8">Admin Dashboard</h1>
      
      <div className="grid grid-cols-1 md:grid-cols-4 gap-4 mb-8">
        <div className="bg-zinc-900 p-4 rounded-lg border border-zinc-800">
          <p className="text-zinc-400 text-sm">Total Users</p>
          <p className="text-2xl">{stats.totalUsers}</p>
        </div>
        <div className="bg-zinc-900 p-4 rounded-lg border border-zinc-800">
          <p className="text-zinc-400 text-sm">Total VPS</p>
          <p className="text-2xl">{stats.totalVps}</p>
        </div>
        <div className="bg-zinc-900 p-4 rounded-lg border border-zinc-800">
          <p className="text-zinc-400 text-sm">Suspended VPS</p>
          <p className="text-2xl">{stats.suspendedVps}</p>
        </div>
        <div className="bg-zinc-900 p-4 rounded-lg border border-zinc-800">
          <p className="text-zinc-400 text-sm">Available Ports</p>
          <p className="text-2xl">{stats.availablePorts}/{stats.totalPorts}</p>
        </div>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
        <div className="bg-zinc-900 p-6 rounded-lg border border-zinc-800">
          <h3 className="text-xl mb-4 font-normal">System Health (Main Node)</h3>
          <div className="space-y-4">
            <div>
              <div className="flex justify-between mb-1"><span>CPU</span><span>{health.cpu}%</span></div>
              <div className="w-full bg-black rounded-full h-2.5">
                <div className="bg-blue-600 h-2.5 rounded-full" style={{width: `${health.cpu}%`}}></div>
              </div>
            </div>
            <div>
              <div className="flex justify-between mb-1"><span>RAM</span><span>{health.ram}%</span></div>
              <div className="w-full bg-black rounded-full h-2.5">
                <div className="bg-blue-600 h-2.5 rounded-full" style={{width: `${health.ram}%`}}></div>
              </div>
            </div>
            <div>
              <div className="flex justify-between mb-1"><span>Disk</span><span>{health.disk}%</span></div>
              <div className="w-full bg-black rounded-full h-2.5">
                <div className="bg-blue-600 h-2.5 rounded-full" style={{width: `${health.disk}%`}}></div>
              </div>
            </div>
          </div>
        </div>

        <div className="bg-zinc-900 p-6 rounded-lg border border-zinc-800">
          <h3 className="text-xl mb-4 font-normal">Quick Actions</h3>
          <div className="grid grid-cols-2 gap-4">
            <button className="bg-blue-600 hover:bg-blue-700 p-3 rounded">+ New VPS</button>
            <button className="bg-blue-600 hover:bg-blue-700 p-3 rounded">Manage Users</button>
            <button className="bg-blue-600 hover:bg-blue-700 p-3 rounded">Node Settings</button>
            <button className="bg-blue-600 hover:bg-blue-700 p-3 rounded">System Logs</button>
          </div>
        </div>
      </div>
    </div>
  );
}
EOF

# 6. Create Admin Backend Component (Saves keys to localStorage dynamically)
cat << 'EOF' > src/components/AdminBackend.jsx
import { useState } from 'react';

export default function AdminBackend() {
  const [projectUrl, setProjectUrl] = useState(localStorage.getItem('cph_supabase_url') || '');
  const [anonKey, setAnonKey] = useState(localStorage.getItem('cph_supabase_anon_key') || '');
  const [secretKey, setSecretKey] = useState(localStorage.getItem('cph_supabase_secret_key') || '');

  const saveConfig = (e) => {
    e.preventDefault();
    localStorage.setItem('cph_supabase_url', projectUrl);
    localStorage.setItem('cph_supabase_anon_key', anonKey);
    localStorage.setItem('cph_supabase_secret_key', secretKey);
    alert('Supabase configuration saved! Reloading application to apply new keys...');
    window.location.reload(); // Reload to re-initialize the Supabase client
  };

  return (
    <div className="p-6 bg-black text-white min-h-screen">
      <h2 className="text-2xl font-normal mb-6">Backend Configuration</h2>
      <form onSubmit={saveConfig} className="bg-zinc-900 p-6 rounded-lg border border-zinc-800 max-w-2xl space-y-4">
        <div>
          <label className="block text-zinc-400 mb-1">Supabase Project URL</label>
          <input 
            type="url" 
            value={projectUrl} 
            onChange={(e) => setProjectUrl(e.target.value)}
            className="w-full bg-black border border-zinc-700 p-2 rounded outline-none focus:border-blue-500"
            placeholder="https://xyz.supabase.co"
            required
          />
        </div>
        <div>
          <label className="block text-zinc-400 mb-1">Anon Key</label>
          <input 
            type="text" 
            value={anonKey} 
            onChange={(e) => setAnonKey(e.target.value)}
            className="w-full bg-black border border-zinc-700 p-2 rounded outline-none focus:border-blue-500"
            required
          />
        </div>
        <div>
          <label className="block text-zinc-400 mb-1">Secret Key (Service Role)</label>
          <input 
            type="password" 
            value={secretKey} 
            onChange={(e) => setSecretKey(e.target.value)}
            className="w-full bg-black border border-zinc-700 p-2 rounded outline-none focus:border-blue-500"
            required
          />
        </div>
        <button type="submit" className="bg-blue-600 hover:bg-blue-700 px-6 py-2 rounded">
          Connect & Save Configuration
        </button>
      </form>
    </div>
  );
}
EOF

# 7. Create Main App.jsx (Real Auth & Role-based Sidebar)
cat << 'EOF' > src/App.jsx
import { useState, useEffect } from 'react';
import { supabase } from './lib/supabaseClient';
import Auth from './components/Auth';
import UserDashboard from './components/UserDashboard';
import MyVps from './components/MyVps';
import PortForwarding from './components/PortForwarding';
import AdminDashboard from './components/AdminDashboard';
import AdminBackend from './components/AdminBackend';

export default function App() {
  const [session, setSession] = useState(null);
  const [profile, setProfile] = useState(null);
  const [view, setView] = useState('user_dashboard');

  useEffect(() => {
    // Get initial session
    supabase.auth.getSession().then(({ data: { session } }) => {
      setSession(session);
      if (session) fetchProfile(session.user.id);
    });

    // Listen for auth changes
    const { data: { subscription } } = supabase.auth.onAuthStateChange((_event, session) => {
      setSession(session);
      if (session) fetchProfile(session.user.id);
      else setProfile(null);
    });

    return () => subscription.unsubscribe();
  }, []);

  const fetchProfile = async (userId) => {
    const { data } = await supabase.from('profiles').select('*').eq('id', userId).single();
    setProfile(data);
  };

  // Show Auth screen if not logged in
  if (!session) return <Auth />;

  // Check if user is Admin or Owner
  const isAdmin = profile?.role === 'owner' || profile?.role === 'admin';

  return (
    <div className="flex min-h-screen bg-black text-white">
      {/* Sidebar */}
      <div className="w-64 bg-zinc-950 p-4 border-r border-zinc-800 hidden md:block">
        <h1 className="text-xl font-bold text-blue-500 mb-6">cph-panel</h1>
        <nav className="space-y-2">
          <button onClick={() => setView('user_dashboard')} className={`block w-full text-left p-2 rounded ${view === 'user_dashboard' ? 'bg-zinc-800' : 'hover:bg-zinc-900'}`}>Dashboard</button>
          <button onClick={() => setView('my_vps')} className={`block w-full text-left p-2 rounded ${view === 'my_vps' ? 'bg-zinc-800' : 'hover:bg-zinc-900'}`}>My VPS</button>
          <button onClick={() => setView('port_forwarding')} className={`block w-full text-left p-2 rounded ${view === 'port_forwarding' ? 'bg-zinc-800' : 'hover:bg-zinc-900'}`}>Port Forwarding</button>
          
          {isAdmin && (
            <>
              <div className="pt-4 mt-4 border-t border-zinc-800 text-zinc-500 text-xs uppercase">Administration</div>
              <button onClick={() => setView('admin_dashboard')} className={`block w-full text-left p-2 rounded ${view === 'admin_dashboard' ? 'bg-zinc-800' : 'hover:bg-zinc-900'}`}>Admin Dashboard</button>
              <button onClick={() => setView('admin_backend')} className={`block w-full text-left p-2 rounded ${view === 'admin_backend' ? 'bg-zinc-800' : 'hover:bg-zinc-900'}`}>Backend Settings</button>
            </>
          )}
          
          <div className="pt-4 mt-4 border-t border-zinc-800">
            <button onClick={() => supabase.auth.signOut()} className="block w-full text-left p-2 rounded text-red-500 hover:bg-zinc-900">Logout</button>
          </div>
        </nav>
      </div>
      
      {/* Main Content */}
      <div className="flex-1 overflow-auto">
        {view === 'user_dashboard' && <UserDashboard user={profile} vpsData={[{id:'1', vps_name:'Test VPS', cpu_cores:2, ram_mb:2048, storage_gb:50, status:'running', created_at: Date.now()}]} />}
        {view === 'my_vps' && <MyVps vps={{id:'1', vps_name:'Test VPS', cpu_cores:2, ram_mb:2048, storage_gb:50, ip_address:'192.168.1.1', status:'stopped', created_at: Date.now()}} />}
        {view === 'port_forwarding' && <PortForwarding vpsId="1" />}
        {view === 'admin_dashboard' && <AdminDashboard stats={{totalUsers: 1, totalVps: 1, suspendedVps: 0, availablePorts: 100, totalPorts: 100}} health={{cpu: 15, ram: 45, disk: 30}} />}
        {view === 'admin_backend' && <AdminBackend />}
      </div>
    </div>
  );
}
EOF

# Clean up default Vite files
rm -f src/App.css
rm -f src/assets/react.svg

# Update main.jsx to remove default App.css import
cat << 'EOF' > src/main.jsx
import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import App from './App.jsx'
import './index.css'

createRoot(document.getElementById('root')).render(
  <StrictMode>
    <App />
  </StrictMode>,
)
EOF

echo "========================================"
echo "Installation Complete!"
echo "========================================"
echo "To start the panel:"
echo "1. cd cph-panel"
echo "2. Run: npm run dev"
echo "3. Open http://localhost:5173"
echo "4. Click 'Sign Up' and create your first account."
echo "5. The FIRST account created automatically becomes the OWNER."
echo "6. The Administration section will appear in your sidebar."
echo "7. Go to Backend Settings to securely input your Supabase keys from the UI."
echo "========================================"