export const API = import.meta.env.VITE_API_BASE_URL;

export async function apiFetch(path, opts = {}) {
  const token = localStorage.getItem('token');
  const headers = { 'Content-Type': 'application/json', ...(opts.headers 
|| {}) };
  if (token) headers.Authorization = `Bearer ${token}`;
  const res = await fetch(`${API}${path}`, { ...opts, headers });
  if (!res.ok) throw new Error((await res.json()).error || 'Error en 
API');
  return res.json();
}


