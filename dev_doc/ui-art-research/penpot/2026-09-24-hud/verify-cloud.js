// 在已连接目标文件的 Penpot MCP execute_code 中运行本文件。
// 只读；不恢复历史版本，不改变选择，也不依赖会话 storage。
const expected = {
  file: 'c828d3cf-7d4e-8145-8008-8f0919f9073c',
  page: '8086b853-2801-807d-8008-985af17836c7',
  revision: 215,
  main: '8086b853-2801-807d-8008-9cc915f221e9',
  sword: '8086b853-2801-807d-8008-9cc915f22203',
  marks: '8086b853-2801-807d-8008-9cc91ea160dd',
  qa: '7537319b-8c1a-8048-8008-a08a60c059ca',
  versionLabel: 'SoT HUD 定版 2026-09-24 · 左剑右印记',
  versionCreatedAt: '2026-09-23T17:02:21.075Z'
};
const f = penpot.currentFile, p = penpot.currentPage;
if (f?.id !== expected.file || p?.id !== expected.page) {
  return { passed: false, reason: '请先打开清单指定的文件和页面。', file: f?.id, page: p?.id };
}
const main = p.getShapeById(expected.main);
const sword = p.getShapeById(expected.sword);
const marks = p.getShapeById(expected.marks);
const qa = p.getShapeById(expected.qa);
if (!main || !sword || !marks || !qa) return { passed: false, reason: '定版节点缺失。' };
const localBounds = n => [n.x - main.x, n.y - main.y, n.width, n.height];
const equals = (a, b) => a.every((v, i) => Math.abs(v - b[i]) < 0.01);
const versions = await f.findVersions();
const namedVersion = versions.find(v => v.label === expected.versionLabel &&
  new Date(v.createdAt).toISOString() === expected.versionCreatedAt && !v.isAutosave);
const checks = {
  namedVersionPresent: !!namedVersion,
  revisionMatches: f.revn === expected.revision,
  mainBoundsMatch: equals([main.x, main.y, main.width, main.height], [0, 38900, 1280, 720]),
  swordBoundsMatch: equals(localBounds(sword), [32, 520, 366, 56]),
  marksBoundsMatch: equals(localBounds(marks), [886, 520, 278, 56])
};
return {
  passed: Object.values(checks).every(Boolean),
  capturedAt: new Date().toISOString(),
  file: f.id, page: p.id, revision: f.revn, checks,
  scope: '节点、布局和命名版本核验；视觉请对照仓库预览。修订变化时先检查差异。'
};
