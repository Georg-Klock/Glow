/* Glow Up · alt — the week widget as a real 3-D object.
   Source of truth: Website/glow-alt/. The Webflow copy is split out of this
   file by build-embed.py, because a Webflow custom-code block caps at 10,000
   characters and this is longer than that.

   The card is one displaced mesh. Every socket is a genuine pocket in that
   mesh: the surface is evaluated from a signed-distance field in the vertex
   shader, so the geometry really is lower where a habit is still open, and the
   normals are taken from the same field per fragment rather than from a normal
   map. Tilt the card and the pockets occlude and catch light because they are
   holes, not painted shadows.

   What this version cannot do is glow. The glow on /glow-up is a PQ AVIF
   handed to the compositor; a WebGL canvas is SDR, so the brightest thing here
   is paper white. See docs/glow.md. */
(function () {
'use strict';

/* ---- the same week as the 2-D widget -------------------------------------
   Copied from Website/week-widget/webflow/footer.html so both read the same
   demo week. If one changes, change both. */
var TODAY = 3, LAST = 6;
var HABITS = [
{ slug: 'gratitude',   name: 'Gratitude',   target: 7, miss: -2 },
{ slug: 'stretch',     name: 'Stretch',     target: 4, pattern: [0, 1] },
{ slug: 'read-book',   name: 'Read Book',   target: 4, pattern: [0, 2] },
{ slug: 'workout',     name: 'Workout',     target: 3, pattern: [0, 1], doneToday: true },
{ slug: 'vo2-max',     name: 'VO2 Max',     target: 2, pattern: [2], doneToday: true },
{ slug: 'tutorial',    name: 'Tutorial',    target: 3, pattern: [0, 2], doneToday: true },
{ slug: 'sunset',      name: 'Sunset',      target: 3, pattern: [0, 1] },
{ slug: 'early-night', name: 'Early night', target: 7, miss: -1 }
];
var LETTERS = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
var SPACERS = [3, 7];
var ICON_BASE = 'https://cdn.prod.website-files.com/620d05babdddc967daa0780a/';
var ICONS = {                                        // the mobile@3x masks the 2-D widget already uploaded
'gratitude': '6aa44997b2a62113c7eecd96', 'stretch': '6aa449991fa1090afdc31dd6',
'read-book': '6aa449981fa1090afdc31d39', 'workout': '6aa4499db2a62113c7eed199',
'vo2-max': '6aa4499dae218f26c362eab5', 'tutorial': '6aa4499dae218f26c362eaa0',
'sunset': '6aa4499ae2c2fc76e7cca80e', 'early-night': '6aa449971c08fb27cb532ea4'
};
function iconURL(slug) { return ICON_BASE + ICONS[slug] + '_gw-mobile-3x-icon-' + slug + '-mask.png'; }

function widths(columns, count) {
if (count <= 0 || columns < count) return [];
var base = Math.floor(columns / count), extra = columns % count, out = [];
for (var i = 0; i < count; i++) out.push(base + (i >= count - extra ? 1 : 0));
return out;
}
function assignColumns(marks) {
var count = marks.length, ends = [], previousEnd = -1, previousIndex = -1, i;
for (i = 0; i < count; i++) {
ends.push(null);
if (marks[i].anchor === null) continue;
var low = previousEnd + (i - previousIndex);
var high = LAST - (count - 1 - i);
var isFinal = i === count - 1 && (marks[i].state === 'done' || marks[i].state === 'open');
var end = isFinal ? LAST : Math.max(low, Math.min(marks[i].anchor, high));
ends[i] = end; previousEnd = end; previousIndex = i;
}
var spans = [], cursor = 0, runStart = 0;
function push(mark, first, last) { spans.push({ state: mark.state, first: first, last: last }); }
for (i = 0; i < count; i++) {
if (ends[i] === null) continue;
var w = widths(ends[i] - cursor, i - runStart), k;
for (k = 0; k < w.length; k++) { push(marks[runStart + k], cursor, cursor + w[k] - 1); cursor += w[k]; }
var first = marks[i].state === 'missed' ? ends[i] : cursor;
push(marks[i], first, ends[i]);
cursor = ends[i] + 1; runStart = i + 1;
}
var tail = widths(LAST - cursor + 1, count - runStart);
for (i = 0; i < tail.length; i++) { push(marks[runStart + i], cursor, cursor + tail[i] - 1); cursor += tail[i]; }
return spans;
}
function rowSpans(target, completed, today) {
var done = Object.keys(completed).map(Number).sort(function (a, b) { return a - b; });
var doneToday = !!completed[today];
var repsLeft = Math.max(0, target - done.length);
var actionableLeft = 0, c;
for (c = today; c <= LAST; c++) if (!completed[c]) actionableLeft++;
var lost = Math.max(0, repsLeft - actionableLeft), live = repsLeft - lost;
var blankPast = [];
for (c = 0; c < today; c++) if (!completed[c]) blankPast.push(c);
var anchored = done.map(function (d) { return { state: 'done', anchor: d }; });
blankPast.slice(0, lost).forEach(function (d) { anchored.push({ state: 'missed', anchor: d }); });
var canOpen = live > 0 && !doneToday;
if (canOpen) anchored.push({ state: 'open', anchor: today });
anchored.sort(function (a, b) { return a.anchor - b.anchor; });
var upcoming = live - (canOpen ? 1 : 0);
for (c = 0; c < upcoming; c++) anchored.push({ state: 'upcoming', anchor: null });
return assignColumns(anchored);
}
function week() {
return HABITS.map(function (h) {
var completed = {}, c;
if (h.target === 7) {
for (c = 0; c < TODAY; c++) if (c !== TODAY + h.miss) completed[c] = true;
} else {
h.pattern.forEach(function (d) { if (d < TODAY) completed[d] = true; });
if (h.doneToday) completed[TODAY] = true;
}
return { habit: h, completed: completed, spans: [] };
});
}

/* ---- plan, in the 2-D widget's own units (CSS px at --s: 1) ---- */
var CELL = 24, GAP = 8, LABEL_W = 98, LABEL_GAP = 4, ICON_W = 24, ICON_GAP = 2.25;
var HEADER_H = 14, HEADER_GAP = 4, PAD_L = 6, PAD_R = 14, PAD_T = 10, PAD_B = 14;
var RADIUS = 22, TEXT = 12, INSET = 1;
var TRACK = 7 * CELL + 6 * GAP;                      // 216
var TRACK_L = PAD_L + LABEL_W + LABEL_GAP;           // 108
var W = TRACK_L + TRACK + PAD_R;                     // 338
var ROWS_TOP = PAD_T + HEADER_H + HEADER_GAP;        // 28
var NROWS = HABITS.length + SPACERS.length;          // 10
var H = ROWS_TOP + NROWS * CELL + (NROWS - 1) * GAP + PAD_B;  // 354
function cellX(c) { return TRACK_L + c * (CELL + GAP); }
function rowY(r) { return ROWS_TOP + r * (CELL + GAP); }

/* ---- the third dimension ----
   Everything below is depth, and none of it exists in the CSS version. */
var THICK = 16;        // slab thickness
var EDGE = 3.2;        // fillet radius where the top face rolls into the side
var WELLD = 3.4;       // how deep a socket is cut into the top face
var RIM = 0.9;         // how far the rounded-over lip eats inward
var PILLTOP = THICK - 0.9;   // a completed mark sits proud of the well, below the face
var PR = 1.0;
var RINGW = 1.7, RINGTOP = THICK - 0.45;
var RAISE = 0.28;      // names, letters and icons stand off the face
var ENGRAVE = 0.5;     // a missed day is cut into it — both as relief in the normal, not as triangles

/* ---- rows in display order (the two spacer rows are real gaps) ----
   ROWS is live: marking a habit done rewrites its `completed` map and every
   span in the row is derived again, exactly as the 2-D widget does it. */
var ROWS = week(), DISPLAY = [];
function relayout() {
ROWS.forEach(function (row) { row.spans = rowSpans(row.habit.target, row.completed, TODAY); });
DISPLAY = ROWS.slice();
SPACERS.forEach(function (at) { DISPLAY.splice(at, 0, null); });
}
relayout();
/* A row emits while it still has an open mark; today's letter emits only
   while any row does. Both rules are the 2-D widget's updateTiers(). */
function emitting(row) {
return !!row && row.spans.some(function (s) { return s.state === 'open'; });
}
function anyOpen() { return ROWS.some(emitting); }
function toggle(rowIndex) {
var row = ROWS[rowIndex];
if (!row) return false;
if (row.completed[TODAY]) delete row.completed[TODAY]; else row.completed[TODAY] = true;
relayout();
return true;
}

var SPAN_KIND = { upcoming: 1, done: 2, open: 3 };   // 0 means "no span here"

/* ---- every socket, in card coordinates ----
   The geometry builder sweeps a pocket around each of these. `kind` says what
   sits in it: nothing, a pill, or a ring. */
function sockets() {
var out = [];
DISPLAY.forEach(function (row, ri) {
if (!row) return;
var index = ROWS.indexOf(row);
row.spans.forEach(function (s) {
if (s.state === 'missed') return;                // a missed day has no socket, only the cross
var n = s.last - s.first + 1;
// the same rule as the 2-D widget: an open mark, or today's own finished one
var tappable = s.state === 'open' ||
(s.state === 'done' && s.first <= TODAY && TODAY <= s.last && !!row.completed[TODAY]);
out.push({
x: cellX(s.first), z: rowY(ri), w: n * CELL + (n - 1) * GAP,
kind: SPAN_KIND[s.state], row: index, tappable: tappable
});
});
});
return out;
}

window.GWA_M = {
W: W, H: H, RADIUS: RADIUS, CELL: CELL, INSET: INSET,
THICK: THICK, EDGE: EDGE, WELLD: WELLD, RIM: RIM,
PILLTOP: PILLTOP, PR: PR, RINGW: RINGW, RINGTOP: RINGTOP,
RAISE: RAISE, ENGRAVE: ENGRAVE,
TEXT: TEXT, PAD_L: PAD_L, PAD_T: PAD_T, HEADER_H: HEADER_H,
ICON_W: ICON_W, ICON_GAP: ICON_GAP, LETTERS: LETTERS, TODAY: TODAY,
ICON_BASE: ICON_BASE, ICONS: ICONS,
sockets: sockets, toggle: toggle, anyOpen: anyOpen, cellX: cellX, rowY: rowY,
rows: function () { return DISPLAY; }
};
})();

