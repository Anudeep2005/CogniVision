const express = require('express');
const router = express.Router();
const apiController = require('../controllers/apiController');

router.post('/register', apiController.registerUser);
router.post('/pair', apiController.pairUsers);
router.post('/location', apiController.saveLocation);
router.post('/location/update', apiController.saveLocation); // Alias
router.post('/alert', apiController.triggerAlert);
router.post('/sos/trigger', apiController.triggerAlert); // Alias

module.exports = router;
