/* 将固定版本的文档源码转换为原生阅读资源；不联网、不改写子模块。 */
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');

const DOCUMENTS = [
  ['index.md', '使用指南'], ['fields/index.md', '推送参数'],
  ['faq/index.md', '常见问答'], ['deploy/index.md', '部署文档'],
  ['harkforward.md', 'HarkForward 使用说明'], ['sms.md', '短信转发'],
  ['api/index.md', 'API 文档'], ['api/TOKENS.md', 'Token 说明'],
  ['api/GOTIFY_COMPAT.md', 'Gotify 兼容接口'], ['api/MCP.md', 'MCP 接口']
];

/** 与文档站目录一致的可读锚点；忽略 Markdown 装饰和标点。 */
function slugify(text) {
  return text.replace(/<[^>]+>/g, '').replace(/\[([^\]]+)\]\([^)]*\)/g, '$1')
    .replace(/[`*~\\]/g, '').replace(/[^a-zA-Z0-9\u3400-\u9fff]+/g, '-')
    .replace(/^-|-$/g, '').toLowerCase() || 'heading';
}

/** 拒绝符号链接及越界路径，资源只取自已检出的文档目录。 */
function localFile(root, relative) {
  const file = path.resolve(root, relative);
  const real = fs.realpathSync(file);
  if (!real.startsWith(fs.realpathSync(root) + path.sep) || !fs.statSync(real).isFile()) {
    throw new Error('文档资源超出允许目录或不是文件');
  }
  return real;
}

/** 仅转换正文；围栏代码及行内代码中的示例保持原文。 */
function compileDocument(source, docPath, docsRoot, images) {
  const sections = [{ anchor: '', title: '', text: '' }];
  const seen = new Map();
  let fence = '';
  for (const line of source.replace(/\r\n/g, '\n').split('\n')) {
    const marker = line.match(/^\s{0,3}(`{3,}|~{3,})/);
    if (marker) {
      if (!fence) fence = marker[1];
      else if (marker[1][0] === fence[0] && marker[1].length >= fence.length) fence = '';
      sections[sections.length - 1].text += line + '\n';
      continue;
    }
    if (fence) {
      sections[sections.length - 1].text += line + '\n';
      continue;
    }
    const heading = line.match(/^#{1,6}\s+(.+?)\s*#*$/);
    if (heading) {
      const base = slugify(heading[1]);
      const count = seen.get(base) || 0;
      seen.set(base, count + 1);
      sections.push({ anchor: count ? `${base}-${count}` : base, title: heading[1], text: '' });
    }
    const transformed = line.split(/(`+[^`]*`+)/g).map((part, index) => {
      if (index % 2) return part;
      return part.replace(/!\[([^\]]*)\]\(([^)]+)\)/g, (_match, alt, raw) => {
        const src = raw.trim().replace(/^<|>$/g, '');
        if (/^(?:[a-z][a-z0-9+.-]*:|\/\/)/i.test(src)) {
          return `**[图片未内置${alt ? '：' + alt : ''}]**`;
        }
        const relative = decodeURIComponent(src.split(/[?#]/)[0]);
        const file = relative.startsWith('/')
          ? localFile(path.join(docsRoot, 'public'), relative.slice(1))
          : localFile(docsRoot, path.posix.join(path.posix.dirname(docPath), relative));
        if (!/\.(png|jpe?g|gif|webp|svg)$/i.test(file)) throw new Error('不支持的本地图片类型');
        const bytes = fs.readFileSync(file);
        const name = crypto.createHash('sha256').update(bytes).digest('hex') + path.extname(file).toLowerCase();
        images.set(name, bytes);
        return `![${alt}]($rawfile("local-docs/images/${name}"))`;
      }).replace(/<br\s*\/?\s*>/gi, ' · ').replace(/<\/?font\b[^>]*>/gi, '');
    }).join('');
    sections[sections.length - 1].text += transformed + '\n';
  }
  return sections.filter(section => section.text.trim().length > 0);
}

/** 按字节比较后写入，避免无变化时让资源编译失去增量缓存。 */
function writeChanged(file, data) {
  const bytes = Buffer.isBuffer(data) ? data : Buffer.from(data);
  if (fs.existsSync(file) && fs.readFileSync(file).equals(bytes)) return;
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, bytes);
}

/** 先完整校验再写资源；清理范围仅限本脚本拥有的 local-docs 目录。 */
function packageLocalDocs(projectRoot) {
  const docsRoot = path.join(projectRoot, 'docs-source/docs');
  if (!fs.existsSync(path.join(docsRoot, 'index.md'))) {
    throw new Error('缺少文档子模块，请先执行 git submodule update --init docs-source');
  }
  const images = new Map();
  const files = new Map();
  const documents = DOCUMENTS.map(([docPath, title], index) => {
    const source = fs.readFileSync(localFile(docsRoot, docPath), 'utf8');
    const sections = compileDocument(source, docPath, docsRoot, images);
    // 子模块中的空白占位文档明确提示，避免原生页出现无说明的空屏。
    if (sections.length === 0) sections.push({ anchor: '', title: '', text: '本文档暂未提供内容。' });
    const resource = `${index}.json`;
    files.set(resource, JSON.stringify({ sections }));
    return { path: docPath, title, resource };
  });
  files.set('manifest.json', JSON.stringify({ documents }));
  for (const [name, bytes] of images) files.set('images/' + name, bytes);
  const out = path.join(projectRoot, 'entry/src/main/resources/rawfile/local-docs');
  // 生成目录内不接受符号链接，防止清理越过脚本的资源边界。
  function prune(directory, prefix = '') {
    if (!fs.existsSync(directory)) return;
    if (fs.lstatSync(directory).isSymbolicLink()) throw new Error('生成资源目录不能是符号链接');
    for (const name of fs.readdirSync(directory)) {
      const file = path.join(directory, name);
      const relative = prefix + name;
      if (fs.lstatSync(file).isSymbolicLink()) throw new Error('生成资源不能是符号链接');
      if (fs.statSync(file).isDirectory()) prune(file, relative + '/');
      else if (!files.has(relative)) fs.unlinkSync(file);
    }
  }
  prune(out);
  for (const [name, data] of files) writeChanged(path.join(out, name), data);
  return { documents: documents.length, images: images.size };
}

module.exports = { compileDocument, packageLocalDocs, slugify };
if (require.main === module) {
  const result = packageLocalDocs(path.resolve(__dirname, '..'));
  process.stdout.write(`本地文档：${result.documents} 篇，${result.images} 张内置图片\n`);
}