/* ===== block 2 of 4 =====================================================
   The decals: the text, icons and missed crosses that are painted onto the
   card rather than modelled into it. Split here only because a Webflow
   custom-code block stops at 10,000 characters. */
(function () {
'use strict';
var M = window.GWA_M;
if (!M) return;
var W = M.W, H = M.H, CELL = M.CELL, TEXT = M.TEXT, PAD_L = M.PAD_L, PAD_T = M.PAD_T;
var HEADER_H = M.HEADER_H, ICON_W = M.ICON_W, ICON_GAP = M.ICON_GAP;
var LETTERS = M.LETTERS, TODAY = M.TODAY, ICON_BASE = M.ICON_BASE, ICONS = M.ICONS;
var cellX = M.cellX, rowY = M.rowY;
function iconURL(slug) { return ICON_BASE + ICONS[slug] + '_gw-mobile-3x-icon-' + slug + '-mask.png'; }

/* ---- decals ----
   Text, icons and the missed cross are not geometry: they are two canvases the
   size of the card. uColor carries what they look like, uMask carries what
   they do to the surface — red raises, green cuts. */
var K = 4;   // texels per unit
function canvas2d() {
var c = document.createElement('canvas');
c.width = Math.round(W * K); c.height = Math.round(H * K);
var ctx = c.getContext('2d');
ctx.scale(K, K);
return { c: c, ctx: ctx };
}
var LIT_SDR = '#969696', EMIT = '#FFFFFF', OFF_DAY = '#888888', RESTING = 'rgba(217,217,217,0.5)';
function fontStack() { return '"GW Inter","Inter",system-ui,-apple-system,sans-serif'; }

function drawDecals(colorCtx, maskCtx, icons) {
var f = TEXT + 'px ' + fontStack(), live = M.anyOpen();
[colorCtx, maskCtx].forEach(function (ctx) { ctx.clearRect(0, 0, W, H); });
[colorCtx, maskCtx].forEach(function (ctx) {
ctx.font = f; ctx.textBaseline = 'middle'; ctx.textAlign = 'left';
});
// weekday letters
colorCtx.textAlign = maskCtx.textAlign = 'center';
LETTERS.forEach(function (letter, i) {
var x = cellX(i) + CELL / 2, y = PAD_T + HEADER_H / 2;
colorCtx.fillStyle = (i === TODAY && live) ? EMIT : OFF_DAY;
colorCtx.fillText(letter, x, y);
maskCtx.fillStyle = '#f00';
maskCtx.fillText(letter, x, y);
});
colorCtx.textAlign = maskCtx.textAlign = 'left';
// names, icons, and the cross for a missed day
M.rows().forEach(function (row, ri) {
if (!row) return;
var y = rowY(ri) + CELL / 2, on = row.spans.some(function (s) { return s.state === 'open'; });
colorCtx.fillStyle = on ? EMIT : LIT_SDR;
colorCtx.fillText(row.habit.name, PAD_L + ICON_W + ICON_GAP, y);
maskCtx.fillStyle = '#f00';
maskCtx.fillText(row.habit.name, PAD_L + ICON_W + ICON_GAP, y);
var ic = icons[row.habit.slug];
if (ic) {
var s = ICON_W / Math.max(ic.width, ic.height) * 0.86;
var w = ic.width * s, h = ic.height * s;
var ix = PAD_L + (ICON_W - w) / 2, iy = y - h / 2;
tinted(colorCtx, ic, ix, iy, w, h, on ? EMIT : LIT_SDR);
tinted(maskCtx, ic, ix, iy, w, h, '#f00');
}
row.spans.forEach(function (s) {
if (s.state !== 'missed') return;
var cx = cellX(s.first) + CELL / 2, cy = y, a = 6.4;
[colorCtx, maskCtx].forEach(function (ctx, i) {
ctx.save();
ctx.strokeStyle = i ? '#0f0' : RESTING;
ctx.lineWidth = 3.4; ctx.lineCap = 'round';
ctx.beginPath();
ctx.moveTo(cx - a, cy - a); ctx.lineTo(cx + a, cy + a);
ctx.moveTo(cx + a, cy - a); ctx.lineTo(cx - a, cy + a);
ctx.stroke();
ctx.restore();
});
});
});
}
var tintCanvas = null;
function tinted(ctx, img, x, y, w, h, colour) {
if (!tintCanvas) { tintCanvas = document.createElement('canvas'); }
tintCanvas.width = img.width; tintCanvas.height = img.height;
var t = tintCanvas.getContext('2d');
t.clearRect(0, 0, img.width, img.height);
t.drawImage(img, 0, 0);
t.globalCompositeOperation = 'source-in';
t.fillStyle = colour;
t.fillRect(0, 0, img.width, img.height);
t.globalCompositeOperation = 'source-over';
ctx.drawImage(tintCanvas, x, y, w, h);
}
function loadIcons() {
var out = {}, keys = Object.keys(ICONS);
return Promise.all(keys.map(function (slug) {
return new Promise(function (res) {
var im = new Image();
im.crossOrigin = 'anonymous';
im.onload = function () { out[slug] = im; res(); };
im.onerror = function () { res(); };
im.src = iconURL(slug);
});
})).then(function () { return out; });
}

var iconCache = null;
function paint(colorCtx, maskCtx) {
if (iconCache) { drawDecals(colorCtx, maskCtx, iconCache); return Promise.resolve(); }
var fonts = document.fonts && document.fonts.load
? document.fonts.load(TEXT + 'px "GW Inter"').catch(function () {})
: Promise.resolve();
return Promise.all([fonts, loadIcons()]).then(function (r) {
iconCache = r[1] || {};
drawDecals(colorCtx, maskCtx, iconCache);
});
}

M.canvas2d = canvas2d;
M.paint = paint;
})();

