#!/usr/bin/env node
/**
 * Propagates the version from package.json into the macOS app's Info.plist.template.
 *
 * Run by `npm run version-bump` immediately after `changeset version` bumps
 * package.json. Updates two keys:
 *
 *   - CFBundleShortVersionString = package.json#version
 *   - CFBundleVersion            = previous_integer + 1
 *
 * The script is line-oriented and avoids a full XML parse so it stays portable
 * on stock Node installs (no plist library needed).
 */

import { readFileSync, writeFileSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(here, "..");
const pkgPath = resolve(repoRoot, "package.json");
const plistPath = resolve(
  repoRoot,
  "Sources/Skillbox/Resources/Info.plist.template"
);

const pkg = JSON.parse(readFileSync(pkgPath, "utf8"));
const newShortVersion = pkg.version;

if (!newShortVersion) {
  console.error("[sync-version] package.json has no version field");
  process.exit(1);
}

const plist = readFileSync(plistPath, "utf8");
const lines = plist.split("\n");

let updatedShort = false;
let updatedBuild = false;
const out = [];

for (let i = 0; i < lines.length; i++) {
  const line = lines[i];
  out.push(line);

  if (line.includes("<key>CFBundleShortVersionString</key>") && i + 1 < lines.length) {
    const next = lines[i + 1];
    const replaced = next.replace(
      /<string>[^<]*<\/string>/,
      `<string>${newShortVersion}</string>`
    );
    out.push(replaced);
    i += 1;
    updatedShort = true;
    continue;
  }

  if (line.includes("<key>CFBundleVersion</key>") && i + 1 < lines.length) {
    const next = lines[i + 1];
    const match = next.match(/<string>(\d+)<\/string>/);
    if (!match) {
      console.error(
        `[sync-version] CFBundleVersion value isn't a plain integer (got "${next.trim()}")`
      );
      process.exit(1);
    }
    const incremented = parseInt(match[1], 10) + 1;
    out.push(next.replace(/<string>\d+<\/string>/, `<string>${incremented}</string>`));
    i += 1;
    updatedBuild = true;
    continue;
  }
}

if (!updatedShort) {
  console.error("[sync-version] CFBundleShortVersionString key not found in Info.plist.template");
  process.exit(1);
}
if (!updatedBuild) {
  console.error("[sync-version] CFBundleVersion key not found in Info.plist.template");
  process.exit(1);
}

writeFileSync(plistPath, out.join("\n"));
console.log(`[sync-version] Info.plist.template synced to ${newShortVersion} (build incremented)`);
