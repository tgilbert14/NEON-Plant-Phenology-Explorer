#!/usr/bin/env node

import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";

const root = resolve(import.meta.dirname, "..");
const html = readFileSync(resolve(root, "docs/index.html"), "utf8");

function fail(message) {
  console.error(`FAIL: ${message}`);
  process.exitCode = 1;
}

function count(pattern) {
  return (html.match(pattern) || []).length;
}

function requireText(pattern, message) {
  if (!pattern.test(html)) fail(message);
}

function sha256(buffer) {
  return createHash("sha256").update(buffer).digest("hex");
}

function dimensions(buffer) {
  if (buffer.subarray(0, 8).equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]))) {
    return [buffer.readUInt32BE(16), buffer.readUInt32BE(20)];
  }
  if (buffer[0] === 0xff && buffer[1] === 0xd8) {
    let offset = 2;
    while (offset + 9 < buffer.length) {
      if (buffer[offset] !== 0xff) { offset += 1; continue; }
      const marker = buffer[offset + 1];
      if (marker === 0xd8 || marker === 0xd9) { offset += 2; continue; }
      const length = buffer.readUInt16BE(offset + 2);
      if ([0xc0, 0xc1, 0xc2, 0xc3, 0xc5, 0xc6, 0xc7, 0xc9, 0xca, 0xcb, 0xcd, 0xce, 0xcf].includes(marker)) {
        return [buffer.readUInt16BE(offset + 7), buffer.readUInt16BE(offset + 5)];
      }
      if (length < 2) break;
      offset += 2 + length;
    }
  }
  throw new Error("unsupported or malformed image");
}

if (count(/<h1\b/gi) !== 1) fail("cover must contain exactly one h1");
if (count(/<main\b/gi) !== 1) fail("cover must contain exactly one main landmark");
requireText(/class="skip-link"[^>]+href="#main"/, "missing skip link to main content");
requireText(/<nav class="site-nav shell" aria-label="Primary navigation">/, "primary navigation needs an accessible label");
requireText(/aria-label="NEON Explorer Suite applications"/, "suite navigation needs an accessible label");
requireText(/aria-current="page"/, "current suite application must be identified");
requireText(/<link rel="canonical" href="https:\/\/tgilbert14\.github\.io\/NEON-Plant-Phenology-Explorer\/">/, "canonical URL is missing or incorrect");
requireText(/og-image-v2\.jpg/, "social card must use og-image-v2.jpg");
requireText(/property="og:image:width" content="1200"/, "Open Graph width must be 1200");
requireText(/property="og:image:height" content="630"/, "Open Graph height must be 630");
requireText(/property="og:image:alt" content="[^"]+"/, "Open Graph image needs alternative text");
requireText(/name="twitter:image:alt" content="[^"]+"/, "Twitter image needs alternative text");
requireText(/<source media="\(max-width: 740px\)" srcset="assets\/phenology-seasonal-mobile-v1\.jpg">/, "mobile hero image source is missing");
requireText(/src="assets\/phenology-seasonal-hero-v1\.jpg"/, "desktop hero image is missing");
requireText(/<img[^>]+alt="[^"]+"/, "hero image needs alternative text");
requireText(/This explorer can/i, "cover must state what the app can answer");
requireText(/This explorer cannot/i, "cover must state what the app cannot answer");
requireText(/Suite role/i, "cover must state the app's suite role");
requireText(/held from Driver voting/i, "cover must state the current Driver disposition");
requireText(/Bundle-backed snapshot through 2024/i, "cover must identify the bundled data vintage");
requireText(/2016–2024/, "cover must identify the verified snapshot range");
requireText(/DP1\.10055\.001/g, "cover must identify the source data product");

const suiteUrls = [
  "NEON-Driver-Cascade", "NEON-Small-Mammal-Tracker-App",
  "NEON-Plant-Phenology-Explorer", "NEON-Plant-Diversity",
  "NEON-Vegetation-Structure-Explorer", "NEON-Ground-Beetle-Tracker",
  "NEON-Mosquito-Pulse", "NEON-Breeding-Birds",
  "NEON-WaterChemistry-Analyte-Viewer-App", "NEON-My-Little-Inverts"
];
for (const slug of suiteUrls) {
  if (!html.includes(`https://tgilbert14.github.io/${slug}/`)) fail(`missing suite URL: ${slug}`);
}

for (const forbidden of [
  /fonts\.googleapis\.com/i, /fonts\.gstatic\.com/i, /cdnjs\.cloudflare\.com/i,
  /unpkg\.com/i, /jsdelivr\.net/i, /fetch\s*\(/i, /mode\s*:\s*["']no-cors["']/i,
  /http:\/\//i
]) {
  if (forbidden.test(html)) fail(`forbidden external runtime or insecure pattern: ${forbidden}`);
}

const assets = [
  ["docs/assets/phenology-seasonal-hero-v1-source.png", 1666, 944, "5bdd6989e8c02bd6318dc01395ac7fd7589580ebe0dc282e33abb33d330f5250"],
  ["docs/assets/phenology-seasonal-hero-v1.jpg", 1666, 944, "6111a72cfc178a3b0751d44a99ebee3f15c71b8c766d45ec9cfd1615a17ef317"],
  ["docs/assets/phenology-seasonal-mobile-v1-source.png", 864, 1821, "17fd2d13a56315967a93480a8f9fda930c438834650fb9df023ee15ffe6ce6bc"],
  ["docs/assets/phenology-seasonal-mobile-v1.jpg", 864, 1821, "b11c9940e56b1c2d49f86b6ea01d6ef6ad5ad82f2ab020d2d03d381711771576"],
  ["docs/og-image-v2.jpg", 1200, 630, "a9415052fab1af2ba6d2aebb4c247ebefaaaaecf8d9cdb8a9d3dc28abb9e62ed"]
];

for (const [file, expectedWidth, expectedHeight, expectedHash] of assets) {
  try {
    const buffer = readFileSync(resolve(root, file));
    const [width, height] = dimensions(buffer);
    if (width !== expectedWidth || height !== expectedHeight) {
      fail(`${file} is ${width}x${height}; expected ${expectedWidth}x${expectedHeight}`);
    }
    const actualHash = sha256(buffer);
    if (actualHash !== expectedHash) fail(`${file} hash changed: ${actualHash}`);
  } catch (error) {
    fail(`${file}: ${error.message}`);
  }
}

if (!process.exitCode) console.log("OK: cover, suite, accessibility, claim, and image contracts passed");
