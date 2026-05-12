/**
 * CogniVision Backend — Auth Route Unit Tests
 * Tests registration validation and health endpoint without real DB/Firebase.
 */

const express = require('express');
const request = require('supertest');

// ── Mocks ──────────────────────────────────────────────────────────────────
jest.mock('../src/config/db', () => jest.fn());
jest.mock('../src/config/firebase', () => ({ initFirebase: jest.fn() }));
jest.mock('../src/models/User');
jest.mock('socket.io', () => {
  const mockOn = jest.fn();
  const mockServer = { on: mockOn };
  return { Server: jest.fn(() => mockServer) };
});

const User = require('../src/models/User');

// Build a minimal Express app (no real DB) for testing
function buildApp() {
  const app = express();
  app.use(express.json());
  app.get('/health', (req, res) => res.json({ status: 'ok' }));
  app.use('/api/auth', require('../src/routes/auth'));
  app.use((err, req, res, next) => {
    res.status(err.status || 500).json({ error: err.message || 'Internal Server Error' });
  });
  return app;
}

// ── Tests ──────────────────────────────────────────────────────────────────
describe('GET /health', () => {
  it('returns status ok', async () => {
    const app = buildApp();
    const res = await request(app).get('/health');
    expect(res.status).toBe(200);
    expect(res.body).toEqual({ status: 'ok' });
  });
});

describe('POST /api/auth/register', () => {
  beforeEach(() => jest.clearAllMocks());

  it('rejects an invalid role', async () => {
    const app = buildApp();
    const res = await request(app).post('/api/auth/register').send({
      firebaseUid: 'uid123',
      role: 'admin',           // invalid
      displayName: 'Test User',
      email: 'test@example.com',
    });
    expect(res.status).toBe(400);
    expect(res.body.error).toMatch(/Invalid role/i);
  });

  it('returns 409 when user already exists', async () => {
    User.findOne.mockResolvedValue({ firebaseUid: 'uid123' });
    const app = buildApp();
    const res = await request(app).post('/api/auth/register').send({
      firebaseUid: 'uid123',
      role: 'user',
      displayName: 'Existing User',
      email: 'existing@example.com',
    });
    expect(res.status).toBe(409);
    expect(res.body.error).toMatch(/already exists/i);
  });

  it('registers a new user successfully', async () => {
    User.findOne.mockResolvedValue(null);
    const mockUser = {
      firebaseUid: 'uid999',
      role: 'user',
      displayName: 'New User',
      email: 'new@example.com',
      save: jest.fn().mockResolvedValue(true),
      toJSON: () => ({ firebaseUid: 'uid999', role: 'user', displayName: 'New User', email: 'new@example.com' }),
    };
    User.mockImplementation(() => mockUser);

    const app = buildApp();
    const res = await request(app).post('/api/auth/register').send({
      firebaseUid: 'uid999',
      role: 'user',
      displayName: 'New User',
      email: 'new@example.com',
    });
    expect(res.status).toBe(201);
  });

  it('registers a guardian role successfully', async () => {
    User.findOne.mockResolvedValue(null);
    const mockGuardian = {
      firebaseUid: 'guardianUid',
      role: 'guardian',
      displayName: 'Guardian Person',
      email: 'guardian@example.com',
      save: jest.fn().mockResolvedValue(true),
    };
    User.mockImplementation(() => mockGuardian);

    const app = buildApp();
    const res = await request(app).post('/api/auth/register').send({
      firebaseUid: 'guardianUid',
      role: 'guardian',
      displayName: 'Guardian Person',
      email: 'guardian@example.com',
    });
    expect(res.status).toBe(201);
  });
});
