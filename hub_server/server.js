require('dotenv').config();
const express  = require('express');
const crypto   = require('crypto');
const path     = require('path');
const Database = require('better-sqlite3');

const SECRET            = process.env.HUB_SECRET || 'noita_mp_hub_secret_change_this';
const PORT              = process.env.PORT || 3000;
const DB_PATH           = process.env.DB_PATH || path.join(__dirname, 'hubs.db');
const HEARTBEAT_TIMEOUT = parseInt(process.env.HEARTBEAT_TIMEOUT || '45000', 10);
const HUB_EXPIRY_DAYS   = parseInt(process.env.HUB_EXPIRY_DAYS || '7', 10);
const FEED_LIMIT        = 200;

const db = new Database(DB_PATH);
db.pragma('journal_mode = WAL');
db.pragma('foreign_keys = ON');

db.exec(`
    CREATE TABLE IF NOT EXISTS hubs (
        id              TEXT PRIMARY KEY,
        name            TEXT NOT NULL,
        owner_steam_id  TEXT NOT NULL,
        invite_code     TEXT NOT NULL UNIQUE,
        only_mods_start INTEGER NOT NULL DEFAULT 0,
        last_activity   INTEGER NOT NULL DEFAULT 0,
        created_at      INTEGER NOT NULL
    );

    CREATE TABLE IF NOT EXISTS moderators (
        hub_id    TEXT NOT NULL REFERENCES hubs(id) ON DELETE CASCADE,
        steam_id  TEXT NOT NULL,
        PRIMARY KEY (hub_id, steam_id)
    );

    CREATE TABLE IF NOT EXISTS lobbies (
        token_id        TEXT PRIMARY KEY,
        hub_id          TEXT NOT NULL REFERENCES hubs(id) ON DELETE CASCADE,
        name            TEXT NOT NULL,
        gamemode        TEXT NOT NULL DEFAULT '',
        settings        TEXT NOT NULL DEFAULT '{}',
        steam_lobby_id  TEXT,
        in_progress     INTEGER NOT NULL DEFAULT 0,
        created_at      INTEGER NOT NULL
    );

    CREATE TABLE IF NOT EXISTS feed (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        hub_id      TEXT NOT NULL REFERENCES hubs(id) ON DELETE CASCADE,
        event_type  TEXT NOT NULL,
        lobby_name  TEXT NOT NULL DEFAULT '',
        winner      TEXT NOT NULL DEFAULT '',
        score       TEXT NOT NULL DEFAULT '',
        extra       TEXT NOT NULL DEFAULT '',
        timestamp   INTEGER NOT NULL
    );

    CREATE TABLE IF NOT EXISTS online_members (
        hub_id    TEXT NOT NULL REFERENCES hubs(id) ON DELETE CASCADE,
        steam_id  TEXT NOT NULL,
        last_seen INTEGER NOT NULL,
        PRIMARY KEY (hub_id, steam_id)
    );
`);

try {
    db.prepare('ALTER TABLE hubs ADD COLUMN last_activity INTEGER NOT NULL DEFAULT 0').run();
    db.prepare('UPDATE hubs SET last_activity = created_at WHERE last_activity = 0').run();
} catch {}

const app = express();
app.use(express.json());

function generateCode(length) {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    return Array.from({ length }, () => chars[crypto.randomInt(chars.length)]).join('');
}

function makeToken(hubId, steamId) {
    return crypto.createHmac('sha256', SECRET).update(hubId + ':' + steamId).digest('hex');
}

function authMiddleware(req, res, next) {
    const token   = req.headers['x-hub-token'];
    const steamId = req.headers['x-steam-id'];
    const hubId   = req.params.hub_id;
    if (!token || !steamId || !hubId) return res.status(401).json({ error: 'missing auth' });
    if (token !== makeToken(hubId, steamId)) return res.status(403).json({ error: 'bad token' });
    req.steamId = steamId;
    next();
}

function getHub(hubId) {
    return db.prepare('SELECT * FROM hubs WHERE id = ?').get(hubId);
}

function isMod(hubId, steamId) {
    return !!db.prepare('SELECT 1 FROM moderators WHERE hub_id = ? AND steam_id = ?').get(hubId, steamId);
}

