#!/usr/bin/env bash
set -euo pipefail

# ===============================
#  Script: setup_habitat.sh
#  Crea proyecto "habitat-clientes" (backend Express + MongoDB Atlas, 
frontend estático)
# ===============================

PROJECT_NAME="habitat-clientes"
BACKEND_DIR="$PROJECT_NAME/backend"
FRONTEND_DIR="$PROJECT_NAME/frontend"

echo "🚀 Inicializando proyecto $PROJECT_NAME ..."

# --- Preguntar variables si no existen ---
if [[ -z "${MONGODB_URI:-}" ]]; then
  read -rp "Ingrese su MONGODB_URI (Atlas): " MONGODB_URI
fi
if [[ -z "${JWT_SECRET:-}" ]]; then
  read -rp "Defina un JWT_SECRET (ej.: una frase larga): " JWT_SECRET
fi
if [[ -z "${CORS_ORIGIN:-}" ]]; then
  read -rp "CORS_ORIGIN (ej.: http://localhost:5500 o la URL de tu 
frontend): " CORS_ORIGIN
fi

# --- Crear estructura ---
mkdir -p 
"$BACKEND_DIR"/{src/{config,middleware,models,routes,utils},scripts} 
"$FRONTEND_DIR"/assets/{css,js}
( cd "$PROJECT_NAME" && git init >/dev/null 2>&1 || true )

# ===============================
# Backend: package.json + deps
# ===============================
pushd "$BACKEND_DIR" >/dev/null

npm init -y >/dev/null
npm i express cors mongoose dotenv bcrypt jsonwebtoken helmet morgan 
>/dev/null
npm i -D nodemon >/dev/null

# patch scripts
tmp_pkg=$(mktemp)
node - <<'EOS' "$PWD/package.json" > "$tmp_pkg"
const fs=require('fs');
const f=process.argv[1];
const pkg=JSON.parse(fs.readFileSync(f,'utf8'));
pkg.scripts={dev:"nodemon src/index.js", start:"node src/index.js", 
seed:"node scripts/seed.js"};
process.stdout.write(JSON.stringify(pkg,null,2));
EOS
mv "$tmp_pkg" package.json

# --- .env ---
cat > .env <<EOF
PORT=8080
MONGODB_URI="${MONGODB_URI}"
JWT_SECRET="${JWT_SECRET}"
CORS_ORIGIN="${CORS_ORIGIN}"
EOF

# --- Código backend ---
cat > src/config/db.js <<'EOF'
const mongoose = require('mongoose');
module.exports = async (uri) => {
  mongoose.set('strictQuery', true);
  await mongoose.connect(uri);
  console.log('✅ MongoDB conectado');
};
EOF

cat > src/middleware/auth.js <<'EOF'
const jwt = require('jsonwebtoken');
module.exports = (req,res,next)=>{
  const h = req.headers.authorization||'';
  const token = h.startsWith('Bearer ') ? h.slice(7) : null;
  if(!token) return res.status(401).json({error:'No token'});
  try{
    const payload = jwt.verify(token, process.env.JWT_SECRET);
    req.user = payload; next();
  }catch(e){ return res.status(401).json({error:'Invalid token'}); }
};
EOF

cat > src/middleware/roles.js <<'EOF'
module.exports = (...rolesPermitidos)=>(req,res,next)=>{
  if(!req.user?.rol || !rolesPermitidos.includes(req.user.rol))
    return res.status(403).json({error:'No autorizado'});
  next();
};
EOF

cat > src/models/Usuario.js <<'EOF'
const { Schema, model } = require('mongoose');
const UsuarioSchema = new Schema({
  nombreUsuario: { type:String, required:true, unique:true, trim:true },
  correo: { type:String, required:true, unique:true, lowercase:true, 
trim:true },
  passwordHash: { type:String, required:true },
  rol: { type:String, enum:['admin','ejecutivo'], default:'ejecutivo' }
},{timestamps:true});
UsuarioSchema.index({nombreUsuario:1},{unique:true});
UsuarioSchema.index({correo:1},{unique:true});
module.exports = model('Usuario', UsuarioSchema);
EOF

cat > src/models/Cliente.js <<'EOF'
const { Schema, model } = require('mongoose');
const ClienteSchema = new Schema({
  rut: { type:String, required:true, unique:true, trim:true },
  nombreCompleto: { type:String, required:true },
  afpActual: { type:String, required:true },
  correo: { type:String, trim:true, lowercase:true },
  telefono: { type:String, trim:true },
  rentaImponible: { type:Number, default:0 }
},{timestamps:true});
ClienteSchema.index({rut:1},{unique:true});
module.exports = model('Cliente', ClienteSchema);
EOF

