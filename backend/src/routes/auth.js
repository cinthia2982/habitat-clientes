import { Router } from 'express';
import bcrypt from 'bcrypt';
import jwt from 'jsonwebtoken';

const r = Router();
r.post('/login', async (req, res) => {
  const { usuarioOEmail, password } = req.body;
  const db = req.app.get('db');
  const user = await db.collection('usuarios').findOne({
    $or: [{ correo: usuarioOEmail }, { nombreUsuario: usuarioOEmail }]
  });
  if (!user) return res.status(401).json({ error: 'Credenciales' });
  const ok = await bcrypt.compare(password, user.contraseña);
  if (!ok) return res.status(401).json({ error: 'Credenciales' });
  const token = jwt.sign({ uid: user._id, rolId: user.rolId }, process.env.JWT_SECRET, { expiresIn: '8h' });
  res.json({ token });
});
export default r;
