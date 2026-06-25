#!/usr/bin/env node
'use strict';
const fs = require('fs');

function main() {
  const inPath = process.argv[2];
  const outPath = process.argv[3];
  if (!inPath || !outPath) { console.error('usage: analyze.js <input.json> <output.json>'); process.exit(1); }
  const data = JSON.parse(fs.readFileSync(inPath, 'utf8'));
  const fileNodes = data.fileNodes || [];
  const importEdges = data.importEdges || [];
  const allEdges = data.allEdges || [];

  const byId = new Map();
  for (const n of fileNodes) byId.set(n.id, n);

  // ---- common prefix ----
  const paths = fileNodes.map(n => n.filePath).filter(Boolean);
  function commonPrefixDir(ps) {
    if (ps.length === 0) return '';
    const split = ps.map(p => p.split('/'));
    let prefix = [];
    for (let i = 0; i < split[0].length - 1; i++) {
      const seg = split[0][i];
      if (split.every(s => s.length > i + 1 && s[i] === seg)) prefix.push(seg);
      else break;
    }
    return prefix.length ? prefix.join('/') + '/' : '';
  }
  const prefix = commonPrefixDir(paths);

  function groupOf(fp) {
    let rest = fp;
    if (prefix && fp.startsWith(prefix)) rest = fp.slice(prefix.length);
    const parts = rest.split('/');
    if (parts.length > 1) return parts[0];
    return '(root)';
  }

  // ---- A. directory groups ----
  const directoryGroups = {};
  const groupByNode = new Map();
  for (const n of fileNodes) {
    const g = groupOf(n.filePath);
    (directoryGroups[g] = directoryGroups[g] || []).push(n.id);
    groupByNode.set(n.id, g);
  }

  // ---- B. node type groups ----
  const nodeTypeGroups = {};
  for (const n of fileNodes) (nodeTypeGroups[n.type] = nodeTypeGroups[n.type] || []).push(n.id);

  // ---- C. adjacency / fan-in fan-out ----
  const fanOut = {}, fanIn = {};
  for (const n of fileNodes) { fanOut[n.id] = 0; fanIn[n.id] = 0; }
  for (const e of importEdges) {
    if (fanOut[e.source] !== undefined) fanOut[e.source]++;
    if (fanIn[e.target] !== undefined) fanIn[e.target]++;
  }

  // ---- D. cross-category edges (by node type) using allEdges non-import ----
  const crossMap = {};
  for (const e of allEdges) {
    const s = byId.get(e.source), t = byId.get(e.target);
    if (!s || !t) continue;
    if (s.type === t.type) continue; // cross type only
    const key = s.type + '>' + t.type + '>' + e.type;
    crossMap[key] = (crossMap[key] || 0) + 1;
  }
  const crossCategoryEdges = Object.entries(crossMap).map(([k, c]) => {
    const [fromType, toType, edgeType] = k.split('>');
    return { fromType, toType, edgeType, count: c };
  }).sort((a, b) => b.count - a.count);

  // ---- E. inter-group import frequency ----
  const interMap = {};
  for (const e of importEdges) {
    const gs = groupByNode.get(e.source), gt = groupByNode.get(e.target);
    if (gs === undefined || gt === undefined || gs === gt) continue;
    const key = gs + '>' + gt;
    interMap[key] = (interMap[key] || 0) + 1;
  }
  const interGroupImports = Object.entries(interMap).map(([k, c]) => {
    const [from, to] = k.split('>');
    return { from, to, count: c };
  }).sort((a, b) => b.count - a.count);

  // ---- F. intra-group density ----
  const intraGroupDensity = {};
  const groupNames = Object.keys(directoryGroups);
  for (const g of groupNames) intraGroupDensity[g] = { internalEdges: 0, totalEdges: 0, density: 0 };
  for (const e of importEdges) {
    const gs = groupByNode.get(e.source), gt = groupByNode.get(e.target);
    if (gs !== undefined) intraGroupDensity[gs].totalEdges++;
    if (gt !== undefined && gt !== gs) intraGroupDensity[gt].totalEdges++;
    if (gs !== undefined && gs === gt) intraGroupDensity[gs].internalEdges++;
  }
  for (const g of groupNames) {
    const d = intraGroupDensity[g];
    d.density = d.totalEdges ? +(d.internalEdges / d.totalEdges).toFixed(3) : 0;
  }

  // ---- G. pattern matching ----
  const dirPatterns = [
    [/^(routes|api|controllers|endpoints|handlers|controller|routers|serializers|blueprints)$/, 'api'],
    [/^(services|core|lib|domain|logic|signals|composables|mailers|jobs|channels)$/, 'service'],
    [/^(models|db|data|persistence|repository|entities|migrations|entity|sql|database)$/, 'data'],
    [/^(components|views|pages|ui|layouts|screens|widgets)$/, 'ui'],
    [/^(middleware|plugins|interceptors|guards)$/, 'middleware'],
    [/^(utils|helpers|common|shared|tools|templatetags|pkg)$/, 'utility'],
    [/^(config|constants|env|settings|management|commands)$/, 'config'],
    [/^(__tests__|test|tests|spec|specs)$/, 'test'],
    [/^(types|interfaces|schemas|contracts|dtos|dto|request|response)$/, 'types'],
    [/^hooks$/, 'hooks'],
    [/^(store|state|reducers|actions|slices)$/, 'state'],
    [/^(assets|static|public)$/, 'assets'],
    [/^(cmd|bin)$/, 'entry'],
    [/^internal$/, 'service'],
    [/^(docs|documentation|wiki)$/, 'documentation'],
    [/^(deploy|deployment|infra|infrastructure|docker|k8s|kubernetes|helm|charts|terraform|tf)$/, 'infrastructure'],
    [/^(\.github|\.gitlab|\.circleci)$/, 'ci-cd'],
  ];
  function patternForDir(name) {
    for (const [re, label] of dirPatterns) if (re.test(name)) return label;
    return null;
  }
  const patternMatches = {};
  for (const g of groupNames) {
    const p = patternForDir(g);
    if (p) patternMatches[g] = p;
  }

  // file-level pattern helper
  function filePattern(fp, type) {
    const base = fp.split('/').pop();
    if (/(\.test\.|\.spec\.)/.test(base) || /^test_.*\.py$/.test(base) || /_test\.go$/.test(base) || /Test\.java$/.test(base) || /_spec\.rb$/.test(base) || /Test\.php$/.test(base) || /Tests\.cs$/.test(base)) return 'test';
    if (/\.d\.ts$/.test(base)) return 'types';
    if (/\.(graphql|gql|proto)$/.test(base)) return 'types';
    if (/\.sql$/.test(base)) return 'data';
    if (/\.(md|rst)$/.test(base)) return 'documentation';
    if (/^Dockerfile/.test(base) || /^docker-compose/.test(base)) return 'infrastructure';
    if (/\.(tf|tfvars)$/.test(base)) return 'infrastructure';
    if (base === 'Makefile') return 'infrastructure';
    if (/\.(ya?ml)$/.test(base) && /(\.github|\.gitlab)/.test(fp)) return 'ci-cd';
    return null;
  }

  // ---- H. deployment topology ----
  const infraFiles = [];
  let hasDockerfile = false, hasCompose = false, hasK8s = false, hasTerraform = false, hasCI = false;
  for (const n of fileNodes) {
    const fp = n.filePath; const base = fp.split('/').pop();
    if (/^Dockerfile/.test(base)) { hasDockerfile = true; infraFiles.push(fp); }
    else if (/^docker-compose/.test(base)) { hasCompose = true; infraFiles.push(fp); }
    else if (/\.(tf|tfvars)$/.test(base)) { hasTerraform = true; infraFiles.push(fp); }
    else if (/(k8s|kubernetes|helm|charts)/.test(fp) && /\.ya?ml$/.test(base)) { hasK8s = true; infraFiles.push(fp); }
    else if (/(\.github\/workflows|\.gitlab-ci|Jenkinsfile)/.test(fp)) { hasCI = true; infraFiles.push(fp); }
  }
  const deploymentTopology = { hasDockerfile, hasCompose, hasK8s, hasTerraform, hasCI, infraFiles };

  // ---- I. data pipeline ----
  const schemaFiles = [], migrationFiles = [], dataModelFiles = [], apiHandlerFiles = [];
  for (const n of fileNodes) {
    const fp = n.filePath; const tags = (n.tags || []).join(' ');
    if (/\.(graphql|gql|proto|prisma)$/.test(fp)) schemaFiles.push(fp);
    if (/migrations?\//.test(fp) && /\.sql$/.test(fp)) migrationFiles.push(fp);
    if (/(models?|entity|entities)\//.test(fp) || /data-model|entity/.test(tags)) dataModelFiles.push(fp);
    if (/(routes?|controllers?|handlers?|api|endpoints?)\//.test(fp) || /api-handler|endpoint|controller/.test(tags)) apiHandlerFiles.push(fp);
  }
  const uniq = a => Array.from(new Set(a));
  const dataPipeline = {
    schemaFiles: uniq(schemaFiles), migrationFiles: uniq(migrationFiles),
    dataModelFiles: uniq(dataModelFiles), apiHandlerFiles: uniq(apiHandlerFiles)
  };

  // ---- J. doc coverage ----
  const docDirs = new Set();
  for (const n of fileNodes) {
    if (/\.(md|rst)$/.test(n.filePath)) docDirs.add(groupOf(n.filePath));
  }
  // also: which code groups have a README within them
  const groupsWithDocs = new Set();
  for (const n of fileNodes) {
    if (/README/i.test(n.filePath.split('/').pop() || '') || /\.(md|rst)$/.test(n.filePath)) {
      groupsWithDocs.add(groupOf(n.filePath));
    }
  }
  const totalGroups = groupNames.length;
  const undocumented = groupNames.filter(g => !groupsWithDocs.has(g));
  const docCoverage = {
    groupsWithDocs: groupsWithDocs.size, totalGroups,
    coverageRatio: totalGroups ? +(groupsWithDocs.size / totalGroups).toFixed(2) : 0,
    undocumentedGroups: undocumented
  };

  // ---- K. dependency direction ----
  const pairCount = {};
  for (const e of interGroupImports) pairCount[e.from + '>' + e.to] = e.count;
  const seen = new Set();
  const dependencyDirection = [];
  for (const e of interGroupImports) {
    const a = e.from, b = e.to;
    const key = [a, b].sort().join('||');
    if (seen.has(key)) continue;
    seen.add(key);
    const ab = pairCount[a + '>' + b] || 0;
    const ba = pairCount[b + '>' + a] || 0;
    if (ab >= ba) dependencyDirection.push({ dependent: a, dependsOn: b });
    else dependencyDirection.push({ dependent: b, dependsOn: a });
  }

  // ---- file stats ----
  const filesPerGroup = {};
  for (const g of groupNames) filesPerGroup[g] = directoryGroups[g].length;
  const nodeTypeCounts = {};
  for (const t of Object.keys(nodeTypeGroups)) nodeTypeCounts[t] = nodeTypeGroups[t].length;

  const result = {
    scriptCompleted: true,
    commonPrefix: prefix,
    directoryGroups,
    nodeTypeGroups,
    crossCategoryEdges,
    interGroupImports,
    intraGroupDensity,
    patternMatches,
    deploymentTopology,
    dataPipeline,
    docCoverage,
    dependencyDirection,
    fileStats: { totalFileNodes: fileNodes.length, filesPerGroup, nodeTypeCounts },
    fileFanIn: fanIn,
    fileFanOut: fanOut
  };
  fs.writeFileSync(outPath, JSON.stringify(result, null, 2));
  console.error('done: ' + fileNodes.length + ' file nodes, ' + groupNames.length + ' groups');
  process.exit(0);
}
try { main(); } catch (e) { console.error(e && e.stack || e); process.exit(1); }
