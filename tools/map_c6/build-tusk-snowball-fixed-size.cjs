'use strict';
// Keep Tusk's complete native rolling snowball at its spawn scale. This only
// writes workspace source/evidence; compilation is a separate build step.
const fs = require('fs'), path = require('path'), cp = require('child_process');
const assert = require('assert'), crypto = require('crypto');
const { Vpk, endOf } = require('./lib.cjs');

const repo = path.resolve(__dirname, '../..');
const game = path.resolve(repo, '../../dota');
const nativeResource = 'particles/units/heroes/hero_tusk/tusk_snowball.vpcf';
const targetResource = 'particles/survival/skills/tusk_snowball_fixed_size.vpcf';
const evidence = path.join(repo, 'output/tusk_snowball_fixed_size');
const source = path.join(repo, 'art/effects/tusk_snowball_fixed_size/source', targetResource);
// Same format as the native source; avoid old-format operator conversions.
const header = '<!-- kv3 encoding:text:version{e21c7f3c-8a33-41c5-9977-a76d3a32aa0d} format:vpcf60:version{cd92a366-0b0d-4811-a18d-f6d472d19709} -->\n';
const checkCompiled = process.argv.includes('--check-compiled');
const check = process.argv.includes('--check') || checkCompiled;
assert(process.argv.slice(2).every(arg => ['--check', '--check-compiled'].includes(arg)),
  'Usage: node build-tusk-snowball-fixed-size.cjs [--check] [--check-compiled]');
const hash = data => crypto.createHash('sha256').update(data).digest('hex');

function parse(text) {
  const tokens = text.match(/resource:"(?:\\.|[^"\\])*"|"(?:\\.|[^"\\])*"|[{}\[\]=,]|[^\s{}\[\]=,]+/g);
  let index = 0;
  function value() {
    const token = tokens[index++];
    assert(token !== undefined, 'Unexpected end of DATA');
    if (token === '{') {
      const object = {};
      while (tokens[index] !== '}') {
        const key = tokens[index++];
        assert.equal(tokens[index++], '=');
        assert(!Object.hasOwn(object, key), 'Duplicate DATA key: ' + key);
        object[key] = value();
        if (tokens[index] === ',') index++;
      }
      index++;
      return object;
    }
    if (token === '[') {
      const array = [];
      while (tokens[index] !== ']') {
        array.push(value());
        if (tokens[index] === ',') index++;
      }
      index++;
      return array;
    }
    if (token.startsWith('resource:')) return { __resource: JSON.parse(token.slice(9)) };
    if (token.startsWith('"')) return JSON.parse(token);
    if (token === 'true' || token === 'false') return token === 'true';
    if (token === 'null') return null;
    assert(Number.isFinite(Number(token)), 'Unexpected DATA token: ' + token);
    return Number(token);
  }
  const result = value();
  assert.equal(index, tokens.length, 'Unparsed DATA tokens');
  return result;
}

function differences(expected, actual, at = '$', out = []) {
  if (Object.is(expected, actual)) return out;
  if (expected !== null && actual !== null && typeof expected === 'object' &&
      typeof actual === 'object' && Array.isArray(expected) === Array.isArray(actual)) {
    for (const key of new Set([...Object.keys(expected), ...Object.keys(actual)])) {
      const child = at + (Array.isArray(expected) ? '[' + key + ']' : '.' + key);
      if (!Object.hasOwn(expected, key)) out.push({ path: child, change: 'added', actual: actual[key] });
      else if (!Object.hasOwn(actual, key)) out.push({ path: child, change: 'removed', expected: expected[key] });
      else differences(expected[key], actual[key], child, out);
    }
  } else out.push({ path: at, change: 'changed', expected, actual });
  return out;
}

fs.mkdirSync(evidence, { recursive: true });
const vpk = new Vpk(path.join(game, 'pak01_dir.vpk'));
const nativeCompiled = vpk.read(nativeResource + '_c');
const nativeFile = path.join(evidence, 'tusk_snowball.native.vpcf_c');
fs.writeFileSync(nativeFile, nativeCompiled);
const dump = cp.execFileSync(path.resolve(repo, '../../bin/win64/resourceinfo.exe'),
  ['-i', nativeFile, '-b', 'DATA', '-baremode'],
  { encoding: 'utf8', windowsHide: true, maxBuffer: 4 * 1024 * 1024 });
