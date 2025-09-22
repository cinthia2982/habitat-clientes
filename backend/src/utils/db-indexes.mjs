import 'dotenv/config';
import { MongoClient } from 'mongodb';

const client = new MongoClient(process.env.MONGODB_URI);
await client.connect();
const db = client.db();

await db.collection('clientes').createIndex({ rut: 1 }, { unique: true });
await db.collection('usuarios').createIndex({ correo: 1 }, { unique: true });

await client.close();