function isOwnerOrMod(hub, steamId) {
    return hub.owner_steam_id === steamId || isMod(hub.id, steamId);
}

function getModerators(hubId) {
    return db.prepare('SELECT steam_id FROM moderators WHERE hub_id = ?').all(hubId).map(r => r.steam_id);
}

function getLobbies(hubId) {
    const rows = db.prepare('SELECT * FROM lobbies WHERE hub_id = ? ORDER BY created_at ASC').all(hubId);
    const out = {};
    for (const r of rows) {
        out[r.token_id] = {
            token_id:       r.token_id,
            name:           r.name,
            gamemode:       r.gamemode,
            settings:       JSON.parse(r.settings),
            steam_lobby_id: r.steam_lobby_id,
            in_progress:    !!r.in_progress,
            created_at:     r.created_at,
        };
    }
    return out;
}

function getFeed(hubId, limit) {
    return db.prepare(
        'SELECT * FROM feed WHERE hub_id = ? ORDER BY id DESC LIMIT ?'
    ).all(hubId, limit || 50).map(r => ({
        event_type: r.event_type,
        lobby_name: r.lobby_name,
        winner:     r.winner,
        score:      r.score,
        extra:      r.extra,
        timestamp:  r.timestamp,
    }));
}

function getOnlineMembers(hubId) {
    return db.prepare('SELECT steam_id FROM online_members WHERE hub_id = ?').all(hubId).map(r => r.steam_id);
}

function buildHubResponse(hub, steamId) {
    return {
        id:             hub.id,
        name:           hub.name,
        invite_code:    hub.invite_code,
        owner_steam_id: hub.owner_steam_id,
        moderators:     getModerators(hub.id),
        lobbies:        getLobbies(hub.id),
        feed:           getFeed(hub.id, 50),
        settings:       { only_mods_can_start: !!hub.only_mods_start },
        online_members: getOnlineMembers(hub.id),
        ...(steamId ? { token: makeToken(hub.id, steamId) } : {}),
    };
}

setInterval(() => {
    db.prepare('DELETE FROM online_members WHERE last_seen < ?').run(Date.now() - HEARTBEAT_TIMEOUT);
}, 10000);

setInterval(() => {
    const cutoff = Date.now() - HUB_EXPIRY_DAYS * 24 * 60 * 60 * 1000;
    const expired = db.prepare('DELETE FROM hubs WHERE last_activity < ?').run(cutoff);
    if (expired.changes > 0) console.log('Deleted ' + expired.changes + ' expired hub(s)');
}, 60 * 60 * 1000);

setInterval(() => {
    db.prepare(
        'DELETE FROM feed WHERE id NOT IN (SELECT id FROM feed AS f2 WHERE f2.hub_id = feed.hub_id ORDER BY id DESC LIMIT ' + FEED_LIMIT + ')'
    ).run();
}, 60000);

app.post('/hub/create', (req, res) => {
    const { owner_steam_id, name } = req.body;
    if (!owner_steam_id || !name) return res.status(400).json({ error: 'missing fields' });
    if (name.length < 1 || name.length > 64) return res.status(400).json({ error: 'invalid name length' });

    const hubId = crypto.randomBytes(8).toString('hex');
    let invite_code, attempts = 0;
    do {
        invite_code = generateCode(8);
        attempts++;
    } while (attempts < 1000 && db.prepare('SELECT 1 FROM hubs WHERE invite_code = ?').get(invite_code));

    const now = Date.now();
    db.prepare(
        'INSERT INTO hubs (id, name, owner_steam_id, invite_code, only_mods_start, last_activity, created_at) VALUES (?, ?, ?, ?, 0, ?, ?)'
    ).run(hubId, name, owner_steam_id, invite_code, now, now);

    db.prepare('INSERT OR REPLACE INTO online_members (hub_id, steam_id, last_seen) VALUES (?, ?, ?)')
        .run(hubId, owner_steam_id, now);

    res.json({ hub_id: hubId, invite_code, token: makeToken(hubId, owner_steam_id) });
});

