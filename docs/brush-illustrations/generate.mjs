// Procedural concept swatches for the brush-graph report. These do not render Painter strokes.
// Run `node docs/brush-illustrations/generate.mjs` to regenerate the tracked SVGs.
import { writeFileSync } from 'node:fs';

const seed = 0x62727573;
let state = seed;
function random() {
  state ^= state << 13;
  state ^= state >>> 17;
  state ^= state << 5;
  return (state >>> 0) / 0x100000000;
}
function circle(x, y, r, color, opacity = 1) {
  return `<circle cx="${x.toFixed(1)}" cy="${y.toFixed(1)}" r="${r.toFixed(1)}" fill="${color}" opacity="${opacity.toFixed(2)}"/>`;
}
function ellipse(x, y, rx, ry, color, opacity = 1) {
  return `<ellipse cx="${x.toFixed(1)}" cy="${y.toFixed(1)}" rx="${rx}" ry="${ry}" fill="${color}" opacity="${opacity.toFixed(2)}"/>`;
}
function pair(name, leftTitle, rightTitle, left, right, defs = '') {
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 960 230" role="img" aria-label="${leftTitle} compared with ${rightTitle}">
  <defs>${defs}</defs>
  <rect x="1" y="1" width="958" height="228" rx="9" fill="#fffdf9" stroke="#b9b7b3"/>
  <path d="M480 1V229" stroke="#b9b7b3"/>
  <text x="24" y="32" font-size="20" font-family="sans-serif" fill="#252c36">${leftTitle}</text>
  <text x="504" y="32" font-size="20" font-family="sans-serif" fill="#252c36">${rightTitle}</text>
  ${left}
  <g transform="translate(480 0)">${right}</g>
</svg>\n`;
  writeFileSync(new URL(`${name}.svg`, import.meta.url), svg);
}

// A dry stroke with separately seeded specks versus an opaque, uniform-width mark.
let pencil = '';
for (let x = 42; x < 442; x += 2.5) {
  const center = 120 + 18 * Math.sin((x - 44) / 60);
  const pressure = 0.35 + 0.65 * Math.sin(Math.PI * (x - 36) / 416);
  for (let k = 0; k < 8; k++) {
    const dx = (random() + random() - 1) * 5 * pressure;
    const dy = (random() + random() + random() - 1.5) * 13 * pressure;
    pencil += circle(x + dx, center + dy, 0.8 + random() * 2.4 * pressure, '#333d49', 0.38 + random() * 0.55);
  }
}
pair('pencil', 'Seeded granular marks', 'Uniform opaque stroke', pencil,
  '<path d="M42 120 C105 83 145 103 190 132 S278 139 325 115 S394 94 442 128" fill="none" stroke="#3d4752" stroke-width="18" stroke-linecap="round"/>');

// The first route keeps only overlaps of two tip masks; the second has two independent colored brush outputs.
let intersect = '';
for (let x = 48; x < 454; x += 2.3) {
  for (let y = 68; y < 186; y += 2.6) {
    const jitterX = (random() - 0.5) * 4;
    const jitterY = (random() - 0.5) * 4;
    const px = x + jitterX;
    const py = y + jitterY;
    const primary = [93, 166, 239, 312, 385].some(cx => ((px - cx) / 39) ** 2 + ((py - (127 + 9 * Math.sin(cx / 50))) / 30) ** 2 < 1);
    const secondary = [73, 133, 212, 271, 340, 412].some(cx => ((px - cx) / 23) ** 2 + ((py - (133 + 11 * Math.sin(cx / 48))) / 39) ** 2 < 1);
    if (primary && secondary && random() > 0.36) {
      intersect += circle(px, py, 0.9 + random() * 1.5, '#375b70', 0.28 + random() * 0.5);
    }
  }
}
let layered = '';
for (let x = 56; x < 432; x += 16) {
  layered += ellipse(x, 112 + 17 * Math.sin(x / 47), 21, 16, '#336b8a', 0.22);
}
for (let x = 63; x < 428; x += 21) {
  layered += ellipse(x, 138 - 15 * Math.cos(x / 56), 17, 20, '#bb7244', 0.32);
}
pair('dual-brush', 'Intersected tip masks', 'Two complete brush outputs', intersect, layered);

// Clone copies a fixed, identifiable source pattern. Smudge drags color already on the destination.
const cloneDefs = '<pattern id="source" width="31" height="30" patternUnits="userSpaceOnUse"><rect width="31" height="30" fill="#e6d9bc"/><path d="M0 15H31M15 0V30" stroke="#72889b" stroke-width="3" opacity=".65"/><circle cx="15" cy="15" r="5" fill="#bd725a"/></pattern><linearGradient id="drag" x1="0" x2="1"><stop stop-color="#c45452" stop-opacity=".65"/><stop offset="1" stop-color="#c45452" stop-opacity="0"/></linearGradient>';
const clone = '<rect x="38" y="65" width="116" height="117" rx="7" fill="url(#source)" stroke="#72889b"/><path d="M167 127H220" stroke="#67717c" stroke-width="2" stroke-dasharray="5 5"/><path d="M215 122L223 127 215 132" fill="none" stroke="#67717c" stroke-width="2"/><path d="M248 154 C289 72 372 80 433 124" fill="none" stroke="#72889b" stroke-width="35" stroke-linecap="round" opacity=".15"/><path d="M248 154 C289 72 372 80 433 124" fill="none" stroke="url(#source)" stroke-width="24" stroke-linecap="round"/>';
let smudge = '<rect x="38" y="76" width="112" height="102" rx="7" fill="#b75452" opacity=".83"/><path d="M142 91 C224 72 302 105 429 104 M143 120 C230 140 320 120 427 140 M143 157 C228 131 323 175 427 161" stroke="url(#drag)" stroke-width="24" fill="none" stroke-linecap="round"/>';
for (let i = 0; i < 28; i++) {
  const x = 147 + random() * 260;
  const y = 83 + random() * 86;
  smudge += circle(x, y, 1 + random() * 4, '#b75452', 0.1 + 0.55 * (1 - (x - 147) / 280));
}
pair('canvas-read', 'Clone: sample a source', 'Smudge: drag local color', clone, smudge, cloneDefs);

// A hypothetical wet-front expansion reaches across a tile boundary; stamping only cannot do so.
const washDefs = '<radialGradient id="wash"><stop stop-color="#5b8492" stop-opacity=".52"/><stop offset=".68" stop-color="#658f9c" stop-opacity=".31"/><stop offset=".89" stop-color="#b88575" stop-opacity=".20"/><stop offset="1" stop-color="#b88575" stop-opacity="0"/></radialGradient>';
let spread = '';
for (let i = 0; i < 11; i++) {
  const x = 125 + i * 22;
  spread += ellipse(x, 128 + Math.sin(i * 0.8) * 12, 64, 48, 'url(#wash)', 0.50);
}
spread += '<path d="M242 65V193" stroke="#78848b" stroke-dasharray="6 5" stroke-width="2"/>';
let stamps = '<path d="M242 65V193" stroke="#78848b" stroke-dasharray="6 5" stroke-width="2"/>';
for (let i = 0; i < 6; i++) {
  stamps += circle(74 + i * 30, 125 + 14 * Math.sin(i * 0.85), 21, '#5b8492', 0.45);
}
pair('wet-front', 'Conceptual wet-front reach', 'Stamp-only: no transport', spread, stamps, washDefs);
