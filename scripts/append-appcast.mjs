#!/usr/bin/env node
/**
 * Appends a new <item> to docs/appcast.xml for the just-released tag.
 *
 * Invoked from .github/workflows/release.yml with these env vars:
 *
 *   TAG     - e.g. "v0.3.0-beta.1"
 *   ZIP     - e.g. "Skillbox-v0.3.0-beta.1.zip"
 *   ED_LINE - the line printed by `sign_update`, like:
 *               sparkle:edSignature="<base64>" length="<bytes>"
 *
 * The script also reads:
 *   - package.json#version (for sparkle:shortVersionString)
 *   - Sources/Skillbox/Resources/Info.plist.template's CFBundleVersion
 *     (for sparkle:version, Sparkle's internal monotonic build number)
 *
 * The asset URL points at the GitHub Release we just created. We don't
 * mirror the zip into docs/ - Pages just serves the manifest.
 */

import { readFileSync, writeFileSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(here, "..");

const tag = process.env.TAG;
const zip = process.env.ZIP;
const edLine = process.env.ED_LINE;
if (!tag || !zip || !edLine) {
  console.error("[append-appcast] missing TAG / ZIP / ED_LINE env vars");
  process.exit(1);
}

// Pull short version + build from the canonical source.
const pkg = JSON.parse(readFileSync(resolve(repoRoot, "package.json"), "utf8"));
const shortVersion = pkg.version;

const plist = readFileSync(
  resolve(repoRoot, "Sources/Skillbox/Resources/Info.plist.template"),
  "utf8"
);
const buildMatch = plist.match(
  /<key>CFBundleVersion<\/key>\s*<string>(\d+)<\/string>/
);
if (!buildMatch) {
  console.error("[append-appcast] couldn't find CFBundleVersion in Info.plist.template");
  process.exit(1);
}
const build = buildMatch[1];

const releaseURL = `https://github.com/mmurakaru/skillbox/releases/download/${tag}/${zip}`;
const releaseNotesURL = `https://github.com/mmurakaru/skillbox/releases/tag/${tag}`;
const pubDate = new Date().toUTCString();

const itemXML = `        <item>
            <title>${tag}</title>
            <sparkle:releaseNotesLink>${releaseNotesURL}</sparkle:releaseNotesLink>
            <pubDate>${pubDate}</pubDate>
            <sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>
            <enclosure
                url="${releaseURL}"
                sparkle:version="${build}"
                sparkle:shortVersionString="${shortVersion}"
                type="application/octet-stream"
                ${edLine.trim()} />
        </item>`;

const appcastPath = resolve(repoRoot, "docs/appcast.xml");
const existing = readFileSync(appcastPath, "utf8");

// Insert the new item right after the opening <channel>'s metadata block,
// before any existing <item>. If no <item> exists yet, insert before </channel>.
let updated;
if (existing.includes("<item>")) {
  updated = existing.replace(/(\s*<item>)/, `\n${itemXML}\n$1`);
} else {
  updated = existing.replace(/(\s*<\/channel>)/, `\n${itemXML}\n$1`);
}

writeFileSync(appcastPath, updated);
console.log(`[append-appcast] added ${tag} (short ${shortVersion}, build ${build})`);