app.post('/hub/join', (req, res) => {
    const { invite_code, steam_id } = req.body;
    if (!invite_code || !steam_id) return res.status(400).json({ error: 'missing fields' });

    const hub = db.prepare('SELECT * FROM hubs WHERE invite_code = ?').get(invite_code.toUpperCase().trim());
    if (!hub) return res.status(404).json({ error: 'hub not found' });

    const now = Date.now();
    db.prepare('UPDATE hubs SET last_activity = ? WHERE id = ?').run(now, hub.id);
    db.prepare('INSERT OR REPLACE INTO online_members (hub_id, steam_id, last_seen) VALUES (?, ?, ?)')
        .run(hub.id, steam_id, now);

    res.json(buildHubResponse(hub, steam_id));
});

app.get('/hub/:hub_id', authMiddleware, (req, res) => {
    const hub = getHub(req.params.hub_id);
    if (!hub) return res.status(404).json({ error: 'not found' });
    res.json(buildHubResponse(hub, null));
});

app.post('/hub/:hub_id/heartbeat', authMiddleware, (req, res) => {
    const hub = getHub(req.params.hub_id);
    if (!hub) return res.status(404).json({ error: 'not found' });

    const now = Date.now();
    db.prepare('INSERT OR REPLACE INTO online_members (hub_id, steam_id, last_seen) VALUES (?, ?, ?)').run(hub.id, req.steamId, now);
    db.prepare('UPDATE hubs SET last_activity = ? WHERE id = ?').run(now, hub.id);

    res.json({
        online_members: getOnlineMembers(hub.id),
        lobbies:        getLobbies(hub.id),
        feed:           getFeed(hub.id, 50),
    });
});

app.post('/hub/:hub_id/leave', authMiddleware, (req, res) => {
    const hub = getHub(req.params.hub_id);
    if (!hub) return res.status(404).json({ error: 'not found' });
    db.prepare('DELETE FROM online_members WHERE hub_id = ? AND steam_id = ?').run(hub.id, req.steamId);
    res.json({ ok: true });
});

app.post('/hub/:hub_id/lobby', authMiddleware, (req, res) => {
    const hub = getHub(req.params.hub_id);
    if (!hub) return res.status(404).json({ error: 'not found' });
    if (hub.owner_steam_id !== req.steamId) return res.status(403).json({ error: 'owner only' });

    const { name, gamemode, settings } = req.body;
    if (!name) return res.status(400).json({ error: 'missing name' });

    const token_id   = crypto.randomBytes(6).toString('hex');
    const created_at = Date.now();

    db.prepare(
        'INSERT INTO lobbies (token_id, hub_id, name, gamemode, settings, steam_lobby_id, in_progress, created_at) VALUES (?, ?, ?, ?, ?, NULL, 0, ?)'
    ).run(token_id, hub.id, name, gamemode || '', JSON.stringify(settings || {}), created_at);

    res.json({ lobby: { token_id, name, gamemode: gamemode || '', settings: settings || {}, steam_lobby_id: null, in_progress: false, created_at } });
});

app.delete('/hub/:hub_id/lobby/:token_id', authMiddleware, (req, res) => {
    const hub = getHub(req.params.hub_id);
    if (!hub) return res.status(404).json({ error: 'not found' });
    if (!isOwnerOrMod(hub, req.steamId)) return res.status(403).json({ error: 'no permission' });
    db.prepare('DELETE FROM lobbies WHERE token_id = ? AND hub_id = ?').run(req.params.token_id, hub.id);
    res.json({ ok: true });
});

