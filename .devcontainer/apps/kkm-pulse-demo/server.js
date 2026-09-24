const express = require('express');
const path = require('path');
const app = express();
const PORT = process.env.PORT || 3000;

// Serve static elements if needed
app.use(express.json());

// Main Dashboard route
app.get('/', (req, res) => {
    res.sendFile(path.join(__dirname, 'views/index.html'));
});

// Simulated KKM Clinic Queue API
app.get('/api/status', (req, res) => {
    res.json({
        hospital: "Hospital Kuala Lumpur (Demo)",
        status: "Normal Operations 🟢",
        activePatients: Math.floor(Math.random() * 50) + 120,
        averageWaitTimeMinutes: Math.floor(Math.random() * 15) + 10,
        staffMood: "Caffeinated & Ready ☕",
        timestamp: new Date().toISOString()
    });
});

// Chaos Engineering Endpoint: Trigger CPU spike to show off Dynatrace Davis AI
app.get('/api/trigger-anomaly', (req, res) => {
    const start = Date.now();
    // Heavy loop for 3 seconds to spike CPU
    while (Date.now() - start < 3000) {
        Math.random() * Math.random();
    }
    res.json({ message: "Anomaly injected! Check your Dynatrace Davis AI dashboard for the CPU spike alert." });
});

// Only listen if run directly (prevents port-in-use errors during testing)
if (require.main === module) {
    app.listen(PORT, () => {
        console.log(`KKM Pulse App running hot on port ${PORT} 🚀`);
    });
}

// Export app for Jest tests
module.exports = app;
