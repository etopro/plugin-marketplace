#!/usr/bin/env node
/**
 * Verify that every `url`-sourced plugin entry in marketplace.json declares the
 * same version as its upstream repository.
 *
 * WHY THIS EXISTS
 * ---------------
 * For a `url`-sourced entry, Claude Code resolves the plugin version from THIS
 * marketplace.json — not from the upstream repo. If the upstream repo is bumped
 * but the entry here is not, the resolved version still matches what users have
 * installed, so `claude plugin install` reports "already installed" and silently
 * skips. Users keep running stale code with no error to point at.
 *
 * Local (`./plugins/...`) entries cannot drift this way: the manifest ships in
 * the same commit as the entry, so they are skipped here.
 *
 * Usage:
 *   node scripts/check-url-plugin-versions.mjs          # report drift, exit 1 on mismatch
 *   node scripts/check-url-plugin-versions.mjs --json   # machine-readable output
 *
 * Requires: `gh` CLI, authenticated (used for the GitHub API).
 */

import { execFile } from "node:child_process";
import { readFile } from "node:fs/promises";
import { promisify } from "node:util";
import { fileURLToPath } from "node:url";
import path from "node:path";

const execFileAsync = promisify(execFile);

const REPO_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const MARKETPLACE = path.join(REPO_ROOT, ".claude-plugin", "marketplace.json");

/** Extract `owner/repo` from a GitHub clone URL. */
function parseGitHubRepo(url) {
  const match = /github\.com[/:]([^/]+)\/(.+?)(?:\.git)?$/.exec(url);
  return match ? `${match[1]}/${match[2]}` : null;
}

async function gh(endpoint) {
  const { stdout } = await execFileAsync("gh", ["api", endpoint], {
    maxBuffer: 10 * 1024 * 1024
  });
  return JSON.parse(stdout);
}

/**
 * Find the upstream plugin.json version.
 *
 * The manifest is NOT always at the repo root: monorepos such as
 * codex-plugin-cc keep it at plugins/<name>/.claude-plugin/plugin.json.
 * So walk the tree and collect every manifest rather than guessing a path.
 */
async function findUpstreamVersions(repo) {
  const tree = await gh(`repos/${repo}/git/trees/HEAD?recursive=1`);
  const manifests = (tree.tree ?? [])
    .map((node) => node.path)
    .filter((p) => p.endsWith(".claude-plugin/plugin.json"));

  const found = [];
  for (const manifestPath of manifests) {
    const blob = await gh(`repos/${repo}/contents/${manifestPath}`);
    const parsed = JSON.parse(Buffer.from(blob.content, "base64").toString("utf8"));
    if (parsed.version) found.push({ path: manifestPath, version: parsed.version });
  }
  return found;
}

async function main() {
  const asJson = process.argv.includes("--json");
  const marketplace = JSON.parse(await readFile(MARKETPLACE, "utf8"));

  const urlEntries = marketplace.plugins.filter(
    (plugin) => typeof plugin.source === "object" && plugin.source?.source === "url"
  );

  const results = [];
  for (const entry of urlEntries) {
    const repo = parseGitHubRepo(entry.source.url);
    if (!repo) {
      results.push({ name: entry.name, status: "skip", reason: "not a GitHub URL" });
      continue;
    }

    let upstream;
    try {
      upstream = await findUpstreamVersions(repo);
    } catch (error) {
      results.push({ name: entry.name, status: "error", reason: error.message.trim() });
      continue;
    }

    if (upstream.length === 0) {
      // Skill-only repos legitimately ship no plugin.json — nothing to compare.
      results.push({
        name: entry.name,
        status: "skip",
        declared: entry.version,
        reason: "no plugin.json upstream (skill-only repo)"
      });
      continue;
    }

    // Resolution order (verified empirically 2026-07-19):
    // a plugin.json at the REPO ROOT wins over marketplace.json. skill-dokku has
    // one, so it installed 1.1.3 even while this file still declared 1.1.2.
    // Without a root manifest (codex-plugin-cc keeps its manifest under
    // plugins/codex/), there is nothing to override with, so marketplace.json is
    // authoritative — and a stale value there causes a silent "already installed"
    // skip. Only that second case is an actual bug.
    const rootManifest = upstream.find(
      (candidate) => candidate.path === ".claude-plugin/plugin.json"
    );
    const match = upstream.find((candidate) => candidate.version === entry.version);

    let status;
    let reason;
    if (match) {
      status = "ok";
    } else if (rootManifest) {
      // Cosmetic: installs resolve from the root manifest, not from this file.
      status = "stale";
      reason = "root plugin.json overrides marketplace.json; installs are correct";
    } else {
      // Authoritative and wrong → users silently keep the installed build.
      status = "drift";
      reason = "no root plugin.json; marketplace.json is authoritative";
    }

    results.push({
      name: entry.name,
      status,
      declared: entry.version,
      upstream: upstream.map((candidate) => `${candidate.version} (${candidate.path})`),
      reason,
      repo
    });
  }

  if (asJson) {
    console.log(JSON.stringify(results, null, 2));
  } else {
    for (const result of results) {
      const label = {
        ok: "OK   ",
        drift: "DRIFT",
        stale: "STALE",
        skip: "SKIP ",
        error: "ERROR"
      }[result.status];
      let line = `${label} ${result.name.padEnd(18)}`;
      if (result.declared) line += ` declared=${result.declared}`;
      if (result.status === "drift" || result.status === "stale") {
        line += `  upstream=${result.upstream.join(", ")}`;
      }
      if (result.reason) line += `  (${result.reason})`;
      console.log(line);
    }
  }

  const stale = results.filter((result) => result.status === "stale");
  if (stale.length > 0) {
    console.log(
      `\n${stale.length} entr${stale.length === 1 ? "y is" : "ies are"} behind upstream but harmless:` +
        ` the repo ships a root plugin.json that overrides this file.` +
        `\nWorth tidying for accuracy; installs already resolve correctly.`
    );
  }

  const drifted = results.filter((result) => result.status === "drift");
  if (drifted.length > 0) {
    console.error(
      `\n${drifted.length} entr${drifted.length === 1 ? "y" : "ies"} out of sync with upstream.` +
        `\nThese repos have NO root plugin.json, so marketplace.json is authoritative.` +
        `\nBump the "version" field here to match, or users will silently keep the` +
        `\nalready-installed build ("already installed" → no update).`
    );
    process.exit(1);
  }
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