const open = dump.indexOf('{');
assert(open >= 0, 'Native DATA block was not decoded');
const native = dump.slice(open, endOf(dump, open)).replace(/\r\n/g, '\n') + '\n';
fs.writeFileSync(path.join(evidence, 'tusk_snowball.native.kv3'), native);

const operatorsKey = native.indexOf('\tm_Operators =');
assert(operatorsKey >= 0, 'Native operators are missing');
const operatorsStart = native.indexOf('[', operatorsKey);
const operatorsEnd = endOf(native, operatorsStart, '[', ']');
const operators = native.slice(operatorsStart, operatorsEnd);
const classText = '_class = "C_OP_InterpolateRadius"';
assert.equal(operators.split(classText).length - 1, 1, 'Expected one native body radius curve');
const classOffset = native.indexOf(classText, operatorsStart);
const curveStart = native.lastIndexOf('{', classOffset);
const curveEnd = endOf(native, curveStart);
const curve = native.slice(curveStart, curveEnd);
assert(/m_flStartScale = 0\.3(?:\s|$)/.test(curve), 'Native spawn scale changed; review before regenerating');
assert(!/m_flEndScale\s*=/.test(curve), 'Native end scale changed; review before regenerating');

// Preserve every byte of decoded DATA besides this single additional field.
const anchor = '\t\t\tm_flStartScale = 0.3\n';
assert.equal(curve.split(anchor).length - 1, 1, 'Expected native start-scale line');
const insertion = '\t\t\tm_flEndScale = 0.3\n';
const fixedCurve = curve.replace(anchor, anchor + insertion);
const fixed = native.slice(0, curveStart) + fixedCurve + native.slice(curveEnd);
assert.equal(fixed.replace(insertion, ''), native,
  'Removing the added end scale must reproduce the entire native DATA exactly');
const expected = header + fixed;
if (check) {
  assert.equal(fs.readFileSync(source, 'utf8'), expected, 'Source differs from the one-field native variant');
} else {
  fs.mkdirSync(path.dirname(source), { recursive: true });
  fs.writeFileSync(source, expected);
}

