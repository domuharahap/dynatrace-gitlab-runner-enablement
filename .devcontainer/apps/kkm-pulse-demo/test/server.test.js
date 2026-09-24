const request = require('supertest');
const app = require('../server');

describe('KKM Health Tech Pulse API Tests', () => {
    
    it('should return the KKM status dashboard JSON successfully', async () => {
        const response = await request(app).get('/api/status');
        
        expect(response.statusCode).toBe(200);
        expect(response.body).toHaveProperty('hospital', 'Hospital Kuala Lumpur (Demo)');
        expect(response.body).toHaveProperty('activePatients');
        expect(response.body).toHaveProperty('staffMood', 'Caffeinated & Ready ☕');
    });

    it('should successfully trigger the anomaly generation endpoint', async () => {
        const response = await request(app).get('/api/trigger-anomaly');
        
        expect(response.statusCode).toBe(200);
        expect(response.body.message).toContain('Anomaly injected!');
    });

});