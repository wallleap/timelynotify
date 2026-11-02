import { hapTasks } from '@ohos/hvigor-ohos-plugin';
import { execFileSync } from 'node:child_process';
import { resolve } from 'node:path';

export default {
  system: hapTasks, /* Built-in plugin of Hvigor. It cannot be modified. */
  plugins: [{
    pluginId: 'timelynotify.local-docs',
    // 配置期先生成资源，确保首次构建及增量构建的资源扫描都能看到文档变化。
    apply() {
      execFileSync(process.execPath, [resolve(__dirname, '../scripts/package-local-docs.cjs')], {
        stdio: 'inherit'
      });
    }
  }]
};
