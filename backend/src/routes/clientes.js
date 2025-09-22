import { Router } from 'express';
import authJWT from '../middleware/authJWT.js';

const r = Router();
r.get('/', authJWT, async (req, res) => {
  const { rut } = req.query;
  if (!rut) return res.status(400).json({ error: 'Falta rut' });
  const db = req.app.get('db');
  const cli = await db.collection('clientes').findOne({ rut });
  if (!cli) return res.status(404).json({ error: 'Cliente no encontrado' });
  await db.collection('historialConsultas').insertOne({
    usuarioId: req.user.uid,
    clienteId: cli._id,
    fechaConsulta: new Date(),
    tipo: 'consulta',
    detalle: 'consulta por RUT'
  });
  res.json(cli);
});
export default r;
