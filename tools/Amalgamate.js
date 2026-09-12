// Amalgamate.js - builds the single-file bundles in dist\ out of the modular
// units, SQLite style. One manifest per bundle in tools\bundles\, listing the
// units in dependency order.
//
// Usage:  node tools\Amalgamate.js [--bundle <name>] [--check]
//
// --check regenerates into memory and fails when a committed bundle differs,
// which is the gate that keeps dist\ from lagging src\. Generation is therefore
// reproducible: the same sources give the same bytes on any day.
// It also runs CheckMirrors.js, so one gate covers both kinds of drift.
//
// Sections are spliced textually, uses clauses merged. It does not parse
// Pascal, only masks comments, strings and directives before looking for
// keywords. Units must have no clashing identifiers and no 'in' file
// references. From mksqlite3c.tcl: begin and end markers, each file in once,
// an AMALGAMATION define, a check of the result before writing.

'use strict';

const fs = require('fs');
const path = require('path');
const mirror = require('./CheckMirrors');

const TOOLS = __dirname;
const ROOT = path.dirname(TOOLS);
const SRC_DIR = path.join(ROOT, 'src');
const DIST_DIR = path.join(ROOT, 'dist');
const BUNDLE_DIR = path.join(TOOLS, 'bundles');
const RULE_WIDTH = 66;

// latin1 is the one codec that round-trips every byte of any single-byte page
const CODEC = 'latin1';

const trimNewlines = (s) => s.replace(/^\n+/, '').replace(/\n+$/, '');

// Blanks comments, strings and directives in place, so a match indexes the original
function maskText(text) {
  const c = text.split('');
  const n = c.length;
  let i = 0;
  while (i < n) {
    let blankTo = -1;
    let fill = ' ';
    if (c[i] === '/' && i + 1 < n && c[i + 1] === '/') {
      blankTo = text.indexOf('\n', i);
      if (blankTo < 0) blankTo = n;
    } else if (c[i] === '{') {
      blankTo = text.indexOf('}', i);
      blankTo = blankTo < 0 ? n : blankTo + 1;
      // a directive gets 'x', because spaces would let a \s* eat it
      if (i + 1 < n && c[i + 1] === '$') fill = 'x';
    } else if (c[i] === '(' && i + 1 < n && c[i + 1] === '*') {
      blankTo = text.indexOf('*)', i + 2);
      blankTo = blankTo < 0 ? n : blankTo + 2;
    } else if (c[i] === "'") {
      blankTo = text.indexOf("'", i + 1);
      blankTo = blankTo < 0 ? n : blankTo + 1;
    }
    if (blankTo < 0) {
      i++;
      continue;
    }
    while (i < blankTo) {
      if (c[i] !== '\n') c[i] = fill;
      i++;
    }
  }
  return c.join('');
}

