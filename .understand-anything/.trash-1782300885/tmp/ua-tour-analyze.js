#!/usr/bin/env node
'use strict';
const fs = require('fs');

function main() {
  const inPath = process.argv[2];
  const outPath = process.argv[3];
  if (!inPath || !outPath) {
    console.error('Usage: node ua-tour-analyze.js <input.json> <output.json>');
    process.exit(1);
  }
  const data = JSON.parse(fs.readFileSync(inPath, 'utf8'));
  const nodes = data.nodes || [];
  const edges = data.edges || [];
  const layers = data.layers || [];

  const byId = new Map();
  for (const n of nodes) byId.set(n.id, n);

  // Fan-in / fan-out
  const fanIn = new Map();
  const fanOut = new Map();
  for (const n of nodes) { fanIn.set(n.id, 0); fanOut.set(n.id, 0); }
  // adjacency for imports/calls forward traversal
  const forwardAdj = new Map();
  for (const n of nodes) forwardAdj.set(n.id, []);
  for (const e of edges) {
    if (!byId.has(e.source) || !byId.has(e.target)) continue;
    fanOut.set(e.source, fanOut.get(e.source) + 1);
    fanIn.set(e.target, fanIn.get(e.target) + 1);
    if (e.type === 'imports' || e.type === 'calls') {
      forwardAdj.get(e.source).push(e.target);
    }
  }

  const nameOf = (id) => (byId.get(id) ? byId.get(id).name : id);
  const sumOf = (id) => (byId.get(id) ? byId.get(id).summary : '');

  const fanInRanking = [...fanIn.entries()]
    .map(([id, c]) => ({ id, fanIn: c, name: nameOf(id) }))
    .sort((a, b) => b.fanIn - a.fanIn).slice(0, 20);
  const fanOutRanking = [...fanOut.entries()]
    .map(([id, c]) => ({ id, fanOut: c, name: nameOf(id) }))
    .sort((a, b) => b.fanOut - a.fanOut).slice(0, 20);

  // Percentile helpers for entry point scoring
  const fanOutVals = [...fanOut.values()].sort((a, b) => a - b);
  const fanInVals = [...fanIn.values()].sort((a, b) => a - b);
  const pct = (sorted, p) => {
    if (!sorted.length) return 0;
    const idx = Math.min(sorted.length - 1, Math.floor(p * sorted.length));
    return sorted[idx];
  };
  const fanOutTop10 = pct(fanOutVals, 0.9);
  const fanInBottom25 = pct(fanInVals, 0.25);

  const entryNames = new Set(['index.ts','index.js','main.ts','main.js','app.ts','app.js',
    'server.ts','server.js','mod.rs','main.go','main.py','main.rs','manage.py','app.py',
    'wsgi.py','asgi.py','run.py','__main__.py','Application.java','Main.java','Program.cs',
    'config.ru','index.php','App.swift','Application.kt','main.cpp','main.c','main.dart']);

  const depth = (fp) => (fp ? fp.split('/').length - 1 : 0);

  const epScores = [];
  for (const n of nodes) {
    let score = 0;
    const fp = n.filePath || '';
    if (n.type === 'document') {
      const isRoot = depth(fp) === 0;
      if (n.name === 'README.md' && isRoot) score += 5;
      else if (/\.md$/.test(n.name) && isRoot) score += 2;
    } else if (n.type === 'file') {
      if (entryNames.has(n.name)) score += 3;
      if (depth(fp) <= 1) score += 1;
      if (fanOut.get(n.id) >= fanOutTop10 && fanOutTop10 > 0) score += 1;
      if (fanIn.get(n.id) <= fanInBottom25) score += 1;
    }
    if (score > 0) epScores.push({ id: n.id, score, name: n.name, summary: sumOf(n.id) });
  }
  epScores.sort((a, b) => b.score - a.score);
  const entryPointCandidates = epScores.slice(0, 5);

  // BFS from top CODE entry point (skip documents)
  const codeEP = epScores.find(c => byId.get(c.id) && byId.get(c.id).type !== 'document');
  const startNode = codeEP ? codeEP.id : (nodes.find(n => n.type === 'file') || {}).id;
  const order = [];
  const depthMap = {};
  if (startNode) {
    const seen = new Set([startNode]);
    let frontier = [startNode];
    depthMap[startNode] = 0;
    order.push(startNode);
    let d = 0;
    while (frontier.length) {
      const next = [];
      for (const cur of frontier) {
        for (const nb of (forwardAdj.get(cur) || [])) {
          if (!seen.has(nb)) {
            seen.add(nb);
            depthMap[nb] = d + 1;
            order.push(nb);
            next.push(nb);
          }
        }
      }
      frontier = next;
      d++;
    }
  }
  const byDepth = {};
  for (const [id, dd] of Object.entries(depthMap)) {
    (byDepth[dd] = byDepth[dd] || []).push(id);
  }

  // Non-code inventory
  const nonCodeFiles = { documentation: [], infrastructure: [], data: [], config: [] };
  for (const n of nodes) {
    const rec = { id: n.id, name: n.name, type: n.type, summary: n.summary };
    if (n.type === 'document') nonCodeFiles.documentation.push(rec);
    else if (['service','pipeline','resource'].includes(n.type)) nonCodeFiles.infrastructure.push(rec);
    else if (['table','schema','endpoint'].includes(n.type)) nonCodeFiles.data.push(rec);
    else if (n.type === 'config') nonCodeFiles.config.push(rec);
  }

  // Clusters: bidirectional pairs, then expand
  const edgeKey = new Set();
  for (const e of edges) {
    if (e.type === 'imports' || e.type === 'calls') edgeKey.add(e.source + '|||' + e.target);
  }
  const undirectedCount = new Map(); // pairKey -> count of directed edges between
  const pairOf = (a, b) => (a < b ? a + '|||' + b : b + '|||' + a);
  for (const e of edges) {
    const k = pairOf(e.source, e.target);
    undirectedCount.set(k, (undirectedCount.get(k) || 0) + 1);
  }
  const seedClusters = [];
  for (const [k] of undirectedCount) {
    const [a, b] = k.split('|||');
    if (edgeKey.has(a + '|||' + b) && edgeKey.has(b + '|||' + a)) {
      seedClusters.push(new Set([a, b]));
    }
  }
  // neighbor map (undirected) for expansion
  const neigh = new Map();
  for (const n of nodes) neigh.set(n.id, new Set());
  for (const e of edges) {
    if (neigh.has(e.source) && neigh.has(e.target)) {
      neigh.get(e.source).add(e.target);
      neigh.get(e.target).add(e.source);
    }
  }
  const clusters = [];
  for (const c of seedClusters) {
    let changed = true;
    while (changed && c.size < 5) {
      changed = false;
      for (const cand of byId.keys()) {
        if (c.has(cand)) continue;
        let links = 0;
        for (const m of c) if (neigh.get(cand) && neigh.get(cand).has(m)) links++;
        if (links >= 2) { c.add(cand); changed = true; if (c.size >= 5) break; }
      }
    }
    let ec = 0;
    const arr = [...c];
    for (let i = 0; i < arr.length; i++)
      for (let j = 0; j < arr.length; j++)
        if (i !== j && edgeKey.has(arr[i] + '|||' + arr[j])) ec++;
    clusters.push({ nodes: arr, edgeCount: ec });
  }
  // dedup clusters by member set
  const seenSets = new Set();
  const uniqClusters = [];
  for (const c of clusters.sort((a, b) => b.edgeCount - a.edgeCount)) {
    const key = [...c.nodes].sort().join(',');
    if (seenSets.has(key)) continue;
    seenSets.add(key);
    uniqClusters.push(c);
  }
  const topClusters = uniqClusters.slice(0, 10);

  // Node summary index
  const nodeSummaryIndex = {};
  for (const n of nodes) nodeSummaryIndex[n.id] = { name: n.name, type: n.type, summary: n.summary };

  const result = {
    scriptCompleted: true,
    entryPointCandidates,
    fanInRanking,
    fanOutRanking,
    bfsTraversal: { startNode, order, depthMap, byDepth },
    nonCodeFiles,
    clusters: topClusters,
    layers: { count: layers.length, list: layers },
    nodeSummaryIndex,
    totalNodes: nodes.length,
    totalEdges: edges.length,
  };
  fs.writeFileSync(outPath, JSON.stringify(result, null, 2));
  console.log('Analysis complete. Nodes:', nodes.length, 'Edges:', edges.length);
}

try { main(); } catch (e) { console.error('FATAL:', e.stack || e); process.exit(1); }
