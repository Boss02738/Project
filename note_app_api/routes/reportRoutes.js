const express = require('express');
const router = express.Router();

const ctrl = require('../controllers/reportController');

router.post('/', ctrl.createReport);
router.get('/', ctrl.listReports);
router.post('/:id/resolve', ctrl.resolveReport);
router.get('/pending', ctrl.listPending);
router.post('/:id/decision', ctrl.decideReport);

module.exports = router;