function parseUnit(unitPath) {
  const text = fs.readFileSync(unitPath, CODEC).replace(/\r\n/g, '\n');
  const mask = maskText(text);

  const mName = /^unit\s+(\w+)\s*;/m.exec(mask);
  if (!mName) throw new Error('no unit header in ' + unitPath);
  const unitEnd = mask.indexOf(';', mask.indexOf('unit ')) + 1;

  const mInt = /^interface\s*$/m.exec(mask);
  const mImpl = /^implementation\s*$/m.exec(mask);
  if (!mInt || !mImpl) throw new Error('missing interface/implementation in ' + unitPath);
  const mInit = /^initialization\s*$/m.exec(mask);
  const mFin = /^finalization\s*$/m.exec(mask);
  const mEnd = /^end\./m.exec(mask);
  if (!mEnd) throw new Error('no final end. in ' + unitPath);

  const preBlock = text.substring(unitEnd, mInt.index);
  const intStart = mInt.index + mInt[0].length;
  const implStart = mImpl.index + mImpl[0].length;
  const sectionStarts = [mInit, mFin, mEnd].filter((m) => m).map((m) => m.index);
  const implEnd = Math.min.apply(null, sectionStarts);
  const initEnd = mFin ? mFin.index : mEnd.index;
  const initBody = mInit ? text.substring(mInit.index + mInit[0].length, initEnd) : '';
  const finBody = mFin ? text.substring(mFin.index + mFin[0].length, mEnd.index) : '';

  // strips a section's uses clause, found in the mask so comments cannot lie
  const stripUses = (body, offset) => {
    const m = /^\s*uses\b[\s\S]*?;/m.exec(mask.substr(offset, body.length));
    if (!m) return [body, []];
    if (text.substr(offset + m.index, m[0].length).indexOf("'") >= 0)
      throw new Error("uses with 'in' reference not supported: " + unitPath);
    // names come from the mask, so a comment between them is already gone
    const names = m[0]
      .replace(/^\s*uses\b/, '')
      .replace(/;\s*$/, '')
      .split(',')
      .map((s) => s.trim())
      .filter((s) => s);
    for (const nm of names)
      if (!/^\w+$/.test(nm))
        throw new Error("unexpected name '" + nm + "' in the uses clause of " + unitPath);
    return [body.slice(0, m.index) + body.slice(m.index + m[0].length), names];
  };

  const [intBody, intUses] = stripUses(text.substring(intStart, mImpl.index), intStart);
  const [implBody, implUses] = stripUses(text.substring(implStart, implEnd), implStart);

  return {
    name: mName[1],
    pre: trimNewlines(preBlock),
    intBody: trimNewlines(intBody),
    implBody: trimNewlines(implBody),
    initBody: trimNewlines(initBody),
    finBody: trimNewlines(finBody),
    uses: intUses.concat(implUses),
    // pre-block switches, re-applied where the unit's code goes
    preSwitches: preBlock.match(/\{\$[A-Za-z]+[+-]\}/g) || [],
    // a unit that turns range or overflow checking off gets bracketed below
    needsGuard: /\{\$[QR][+-]\}/.test(text),
  };
}

