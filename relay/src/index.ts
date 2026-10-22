// Lunte relay: Club members share Booms, reactions and a short "why". See docs/contract.md §5.
import { DurableObject } from "cloudflare:workers";

interface Env {
  CLUBS: DurableObjectNamespace<Club>;
}

const CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"; // 32 characters, so `byte & 31` picks one without bias
const CODE_RE = /^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{6}$/;
const BOOM_ID_RE = /^[A-Za-z0-9_-]{1,64}$/; // the app sends String(Int(ts * 1000))
const PROOF_RE = /^[0-9a-f]{64}$/i;
const MAX_BODY = 2048;
const MAX_MEMBERS = 50;
const JOINS_PER_HOUR = 10;
const HOUR_MS = 3_600_000;
const KEEP_EVENTS = 500;
const PAGE_SIZE = 100;

const json = (status: number, body: unknown) => Response.json(body, { status });
const fail = (status: number, error: string) => json(status, { error });

export default {
  async fetch(req, env) {
    try {
      return await route(req, env);
    } catch (err) {
      console.error(err);
      return fail(500, "internal error");
    }
  },
} satisfies ExportedHandler<Env>;

async function route(req: Request, env: Env): Promise<Response> {
  const url = new URL(req.url);
  const [root, code, action, ...rest] = url.pathname.split("/").filter(Boolean);
  if (root !== "clubs" || rest.length > 0) return fail(404, "not found");

  let body = "";
  if (req.method === "POST") {
    const text = await readBody(req);
    if (text === null) return fail(413, "body is over 2 KB");
    body = text;
  }

  if (code === undefined) return req.method === "POST" ? createClub(env) : fail(404, "not found");

  const club = code.toUpperCase();
  if (!CODE_RE.test(club)) return fail(404, "unknown club");
  const stub = env.CLUBS.get(env.CLUBS.idFromName(club));
  const token = req.headers.get("authorization")?.match(/^Bearer\s+(\S+)$/i)?.[1] ?? null;

  if (req.method === "POST" && action === "join") return stub.join(body);
  if (req.method === "POST" && action === "events") return stub.post(token, body);
  if (req.method === "GET" && action === "events") return stub.list(token, url.searchParams.get("after"));
  return fail(404, "not found");
}

async function createClub(env: Env): Promise<Response> {
  // ponytail: no rate limit on creating Clubs.
  for (let attempt = 0; attempt < 5; attempt++) {
    const club = Array.from(crypto.getRandomValues(new Uint8Array(6)), (b) => CODE_ALPHABET[b & 31]).join("");
    if (await env.CLUBS.get(env.CLUBS.idFromName(club)).create()) return json(201, { club });
  }
  return fail(500, "no free club code");
}

/** The body as text, or null when it is over 2 KB. */
async function readBody(req: Request): Promise<string | null> {
  if (Number(req.headers.get("content-length")) > MAX_BODY) return null;
  // ponytail: a body without Content-Length is buffered before the check; Cloudflare's request limit bounds it.
  const buf = await req.arrayBuffer();
  return buf.byteLength > MAX_BODY ? null : new TextDecoder().decode(buf);
}

type EventRow = {
  seq: number;
  type: string;
  boom: string | null;
  ts: number;
  emoji: string | null;
  text: string | null;
  from_name: string | null;
};

type NewEvent = { type: string; boom?: string; ts: number; emoji?: string; text?: string; from?: string };

export class Club extends DurableObject<Env> {
  private sql = this.ctx.storage.sql;