/* ===== block 3 of 4 =====================================================
   The geometry. Split here only because a Webflow custom-code block stops at
   10,000 characters; in this repository it is one file.

   This started as a displaced grid sampled from a distance field, which is the
   obvious way to get pockets and the wrong one: a pocket rim is a curve, an
   axis-aligned grid cannot follow it, and at any real zoom every rim came back
   as a row of saw teeth. So the pockets are built as what they are — a lip, a
   wall, a fillet and a floor, swept around each socket's own outline — and the
   card's top face is triangulated with a hole where each one goes. The mesh is
   about 40,000 triangles and exact at every zoom, where the grid was 550,000
   and exact at none. */
(function () {
'use strict';
var M = window.GWA_M;
if (!M) return;
var W = M.W, H = M.H, RADIUS = M.RADIUS, THICK = M.THICK, EDGE = M.EDGE;
var WELLD = M.WELLD, RIM = M.RIM, CELL = M.CELL, INSET = M.INSET;
var PILLTOP = M.PILLTOP, PR = M.PR, RINGW = M.RINGW, RINGTOP = M.RINGTOP;
var EB = 1.5;      // fillet where the side wall meets the underside
var FR = 0.5;      // fillet where a pocket wall meets its floor
var BV = 0.3;      // bevel on the open ring's top edges
var SEG = 14;      // segments per corner, so a socket end is a 28-sided arc
var LIP = 4, FIL = 3;

/* A rounded rectangle as a closed loop of points with their outward normals.
   Offsetting one is exact and costs nothing: shrink both half-extents and the
   radius by the same amount and every point and normal still lines up, which
   is what lets a lip, a wall and a floor share one point count. */
function rrLoop(bx, bz, r, seg) {
var pts = [], k, i, a;
r = Math.max(0, Math.min(r, bx, bz));
var cx = bx - r, cz = bz - r;
var centres = [[cx, cz], [-cx, cz], [-cx, -cz], [cx, -cz]];
for (k = 0; k < 4; k++) {
for (i = 0; i <= seg; i++) {
a = (k + i / seg) * Math.PI / 2;
var nx = Math.cos(a), nz = Math.sin(a);
pts.push({ x: centres[k][0] + nx * r, z: centres[k][1] + nz * r, nx: nx, nz: nz });
}
}
return pts;
}

function Builder() { this.p = []; this.n = []; this.m = []; this.i = []; }
Builder.prototype.vert = function (x, y, z, nx, ny, nz, mat) {
this.p.push(x, y, z); this.n.push(nx, ny, nz); this.m.push(mat);
return this.p.length / 3 - 1;
};
/* One ring of a swept profile: the loop offset inward by `off`, lifted to `y`,
   with a normal built from a radial part and an up part. */
Builder.prototype.ring = function (bx, bz, r, cx, cz, off, y, rad, up, mat) {
var loop = rrLoop(bx - off, bz - off, r - off, SEG), out = [], i;
var len = Math.sqrt(rad * rad + up * up) || 1;
for (i = 0; i < loop.length; i++) {
var p = loop[i];
out.push(this.vert(cx + p.x, y, cz + p.z, p.nx * rad / len, up / len, p.nz * rad / len, mat));
}
return out;
};
Builder.prototype.strip = function (a, b) {
for (var i = 0; i < a.length; i++) {
var j = (i + 1) % a.length;
this.i.push(a[i], b[i], a[j], a[j], b[i], b[j]);
}
};
Builder.prototype.fan = function (ring, cx, cz, y, ny, mat) {
var c = this.vert(cx, y, cz, 0, ny, 0, mat), i;
for (i = 0; i < ring.length; i++) {
var j = (i + 1) % ring.length;
if (ny > 0) this.i.push(c, ring[i], ring[j]); else this.i.push(c, ring[j], ring[i]);
}
};

/* A pocket: rounded-over lip, wall, floor fillet, floor. Everything is driven
   off the socket's own outline, so the opening is exactly the rectangle the
   2-D widget draws. */
function pocket(B, bx, bz, r, cx, cz, mat) {
var prev = null, i, b, off, y;
for (i = 0; i <= LIP; i++) {
b = i / LIP * Math.PI / 2;
off = RIM * Math.sin(b);
y = THICK - RIM + RIM * Math.cos(b);
var ring = B.ring(bx, bz, r, cx, cz, off, y, -Math.sin(b), Math.cos(b), mat);
if (prev) B.strip(prev, ring);
prev = ring;
}
var floorY = THICK - WELLD;
var wall = B.ring(bx, bz, r, cx, cz, RIM, floorY + FR, -1, 0, mat);
B.strip(prev, wall);
prev = wall;
for (i = 1; i <= FIL; i++) {
var g = i / FIL * Math.PI / 2;
var ring2 = B.ring(bx, bz, r, cx, cz, RIM + FR - FR * Math.cos(g), floorY + FR - FR * Math.sin(g),
-Math.cos(g), Math.sin(g), mat);
B.strip(prev, ring2); prev = ring2;
}
B.fan(prev, cx, cz, floorY, 1, mat);
}

/* A finished mark: a pill seated in its pocket, proud of the floor and just
   below the face. */
function pill(B, bx, bz, r, cx, cz) {
var d = RIM + INSET;                                 // clear the pocket wall, not the opening
var pb = bx - d, pz = bz - d, pr = r - d, prev = null, i;
var top = B.ring(pb, pz, pr, cx, cz, PR, PILLTOP, 0, 1, 2);
B.fan(top, cx, cz, PILLTOP, 1, 2);
prev = top;
for (i = 1; i <= LIP; i++) {
var b = i / LIP * Math.PI / 2;
var ring = B.ring(pb, pz, pr, cx, cz, PR - PR * Math.sin(b), PILLTOP - PR + PR * Math.cos(b),
Math.sin(b), Math.cos(b), 2);
B.strip(prev, ring); prev = ring;
}
B.strip(prev, B.ring(pb, pz, pr, cx, cz, 0, THICK - WELLD, 1, 0, 2));
}

/* An open mark: a ring standing on the pocket floor, bevelled so its top edge
   catches a light. */
function openRing(B, bx, bz, r, cx, cz) {
var d = RIM + INSET;
var ob = bx - d, oz = bz - d, orr = r - d, floorY = THICK - WELLD;
var a = B.ring(ob, oz, orr, cx, cz, 0, floorY, 1, 0, 3);
var b = B.ring(ob, oz, orr, cx, cz, 0, RINGTOP - BV, 1, 0, 3);
B.strip(a, b);
var c = B.ring(ob, oz, orr, cx, cz, BV, RINGTOP, 1, 1, 3);
B.strip(b, c);
var d = B.ring(ob, oz, orr, cx, cz, RINGW - BV, RINGTOP, 0, 1, 3);
B.strip(c, d);
var e = B.ring(ob, oz, orr, cx, cz, RINGW, RINGTOP - BV, -1, 1, 3);
B.strip(d, e);
var f = B.ring(ob, oz, orr, cx, cz, RINGW, floorY, -1, 0, 3);
B.strip(e, f);
}

function build(THREE) {
var B = new Builder(), i, prev = null;

// the slab: top-edge fillet, side wall, bottom fillet, underside
for (i = 0; i <= LIP; i++) {
var phi = i / LIP * Math.PI / 2;
var off = EDGE - EDGE * Math.sin(phi);
var ring = B.ring(W / 2, H / 2, RADIUS, 0, 0, off, THICK - EDGE + EDGE * Math.cos(phi),
Math.sin(phi), Math.cos(phi), 0);
if (prev) B.strip(prev, ring);
prev = ring;
}
var low = B.ring(W / 2, H / 2, RADIUS, 0, 0, 0, EB, 1, 0, 0);
B.strip(prev, low); prev = low;
for (i = 1; i <= FIL; i++) {
var g = i / FIL * Math.PI / 2;
var ring2 = B.ring(W / 2, H / 2, RADIUS, 0, 0, EB - EB * Math.cos(g), EB - EB * Math.sin(g),
Math.cos(g), -Math.sin(g), 0);
B.strip(prev, ring2); prev = ring2;
}
B.fan(prev, 0, 0, 0, -1, 0);

// every socket, and what sits in it
var holes = [];
M.sockets().forEach(function (s) {
var bx = s.w / 2, bz = CELL / 2, r = CELL / 2;
var cx = s.x + bx - W / 2, cz = s.z + bz - H / 2;
pocket(B, bx, bz, r, cx, cz, 1);
if (s.kind === 2) pill(B, bx, bz, r, cx, cz);
else if (s.kind === 3) openRing(B, bx, bz, r, cx, cz);
holes.push({ bx: bx, bz: bz, r: r, cx: cx, cz: cz });
});

// the top face, with a hole where each pocket opens
var shape = new THREE.Shape(rrLoop(W / 2 - EDGE, H / 2 - EDGE, RADIUS - EDGE, SEG)
.map(function (p) { return new THREE.Vector2(p.x, p.z); }));
shape.holes = holes.map(function (o) {
var pts = rrLoop(o.bx, o.bz, o.r, SEG).map(function (p) {
return new THREE.Vector2(o.cx + p.x, o.cz + p.z);
});
pts.reverse();
return new THREE.Path(pts);
});
var face = new THREE.ShapeGeometry(shape);
var fp = face.attributes.position.array, fi = face.index.array;
var base = B.p.length / 3;
for (i = 0; i < fp.length; i += 3) B.vert(fp[i], THICK, fp[i + 1], 0, 1, 0, 0);
for (i = 0; i < fi.length; i += 3) B.i.push(base + fi[i], base + fi[i + 2], base + fi[i + 1]);
face.dispose();

var geo = new THREE.BufferGeometry();
geo.setAttribute('position', new THREE.Float32BufferAttribute(B.p, 3));
geo.setAttribute('normal', new THREE.Float32BufferAttribute(B.n, 3));
geo.setAttribute('aMat', new THREE.Float32BufferAttribute(B.m, 1));
geo.setIndex(B.i);
return geo;
}

window.GWA_G = { build: build };
})();

