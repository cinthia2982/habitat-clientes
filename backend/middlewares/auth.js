const jwt = require('jsonwebtoken');

function authRequired(req, res, next) {
  const h = req.headers.authorization || '';
  const [scheme, token] = h.split(' ');
  if (scheme !== 'Bearer' || !token) {
    return res.status(401).json({ ok:false, error:'Token ausente' });
  }
  try {
    const payload = jwt.verify(token, process.env.JWT_SECRET);
    req.user = payload;
    return next();
  } catch (e) {
    return res.status(401).json({ ok:false, error:'Token inválido' });
  }
}

module.exports = { authRequired };
