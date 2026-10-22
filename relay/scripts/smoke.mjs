// Smoke test for the relay. Start it first: npx wrangler dev --local --port 8787
// Usage: node scripts/smoke.mjs [base url]
import assert from "node:assert/strict";
import { createHash, randomBytes } from "node:crypto";

const BASE = process.argv[2] ?? "http://localhost:8787";
let checks = 0;

async function call(method, path, { token, body, raw } = {}) {
  const headers = token ? { authorization: `Bearer ${token}` } : {};
  const res = await fetch(BASE + path, { method, headers, body: raw ?? (body && JSON.stringify(body)) });
  return { status: res.status, json: await res.json() };
}

function expect(res, status, label) {
  assert.equal(res.status, status, `${label}: got ${res.status} ${JSON.stringify(res.json)}`);
  checks++;
  return res.json;
}

// A Club, two members, one Boom.
const { club } = expect(await call("POST", "/clubs"), 201, "create club");
assert.match(club, /^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{6}$/);
const events = `/clubs/${club}/events`;

const join = (name, c = club) => call("POST", `/clubs/${c}/join`, { body: { name } });
const paal = expect(await join("  Paal  "), 200, "paal joins");
const ola = expect(await join("Ola"), 200, "ola joins");
assert.ok(paal.member && paal.token && paal.member !== ola.member && paal.token !== ola.token);

// Names are unique after NFKC and lowercasing, and can't hide invisible characters.
expect(await join("PAAL"), 409, "same name, other case");
expect(await join("Ｐａａｌ"), 409, "same name, full-width");
expect(await join("Ola\u200B"), 400, "zero-width space in name");
expect(await join("O\u0007la"), 400, "control character in name");

// Every join shows up in the feed, so nobody joins unnoticed.
let list = expect(await call("GET", `${events}?after=0`, { token: ola.token }), 200, "list joins");
assert.deepEqual(list.events.map(({ seq, ts, ...e }) => e), [{ type: "join", from: "Paal" }, { type: "join", from: "Ola" }]);
assert.ok(list.events.every((e) => typeof e.seq === "number" && typeof e.ts === "number"));
const firstSeq = list.events[0].seq;
const joinedSeq = list.events[1].seq;

const secret = randomBytes(32).toString("hex");
const proof = createHash("sha256").update(secret).digest("hex");
const boomId = String(Date.now());
const boomTs = Date.now() / 1000;
const boom = expect(
  await call("POST", events, { token: paal.token, body: { type: "boom", boom: boomId, ts: boomTs, proof } }),
  201,
  "post boom",
);
assert.equal(typeof boom.seq, "number");

// Ola sees the Boom, with no `from` and no proof.
list = expect(await call("GET", `${events}?after=${joinedSeq}`, { token: ola.token }), 200, "ola lists");
assert.deepEqual(list.events, [{ seq: boom.seq, type: "boom", boom: boomId, ts: boomTs }]);

// Ola reacts; it comes back with `from`.
const react = expect(
  await call("POST", events, { token: ola.token, body: { type: "react", boom: boomId, emoji: "🧯" } }),
  201,
  "react",
);
list = expect(await call("GET", `${events}?after=${boom.seq}`, { token: paal.token }), 200, "list after boom");
assert.equal(list.events.length, 1);
assert.deepEqual({ ...list.events[0], ts: 0 }, { seq: react.seq, type: "react", boom: boomId, ts: 0, emoji: "🧯", from: "Ola" });

// Boom ids are unique, so nobody can re-post Paal's Boom with their own proof.
const olaSecret = randomBytes(32).toString("hex");
const olaProof = createHash("sha256").update(olaSecret).digest("hex");
const dupBoom = { type: "boom", boom: boomId, ts: boomTs, proof: olaProof };
expect(await call("POST", events, { token: ola.token, body: dupBoom }), 409, "duplicate boom id");
expect(await call("POST", events, { token: ola.token, body: { type: "react", boom: "999", emoji: "😂" } }), 404, "react, unknown boom");

// A why needs the Boom's secret.
const why = { type: "why", boom: boomId, text: "  the tests kept failing  " };
expect(await call("POST", events, { token: ola.token, body: { ...why, secret: olaSecret } }), 403, "why, wrong secret");
expect(await call("POST", events, { token: paal.token, body: { ...why, boom: "999", secret } }), 404, "why, unknown boom");
const whyRes = expect(await call("POST", events, { token: paal.token, body: { ...why, secret } }), 201, "why, right secret");
list = expect(await call("GET", `${events}?after=${react.seq}`, { token: ola.token }), 200, "list after react");
assert.equal(list.events.length, 1);
assert.equal(list.events[0].seq, whyRes.seq);
assert.equal(list.events[0].text, "the tests kept failing");
assert.equal(list.events[0].from, "Paal");