cat > src/models/HistorialConsulta.js <<'EOF'
const { Schema, model, Types } = require('mongoose');
const HistSchema = new Schema({
  usuarioId: { type:Types.ObjectId, ref:'Usuario', required:true },
  clienteId: { type:Types.ObjectId, ref:'Cliente' },
  rutConsultado: { type:String, required:true },
  fechaConsulta: { type:Date, default:Date.now }
},{timestamps:true});
HistSchema.index({usuarioId:1, fechaConsulta:-1});
module.exports = model('HistorialConsulta', HistSchema);
EOF

cat > src/utils/validarRut.js <<'EOF'
module.exports = function validarRut(rut){
  return typeof rut === 'string' && rut.length >= 8; // mejora opcional
}
EOF

cat > src/routes/auth.routes.js <<'EOF'
const router = require('express').Router();
const jwt = require('jsonwebtoken');
const bcrypt = require('bcrypt');
const Usuario = require('../models/Usuario');

router.post('/login', async (req,res)=>{
  const { usuario, password } = req.body;
  const u = await Usuario.findOne({ 
$or:[{nombreUsuario:usuario},{correo:usuario}] });
  if(!u) return res.status(401).json({error:'Credenciales inválidas'});
  const ok = await bcrypt.compare(password, u.passwordHash);
  if(!ok) return res.status(401).json({error:'Credenciales inválidas'});
  const token = jwt.sign({ id:u._id, rol:u.rol, usuario:u.nombreUsuario }, 
process.env.JWT_SECRET, { expiresIn:'1h' });
  res.json({ token });
});

router.get('/me', (req,res)=> res.json({status:'ok'}));

module.exports = router;
EOF

cat > src/routes/clientes.routes.js <<'EOF'
const router = require('express').Router();
const auth = require('../middleware/auth');
const roles = require('../middleware/roles');
const Cliente = require('../models/Cliente');
const Hist = require('../models/HistorialConsulta');

router.get('/', auth, async (req,res)=>{
  const { rut } = req.query;
  if(!rut) return res.status(400).json({error:'Falta rut'});
  const cliente = await Cliente.findOne({rut});
  if(cliente) await Hist.create({usuarioId:req.user.id, 
clienteId:cliente._id, rutConsultado:rut});
  else await Hist.create({usuarioId:req.user.id, rutConsultado:rut});
  res.json({ cliente });
});

router.post('/', auth, roles('admin','ejecutivo'), async (req,res)=>{
  const c = await Cliente.create(req.body);
  res.status(201).json(c);
});

router.put('/:id', auth, roles('admin','ejecutivo'), async (req,res)=>{
  const c = await Cliente.findByIdAndUpdate(req.params.id, req.body, 
{new:true});
  res.json(c);
});

router.delete('/:id', auth, roles('admin'), async (req,res)=>{
  await Cliente.findByIdAndDelete(req.params.id);
  res.status(204).end();
});

module.exports = router;
EOF

cat > src/index.js <<'EOF'
require('dotenv').config();
const express = require('express');
const helmet = require('helmet');
const morgan = require('morgan');
const cors = require('cors');
const connectDB = require('./config/db');

const app = express();
app.use(helmet());
app.use(morgan('dev'));
app.use(cors({ origin: process.env.CORS_ORIGIN?.split(',')||true, 
credentials:true }));
app.use(express.json());

app.get('/health', (_req,res)=>res.json({ok:true}));

app.use('/auth', require('./routes/auth.routes'));
app.use('/clientes', require('./routes/clientes.routes'));

const start = async ()=>{
  await connectDB(process.env.MONGODB_URI);
  app.listen(process.env.PORT||8080, ()=> console.log(`🚀 API en 
:${process.env.PORT||8080}`));
};
start();
EOF

cat > scripts/seed.js <<'EOF'
require('dotenv').config();
const bcrypt = require('bcrypt');
const mongoose = require('mongoose');
const Usuario = require('../src/models/Usuario');
const Cliente = require('../src/models/Cliente');

(async()=>{
  await mongoose.connect(process.env.MONGODB_URI);
  console.log('Conectado');

  const pass = await bcrypt.hash('Admin123*', 10);
  await Usuario.deleteMany({});
  await Usuario.create([
    { nombreUsuario:'admin', correo:'admin@habitat.cl', passwordHash:pass, 
rol:'admin' },
    { nombreUsuario:'ejecutivo1', correo:'ejecutivo1@habitat.cl', 
passwordHash:await bcrypt.hash('Ejecutivo123*',10), rol:'ejecutivo' }
  ]);

  await Cliente.deleteMany({});
  await Cliente.create([
    { rut:'11.111.111-1', nombreCompleto:'Juan Pérez', afpActual:'Modelo', 
correo:'juan@mail.com', telefono:'+56911111111', rentaImponible:900000 },
    { rut:'22.222.222-2', nombreCompleto:'María López', 
afpActual:'Hábitat', correo:'maria@mail.com', telefono:'+56922222222', 
rentaImponible:1200000 }
  ]);

  console.log('Seed OK'); await mongoose.disconnect(); process.exit(0);
})().catch(e=>{console.error(e);process.exit(1);});
EOF