const children = [...native.matchAll(/m_ChildRef = resource:"([^"]+)"/g)].map(match => match[1]);
assert.equal(children.length, 10, 'Native child set changed; review before regenerating');
for (const child of children) assert(vpk.entries.has(child + '_c'), 'Missing native child: ' + child);
assert(native.includes('m_model = resource:"models/particle/snowball.vmdl"'));
assert(vpk.entries.has('models/particle/snowball.vmdl_c'));
assert.equal((native.match(/m_bEndCap = true/g) || []).length, 2, 'Keep both native shatter endcaps');
const report = {
  native_resource: nativeResource,
  target_resource: targetResource,
  source: path.relative(repo, source).replace(/\\/g, '/'),
  source_format: 'vpcf60',
  native_compiled_sha256: hash(nativeCompiled),
  native_data_sha256: hash(native),
  source_sha256: hash(expected),
  only_change: 'C_OP_InterpolateRadius.m_flEndScale: native default 1.0 -> explicit 0.3 (same as m_flStartScale)',
  native_data_identical_after_removing_added_field: true,
  native_children: children,
  native_model: 'models/particle/snowball.vmdl',
  native_endcaps: 2,
  compile_performed: false,
};
fs.writeFileSync(path.join(evidence, 'verification.json'), JSON.stringify(report, null, 2) + '\n');
if (checkCompiled) {
  const compiledFile = path.join(repo, targetResource + '_c');
  const compiledBytes = fs.readFileSync(compiledFile);
  const compiledDump = cp.execFileSync(path.resolve(repo, '../../bin/win64/resourceinfo.exe'),
    ['-i', compiledFile, '-b', 'DATA', '-baremode'],
    { encoding: 'utf8', windowsHide: true, maxBuffer: 4 * 1024 * 1024 });
  const compiledOpen = compiledDump.indexOf('{');
  assert(compiledOpen >= 0, 'Compiled DATA block was not decoded');
  const compiledData = compiledDump.slice(compiledOpen, endOf(compiledDump, compiledOpen)).replace(/\r\n/g, '\n') + '\n';
  fs.writeFileSync(path.join(evidence, 'tusk_snowball_fixed_size.compiled.kv3'), compiledData);
  const nativeTree = parse(native), expectedTree = parse(fixed), compiledTree = parse(compiledData);
  const intended = differences(nativeTree, expectedTree);
  assert.equal(intended.length, 1, 'Source has exactly one structural change');
  assert.equal(intended[0].path, '$.m_Operators[3].m_flEndScale');
  assert.equal(intended[0].actual, 0.3);

  // vpcf60 upgrades the legacy CP override to an equivalent dynamic float.
  // Accept this exact replacement only: both representations read CP2.x.
  // The native 800 literal is overridden by CP2, so it is not a speed change.
  const normalizedExpected = structuredClone(expectedTree);
  const speedIndex = expectedTree.m_Operators.findIndex(op => op._class === 'C_OP_MaxVelocity');
  assert(speedIndex >= 0, 'Native maximum velocity operator is required');
  const nativeSpeed = expectedTree.m_Operators[speedIndex];
  assert.equal(nativeSpeed.m_flMaxVelocity, 800);
  assert.equal(nativeSpeed.m_nOverrideCP, 2);
  const convertedSpeed = structuredClone(nativeSpeed);
  convertedSpeed.m_flMaxVelocity = {
    m_nType: 'PF_TYPE_CONTROL_POINT_COMPONENT', m_nControlPoint: 2, m_nVectorComponent: 0,
  };
  delete convertedSpeed.m_nOverrideCP;
  const normalizations = [];
  if (differences(convertedSpeed, compiledTree.m_Operators[speedIndex]).length === 0) {
    normalizedExpected.m_Operators[speedIndex] = convertedSpeed;
    normalizations.push({
      path: '$.m_Operators[' + speedIndex + ']',
      reason: 'Legacy maximum-speed override CP2 becomes a dynamic float reading CP2.x; all other operator fields are identical',
      source: nativeSpeed,
      compiled: convertedSpeed,
    });
  }
  // Compare every remaining field, including unknown future fields. Never
  // discard unexpected mismatches as generic compiler noise.
  const compilerDifferences = differences(normalizedExpected, compiledTree);
  const compiledReport = {
    status: compilerDifferences.length === 0 ? 'PASS' : 'FAIL',
    native_resource: nativeResource,
    compiled_resource: targetResource + '_c',
    native_compiled_sha256: report.native_compiled_sha256,
    source_sha256: report.source_sha256,
    compiled_sha256: hash(compiledBytes),
    intended_changes: intended,
    actual_changes_from_native: differences(nativeTree, compiledTree),
    accepted_compiler_normalizations: normalizations,
    unexpected_compiler_changes: compilerDifferences,
    native_children: compiledTree.m_Children,
    native_renderers: compiledTree.m_Renderers,
    native_initializers: compiledTree.m_Initializers,
    native_cp2_speed: compiledTree.m_Operators.find(op => op._class === 'C_OP_MaxVelocity'),
    native_endcaps: compiledTree.m_Children.filter(child => child.m_bEndCap === true).length,
  };
  fs.writeFileSync(path.join(evidence, 'compiled_verification.json'), JSON.stringify(compiledReport, null, 2) + '\n');
  assert.deepStrictEqual(compilerDifferences, [], 'Unexpected compiler changes; see output/tusk_snowball_fixed_size/compiled_verification.json');
  assert.deepStrictEqual(compiledTree.m_Children, nativeTree.m_Children, 'All ten children and both endcaps are native');
  assert.deepStrictEqual(compiledTree.m_Renderers, nativeTree.m_Renderers, 'Native model and renderer settings');
  assert.deepStrictEqual(compiledTree.m_Initializers, nativeTree.m_Initializers, 'Native CP3 initial size and CP2 spin');
  assert.deepStrictEqual(compiledTree.m_ForceGenerators, nativeTree.m_ForceGenerators, 'Native attraction');
  assert.deepStrictEqual(compiledReport.native_cp2_speed,
    normalizedExpected.m_Operators[speedIndex], 'Native CP2 movement speed');
  console.log('TUSK_SNOWBALL_FIXED_SIZE_COMPILED_PASS ' + compiledFile);
} else {
  console.log('TUSK_SNOWBALL_FIXED_SIZE_' + (check ? 'CHECK' : 'SOURCE') + '_PASS ' + source);
}