app.put('/hub/:hub_id/lobby/:token_id/state', authMiddleware, (req, res) => {
    const hub = getHub(req.params.hub_id);
    if (!hub) return res.status(404).json({ error: 'not found' });
    if (!isOwnerOrMod(hub, req.steamId)) return res.status(403).json({ error: 'no permission' });

    const lobby = db.prepare('SELECT * FROM lobbies WHERE token_id = ? AND hub_id = ?').get(req.params.token_id, hub.id);
    if (!lobby) return res.status(404).json({ error: 'lobby not found' });

    const { settings, in_progress, name, gamemode, steam_lobby_id } = req.body;
    db.prepare(`
        UPDATE lobbies SET
            settings       = COALESCE(?, settings),
            in_progress    = COALESCE(?, in_progress),
            name           = COALESCE(?, name),
            gamemode       = COALESCE(?, gamemode),
            steam_lobby_id = COALESCE(?, steam_lobby_id)
        WHERE token_id = ?
    `).run(
        settings       !== undefined ? JSON.stringify(settings) : null,
        in_progress    !== undefined ? (in_progress ? 1 : 0)   : null,
        name           !== undefined ? name           : null,
        gamemode       !== undefined ? gamemode       : null,
        steam_lobby_id !== undefined ? steam_lobby_id : null,
        lobby.token_id
    );

    const updated = db.prepare('SELECT * FROM lobbies WHERE token_id = ?').get(lobby.token_id);
    res.json({ lobby: {
        token_id:       updated.token_id,
        name:           updated.name,
        gamemode:       updated.gamemode,
        settings:       JSON.parse(updated.settings),
        steam_lobby_id: updated.steam_lobby_id,
        in_progress:    !!updated.in_progress,
        created_at:     updated.created_at,
    }});
});

app.post('/hub/:hub_id/moderator', authMiddleware, (req, res) => {
    const hub = getHub(req.params.hub_id);
    if (!hub) return res.status(404).json({ error: 'not found' });
    if (hub.owner_steam_id !== req.steamId) return res.status(403).json({ error: 'owner only' });
    const { steam_id } = req.body;
    if (!steam_id) return res.status(400).json({ error: 'missing steam_id' });
    db.prepare('INSERT OR IGNORE INTO moderators (hub_id, steam_id) VALUES (?, ?)').run(hub.id, steam_id);
    res.json({ moderators: getModerators(hub.id) });
});

app.delete('/hub/:hub_id/moderator/:steam_id', authMiddleware, (req, res) => {
    const hub = getHub(req.params.hub_id);
    if (!hub) return res.status(404).json({ error: 'not found' });
    if (hub.owner_steam_id !== req.steamId) return res.status(403).json({ error: 'owner only' });
    db.prepare('DELETE FROM moderators WHERE hub_id = ? AND steam_id = ?').run(hub.id, req.params.steam_id);
    res.json({ moderators: getModerators(hub.id) });
});

app.put('/hub/:hub_id/settings', authMiddleware, (req, res) => {
    const hub = getHub(req.params.hub_id);
    if (!hub) return res.status(404).json({ error: 'not found' });
    if (hub.owner_steam_id !== req.steamId) return res.status(403).json({ error: 'owner only' });
    const { only_mods_can_start } = req.body;
    if (only_mods_can_start !== undefined) {
        db.prepare('UPDATE hubs SET only_mods_start = ? WHERE id = ?').run(only_mods_can_start ? 1 : 0, hub.id);
    }
    const updated = getHub(hub.id);
    res.json({ settings: { only_mods_can_start: !!updated.only_mods_start } });
});

app.post('/hub/:hub_id/feed', authMiddleware, (req, res) => {
    const hub = getHub(req.params.hub_id);
    if (!hub) return res.status(404).json({ error: 'not found' });
    const { event_type, lobby_name, winner, score, extra } = req.body;
    if (!event_type) return res.status(400).json({ error: 'missing event_type' });
    const timestamp = Date.now();
    db.prepare(
        'INSERT INTO feed (hub_id, event_type, lobby_name, winner, score, extra, timestamp) VALUES (?, ?, ?, ?, ?, ?, ?)'
    ).run(hub.id, event_type, lobby_name || '', winner || '', score || '', extra || '', timestamp);
    res.json({ entry: { event_type, lobby_name: lobby_name || '', winner: winner || '', score: score || '', extra: extra || '', timestamp } });
});

app.delete('/hub/:hub_id', authMiddleware, (req, res) => {
    const hub = getHub(req.params.hub_id);
    if (!hub) return res.status(404).json({ error: 'not found' });
    if (hub.owner_steam_id !== req.steamId) return res.status(403).json({ error: 'owner only' });
    db.prepare('DELETE FROM hubs WHERE id = ?').run(hub.id);
    res.json({ ok: true });
});

app.listen(PORT, () => console.log('Hub server running on port ' + PORT + ', db: ' + DB_PATH));
