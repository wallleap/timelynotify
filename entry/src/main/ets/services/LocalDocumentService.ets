import { util } from '@kit.ArkTS';
import { AppContextStore } from '../common/AppContextStore';

/** 构建时生成的文档清单，资源路径不接受路由参数直接拼接。 */
export interface LocalDocumentInfo {
  path: string;
  title: string;
  resource: string;
}

/** 原生滚动定位以章节为单位，正文仍由 Markdown 组件渲染。 */
export interface LocalDocumentSection {
  anchor: string;
  title: string;
  text: string;
}

export interface LocalDocumentTarget {
  document: LocalDocumentInfo;
  anchor: string;
}

interface LocalDocumentManifest {
  documents: LocalDocumentInfo[];
}

interface LocalDocumentContent {
  sections: LocalDocumentSection[];
}

/** 隔离文档资源读取和链接解析，不访问网络或任意沙箱文件。 */
export class LocalDocumentService {
  static isDocumentUrl(url: string): boolean {
    return /^https?:\/\/docs\.timelynotify\.oicode\.cn(?:[/?#]|$)/i.test(url);
  }

  /** 仅从应用包读取 UTF-8 资源，Context 缺失交由页面提供重试。 */
  private static async readJson(resource: string): Promise<string> {
    const context = AppContextStore.getInstance().getContext();
    if (!context) {
      throw new Error('应用尚未准备好');
    }
    try {
      const bytes: Uint8Array = await context.resourceManager.getRawFileContent('local-docs/' + resource);
      return util.TextDecoder.create('utf-8').decodeToString(bytes);
    } catch (_err) {
      throw new Error('无法读取内置文档资源');
    }
  }

  static async getDocuments(): Promise<LocalDocumentInfo[]> {
    const manifest = JSON.parse(await LocalDocumentService.readJson('manifest.json')) as LocalDocumentManifest;
    return manifest.documents;
  }

  static async getSections(document: LocalDocumentInfo): Promise<LocalDocumentSection[]> {
    const content = JSON.parse(await LocalDocumentService.readJson(document.resource)) as LocalDocumentContent;
    return content.sections;
  }

  /** 兼容站点目录、.md/.html、相对链接和锚点；只允许清单中的完整对象身份。 */
  static resolveLink(documents: LocalDocumentInfo[], currentPath: string, url: string): LocalDocumentTarget | null {
    let relative: string = url.trim();
    if (LocalDocumentService.isDocumentUrl(relative)) {
      relative = relative.replace(/^https?:\/\/docs\.timelynotify\.oicode\.cn/i, '') || '/';
    } else if (/^(?:[a-z][a-z0-9+.-]*:|\/\/)/i.test(relative)) {
      return null;
    }
    const hash: number = relative.indexOf('#');
    let anchor: string = '';
    try {
      anchor = hash >= 0 ? decodeURIComponent(relative.slice(hash + 1)) : '';
      relative = decodeURIComponent((hash >= 0 ? relative.slice(0, hash) : relative).split('?')[0]);
    } catch (_err) {
      return null;
    }
    if (/[\\\x00-\x1f]/.test(relative)) {
      return null;
    }
    const base: string = relative.startsWith('/') ? '' : currentPath.slice(0, currentPath.lastIndexOf('/') + 1);
    const parts: string[] = [];
    // 纯锚点保持当前文档；其它链接按文档源码所在目录解析。
    const source: string = relative.length === 0 ? currentPath : base + relative;
    for (const part of source.split('/')) {
      if (part === '' || part === '.') {
        continue;
      }
      if (part === '..') {
        if (parts.length === 0) {
          return null;
        }
        parts.pop();
      } else {
        parts.push(part);
      }
    }
    const normalized: string = parts.join('/');
    for (const document of documents) {
      const stem: string = document.path.replace(/\.md$/, '');
      const directory: string = document.path === 'index.md' ? '' : stem.replace(/\/index$/, '');
      if (normalized === document.path || normalized === stem || normalized === stem + '.html' ||
        normalized === directory || normalized === directory + '.html') {
        return { document, anchor };
      }
    }
    return null;
  }
}