function manifestPaths(manifestPath, name) {
  const paths = fs
    .readFileSync(manifestPath, CODEC)
    .split(/\r?\n/)
    .map((line) => line.split('#')[0].trim())
    .filter((line) => line);
  const seen = Object.create(null);
  for (const p of paths) {
    const key = p.toLowerCase().replace(/\//g, '\\');
    if (seen[key]) throw new Error(p + ' is listed twice in ' + name + '.manifest');
    seen[key] = true;
  }
  return paths;
}

// one line per marker, the way mksqlite3c.tcl brackets an embedded file
function marker(word, unit, part) {
  const text = ' ' + word + ' ' + unit.name + '.pas ' + part + ' ';
  const pad = Math.max(RULE_WIDTH - text.length, 4);
  const left = Math.floor(pad / 2);
  return '// ' + '-'.repeat(left) + text + '-'.repeat(pad - left);
}

function renderBundle(name, manifestPath) {
  const paths = manifestPaths(manifestPath, name);
  const units = paths.map((p) => parseUnit(path.join(SRC_DIR, p)));
  const embedded = units.map((u) => u.name);

  // merge external uses, first appearance wins the position
  const uses = [];
  for (const u of units)
    for (const n of u.uses)
      if (embedded.indexOf(n) < 0 && uses.indexOf(n) < 0) uses.push(n);

  const anyGuard = units.some((u) => u.needsGuard);
  const restore =
    '{$IFDEF BPAMALG_R}{$R+}{$ELSE}{$R-}{$ENDIF}' +
    '{$IFDEF BPAMALG_Q}{$Q+}{$ELSE}{$Q-}{$ENDIF}';

  const out = [];
  out.push('unit ' + name + ';');
  out.push('');
  out.push('// ' + name + '.pas - GENERATED FILE, DO NOT EDIT.');
  out.push('// Single-file bundle amalgamated from the DelphiBoostPack modular units:');
  for (const p of paths) out.push('//   src\\' + p.replace(/\//g, '\\'));
  out.push('// Fix bugs in the modular units, then regenerate with:');
  out.push('//   node tools\\Amalgamate.js');
  out.push('// One bundle per project: two that share a helper declare it twice.');
  out.push('');
  out.push('{$DEFINE BPAMALGAMATION}');
  out.push('');
  out.push('interface');
  out.push('');
  out.push('uses');
  out.push('  ' + uses.join(', ') + ';');
  if (anyGuard) {
    out.push('');
    out.push('// Range and overflow checking as the consumer set it: a unit that turns');
    out.push('// either off is bracketed, so its setting ends where the unit does.');
    out.push('{$IFOPT R+}{$DEFINE BPAMALG_R}{$ELSE}{$UNDEF BPAMALG_R}{$ENDIF}');
    out.push('{$IFOPT Q+}{$DEFINE BPAMALG_Q}{$ELSE}{$UNDEF BPAMALG_Q}{$ENDIF}');
  }

  const emit = (u, part, body, prefix) => {
    out.push('');
    out.push(marker('begin', u, part));
    out.push('');
    for (const line of prefix) out.push(line);
    out.push(body);
    if (u.needsGuard) out.push(restore);
    out.push(marker('end', u, part));
  };

  for (const u of units) emit(u, 'interface', u.intBody, u.pre ? [u.pre, ''] : []);
  out.push('');
  out.push('implementation');
  // the unit's own switches, so its code compiles as it did alone
  for (const u of units)
    emit(u, 'implementation', u.implBody,
      u.preSwitches.length ? [u.preSwitches.join(''), ''] : []);

  const section = (keyword, ordered) => {
    const bodies = ordered.filter((u) => u[keyword + 'Body']);
    if (!bodies.length) return;
    out.push('');
    out.push(keyword === 'init' ? 'initialization' : 'finalization');
    for (const u of bodies) {
      out.push('  // from ' + u.name + '.pas');
      out.push(u[keyword + 'Body']);
    }
  };
  section('init', units);
  // reverse, the order the compiler would have finalized these units in
  section('fin', units.slice().reverse());
  out.push('');
  out.push('end.');

  const text = out.map((line) => line + '\n').join('');

  // nothing is written until the splice proves to be one well formed unit
  const outMask = maskText(text);
  for (const pat of ['^unit\\s+\\w+\\s*;', '^interface\\s*$', '^implementation\\s*$', '^end\\.']) {
    const hits = outMask.match(new RegExp(pat, 'gm'));
    const count = hits ? hits.length : 0;
    if (count !== 1) throw new Error(name + '.pas: expected 1 match of ' + pat + ', got ' + count);
  }

  return { text: text.replace(/\n/g, '\r\n'), unitCount: units.length };
}

function main() {
  const argv = process.argv.slice(2);
  const check = argv.indexOf('--check') >= 0;
  const only = argv.indexOf('--bundle') >= 0 ? argv[argv.indexOf('--bundle') + 1] : '';

  let manifests = fs
    .readdirSync(BUNDLE_DIR)
    .filter((f) => f.toLowerCase().endsWith('.manifest'));
  if (only) manifests = manifests.filter((f) => path.basename(f, '.manifest') === only);
  if (!manifests.length) throw new Error("no manifest found for '" + only + "' in " + BUNDLE_DIR);

  const stale = [];
  for (const m of manifests) {
    const name = path.basename(m, '.manifest');
    const built = renderBundle(name, path.join(BUNDLE_DIR, m));
    const outPath = path.join(DIST_DIR, name + '.pas');
    const lines = built.text.split('\r\n').length;
    if (check) {
      const committed = fs.existsSync(outPath) ? fs.readFileSync(outPath, CODEC) : null;
      if (committed === built.text) continue;
      stale.push(name);
      console.log(committed === null
        ? 'MISSING  dist\\' + name + '.pas'
        : 'STALE    dist\\' + name + '.pas does not match ' + name + '.manifest sources');
      continue;
    }
    if (!fs.existsSync(DIST_DIR)) fs.mkdirSync(DIST_DIR, { recursive: true });
    fs.writeFileSync(outPath, built.text, CODEC);
    console.log('generated ' + outPath + ' (' + built.unitCount + ' units, ' + lines + ' lines)');
  }

  if (!check) return;
  if (stale.length) {
    console.log('Bundles are out of date. Regenerate with: node tools\\Amalgamate.js');
    process.exitCode = 1;
  } else {
    console.log('All bundles match their sources.');
  }
  if (!mirror.report(mirror.checkMirrors(SRC_DIR))) process.exitCode = 1;
}

main();
