import 'dotenv/config';
import bcrypt from 'bcrypt';
import { MongoClient } from 'mongodb';

const client = new MongoClient(process.env.MONGODB_URI);
await client.connect();
const db = client.db();

let rol = await db.collection('roles').findOne({ nombreRol: 'Admin' });
if (!rol) {
  const r = await db.collection('roles').insertOne({ nombreRol: 'Admin', permisos: ['*'] });
  rol = { _id: r.insertedId };
}
const existe = await db.collection('usuarios').findOne({ correo: 'admin@demo.cl' });
if (!existe) {
  const hash = await bcrypt.hash('Admin123!', 10);
  await db.collection('usuarios').insertOne({ nombreUsuario: 'admin', correo: 'admin@demo.cl', contraseña: hash, rolId: rol._id });
  console.log('admin listo');
} else {
  console.log('admin existe');
}
await client.close();