// Nothing ever returns the proof or the secret.
const all = JSON.stringify(expect(await call("GET", events, { token: ola.token }), 200, "list all"));
assert.ok(!all.includes(proof) && !all.includes(secret) && !all.includes("proof") && !all.includes("secret"));

// Errors.
expect(await call("GET", events, { token: "not-a-token" }), 401, "bad token");
expect(await call("GET", events), 401, "no token");
expect(await call("POST", events, { token: "x", body: { type: "react", boom: boomId, emoji: "😂" } }), 401, "post, bad token");
expect(await call("POST", "/clubs/ZZZZZZ/join", { body: { name: "Kari" } }), 404, "unknown club");
expect(await call("GET", "/clubs/ZZZZZZ/events", { token: ola.token }), 404, "unknown club events");
expect(await call("POST", "/clubs/ZZZZZZ/events", { token: ola.token, body: { type: "react", boom: boomId, emoji: "😂" } }), 404, "unknown club post");
expect(await call("POST", "/clubs/nope/join", { body: { name: "Kari" } }), 404, "malformed club code");
expect(await call("POST", `/clubs/${club}/join`, { raw: JSON.stringify({ name: "x".repeat(3000) }) }), 413, "oversized body");
expect(await call("POST", events, { token: ola.token, raw: "x".repeat(2049) }), 413, "oversized event");
expect(await call("POST", events, { token: ola.token, body: { type: "react", boom: boomId, emoji: "🧯😂" } }), 400, "two emoji");
expect(await call("POST", events, { token: ola.token, body: { type: "react", boom: boomId, emoji: "👨‍👩‍👧‍👦" } }), 400, "one grapheme, 25 bytes");
expect(await call("POST", events, { token: ola.token, body: { type: "react", boom: boomId, emoji: "🇳🇴" } }), 201, "flag emoji");
expect(await call("POST", events, { token: ola.token, body: { type: "nope", boom: boomId } }), 400, "unknown type");
expect(await call("POST", events, { token: ola.token, raw: "{not json" }), 400, "bad json");
expect(await call("POST", events, { token: paal.token, body: { ...why, text: "x".repeat(141), secret } }), 400, "why too long");
expect(await call("POST", events, { token: paal.token, body: { ...why, text: "   ", secret } }), 400, "why blank");
expect(await call("POST", `/clubs/${club}/join`, { body: { name: "   " } }), 400, "blank name");
expect(await call("POST", `/clubs/${club}/join`, { body: { name: "x".repeat(25) } }), 400, "name too long");
expect(await call("GET", `${events}?after=-1`, { token: ola.token }), 400, "bad after");

// Paging: at most 100 per call, oldest first, only seq > after.
const post = () => call("POST", events, { token: ola.token, body: { type: "react", boom: boomId, emoji: "😂" } });
for (let i = 0; i < 120; i++) assert.equal((await post()).status, 201);
let page = expect(await call("GET", `${events}?after=0`, { token: ola.token }), 200, "page 1");
assert.equal(page.events.length, 100);
const seqs = page.events.map((e) => e.seq);
assert.deepEqual(seqs, [...seqs].sort((a, b) => a - b));
assert.equal(seqs[0], firstSeq);
const last = seqs.at(-1);
page = expect(await call("GET", `${events}?after=${last}`, { token: ola.token }), 200, "page 2");
assert.ok(page.events.length > 0 && page.events.every((e) => e.seq > last));
assert.equal(page.events[0].seq, last + 1);

// Only the last 500 are kept.
let newest = 0;
for (let i = 0; i < 400; i++) newest = (await post()).json.seq;
page = expect(await call("GET", `${events}?after=0`, { token: ola.token }), 200, "after trimming");
assert.equal(page.events[0].seq, newest - 499);
assert.ok(!page.events.some((e) => e.type === "boom"), "the boom event is trimmed from the feed");

// The Boom itself is never trimmed: its id stays taken and its owner can still say why.
expect(await call("POST", events, { token: ola.token, body: dupBoom }), 409, "duplicate boom id after trimming");
expect(await call("POST", events, { token: ola.token, body: { ...why, secret: olaSecret } }), 403, "wrong secret after trimming");
expect(await call("POST", events, { token: paal.token, body: { ...why, text: "still mine", secret } }), 201, "why after trimming");

// At most 10 joins per Club per hour.
const { club: club2 } = expect(await call("POST", "/clubs"), 201, "create second club");
for (let i = 1; i <= 10; i++) expect(await join(`member ${i}`, club2), 200, `join ${i} of 10`);
expect(await join("member 11", club2), 429, "11th join this hour");

console.log(`smoke: ${checks} checks passed against ${BASE} (club ${club})`);
