const router = require('express').Router();
const { authRequired } = require('../middlewares/auth');

router.get('/me', authRequired, async (req, res) => {
  const { uid, rolId } = req.user || {};
  return res.json({ ok:true, uid, rolId });
});

module.exports = router;
