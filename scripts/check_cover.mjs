#!/usr/bin/env node

import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";

const root = resolve(import.meta.dirname, "..");
const html = readFileSync(resolve(root, "docs/index.html"), "utf8");
const ui = readFileSync(resolve(root, "ui.R"), "utf8");
const css = readFileSync(resolve(root, "www/phe.css"), "utf8");

function fail(message) {
  console.error(`FAIL: ${message}`);
  process.exitCode = 1;
}

function count(pattern, source = html) {
  return (source.match(pattern) || []).length;
}

function requireText(pattern, message, source = html) {
  if (!pattern.test(source)) fail(message);
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
requireText(/<html\s+lang="en">/i, "document language must be English");
requireText(/class="skip"[^>]+href="#main"/, "missing skip link to the poster");
requireText(/<nav\b[^>]+aria-label="NEON Explorer Suite"/, "suite route needs an accessible label");
requireText(/<link rel="canonical" href="https:\/\/tgilbert14\.github\.io\/NEON-Plant-Phenology-Explorer\/">/, "canonical URL is missing or incorrect");
requireText(/og-image-v2\.jpg/, "social card must use og-image-v2.jpg");
requireText(/property="og:image:width" content="1200"/, "Open Graph width must be 1200");
requireText(/property="og:image:height" content="630"/, "Open Graph height must be 630");
requireText(/property="og:image:alt" content="[^"]+"/, "Open Graph image needs alternative text");
requireText(/name="twitter:image:alt" content="[^"]+"/, "Twitter image needs alternative text");
requireText(/<source media="\(max-width: 700px\)" srcset="assets\/phenology-seasonal-mobile-v1\.jpg">/, "mobile poster image source is missing");
requireText(/src="assets\/phenology-seasonal-hero-v1\.jpg"/, "desktop hero image is missing");
requireText(/<img[^>]+alt="[^"]+"/, "hero image needs alternative text");
requireText(/Read the seasons\./i, "poster hook is missing");
requireText(/Follow tagged plants through the turning year\./i, "poster promise is missing");
requireText(/Pick a place/i, "poster CTA must be contextual");
for (const [source, surface] of [[html, "Pages"], [ui, "in-app"]]) {
  if (/Editorial illustration—not a field photograph or data record\./i.test(source)) {
    fail(`${surface} poster must not restore the visible illustration disclaimer`);
  }
  if (/<figcaption\b/i.test(source)) {
    fail(`${surface} poster must not restore a visible art caption`);
  }
}
requireText(/fixed roster of tagged plants/i, "cover must state the observation scope");
requireText(/not plant abundance, productivity/i, "cover must state the primary claim boundary");
requireText(/DP1\.10055\.001/g, "cover must identify the source data product");
if (count(/https:\/\/tgilbert14\.github\.io\/NEON-Driver-Cascade\//g) !== 1) {
  fail("poster face must contain exactly one Driver route");
}
for (const forbiddenPosterBlock of [/hero-facts/i, /splash-contract/i, /release receipt/i, /suite-app/i]) {
  if (forbiddenPosterBlock.test(html)) fail(`poster contains a retired report block: ${forbiddenPosterBlock}`);
}

requireText(/phenology_poster\s*<-\s*function/, "in-app Living Poster component is missing", ui);
requireText(/Read the seasons\./i, "in-app poster hook diverges from Pages", ui);
requireText(/Follow tagged plants through the turning year\./i, "in-app poster promise diverges from Pages", ui);
requireText(/href = "#site-picker-start"/, "in-app poster CTA must route to the picker", ui);
requireText(/id = "site-picker-start"[^\n]+tabindex = "-1"/, "in-app picker target must be focusable", ui);
requireText(/phenology-seasonal-mobile-v1\.jpg/, "in-app poster needs a responsive mobile asset", ui);
if (count(/NEON-Driver-Cascade\//g, ui) !== 1) fail("in-app poster must contain exactly one Driver route");
requireText(/@media \(prefers-reduced-motion: reduce\)/, "poster CSS needs reduced-motion handling", css);
requireText(/@media \(forced-colors: active\)/, "poster CSS needs forced-colors handling", css);

for (const forbidden of [
  /fonts\.googleapis\.com/i, /fonts\.gstatic\.com/i, /cdnjs\.cloudflare\.com/i,
  /unpkg\.com/i, /jsdelivr\.net/i, /fetch\s*\(/i, /mode\s*:\s*["']no-cors["']/i,
  /(?:href|src)=["']http:\/\//i
]) {
  if (forbidden.test(html)) fail(`forbidden external runtime or insecure pattern: ${forbidden}`);
}

const assets = [
  ["docs/assets/phenology-seasonal-hero-v1-source.png", 1666, 944, "5bdd6989e8c02bd6318dc01395ac7fd7589580ebe0dc282e33abb33d330f5250"],
  ["docs/assets/phenology-seasonal-hero-v1.jpg", 1666, 944, "6111a72cfc178a3b0751d44a99ebee3f15c71b8c766d45ec9cfd1615a17ef317"],
  ["docs/assets/phenology-seasonal-mobile-v1-source.png", 864, 1821, "17fd2d13a56315967a93480a8f9fda930c438834650fb9df023ee15ffe6ce6bc"],
  ["docs/assets/phenology-seasonal-mobile-v1.jpg", 864, 1821, "b11c9940e56b1c2d49f86b6ea01d6ef6ad5ad82f2ab020d2d03d381711771576"],
  ["docs/og-image-v2.jpg", 1200, 630, "cd6390b20670f6d1ef3a7c08fe2906df1e05e0a8b162963420119c79c6d9db94"],
  ["www/assets/phenology-seasonal-hero-v1.jpg", 1666, 944, "6111a72cfc178a3b0751d44a99ebee3f15c71b8c766d45ec9cfd1615a17ef317"],
  ["www/assets/phenology-seasonal-mobile-v1.jpg", 864, 1821, "b11c9940e56b1c2d49f86b6ea01d6ef6ad5ad82f2ab020d2d03d381711771576"]
];

const sourceHashes = [
  ["docs/assets/phenology-social-render.html", "39aa17020a4bb582cb1b2593436dc122c3e260196ea73ff676077e344fe4c114"],
  ["docs/assets/phenology-social-v1.svg", "2ead4991f8f1093ecae7faacac6ddac20e93a5a55f9252ad68e3c898d296bd41"]
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

for (const [file, expectedHash] of sourceHashes) {
  try {
    const actualHash = sha256(readFileSync(resolve(root, file)));
    if (actualHash !== expectedHash) fail(`${file} hash changed: ${actualHash}`);
  } catch (error) {
    fail(`${file}: ${error.message}`);
  }
}

if (!process.exitCode) console.log("OK: Pages and in-app Living Poster, accessibility, claim, and image contracts passed");
