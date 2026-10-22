import fs from "node:fs";

// Every Shiny custom-message handler must accept exactly one payload argument,
// and every message the server sends must have a handler. Handlers can live in
// the www/ scripts or inline in R sources (tags$script strings), so scan both;
// app.R is included when present (single-file apps).
const files = ["www/app.js", "www/pincards.js", "app.R", "ui.R", "server.R", "global.R"]
  .filter((file) => fs.existsSync(file));
const handlerPattern = /Shiny\.addCustomMessageHandler\(\s*["']([^"']+)["']\s*,\s*function\s*\(([^)]*)\)/g;
const sendPattern = /sendCustomMessage\(\s*(?:type\s*=\s*)?["']([^"']+)["']/g;
let seen = 0;
const invalid = [];
const handled = new Set();
const sent = new Map();

for (const file of files) {
  const source = fs.readFileSync(file, "utf8");
  for (const match of source.matchAll(handlerPattern)) {
    seen += 1;
    handled.add(match[1]);
    const params = match[2]
      .split(",")
      .map((value) => value.trim())
      .filter(Boolean);
    if (params.length !== 1) invalid.push(`${file}: ${match[0]}`);
  }
  if (file.endsWith(".R")) {
    for (const match of source.matchAll(sendPattern)) {
      if (!sent.has(match[1])) sent.set(match[1], file);
    }
  }
}

if (seen !== 5) {
  throw new Error(`expected 5 Shiny custom message handlers, found ${seen}`);
}
if (invalid.length) {
  throw new Error(`Shiny custom message handlers must accept exactly one payload argument:\n${invalid.join("\n")}`);
}
const orphans = [...sent.entries()].filter(([name]) => !handled.has(name));
if (orphans.length) {
  throw new Error(`messages sent with no handler:\n${orphans.map(([name, file]) => `${file}: ${name}`).join("\n")}`);
}

console.log(`OK: ${seen} Shiny custom message handlers accept exactly one payload argument; ` +
  `all ${sent.size} sent message types have a handler (scanned ${files.join(", ")}).`);