  /** Claims this code and creates its tables. False if the Club already exists. */
  create(): boolean {
    if (this.exists()) return false;
    this.sql.exec(`
      CREATE TABLE club (created_at INTEGER NOT NULL);
      CREATE TABLE members (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        name_key TEXT NOT NULL UNIQUE, -- NFKC + lowercase, so "Paal" and "PAAL" are the same name
        token_hash TEXT NOT NULL UNIQUE,
        joined_at INTEGER NOT NULL      -- ms, for the joins-per-hour limit
      );
      CREATE TABLE booms (              -- never trimmed, so a why can always find its Boom's proof
        id TEXT PRIMARY KEY,
        proof TEXT NOT NULL,            -- never returned
        ts REAL NOT NULL
      );
      CREATE TABLE events (
        seq INTEGER PRIMARY KEY AUTOINCREMENT, -- never reused, so ?after= paging stays correct after trimming
        type TEXT NOT NULL,
        boom TEXT,      -- NULL for joins
        ts REAL NOT NULL,
        emoji TEXT,
        text TEXT,
        from_name TEXT  -- always NULL for booms: Booms are anonymous
      );
    `);
    this.sql.exec("INSERT INTO club (created_at) VALUES (?)", Date.now());
    return true;
  }

  async join(body: string): Promise<Response> {
    if (!this.exists()) return fail(404, "unknown club");
    const name = trimmedText(parseObject(body)?.name, 24);
    if (name === null || /\p{C}/u.test(name)) return fail(400, "name must be 1-24 visible characters");

    const token = randomHex(32);
    const tokenHash = await sha256Hex(token);
    // No await from here on, so two joins can't both take the last seat, the last join this hour, or the same name.
    const now = Date.now();
    if (this.count("SELECT COUNT(*) AS n FROM members WHERE joined_at > ?", now - HOUR_MS) >= JOINS_PER_HOUR) {
      return fail(429, "too many joins this hour");
    }
    if (this.count("SELECT COUNT(*) AS n FROM members") >= MAX_MEMBERS) return fail(400, "club is full");
    const nameKey = name.normalize("NFKC").toLowerCase();
    if (this.count("SELECT COUNT(*) AS n FROM members WHERE name_key = ?", nameKey) > 0) return fail(409, "name is taken");

    const member = randomHex(8);
    this.sql.exec(
      "INSERT INTO members (id, name, name_key, token_hash, joined_at) VALUES (?, ?, ?, ?, ?)",
      member, name, nameKey, tokenHash, now,
    );
    this.append({ type: "join", ts: now / 1000, from: name });
    return json(200, { member, token });
  }

  async post(token: string | null, body: string): Promise<Response> {
    if (!this.exists()) return fail(404, "unknown club");
    const from = await this.memberName(token);
    if (from === null) return fail(401, "bad token");

    const e = parseObject(body);
    if (e === null) return fail(400, "body must be a JSON object");
    if (typeof e.boom !== "string" || !BOOM_ID_RE.test(e.boom)) return fail(400, "bad boom id");
    const boom = e.boom;
    const storedProof = this.sql.exec<{ proof: string }>("SELECT proof FROM booms WHERE id = ?", boom).toArray()[0]?.proof;
    const now = Date.now() / 1000;

    switch (e.type) {
      case "boom": {
        if (typeof e.ts !== "number" || !Number.isFinite(e.ts) || e.ts <= 0) return fail(400, "bad ts");
        if (typeof e.proof !== "string" || !PROOF_RE.test(e.proof)) return fail(400, "proof must be sha256 hex");
        if (storedProof !== undefined) return fail(409, "boom id is taken");
        this.sql.exec("INSERT INTO booms (id, proof, ts) VALUES (?, ?, ?)", boom, e.proof.toLowerCase(), e.ts);
        return this.created({ type: "boom", boom, ts: e.ts });
      }
      case "react": {
        const emoji = e.emoji;
        if (typeof emoji !== "string" || graphemes(emoji) !== 1 || utf8Length(emoji) > 16) {
          return fail(400, "emoji must be one grapheme of at most 16 bytes");
        }
        if (storedProof === undefined) return fail(404, "unknown boom");
        return this.created({ type: "react", boom, ts: now, emoji, from });
      }
      case "why": {
        const text = trimmedText(e.text, 140);
        if (text === null) return fail(400, "text must be 1-140 characters");
        if (typeof e.secret !== "string") return fail(400, "missing secret");
        // Only the Boom's owner knows the secret behind its proof.
        if (storedProof === undefined) return fail(404, "unknown boom");
        if ((await sha256Hex(e.secret)) !== storedProof) return fail(403, "secret does not match this boom");
        return this.created({ type: "why", boom, ts: now, text, from });
      }
      default:
        return fail(400, "unknown event type");
    }
  }