/* ===== block 4 of 4 ===================================================== */
(function () {
'use strict';
var M = window.GWA_M, G = window.GWA_G;
if (!M || !G) return;
var W = M.W, H = M.H, THICK = M.THICK, WELLD = M.WELLD;

var VERT = [
'attribute float aMat;',
'varying vec3 vN, vWorld;',
'varying vec2 vP;',
'varying float vMat;',
'void main(){',
'  vMat = aMat;',
'  vP = vec2(position.x+' + (W / 2).toFixed(1) + ', position.z+' + (H / 2).toFixed(1) + ');',
'  vN = mat3(modelMatrix)*normal;',
'  vec4 wp = modelMatrix*vec4(position,1.0);',
'  vWorld = wp.xyz;',
'  gl_Position = projectionMatrix*viewMatrix*wp;',
'}'
].join('\n');

/* The lettering and the icons are the one thing here that is not geometry:
   they are a relief read off a mask texture and folded into the normal. A
   quarter of a millimetre of silkscreen does not need its own triangles, and
   saying so is cheaper than pretending otherwise. */
var FRAG = [
'precision highp float;',
'const float W=' + W.toFixed(1) + ';',
'const float H=' + H.toFixed(1) + ';',
'const float THICK=' + THICK.toFixed(2) + ';',
'const float WELLD=' + WELLD.toFixed(2) + ';',
'const float RAISE=' + M.RAISE.toFixed(2) + ';',
'const float ENGRAVE=' + M.ENGRAVE.toFixed(2) + ';',
'uniform sampler2D uColor, uMask;',
'uniform vec3 uCam;',
'varying vec3 vN, vWorld;',
'varying vec2 vP;',
'varying float vMat;',
'vec3 s2l(vec3 c){ return pow(c, vec3(2.2)); }',
'float rel(vec2 uv){ vec2 m = texture2D(uMask, uv).rg; return RAISE*m.r-ENGRAVE*m.g; }',
'void main(){',
'  vec2 uv = vP/vec2(W,H);',
'  vec3 n = normalize(vN);',
'  if(n.y > 0.92){',
'    float e = 0.32;',
'    float rx = rel(uv+vec2(e/W,0.0))-rel(uv-vec2(e/W,0.0));',
'    float rz = rel(uv+vec2(0.0,e/H))-rel(uv-vec2(0.0,e/H));',
'    n = normalize(n + vec3(-rx/(2.0*e), 0.0, -rz/(2.0*e)));',
'  }',
'  vec3 base; float sh, f0;',
'  if(vMat<0.5){ base=s2l(vec3(0.125)); sh=16.0; f0=0.05; }',
'  else if(vMat<1.5){ base=s2l(vec3(0.098)); sh=12.0; f0=0.05; }',
'  else if(vMat<2.5){ base=s2l(vec3(0.851)); sh=48.0; f0=0.07; }',
'  else { base=s2l(vec3(1.0)); sh=90.0; f0=0.09; }',
'  if(vMat<0.5){ vec4 d = texture2D(uColor, uv); base = mix(base, s2l(d.rgb), d.a); }',
'  vec3 v = normalize(uCam-vWorld);',
'  float ao = mix(0.42, 1.0, smoothstep(THICK-WELLD-0.6, THICK-0.3, vWorld.y));',
'  vec3 sky = vec3(0.16,0.17,0.20), ground = vec3(0.012,0.012,0.015);',
'  vec3 col = base*mix(ground, sky, n.y*0.5+0.5)*ao;',
'  vec3 L1 = normalize(vec3(-0.45, 0.82, 0.36));',
'  vec3 L2 = normalize(vec3(0.72, 0.42, -0.30));',
'  vec3 C1 = vec3(1.0,0.99,0.96)*1.15, C2 = vec3(0.55,0.62,0.78)*0.55;',
'  col += base*max(dot(n,L1),0.0)*C1*ao;',
'  col += base*max(dot(n,L2),0.0)*C2*ao;',
'  float fres = pow(1.0-max(dot(n,v),0.0), 5.0);',
'  float F = f0+(1.0-f0)*fres;',
'  float norm = (sh+8.0)/28.0;',
'  col += C1*pow(max(dot(n,normalize(L1+v)),0.0), sh)*F*norm*ao;',
'  col += C2*pow(max(dot(n,normalize(L2+v)),0.0), sh)*F*norm*ao*0.5;',
'  col += vec3(0.30,0.34,0.42)*fres*0.12;',
'  col = col/(col+vec3(1.0));',
'  gl_FragColor = vec4(pow(col, vec3(1.0/2.2)), 1.0);',
'}'
].join('\n');

function boot(THREE, host) {
var small = window.matchMedia('(max-width: 767px)').matches;
var colour = M.canvas2d(), mask = M.canvas2d();
var uColor = new THREE.CanvasTexture(colour.c);
var uMask = new THREE.CanvasTexture(mask.c);
[uColor, uMask].forEach(function (t) {
t.flipY = false;                                    // vP.y = 0 is the canvas's first row, not its last
t.wrapS = t.wrapT = THREE.ClampToEdgeWrapping;
t.minFilter = THREE.LinearMipmapLinearFilter;
t.anisotropy = 8;
if ('colorSpace' in t) t.colorSpace = THREE.NoColorSpace;
});

/* Both sides, and the normal is taken from the attribute rather than from
   gl_FrontFacing. Every ring carries the outward normal its profile says it
   has, and a swept strip's winding flips depending on which of its two loops
   is the outer one — reading the facing instead turned every pocket floor and
   every pill upside down and lit them with the ground colour. */
var mat = new THREE.ShaderMaterial({
uniforms: { uMask: { value: uMask }, uColor: { value: uColor }, uCam: { value: new THREE.Vector3() } },
vertexShader: VERT, fragmentShader: FRAG, side: THREE.DoubleSide
});
var card = new THREE.Mesh(G.build(THREE), mat);
var scene = new THREE.Scene();
scene.add(card);

/* The CSS card carries a box-shadow that slides with the tilt. This is that
   shadow: one quad under the slab, a blurred rounded rectangle, moved the
   opposite way to the lean. Without it the card floats. */
var shadowGeo = new THREE.PlaneGeometry(M.W + 300, M.H + 300);
shadowGeo.rotateX(-Math.PI / 2);
/* It hangs 70 units down, not 8. A 7-degree lean on both axes drops a corner
   about 42 units, so a shadow plane any closer gets *intersected* by the card
   and shows through it as a hard diagonal wedge. Turning off depth testing is
   not the fix either: a transparent object is drawn after the opaque ones, so
   it then paints over the whole card and dims it. Depth does the right thing
   once nothing intersects. */
var shadow = new THREE.Mesh(shadowGeo, new THREE.ShaderMaterial({
transparent: true, depthWrite: false,
vertexShader: [
'varying vec2 vXZ;',
'void main(){ vXZ = vec2(position.x, position.z);',
'gl_Position = projectionMatrix*modelViewMatrix*vec4(position,1.0); }'
].join('\n'),
fragmentShader: [
'precision mediump float;',
'varying vec2 vXZ;',
'float sdRR(vec2 p, vec2 b, float r){ vec2 q=abs(p)-b+r; return min(max(q.x,q.y),0.0)+length(max(q,0.0))-r; }',
'void main(){',
'  float d = sdRR(vXZ, vec2(' + (M.W / 2).toFixed(1) + ',' + (M.H / 2).toFixed(1) + '), ' + M.RADIUS.toFixed(1) + ');',
'  float a = 1.0-smoothstep(-52.0, 52.0, d);',
'  gl_FragColor = vec4(0.0, 0.0, 0.0, a*a*0.62);',
'}'
].join('\n')
}));
shadow.renderOrder = -1;
scene.add(shadow);

var camera = new THREE.PerspectiveCamera(30, 1, 10, 4000);
var renderer = new THREE.WebGLRenderer({ antialias: true, alpha: true, powerPreference: 'high-performance' });
renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, small ? 1.75 : 2));
if ('outputColorSpace' in renderer) renderer.outputColorSpace = THREE.LinearSRGBColorSpace;
host.appendChild(renderer.domElement);

/* ---- the 2-D widget's movement, exactly ----
   Not an orbit. The CSS version tilts the card toward the pointer by at most
   7 degrees, eases at 0.055 a frame, and returns to flat when the pointer
   leaves the document or the tab is hidden — and it does none of that without
   a fine pointer, or under prefers-reduced-motion. Those numbers are lifted
   from Website/week-widget/webflow/footer.html so the two pages move alike.

   The camera does not move at all. It sits square on at a fixed 900 units,
   which is the CSS `perspective: 900px` at --s: 1 with a 338-unit card, so the
   foreshortening matches too; framing is done by fitting the field of view
   rather than by dollying, which would change the perspective. */
var MAX = 7 * Math.PI / 180, EASE = 0.055, PERSP = 900;
var tiltX = 0, tiltZ = 0, wantX = 0, wantZ = 0;
var fine = window.matchMedia('(hover: hover) and (pointer: fine)');
var still = window.matchMedia('(prefers-reduced-motion: reduce)');
function tiltOn() { return fine.matches && !still.matches; }

/* Fit by field of view, at the tilt extremes, so the framing does not breathe
   while the card moves. */
var CORNERS = [];
(function () {
for (var sx = -1; sx <= 1; sx += 2) for (var sz = -1; sz <= 1; sz += 2) for (var sy = 0; sy <= 1; sy++) {
CORNERS.push([sx * W / 2, sy * THICK - THICK * 0.4, sz * H / 2]);
}
})();
function fitFov() {
var need = 0, i, k;
for (k = 0; k < 4; k++) {
var ax = (k & 1 ? 1 : -1) * MAX, az = (k & 2 ? 1 : -1) * MAX;
var ca = Math.cos(ax), sa = Math.sin(ax), cb = Math.cos(az), sb = Math.sin(az);
for (i = 0; i < CORNERS.length; i++) {
var p = CORNERS[i];
// rotate about Z then about X, the same order the card is drawn with
var x = p[0] * cb - p[1] * sb, y = p[0] * sb + p[1] * cb, z = p[2];
var y2 = y * ca - z * sa, z2 = y * sa + z * ca;
var depth = PERSP - y2;                                   // the camera looks down -Y
if (depth < 1) depth = 1;
need = Math.max(need, Math.abs(z2) / depth, Math.abs(x) / (camera.aspect * depth));
}
}
return 2 * Math.atan(need * 1.06) * 180 / Math.PI;
}
function resize() {
var w = host.clientWidth, h = host.clientHeight;
if (!w || !h) return;
renderer.setSize(w, h, false);
camera.aspect = w / h;
camera.fov = Math.min(fitFov(), 70);
camera.updateProjectionMatrix();
}
camera.position.set(0, PERSP, 0);
camera.up.set(0, 0, -1);                                     // screen up is -Z, as in the CSS card
camera.lookAt(0, THICK * 0.4, 0);

document.addEventListener('pointermove', function (e) {
if (!tiltOn() || (e.pointerType && e.pointerType !== 'mouse')) return;
var r = host.getBoundingClientRect();
var dx = (e.clientX - (r.left + r.width / 2)) / (window.innerWidth / 2);
var dy = (e.clientY - (r.top + r.height / 2)) / (window.innerHeight / 2);
wantZ = -Math.max(-1, Math.min(1, dx)) * MAX;              // CSS rotateY
wantX = -Math.max(-1, Math.min(1, dy)) * MAX;              // CSS rotateX
}, { passive: true });
document.addEventListener('pointerleave', function () { wantX = wantZ = 0; });
document.addEventListener('visibilitychange', function () { if (document.hidden) wantX = wantZ = 0; });
still.addEventListener('change', function () { if (!tiltOn()) wantX = wantZ = 0; });

/* ---- tapping a mark ----
   The same rule as the 2-D widget: an open mark can be finished and today's
   own finished mark can be undone. Everything else ignores the tap. A hit is
   resolved against the card's own plane, so it stays right while it is tilted. */
var ray = new THREE.Raycaster(), ndc = new THREE.Vector2(), local = new THREE.Vector3();
function socketAt(e) {
var r = host.getBoundingClientRect();
ndc.set((e.clientX - r.left) / r.width * 2 - 1, -((e.clientY - r.top) / r.height * 2 - 1));
ray.setFromCamera(ndc, camera);
var hit = ray.intersectObject(card, false)[0];
if (!hit) return null;
card.worldToLocal(local.copy(hit.point));
var px = local.x + W / 2, pz = local.z + H / 2, list = M.sockets(), i;
for (i = 0; i < list.length; i++) {
var t = list[i];
if (px >= t.x && px <= t.x + t.w && pz >= t.z && pz <= t.z + M.CELL) return t;
}
return null;
}
function repaint() {
card.geometry.dispose();
card.geometry = G.build(THREE);
M.paint(colour.ctx, mask.ctx);
uColor.needsUpdate = true; uMask.needsUpdate = true;
}
var downAt = null;
host.addEventListener('pointerdown', function (e) { downAt = { x: e.clientX, y: e.clientY }; });
host.addEventListener('pointerup', function (e) {
if (!downAt || Math.hypot(e.clientX - downAt.x, e.clientY - downAt.y) > 8) { downAt = null; return; }
downAt = null;
var t = socketAt(e);
if (t && t.tappable && M.toggle(t.row)) repaint();
});
host.addEventListener('pointermove', function (e) {
if (!fine.matches) return;
var t = socketAt(e);
host.style.cursor = (t && t.tappable) ? 'pointer' : 'default';
}, { passive: true });

var visible = true;
if (window.IntersectionObserver) {
new IntersectionObserver(function (es) { visible = es[0].isIntersecting; }).observe(host);
}
function frame() {
requestAnimationFrame(frame);
if (!visible) return;
tiltX += (wantX - tiltX) * EASE;
tiltZ += (wantZ - tiltZ) * EASE;
card.rotation.set(tiltX, 0, tiltZ);
shadow.position.set(-tiltZ / MAX * 20, -70, -tiltX / MAX * 20);
mat.uniforms.uCam.value.copy(camera.position);
renderer.render(scene, camera);
}

M.paint(colour.ctx, mask.ctx).then(function () {
uColor.needsUpdate = true; uMask.needsUpdate = true;
});

if (host.dataset.debug) {
window.GWA = { camera: camera, mesh: card, tilt: function (x, z) { wantX = x; wantZ = z; } };
var q = new URLSearchParams(location.search);
if (q.has('tx')) wantX = tiltX = parseFloat(q.get('tx')) * MAX;
if (q.has('tz')) wantZ = tiltZ = parseFloat(q.get('tz')) * MAX;
}
window.addEventListener('resize', resize);
if (window.ResizeObserver) new ResizeObserver(resize).observe(host);
resize();
frame();
host.dataset.ready = '1';
}

function start() {
var host = document.getElementById('gwa');
if (!host) return;
if (!window.THREE) { host.dataset.error = 'three'; return; }
var gl = document.createElement('canvas').getContext('webgl2') ||
document.createElement('canvas').getContext('webgl');
if (!gl) { host.dataset.error = 'webgl'; return; }
boot(window.THREE, host);
}
if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start);
else start();
})();
