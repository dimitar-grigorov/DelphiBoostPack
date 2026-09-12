// CheckMirrors.js - keeps a deliberately duplicated region honest.
//
// Usage:  node tools\CheckMirrors.js
//
// A unit that must not depend on another may copy a small, frozen, stateless
// piece of it. Both copies get bracketed:
//
//   // bp:mirror <name>
//   ...the lines...
//   // bp:mirror-end
//
// Every region sharing a name must be byte-identical, so editing one copy
// fails the check until the other matches. No stored hash to regenerate and no
// registry: the copies are each other's reference. Amalgamate.js --check runs
// this, which puts it behind tools\VerifyBundles.cmd.
//
// That byte-identity is the whole contract, so a region must hold nothing
// unit-specific: no local exception class, no constant that differs. A guard
// that wants to raise the unit's own error belongs in the caller, outside the
// brackets. Plain comments, because Delphi 7 has no {$REGION}.

'use strict';

const fs = require('fs');
const path = require('path');

const SRC_DIR = path.join(path.dirname(__dirname), 'src');
const CODEC = 'latin1';

const BEGIN = /^\s*\/\/\s*bp:mirror\s+([A-Za-z0-9][A-Za-z0-9-]*)\s*$/;
const END = /^\s*\/\/\s*bp:mirror-end\s*$/;

function pasFiles(dir) {
  const out = [];
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) out.push.apply(out, pasFiles(full));
    else if (entry.name.toLowerCase().endsWith('.pas')) out.push(full);
  }
  return out;
}

// every bracketed region in one file, with the line each one opened on
function regionsIn(file, root, problems) {
  const rel = path.relative(root, file);
  const lines = fs.readFileSync(file, CODEC).replace(/\r\n/g, '\n').split('\n');
  const found = [];
  let open = null;
  for (let i = 0; i < lines.length; i++) {
    const begun = BEGIN.exec(lines[i]);
    if (begun) {
      if (open) problems.push(rel + ':' + (i + 1) + ": '" + begun[1] + "' opens inside '" + open.name + "'");
      else open = { name: begun[1], file: rel, line: i + 1, body: [] };
      continue;
    }
    if (END.test(lines[i])) {
      if (!open) problems.push(rel + ':' + (i + 1) + ': bp:mirror-end without a bp:mirror');
      else found.push(open);
      open = null;
      continue;
    }
    if (open) open.body.push(lines[i]);
  }
  if (open) problems.push(rel + ':' + open.line + ": '" + open.name + "' is never closed");
  return found;
}

// names the first line that differs, which is where a reader has to look
function firstDifference(a, b) {
  const n = Math.max(a.body.length, b.body.length);
  for (let i = 0; i < n; i++)
    if (a.body[i] !== b.body[i])
      return {
        here: a.file + ':' + (a.line + 1 + i) + '  ' + (a.body[i] === undefined ? '<region ends>' : a.body[i].trim()),
        there: b.file + ':' + (b.line + 1 + i) + '  ' + (b.body[i] === undefined ? '<region ends>' : b.body[i].trim()),
      };
  return null;
}

function checkMirrors(root) {
  const problems = [];
  const byName = Object.create(null);
  for (const file of pasFiles(root))
    for (const region of regionsIn(file, root, problems)) {
      if (!byName[region.name]) byName[region.name] = [];
      byName[region.name].push(region);
    }

  const names = Object.keys(byName).sort();
  for (const name of names) {
    const copies = byName[name];
    // a lone region means its partner was deleted or renamed, not that it is fine
    if (copies.length < 2) {
      problems.push("mirror '" + name + "' has only one copy, in " + copies[0].file);
      continue;
    }
    for (let i = 1; i < copies.length; i++) {
      const diff = firstDifference(copies[0], copies[i]);
      if (!diff) continue;
      problems.push(
        "mirror '" + name + "' differs between its copies:\n" +
        '    ' + diff.here + '\n' +
        '    ' + diff.there);
    }
  }
  return { problems: problems, names: names, count: names.reduce((n, k) => n + byName[k].length, 0) };
}

function report(result) {
  for (const p of result.problems) console.log('MIRROR   ' + p);
  if (result.problems.length) {
    console.log('Mirrored regions disagree. Make the copies identical, or drop one.');
    return false;
  }
  console.log('All ' + result.count + ' mirrored regions match (' + result.names.length + ' named).');
  return true;
}

module.exports = { checkMirrors: checkMirrors, report: report, SRC_DIR: SRC_DIR };

if (require.main === module) if (!report(checkMirrors(SRC_DIR))) process.exitCode = 1;
