import 'dotenv/config';
import express from 'express';
import cors from 'cors';
import morgan from 'morgan';
import { MongoClient } from 'mongodb';
import authRouter from './routes/auth.js';
import clientesRouter from './routes/clientes.js';

const app = express();
app.use(express.json());
app.use(morgan('dev'));

const allowed = (process.env.CORS_ORIGINS || '').split(',');
app.use(cors({ origin: (origin, cb) => {
  if (!origin || allowed.includes(origin)) return cb(null, true);
  cb(new Error('Not allowed by CORS'));
}}));

const client = new MongoClient(process.env.MONGODB_URI);
await client.connect();
const db = client.db();
app.set('db', db);

app.use('/auth', authRouter);
app.use('/clientes', clientesRouter);

const port = process.env.PORT || 8080;
app.listen(port, () => console.log(`API on :${port}`));