  async list(token: string | null, after: string | null): Promise<Response> {
    if (!this.exists()) return fail(404, "unknown club");
    if ((await this.memberName(token)) === null) return fail(401, "bad token");
    if (after !== null && !/^\d{1,15}$/.test(after)) return fail(400, "after must be a whole number");

    const rows = this.sql
      .exec<EventRow>(
        "SELECT seq, type, boom, ts, emoji, text, from_name FROM events WHERE seq > ? ORDER BY seq LIMIT ?",
        Number(after ?? 0),
        PAGE_SIZE,
      )
      .toArray();
    // Drop NULL columns, so a boom comes back as {seq, type, boom, ts} with no `from`, and a join with no `boom`.
    const events = rows.map(({ from_name, ...rest }) =>
      Object.fromEntries(Object.entries({ ...rest, from: from_name }).filter(([, v]) => v !== null)),
    );
    return json(200, { events });
  }

  /** Appends to the feed and trims it to the last 500. */
  private append(e: NewEvent): number {
    const { seq } = this.sql
      .exec<{ seq: number }>(
        "INSERT INTO events (type, boom, ts, emoji, text, from_name) VALUES (?, ?, ?, ?, ?, ?) RETURNING seq",
        e.type, e.boom ?? null, e.ts, e.emoji ?? null, e.text ?? null, e.from ?? null,
      )
      .one();
    this.sql.exec("DELETE FROM events WHERE seq <= ?", seq - KEEP_EVENTS);
    return seq;
  }

  private created(e: NewEvent): Response {
    return json(201, { seq: this.append(e) });
  }

  /** Whether create() ran here. It only reads, so probing a code that was never created writes nothing. */
  private exists(): boolean {
    const hasTable = this.sql.exec("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'club'").toArray().length > 0;
    return hasTable && this.sql.exec("SELECT 1 FROM club").toArray().length > 0;
  }

  private count(query: string, ...params: unknown[]): number {
    return this.sql.exec<{ n: number }>(query, ...params).one().n;
  }

  private async memberName(token: string | null): Promise<string | null> {
    if (token === null) return null;
    const hash = await sha256Hex(token);
    const row = this.sql.exec<{ name: string }>("SELECT name FROM members WHERE token_hash = ?", hash).toArray()[0];
    return row?.name ?? null;
  }
}

function parseObject(text: string): Record<string, unknown> | null {
  try {
    const value: unknown = JSON.parse(text);
    return value !== null && typeof value === "object" && !Array.isArray(value) ? (value as Record<string, unknown>) : null;
  } catch {
    return null;
  }
}

const segmenter = new Intl.Segmenter();
// Grapheme clusters, the same thing Swift's String.count counts.
const graphemes = (s: string) => [...segmenter.segment(s)].length;
const utf8Length = (s: string) => new TextEncoder().encode(s).length;

/** The trimmed string if it is 1...max characters long, else null. */
function trimmedText(value: unknown, max: number): string | null {
  if (typeof value !== "string") return null;
  const s = value.trim();
  const n = graphemes(s);
  return n >= 1 && n <= max ? s : null;
}

const hex = (bytes: ArrayBuffer | Uint8Array) =>
  Array.from(new Uint8Array(bytes), (b) => b.toString(16).padStart(2, "0")).join("");
const randomHex = (byteCount: number) => hex(crypto.getRandomValues(new Uint8Array(byteCount)));
const sha256Hex = async (s: string) => hex(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s)));
