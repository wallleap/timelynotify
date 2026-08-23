import { common } from '@kit.AbilityKit';

// 全局 Context 存储：EntryAbility.onCreate 注入后，任何地方都能取到 UIAbilityContext
// 避免在组件/CustomDialog 之间到处传 context，也不用在声明期拿不到 context
export class AppContextStore {
  private static instance: AppContextStore | null = null;
  private appContext: common.Context | null = null;

  private constructor() {}

  static getInstance(): AppContextStore {
    if (!AppContextStore.instance) {
      AppContextStore.instance = new AppContextStore();
    }
    return AppContextStore.instance;
  }

  setContext(context: common.Context): void {
    this.appContext = context;
  }

  getContext(): common.Context | null {
    return this.appContext;
  }
}
