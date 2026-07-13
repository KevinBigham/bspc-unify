#!/usr/bin/env node
import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const unify = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const workspace = resolve(unify, '..');
const paths = [
  resolve(unify, 'domain-contract.json'),
  resolve(workspace, 'BSPC-main/ACTIVE/lib/domain/contract.json'),
  resolve(workspace, 'BSPC-Coach-App-main/shared/domain/contract.json'),
];
const normalized = paths.map((path) => JSON.stringify(JSON.parse(readFileSync(path, 'utf8'))));
if (!normalized.every((value) => value === normalized[0])) {
  throw new Error('UNIFY, Family, and Coach domain contracts diverge');
}

const contract = JSON.parse(normalized[0]);
const canonical = readFileSync(resolve(unify, '01_CANONICAL_SCHEMA.sql'), 'utf8');
for (const value of [...contract.practiceGroups, ...contract.courses, ...contract.standardLevels]) {
  if (!canonical.includes(`'${value}'`)) throw new Error(`Canonical schema is missing domain value ${value}`);
}
console.log('cross-repo domain drift check passed');