# .gitignore
cat > .gitignore <<'EOF'
node_modules
.env
npm-debug.log
EOF

echo "🌱 Ejecutando seed inicial..."
npm run seed

popd >/dev/null

# ===============================
# Frontend: archivos básicos
# ===============================
pushd "$FRONTEND_DIR" >/dev/null

cat > index.html <<'EOF'
<!doctype html><html lang="es"><head>
<meta charset="utf-8"><meta name="viewport" 
content="width=device-width,initial-scale=1">
<title>Login - Hábitat</title><link rel="stylesheet" 
href="assets/css/styles.css">
</head><body>
<main class="container">
  <h1>Ingreso Ejecutivos</h1>
  <form id="frmLogin">
    <input id="usuario" placeholder="Usuario o correo" required>
    <input id="password" type="password" placeholder="Contraseña" 
required>
    <button>Ingresar</button>
  </form>
  <p id="msg"></p>
</main>
<script src="assets/js/api.js"></script>
<script src="assets/js/auth.js"></script>
</body></html>
EOF

cat > cliente.html <<'EOF'
<!doctype html><html lang="es"><head>
<meta charset="utf-8"><meta name="viewport" 
content="width=device-width,initial-scale=1">
<title>Consulta Cliente</title><link rel="stylesheet" 
href="assets/css/styles.css">
</head><body>
<main class="container">
  <h1>Consulta por RUT</h1>
  <input id="rut" placeholder="11.111.111-1">
  <button id="btnBuscar">Buscar</button>
  <pre id="out"></pre>
</main>
<script src="assets/js/api.js"></script>
<script src="assets/js/clientes.js"></script>
</body></html>
EOF

cat > assets/css/styles.css <<'EOF'
*{box-sizing:border-box}body{font-family:system-ui,Arial;margin:0;background:#f6f7f8}
.container{max-width:520px;margin:40px 
auto;padding:24px;background:#fff;border-radius:16px;box-shadow:0 4px 16px 
rgba(0,0,0,.08)}
input,button{width:100%;padding:12px;margin:8px 
0;border-radius:10px;border:1px solid #ddd}
button{cursor:pointer}
pre{background:#111;color:#0f0;padding:12px;border-radius:12px;overflow:auto}
EOF

cat > assets/js/api.js <<'EOF'
const baseURL = (typeof window !== 'undefined' && 
window.location.hostname==='localhost')
  ? 'http://localhost:8080'
  : 'https://TU-BACKEND-PUBLICO';

async function api(path, {method='GET', body, auth=true}={}){
  const headers = {'Content-Type':'application/json'};
  const token = localStorage.getItem('token');
  if(auth && token) headers['Authorization'] = 'Bearer '+token;
  const res = await fetch(baseURL+path, {method, headers, body: 
body?JSON.stringify(body):undefined});
  if(!res.ok) throw new Error((await res.json()).error||res.statusText);
  return res.json();
}
EOF

cat > assets/js/auth.js <<'EOF'
const frm = document.getElementById('frmLogin');
const msg = document.getElementById('msg');
frm?.addEventListener('submit', async (e)=>{
  e.preventDefault();
  msg.textContent='Autenticando...';
  try{
    const usuario = document.getElementById('usuario').value.trim();
    const password = document.getElementById('password').value.trim();
    const { token } = await api('/auth/login', {method:'POST', 
body:{usuario,password}, auth:false});
    localStorage.setItem('token', token);
    window.location.href = 'cliente.html';
  }catch(err){ msg.textContent=err.message; }
});
EOF

cat > assets/js/clientes.js <<'EOF'
const out = document.getElementById('out');
document.getElementById('btnBuscar')?.addEventListener('click', async 
()=>{
  const rut = document.getElementById('rut').value.trim();
  out.textContent='Buscando...';
  try{
    const data = await api('/clientes?rut='+encodeURIComponent(rut));
    out.textContent = JSON.stringify(data, null, 2);
  }catch(err){ out.textContent = 'Error: '+err.message; }
});
EOF

cat > .gitignore <<'EOF'
.vercel
.DS_Store
EOF

popd >/dev/null

cat <<'EOT'

✅ Proyecto creado correctamente.

Pasos para iniciar:

1) Backend (terminal 1):
   cd habitat-clientes/backend
   npm run dev
   # -> http://localhost:8080/health

2) Frontend (terminal 2):
   cd habitat-clientes/frontend
   python3 -m http.server 5500
   # Abre: http://localhost:5500/index.html
   # Login: usuario=admin  contraseña=Admin123*

Para producción:
- Backend en Render (PORT, MONGODB_URI, JWT_SECRET, CORS_ORIGIN)
- Frontend en Vercel/Netlify
- Actualiza CORS_ORIGIN en backend y baseURL en frontend

¡Éxitos! 🟢
EOT





app.use('/auth', require('./routes/auth.me.routes'));
