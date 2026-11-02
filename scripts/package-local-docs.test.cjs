/* 打包回归：防止代码示例被转换、远程图片泄漏及资源残留。 */
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { compileDocument, packageLocalDocs, slugify } = require('./package-local-docs.cjs');

test('站点 client-token 与转义的 device_key 锚点保持可达', () => {
  assert.equal(slugify('client_token'), 'client-token');
  assert.equal(slugify('GET /:device\\_key/message'), 'get-device-key-message');
});

test('保留代码示例，正文远程图片占位，标题生成可定位章节', () => {
  const source = '# 同名\n![远程图](https://example.invalid/a.png)\n' +
    '`![行内](https://example.invalid/inline.png)`\n```md\n' +
    '## 代码标题\n![示例](https://example.invalid/code.png)\n```\n# 同名\n正文';
  const sections = compileDocument(source, 'index.md', '.', new Map());
  assert.deepEqual(sections.map(section => section.anchor), ['同名', '同名-1']);
  assert.match(sections[0].text, /\[图片未内置：远程图\]/);
  assert.match(sections[0].text, /`!\[行内\]\(https:/);
  assert.match(sections[0].text, /## 代码标题\n!\[示例\]\(https:/);
});

test('本地图片打包、去重和缺图失败；忽略未引用的大型站点资源', () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'local-docs-test-'));
  try {
    fs.mkdirSync(path.join(root, 'public/images'), { recursive: true });
    fs.writeFileSync(path.join(root, 'public/images/a.png'), 'fixture-image');
    fs.writeFileSync(path.join(root, 'public/images/unused.png'), 'not-used');
    const images = new Map();
    const sections = compileDocument('![](/images/a.png)\n![again](/images/a.png)', 'index.md', root, images);
    assert.equal(images.size, 1);
    assert.equal(sections[0].text.match(/\$rawfile\("local-docs\/images\//g).length, 2);
    assert.throws(() => compileDocument('![](/images/missing.png)', 'index.md', root, images));
    fs.symlinkSync(__filename, path.join(root, 'public/images/escape.png'));
    assert.throws(() => compileDocument('![](/images/escape.png)', 'index.md', root, images), /超出/);
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});

test('真实文档全部打包，重复运行保持字节和 mtime，已删除派生资源被清除', () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'local-docs-test-'));
  try {
    fs.cpSync(path.resolve(__dirname, '../docs-source/docs'), path.join(root, 'docs-source/docs'), { recursive: true });
    assert.deepEqual(packageLocalDocs(root), { documents: 10, images: 12 });
    const out = path.join(root, 'entry/src/main/resources/rawfile/local-docs');
    const before = fs.statSync(path.join(out, 'manifest.json')).mtimeMs;
    fs.writeFileSync(path.join(out, 'old.json'), 'obsolete');
    packageLocalDocs(root);
    assert.equal(fs.statSync(path.join(out, 'manifest.json')).mtimeMs, before);
    assert.equal(fs.existsSync(path.join(out, 'old.json')), false);
    const manifest = JSON.parse(fs.readFileSync(path.join(out, 'manifest.json')));
    for (const document of manifest.documents) {
      const content = JSON.parse(fs.readFileSync(path.join(out, document.resource)));
      const anchors = content.sections.map(section => section.anchor);
      assert.equal(new Set(anchors).size, anchors.length, document.path);
      const text = content.sections.map(section => section.text).join('\n');
      // 网络图片仅允许留在代码示例中，不能作为图片节点存在于正文。
      assert.ok(content.sections.length > 0, document.path);
      if (document.path === 'deploy/index.md') assert.match(text, /\[图片未内置\]/);
    }
    fs.renameSync(path.join(root, 'docs-source/docs'), path.join(root, 'docs-source/absent'));
    assert.throws(() => packageLocalDocs(root), /submodule update --init/);
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});
