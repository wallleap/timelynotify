import { hilog } from '@kit.PerformanceAnalysisKit';
import { promptAction, UIContext } from '@kit.ArkUI';
import { BusinessError, pasteboard } from '@kit.BasicServicesKit';
import { common, Want } from '@kit.AbilityKit';
import { fileIo, picker } from '@kit.CoreFileKit';
import { ServerEntry } from '../model/ServerEntry';
import { ServerManager } from '../services/ServerManager';
import { NotifyMessage } from '../model/NotifyMessage';
import { NotifyMessageService } from '../services/NotifyMessageService';
import { MessageCacheStore } from '../services/MessageCacheStore';
import { ServerSettingsDialog } from '../components/ServerSettingsDialog';
import {
  KEY_IMMERSIVE_LIGHT_ENABLED,
  resolveBlurStyle,
  SUPPORTS_IMMERSIVE_MATERIAL
} from '../utils/ImmersiveUtil';
import { hdsMaterial, HdsNavigation, HdsNavigationTitleMode, ScrollEffectType, TextStyleMode } from '@kit.UIDesignKit';
import {
  DOMAIN,
  KEY_HOME_TAB_INDEX,
  KEY_INDEX_PAGE_VISIBLE,
  KEY_NOTIFY_EDITING,
  KEY_NOTIFY_REFRESH_SIGNAL
} from '../common/Constant';
import showToast from '../components/showToast';

const TAG: string = 'NotifyView';

// 前台轮询间隔（ms）：「通知」Tab 可见期间静默拉取新消息，
// 补齐"用户停留列表页时新消息不及时出现"的场景
const POLL_INTERVAL_MS: number = 15000;

// HDS 顶栏右侧系统 menu 槽位（「多选/取消」文字胶囊 + 删除图标按钮）的占位宽度（vp）。
// stackBuilder 为全宽叠层，menu 悬浮叠加其上、不参与 Row 布局，需放一个等宽透明占位
// 约束标题区宽度，长标题省略号才会在按钮前收尾，不会钻到按钮下方。
// 宽度组成：文字胶囊 ≈60 + 按钮间距 ≈8 + 图标按钮 ≈40 + 视觉余量 ≈8
const TITLE_MENU_RESERVE_VP: number = 116;

// 列表项 inboxContent 多行摘要最多展示行数（与普通正文 maxLines(4) 保持一致）
const INBOX_LIST_MAX_LINES: number = 4;

// ====== 正文富文本解析：自动识别 URL 和验证码 ======

// 文本段类型
interface TextSegment {
  text: string;
  type: number; // 0=普通, 1=URL, 2=验证码
}
const SEG_NORMAL: number = 0;
const SEG_URL: number = 1;
const SEG_CODE: number = 2;

// 匹配项（临时结构，用于收集正则结果后排序合并）
interface MatchInfo {
  start: number;
  end: number;
  text: string;
  type: number;
}

// 列表展示分组：无 group 或同 group 仅加载到 1 条时按普通卡片展示；
// 同 group 达到 2 条及以上时折叠为一个 ListItemGroup（折叠卡 header + 展开后多条子 ListItem）
interface NotifySection {
  // ForEach 稳定键：普通卡片与分组使用不同前缀，避免虚拟列表复用错位
  key: string;
  // 非空表示该 section 是 group 分组
  groupKey: string;
  // 组内消息按时间倒序（新→旧），首条为最新消息
  messages: NotifyMessage[];
  // 是否以折叠分组样式渲染
  grouped: boolean;
}

/**
 * 将正文按 URL（http/https）和验证码（4-8 位连续数字）切分为文本段数组。
 * URL 段和验证码段在渲染时以强调色高亮 + 可点击；普通段按默认样式渲染。
 * 验证码区间若与 URL 重叠则跳过（避免把 URL 中的数字串误识别为验证码）。
 */
function parseTextSegments(text: string): TextSegment[] {
  if (!text || text.length === 0) {
    return [];
  }
  const urlPattern: RegExp = /https?:\/\/[^\s<>"'\])]+/g;
  const codePattern: RegExp = /\b\d{4,8}\b/g;

  const matches: MatchInfo[] = [];
  let m: RegExpExecArray | null;
  while ((m = urlPattern.exec(text)) !== null) {
    const info: MatchInfo = { start: m.index, end: m.index + m[0].length, text: m[0], type: SEG_URL };
    matches.push(info);
  }
  while ((m = codePattern.exec(text)) !== null) {
    // 跳过与已有 URL 匹配重叠的区间
    let overlaps = false;
    for (let i = 0; i < matches.length; i++) {
      if (m.index < matches[i].end && m.index + m[0].length > matches[i].start) {
        overlaps = true;
        break;
      }
    }
    if (!overlaps) {
      const info: MatchInfo = { start: m.index, end: m.index + m[0].length, text: m[0], type: SEG_CODE };
      matches.push(info);
    }
  }

  // 按起始位置排序后构建文本段数组
  matches.sort((a: MatchInfo, b: MatchInfo) => a.start - b.start);
  const segments: TextSegment[] = [];
  let lastEnd = 0;
  for (let i = 0; i < matches.length; i++) {
    if (matches[i].start > lastEnd) {
      segments.push({ text: text.substring(lastEnd, matches[i].start), type: SEG_NORMAL });
    }
    segments.push({ text: matches[i].text, type: matches[i].type });
    lastEnd = matches[i].end;
  }
  if (lastEnd < text.length) {
    segments.push({ text: text.substring(lastEnd), type: SEG_NORMAL });
  }
  return segments;
}

// 通知页 - 展示接收到的 HTTP 推送消息列表
@Component
export struct NotifyView {
  @State title: string = '';
  @State messages: NotifyMessage[] = [];
  @State loading: boolean = false;
  @State errorMsg: string = '';
  @State refreshing: boolean = false;
  @State hasClientToken: boolean = false;
  // 触底分页加载更老消息
  @State loadingMore: boolean = false;
  @State hasMore: boolean = true;
  // 点击查看的消息详情（bindContentCover 全屏模态）
  @State showDetail: boolean = false;
  @State selectedMessage: NotifyMessage | null = null;
  // 多选模式状态：经 @StorageLink 同步到 AppStorage，Index.onBackPress 读取以拦截系统返回退出编辑
  @StorageLink(KEY_NOTIFY_EDITING) @Watch('onIsEditingChanged') isEditing: boolean = false;
  @State selectedIds: number[] = [];
  // 导出选中消息：防重复触发
  @State exportingSelected: boolean = false;
  // 当前展开的 group 标识集合；折叠状态只属于 UI 展示层，数据源仍以 messages 为准
  @State expandedGroups: string[] = [];
  // 折叠态分组主卡片的实测高度（vp），按 groupKey 缓存。空壳层高度必须显式与主卡片一致：
  // 在虚拟化 List 中给空壳设 height('100%') 会被解析成接近整个列表视口的高度，空壳会拉成通屏大面板
  @State groupCardHeights: Map<string, number> = new Map<string, number>();
  // 左滑互斥：当前展开左滑的消息 ID（-1 表示无）
  // 状态栏高度（vp），详情模态标题栏顶部避让用；EntryAbility 沉浸式布局初始化时写入 AppStorage（键值见 ImmersiveUtil）
  @StorageProp('statusBarHeight') statusBarHeight: number = 36;
  // 底部导航条高度（vp），编辑操作栏与列表底部占位避让用
  @StorageProp('navBarHeight') navBarHeight: number = 0;
  // 沉浸光感用户开关（API 26+ 生效；MineView Toggle 切换后经 AppStorage 同步，此处自动重渲染切换分支）
  @StorageProp(KEY_IMMERSIVE_LIGHT_ENABLED) immersiveLightEnabled: boolean = true;
  // 主页当前选中 Tab 索引（Index 经 @StorageLink 写入）：切走「通知」Tab 时自动退出多选模式；
  // 切回「通知」Tab（值为 0）时自动刷新列表
  @StorageProp(KEY_HOME_TAB_INDEX) @Watch('onHomeTabIndexChanged') homeTabIndex: number = 0;
  // 通知列表刷新信号（EntryAbility 回前台/点击通知拉起时自增）：@Watch 变化后自动拉取最新消息，
  // 保证用户回到列表/点通知进来时列表始终是最新的
  @StorageProp(KEY_NOTIFY_REFRESH_SIGNAL) @Watch('onRefreshSignalChanged') refreshSignal: number = 0;
  // 主页页面可见状态（Index onPageShow/onPageHide 写入）：Index 被 router 跳转覆盖/退后台时组件
  // 自身不会销毁（aboutToDisappear 不触发），需借助页面级显隐信号停止/恢复前台轮询
  @StorageProp(KEY_INDEX_PAGE_VISIBLE) @Watch('onPageVisibleChanged') indexPageVisible: boolean = true;
  // 下拉刷新状态：自定义刷新指示器不会自动隐藏，需按状态控制显隐
  @State refreshState: RefreshStatus = RefreshStatus.Inactive;
  // ⚠️ ArkUI 官方模式：CustomDialogController 必须在 struct 字段声明时直接初始化
  private dialogController: CustomDialogController = new CustomDialogController({
    builder: ServerSettingsDialog(),
    alignment: DialogAlignment.Center,
    autoCancel: true,
    offset: { dx: 0, dy: 0 },
  });
  private onChange: ((list: ServerEntry[], curId: string) => void) | null = null;
  // 请求代际：服务器切换/新请求发起后递增，过期响应直接丢弃，防止旧服务器数据写入列表
  private loadSeq: number = 0;
  // 补拉标志：loadMessages 在请求进行中被调用时置 true，当前请求结束后补拉一次
  private loadQueued: boolean = false;
  private scroller: Scroller = new Scroller();
  // 前台轮询定时器句柄（setTimeout 链式循环；-1 表示当前无待执行任务）
  private pollTimer: number = -1;
  // 轮询启用开关：「通知」Tab 可见时为 true；与 pollTimer 配合，
  // 防止飞行中的轮询请求在切走 Tab 后又重启循环
  private pollingEnabled: boolean = false;
  // 轮询请求进行中标记：防止慢网络下请求堆积
  private pollInFlight: boolean = false;

  aboutToAppear() {
    // ServerManager 可能还在异步 load，必须先 await ensureLoaded 再读当前 server，
    // 否则 currentId='' 会走兜底生产 URL，显示/请求错误的地址。
    this.initAfterServerManagerReady();
    this.onChange = (_list: ServerEntry[], _curId: string): void => {
      // 切换服务器后列表会整体刷新，selectedIds 属于旧服务器的消息 ID，继续操作会错删/报错，必须退出多选
      this.exitEditMode();
      this.refresh();
      // 旧服务器的消息不属于新服务器：立即清空列表与分页状态（新服务器拉取失败时也不残留旧数据），
      // 并递增代际使飞行中的旧请求响应过期丢弃
      this.messages = [];
      this.hasMore = false;
      // 展开状态属于当前服务器，切换后一并清空
      this.expandedGroups = [];
      this.groupCardHeights = new Map<string, number>();
      this.loadSeq++;
      // 服务器切换后重新拉取消息
      this.loadMessages();
    };
    ServerManager.getInstance().addChangeListener(this.onChange);
    // 「通知」Tab 为默认首 Tab，组件创建即可见时启动前台轮询
    if (this.homeTabIndex === 0) {
      this.startPolling();
    }
  }

  aboutToDisappear() {
    if (this.onChange) {
      ServerManager.getInstance().removeChangeListener(this.onChange);
    }
    // 组件销毁时停止轮询，避免定时器泄漏
    this.stopPolling();
  }

  // 降级顶栏：低版本 SDK 手工 Stack 叠层，blurStyle + 半透明底色实现毛玻璃
  @Builder
  fallbackTitleBar() {
    Row({ space: 8 }) {
      Row({ space: 2 }) {
        Text(this.title)
          .fontSize(24)
          .fontColor($r('app.color.text_primary_color'))
          .fontWeight(FontWeight.Bold)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          // 短标题保持内容宽度、箭头紧贴标题；长标题时收缩出省略号
          // （Row/Column 子组件 flexShrink 默认 0，必须显式声明才会收缩）
          .flexShrink(1);

        Image($r('app.media.select_more'))
          .width(24)
          .height(24)
          .objectFit(ImageFit.Contain)
          .fillColor($r('app.color.text_primary_color'))
          .flexShrink(0)
          .onClick(() => {
            this.handleMoreClicked();
          });
      }
      .layoutWeight(1)
      .width(0)
      .padding({ right: 48 })
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        this.handleMoreClicked();
      });

      // 多选胶囊按钮：非编辑态进入多选；编辑态退出并清空选中
      this.multiSelectPill();

      // 删除胶囊按钮
      this.deletePill();
    }
    .width('100%')
    .padding({
      left: 16,
      right: 16,
      top: 16 + this.statusBarHeight,
      bottom: 16
    })
    .alignItems(VerticalAlign.Center)
    // blurStyle 只做模糊不调色 → 必须叠加半透明底色才看得到毛玻璃
    .backgroundBlurStyle(resolveBlurStyle('bar')!)
    .backgroundColor($r('app.color.index_page_top_glass_background'));
  }

  // 降级分支「多选/取消」胶囊按钮：未编辑态显示「多选」进入选择；编辑态显示「取消」清空/退出；
  // 毛玻璃模糊 + 半透明底色 + 高亮描边（与 HDS 分支系统 menu 槽位的两个按钮行为一致）
  @Builder
  multiSelectPill() {
    Row() {
      Text(this.isEditing ? '取消' : '多选')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary_color'))
    }
    .height(38)
    .padding({ left: 14, right: 14 })
    .borderRadius(38)
    .alignItems(VerticalAlign.Center)
    .border({ width: 1, color: $r('app.color.glass_button_border') })
    .backgroundBlurStyle(resolveBlurStyle('card')!)
    .backgroundColor($r('app.color.glass_button_background'))
    .onClick(() => {
      this.handleMultiSelectClicked();
    });
  }

  // 降级分支删除胶囊按钮：样式与「多选」一致，内部为删除图标；
  // 非编辑态点击走清空全部（二次确认并重点提示不可恢复），编辑态点击删除选中消息
  @Builder
  deletePill() {
    Row() {
      Image($r('app.media.delete'))
        .width(24)
        .height(24)
        .objectFit(ImageFit.Contain)
        .fillColor($r('app.color.text_primary_color'))
    }
    .height(38)
    .width(38)
    .borderRadius(38)
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .border({ width: 1, color: $r('app.color.glass_button_border') })
    .backgroundBlurStyle(resolveBlurStyle('card')!)
    .backgroundColor($r('app.color.glass_button_background'))
    .onClick(() => {
      this.handleDeletePillClicked();
    });
  }

  // HDS 顶栏自定义内容（塞入 HdsNavigation.titleBar.content.stackBuilder）。
  // 状态栏避让由 titleBar 级 avoidLayoutSafeArea: true 负责（系统将内容整体下移 statusBarHeight）；
  // 此处 padding 只留纯视觉余量，不得再叠加 statusBarHeight（titleBar 高度固定，会溢出裁剪 → 文字消失）。
  // ⚠️ stackBuilder 是全宽叠层，与右侧系统 menu 槽位区域重叠：
  //   1. 标题 Row 与透明占位节点都必须设 hitTestBehavior(None)（默认 Default 会阻塞兄弟节点），
  //      否则点击 menu 的「多选/删除」会误触发 title 事件；None 不阻塞子节点，标题/图标的 onClick 仍生效；
  //   2. menu 悬浮叠加不参与 Row 布局，标题 Row 末尾放一个等宽透明占位（TITLE_MENU_RESERVE_VP），
  //      标题区宽度才会被真实约束，长标题省略号在按钮前收尾，不会钻到按钮下方。
  @Builder
  customTitleContent() {
    Row({ space: 8 }) {
      Row({ space: 2 }) {
        Text(this.title)
          .fontSize(24)
          .fontColor($r('app.color.text_primary_color'))
          .fontWeight(FontWeight.Bold)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          // 不占满剩余空间：短标题按内容宽度排布，展开箭头紧贴标题；
          // 长标题时外层定宽 Row（layoutWeight + menu 占位）空间不足，本节点 flexShrink(1) 被压缩出省略号。
          // 注意：Row/Column 子组件 flexShrink 默认 0（不收缩），必须显式声明，否则长标题会把箭头挤出
          .flexShrink(1)
          // 点击标题文本打开服务器设置弹窗
          .onClick(() => {
            this.handleMoreClicked();
          });

        Image($r('app.media.select_more'))
          .width(24)
          .height(24)
          .objectFit(ImageFit.Contain)
          .fillColor($r('app.color.text_primary_color'))
          .flexShrink(0)
          .onClick(() => {
            this.handleMoreClicked();
          });
      }
      .layoutWeight(1)
      .width(0)
      .alignItems(VerticalAlign.Center)
      // 自身不参与触摸测试，避免拦截右侧系统 menu 槽位按钮的点击（子节点 onClick 不受影响）
      .hitTestBehavior(HitTestMode.None);

      // 系统 menu 槽位等宽透明占位：把 menu 悬浮区从 Row 布局中扣除，标题省略号才不会被按钮盖住
      Row()
        .width(TITLE_MENU_RESERVE_VP)
        .height(1)
        .hitTestBehavior(HitTestMode.None);
    }
    .width('100%')
    .padding({
      left: 16,
      right: 16,
      top: 16,
      bottom: 16
    })
    .alignItems(VerticalAlign.Center);
  }

  // NotifyView Refresh 主体（含分支 view），两条渲染路径共用
  @Builder
  refreshContentBody() {
    Refresh({ refreshing: this.refreshing, builder: this.refreshHeaderBuilder() }) {
      if (this.needGuideToConfig()) {
        this.guideView();
      } else if (this.loading && this.messages.length === 0) {
        this.loadingView();
      } else if (this.errorMsg.length > 0 && this.messages.length === 0) {
        this.errorView();
      } else if (this.messages.length === 0) {
        this.emptyView();
      } else {
        this.listView();
      }
    }
    // ⚠️ 官方 HDS 动态模糊必配：Refresh 外层也不裁剪溢出，否则穿出 titleBar 背面的内容会被 Refresh 边界裁掉
    .clip(false)
    .width('100%')
    .height('100%')
    .onStateChange((state: RefreshStatus) => {
      // 同步刷新状态给自定义指示器，控制其显隐
      // Done（刷新结束）不会自动回到 Inactive，需直接视为隐藏，避免加载完成后指示器常驻
      this.refreshState = state === RefreshStatus.Done ? RefreshStatus.Inactive : state;
    })
    .onRefreshing(() => {
      this.refreshing = true;
      this.loadMessages();
    });
  }

  // NotifyView 主体（Refresh + 多选底部操作栏），两条渲染路径共用
  @Builder
  viewportBody() {
    Column() {
      Column() {
        this.refreshContentBody();
      }
      .width('100%')
      .layoutWeight(1);

      // 多选模式底部操作栏
      if (this.isEditing && this.messages.length > 0) {
        this.editActionBar();
      }
    }
    .width('100%')
    .height('100%');
  }

  build() {
    if (SUPPORTS_IMMERSIVE_MATERIAL && this.immersiveLightEnabled) {
      // ─── API 26+: HdsNavigation 原生沉浸光感（titleBar 内置 systemMaterialEffect）───
      HdsNavigation() {
        this.viewportBody();
      }
      .titleBar({
        enableComponentSafeArea: true,
        // ⚠️ stackBuilder 全自定义区域系统不做状态栏避让（系统 mainTitle 槽位才自带避让），
        // 必须显式开启 avoidLayoutSafeArea，titleBar 内容整体下移 statusBarHeight，总高自动变为 statusBarHeight+56；
        // stackBuilder 内部不要再手工加 statusBarHeight（titleBar 高度固定会溢出裁剪）
        avoidLayoutSafeArea: true,
        content: {
          // 全自定义标题区：服务器标题 + 更多入口（胶囊按钮已迁至系统 menu 槽位获得沉浸光感）
          stackBuilder: (): void => {
            this.customTitleContent();
          },
          // 系统槽位按钮：系统渲染胶囊/图标样式，自动跟随 titleBar 沉浸光感材质
          menu: {
            value: [
              {
                content: {
                  // 文字按钮必须显式指定 TextStyleMode.NORMAL（胶囊样式），默认为图标渲染模式
                  label: this.isEditing ? '取消' : '多选',
                  type: TextStyleMode.NORMAL,
                  action: (): void => {
                    this.handleMultiSelectClicked();
                  }
                }
              },
              {
                content: {
                  icon: $r('app.media.delete'),
                  action: (): void => {
                    this.handleDeletePillClicked();
                  }
                }
              }
            ]
          },
        },
        style: {
          // 滚动到顶栏下方时触发 GradientBlur 渐变模糊：采样下层内容做动态光感模糊
          scrollEffectOpts: {
            enableScrollEffect: true,
            scrollEffectType: ScrollEffectType.GRADIENT_BLUR
          },
          systemMaterialEffect: {
            materialType: hdsMaterial.MaterialType.ADAPTIVE,
            // 官方推荐 ADAPTIVE：系统按设备算力自适应档位，避免低端机卡顿/发热
            //（EXQUISITE 需 getSystemMaterialTypes() 检测支持后才可硬编码）
            materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
          },
        }
      })
      .hideBackButton(true)
      .titleMode(HdsNavigationTitleMode.MINI)
      // 官方：绑定 List 滚动 → scrollEffectOpts 才会根据滚动偏移激活 GradientBlur 渐变模糊
      .bindToScrollable([this.scroller])
      .width('100%')
      .height('100%')
      // 点击消息卡片弹出全屏详情模态（内部已做状态栏避让 + 顶部圆角）
      .bindContentCover(this.showDetail, this.detailBuilder(), {
        onDisappear: () => {
          this.showDetail = false;
        }
      })
      .backgroundColor($r('app.color.index_page_body_background'));
    } else {
      // ─── API < 26: Stack + 手工顶栏叠层（backgroundBlurStyle 降级）───
      Column() {
        Stack({ alignContent: Alignment.Top }) {
          this.refreshContentBody();
          // 顶栏层（上层）：blurStyle + 半透明底色糊住下层滚动内容
          this.fallbackTitleBar();
        }
        .width('100%')
        .layoutWeight(1);

        // 多选模式底部操作栏
        if (this.isEditing && this.messages.length > 0) {
          this.editActionBar();
        }
      }
      .width('100%')
      .height('100%')
      .bindContentCover(this.showDetail, this.detailBuilder(), {
        onDisappear: () => {
          this.showDetail = false;
        }
      })
      .backgroundColor($r('app.color.index_page_body_background'));
    }
  }

  @Builder
  guideView() {
    Column({ space: 12 }) {
      Text('未配置客户端 Token')
        .fontSize(16)
        .fontColor($r('app.color.text_tertiary_color'));
      Text('查询历史消息需要客户端 Token 认证，请到「我的」页面配置')
        .fontSize(13)
        .fontColor($r('app.color.text_quinary_color'))
        .textAlign(TextAlign.Center)
        .width('70%');
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center);
  }

  @Builder
  loadingView() {
    Column({ space: 8 }) {
      LoadingProgress()
        .width(40)
        .height(40)
        .color($r('app.color.text_accent_color'));
      Text('加载中…')
        .fontSize(13)
        .fontColor($r('app.color.text_quinary_color'));
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center);
  }

  @Builder
  errorView() {
    Column({ space: 12 }) {
      Text(this.errorMsg)
        .fontSize(14)
        .fontColor($r('app.color.text_error_color'))
        .textAlign(TextAlign.Center)
        .width('80%');
      Text('下拉重试')
        .fontSize(13)
        .fontColor($r('app.color.text_accent_color'))
        .padding(8)
        .onClick(() => {
          this.loadMessages();
        });
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center);
  }

  @Builder
  emptyView() {
    Column({ space: 8 }) {
      Text('暂无消息')
        .fontSize(15)
        .fontColor($r('app.color.text_quinary_color'));
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center);
  }

  // 仅在下拉/刷新过程中显示，静止（Inactive）时隐藏
  @Builder
  refreshHeaderBuilder() {
    Column() {
      // 顶部 spacer 让刷新圈显示在 titleBar 下方：
      // - HDS：enableComponentSafeArea 内容区起点已在 titleBar 总高（statusBarHeight+56）下方，
      //   spacer 仅需 8 余量；重复叠加 statusBarHeight 会导致刷新圈被双重下推（真机实证）
      // - 降级：Stack 叠层内容从窗口顶开始，需 statusBarHeight + titleBar(64) + 16 余量
      Row().height(SUPPORTS_IMMERSIVE_MATERIAL && this.immersiveLightEnabled ? 8 : this.statusBarHeight + 64 + 16);

      if (this.refreshState !== RefreshStatus.Inactive) {
        LoadingProgress()
          .width(28)
          .height(28)
          .color($r('app.color.text_accent_color'));
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center);
  }

  @Builder
  listView() {
    List({ space: 10, scroller: this.scroller }) {
      // 降级分支：Stack 叠层内容从窗口顶开始，占位还需叠加 statusBarHeight + titleBar(64) 手工避让
      if (SUPPORTS_IMMERSIVE_MATERIAL && this.immersiveLightEnabled) {
        ListItem() {
          Row()
            .width('100%')
            .height(4);
        }
      } else {
        ListItem() {
          Row()
            .width('100%')
            .height(this.statusBarHeight + 64 + 14);
        }
      }

      ForEach(this.buildSections(), (section: NotifySection) => {
        if (section.grouped) {
          if (this.isGroupExpanded(section.groupKey)) {
            // 展开态 = ListItemGroup：header 为分组名顶栏，每条消息是独立子 ListItem
            // （各自支持左滑删除/独立点击）。展开/收起在 animateTo 中切换，
            // 子 ListItem 增删由 List 做布局动画
            ListItemGroup({ space: 0, header: this.groupExpandedHeader(section) }) {
              ForEach(section.messages, (m: NotifyMessage, index?: number) => {
                ListItem() {
                  // 第一条绑定共享元素 id（与折叠卡内容一一对应），其余行传空串不参与
                  this.groupMessageRow(m, index === section.messages.length - 1,
                    index === 0 ? `gmc:${section.groupKey}` : '');
                }
                .swipeAction({
                  end: {
                    builder: () => {
                      // 仅末行删除按钮带右下圆角，与分组卡片底边弧线衔接
                      this.swipeDeleteBuilder(m, 0, index === section.messages.length - 1 ? 12 : 0);
                    }
                  }
                });
              }, (m: NotifyMessage) => `group-child:${section.groupKey}:${m.id}`);
            }
          } else {
            // 折叠态 = 单个 ListItem（层叠卡片）。swipeAction 只能挂在 ListItem 上、
            // ListItemGroup 的 header 不支持左滑，因此折叠态必须独立成 ListItem；
            // 左滑删除按钮语义为「删除整个分组」
            ListItem() {
              this.groupHeaderBuilder(section);
            }
            .swipeAction({
              end: {
                builder: () => {
                  this.swipeDeleteGroupBuilder(section);
                }
              }
            });
          }
        } else {
          ListItem() {
            this.messageRow(section.messages[0]);
          }
          .swipeAction({
            end: {
              builder: () => {
                // 普通卡片四角圆角 12，删除按钮右侧两角与卡片弧线一致
                this.swipeDeleteBuilder(section.messages[0], 12, 12);
              }
            }
          });
        }
      }, (section: NotifySection) => section.key);

      // 触底加载指示器
      if (this.loadingMore) {
        ListItem() {
          Row({ space: 6 }) {
            LoadingProgress()
              .width(18)
              .height(18)
              .color($r('app.color.text_accent_color'));
            Text('加载更多…')
              .fontSize(12)
              .fontColor($r('app.color.text_quinary_color'));
          }
          .width('100%')
          .height(44)
          .justifyContent(FlexAlign.Center);
        }
      } else if (!this.hasMore && this.messages.length > 0) {
        ListItem() {
          Text('没有更多了')
            .fontSize(12)
            .fontColor($r('app.color.text_quinary_color'))
            .width('100%')
            .height(40)
            .textAlign(TextAlign.Center);
        }
      }

      // 底部占位：随内容一起滚动，末尾消息才能滑入 TabBar 毛玻璃下方（padding 是硬边界做不到）
      // TabBar 总高 = 56 + 导航条高度，占位 64/72 保持视觉余量不变
      ListItem() {
        Row()
          .width('100%')
          .height(SUPPORTS_IMMERSIVE_MATERIAL && this.immersiveLightEnabled ? this.navBarHeight + 72 :
            this.navBarHeight + 64);
      }
    }
    .width('100%')
    .height('100%')
    // 顶/底避让均由首尾占位实现（可滚动穿透顶栏/TabBar）；左右仅保留边距
    .padding({ left: 16, right: 16 })
    .align(Alignment.Top)
    // ⚠️ 官方 HDS 动态模糊必配：List 不裁剪溢出内容，这样卡片才能向上"穿出"至 titleBar 背面被材质采样
    .clip(false)
    .onReachEnd(() => {
      // 列表按时间倒序（新→旧），末尾是最旧消息；取末尾消息 ID 作 since 加载更老的
      this.loadMore();
    });
  }

  // 自定义下拉刷新指示器：顶部留出状态栏高度 + 毛玻璃顶栏高度（64），
  // 刷新圈显示在顶栏下方而不是被玻璃盖住

  @Builder
  messageRow(m: NotifyMessage) {
    Row({ space: 12 }) {
      if (this.isEditing) {
        Checkbox()
          .select(this.isSelected(m.id))
          .selectedColor($r('app.color.text_accent_color'))
          .shape(CheckBoxShape.CIRCLE);
      }
      Column({ space: 6 }) {
        // 上：标题/副标题/正文（左占剩余空间）+ icon（右 42x42）
        Row({ space: 8 }) {
          Column() {
            if (m.title && m.title.length > 0) {
              Text(m.title)
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.text_primary_color'))
                .width('100%')
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis });
            }
            if (m.subtitle && m.subtitle.length > 0) {
              Text(m.subtitle)
                .fontSize(13)
                .fontColor($r('app.color.text_accent_color'))
                .width('100%')
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis });
            }
            // 正文优先展示 extras.inboxcontent 多行摘要（每行一条），无则回退普通正文
            if (m.inboxContent.length > 0) {
              this.inboxRichTextList(m.inboxContent)
            } else if (m.body && m.body.length > 0) {
              this.bodyRichTextList(m.body)
            }
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start);

          if (m.image && m.image.length > 0) {
            Image(m.image)
              .width(38)
              .height(38)
              .borderRadius(12)
              .objectFit(ImageFit.Cover)
              .flexShrink(0)
              .alt($r('app.media.app_icon'));
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Top);

        // 下：时间居右
        Text(this.formatTime(m.timestamp))
          .fontSize(11)
          .fontColor($r('app.color.text_quinary_color'))
          .width('100%')
          .textAlign(TextAlign.End);
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start);
    }
    .width('100%')
    .padding(12)
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(12)
    .alignItems(VerticalAlign.Top)
    .onClick(() => {
      if (this.isEditing) {
        this.toggleSelect(m.id);
      } else {
        this.selectedMessage = m;
        this.showDetail = true;
      }
    });
  }

  // 「N 条通知」灰色胶囊徽标（折叠卡底部与展开态顶栏共用同一视觉，纯视觉无交互）。
  // 几何转场绑在调用处包裹它的直接 Row 节点上（gmb）；注意该 Row 不可嵌套在另一个
  // geometryTransition 节点内部，否则收起方向的 in 节点 opacity 不会恢复（徽标永久消失）
  @Builder
  groupCountBadge(count: number) {
    Text(`${count} 条通知`)
      .fontSize(10)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('app.color.group_count_badge_text'))
      .padding({ left: 8, right: 8, top: 2, bottom: 2 })
      .borderRadius(10)
      .backgroundColor($r('app.color.group_count_badge_bg'));
  }

  // 分组头卡片内容（主卡片与空壳层共用）：
  // visible=true → 正常渲染（主卡片）；visible=false → 内容 Visibility.Hidden（不可见但保留布局空间，
  // 使空壳与主卡片高度一致，解决空 Column height('100%') 在内容尺寸 Stack 中高度为 0 的问题）
  @Builder
  groupCardContent(section: NotifySection, visible: boolean) {
    if (this.isEditing) {
      Checkbox()
        .select(this.isGroupAllSelected(section.messages))
        .selectedColor($r('app.color.text_accent_color'))
        .shape(CheckBoxShape.CIRCLE)
        .visibility(visible ? Visibility.Visible : Visibility.Hidden)
        .onClick(() => {
          this.toggleGroupSelection(section.messages);
        });
    }
    Column({ space: 6 }) {
      // 上：标题/副标题/正文（左占剩余空间）+ icon（右 38x38）
      // 该 Row 与展开列表第一行的上半 Row 结构完全一致，作为 gmc 共享元素：
      // 展开时平滑「飞」到第一行，收起时反向飞回。只包上半 Row（不含底部徽标/时间行），
      // 避免与徽标的 gmb 转场嵌套（嵌套几何转场会导致徽标收起后 opacity 不恢复）
      Row({ space: 8 }) {
        Column() {
          if (section.messages[0].title && section.messages[0].title.length > 0) {
            Text(section.messages[0].title)
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary_color'))
              .width('100%')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis });
          }
          if (section.messages[0].subtitle && section.messages[0].subtitle.length > 0) {
            Text(section.messages[0].subtitle)
              .fontSize(13)
              .fontColor($r('app.color.text_accent_color'))
              .width('100%')
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis });
          }
          // 正文优先展示 extras.inboxcontent 多行摘要，无则回退普通正文
          if (section.messages[0].inboxContent.length > 0) {
            this.inboxRichTextList(section.messages[0].inboxContent)
          } else if (section.messages[0].body && section.messages[0].body.length > 0) {
            this.bodyRichTextList(section.messages[0].body)
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start);

        if (section.messages[0].image && section.messages[0].image.length > 0) {
          Image(section.messages[0].image)
            .width(38)
            .height(38)
            .borderRadius(12)
            .objectFit(ImageFit.Cover)
            .flexShrink(0)
            .alt($r('app.media.app_icon'));
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)
      .geometryTransition(visible ? `gmc:${section.groupKey}` : '')
      .transition(TransitionEffect.OPACITY.animation({ duration: 200 }));

      // 下：左侧条数徽标（gmb 共享元素，飞到展开顶栏；与 gmc 是兄弟节点，不可嵌套），右侧时间
      // （折叠态不放箭头，点击整张卡片展开）
      Row() {
        Row() {
          this.groupCountBadge(section.messages.length);
        }
        .flexShrink(0)
        .geometryTransition(visible ? `gmb:${section.groupKey}` : '')
        .transition(TransitionEffect.OPACITY.animation({ duration: 200 }));
        Blank();
        Text(this.formatTime(section.messages[0].timestamp))
          .fontSize(11)
          .fontColor($r('app.color.text_quinary_color'));
      }
      .width('100%')
      .margin({ top: 2 })
      .alignItems(VerticalAlign.Center);
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Start)
    .visibility(visible ? Visibility.Visible : Visibility.Hidden)
    .onClick(() => {
      this.handleGroupHeaderClick(section);
    });
  }

  // 折叠态分组卡片左滑露出的删除按钮：语义为删除整个分组（组内全部消息）
  @Builder
  swipeDeleteGroupBuilder(section: NotifySection) {
    Row() {
      Text('删除')
        .fontSize(15)
        .fontColor('#FFFFFF')
        .padding({ left: 20, right: 20 })
        .onClick(() => {
          this.confirmDeleteGroup(section);
        });
    }
    .height('100%')
    .backgroundColor($r('app.color.text_error_color'))
    // 与主卡片右侧 12vp 圆角衔接，避免左滑时方角红块在卡片弧线外露出灰底
    .borderRadius({ topLeft: 0, topRight: 12, bottomLeft: 0, bottomRight: 12 });
  }

  // 折叠态层叠空壳层：视觉上是一张「内缩 + 下沉」的卡片，垫在主卡片背面制造层级感。
  // inset = 单侧水平内缩 vp，yOffset = 向下偏移 vp。
  // 高度直接取主卡片实测高度（groupCardHeights）：不能用 height('100%')，
  // 虚拟化 List 中百分比高度会被解析成接近整个列表视口高度，空壳会拉成通屏大面板；
  // 也不渲染 Hidden 占位内容，避免多一层布局。hitTestBehavior(None) 不拦截触摸。
  @Builder
  groupShellLayer(section: NotifySection, inset: number, yOffset: number, bgColor: Resource) {
    Row() {
      Column()
        .layoutWeight(1)
        .height('100%')
        .borderRadius(12)
        .backgroundColor(bgColor);
    }
    .width('100%')
    // 高度 = 主卡片实测高度（vp）；未测量到（0）时由调用方跳过渲染，不会出现高度塌陷
    .height(this.groupCardHeights.get(section.groupKey) ?? 0)
    .padding({ left: inset, right: inset })
    .offset({ y: yOffset })
    .hitTestBehavior(HitTestMode.None);
  }

  // 分组头卡片：展示组内最新一条消息，右下角显示组内条数与展开/收起箭头。
  // 折叠态在主卡片后方垫 1-2 张空壳卡片（向下偏移 + 两侧内缩），产生层叠透视效果：
  //   2 条 → 1 层叠加（offset 9vp，左右内缩 8vp）
  //   3 条及以上 → 2 层叠加（浅层 offset 9vp/内缩 8vp，深层 offset 18vp/内缩 16vp）
  // 空壳半透明无投影（与全应用卡片平面风格一致），借鉴 iOS 通知堆叠的半透明后层：
  // 亮色=半透明白罩（后层比背景略亮，像叠放的白纸，shallow 80% / deep 50%），
  // 暗色=半透明白罩（后层比背景略亮，shallow 12% / deep 4%）；
  // 两档不同透明度区分浅/深两层，层次同时由「越深越窄越低」的几何阶梯加强
  // 展开后空壳层消失，仅展示主卡片 + 子项列表
  // 空壳层渲染相同内容但 Visibility.Hidden（保留布局空间保证高度一致），仅背景可见；
  // hitTestBehavior(None) 确保空壳不拦截任何触摸事件
  //
  // ⚠️ 关键：空壳层用 offset 向下偏移后会超出 Stack 内容底部 → 必须给 Stack 加
  // paddingBottom 预留空间，让空壳层完全落在 Stack 边界内（否则会被父容器裁剪不可见）。
  @Builder
  groupHeaderBuilder(section: NotifySection) {
    Stack({ alignContent: Alignment.TopStart }) {
      // ─── 叠加空壳层（折叠态 only）───
      // Stack 中后声明的子组件在上层，空壳须先于主卡片声明才能垫在背面；
      // 主卡片高度测量完成后才渲染，避免首帧 0 高闪烁
      if (!this.isGroupExpanded(section.groupKey) && section.messages.length >= 3
        && (this.groupCardHeights.get(section.groupKey) ?? 0) > 0) {
        // 深层：下沉 18vp、两侧各内缩 16vp，视觉最远；比浅层更深一档，两层阶梯可辨
        this.groupShellLayer(section, 16, 18, $r('app.color.card_shell_deep'));
      }
      if (!this.isGroupExpanded(section.groupKey) && section.messages.length >= 2
        && (this.groupCardHeights.get(section.groupKey) ?? 0) > 0) {
        // 浅层：下沉 9vp、两侧各内缩 8vp，介于深层与主卡片之间
        this.groupShellLayer(section, 8, 9, $r('app.color.card_shell_shallow'));
      }
      // ─── 主卡片（最上层）───
      Row({ space: 12 }) {
        this.groupCardContent(section, true)
      }
      .width('100%')
      .padding(12)
      .backgroundColor($r('app.color.card_background'))
      .borderRadius(12)
      .alignItems(VerticalAlign.Top)
      // 卡片底色随折叠态离场淡入淡出，配合消息内容的共享元素飞行，避免白底瞬间跳变
      .transition(TransitionEffect.OPACITY.animation({ duration: 200 }))
      // 上报主卡片实测高度（vp），空壳层用同一高度渲染；内容随轮询变化时同步更新
      .onAreaChange((_oldValue: Area, newValue: Area) => {
        // 当前 API 下 Area.height 的回调数值单位为 vp（不是 px，切勿再做 px2vp，
        // 否则空壳高度会被缩小数倍、完全藏在主卡片身后不可见）
        this.updateGroupCardHeight(section.groupKey, newValue.height as number);
      });
    }
    .width('100%')
    // paddingBottom 恰好等于空壳下沉量（无描边故无边框余量）：空壳底边与 Stack 底部齐平，
    // 空壳下沿到下一项的距离 = List space(10vp)，与普通卡片间距视觉一致；展开/单条 → 0
    .padding({ bottom:
      (!this.isGroupExpanded(section.groupKey) && section.messages.length >= 3) ? 18
        : (!this.isGroupExpanded(section.groupKey) && section.messages.length >= 2) ? 9 : 0
    });
  }

  // 展开态分组顶栏：app 图标 + group 名称（左）+ 条数 + 折叠箭头（右），底部分隔线，仅上方圆角
  @Builder
  groupExpandedHeader(section: NotifySection) {
    Column() {
      Row({ space: 8 }) {
        if (this.isEditing) {
          Checkbox()
            .select(this.isGroupAllSelected(section.messages))
            .selectedColor($r('app.color.text_accent_color'))
            .shape(CheckBoxShape.CIRCLE)
        } else {
          // 顶栏图标与消息卡片保持一致：优先用消息自带图标，无则回退 app 图标
          if (section.messages[0].image && section.messages[0].image.length > 0) {
            Image(section.messages[0].image)
              .width(24)
              .height(24)
              .borderRadius(6)
              .objectFit(ImageFit.Cover)
              .flexShrink(0)
              .alt($r('app.media.app_icon'));
          } else {
            Image($r('app.media.app_icon'))
              .width(24)
              .height(24)
              .borderRadius(6)
              .objectFit(ImageFit.Cover)
              .flexShrink(0);
          }
        }
        Text(section.groupKey)
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary_color'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1);
        // 条数徽标与折叠卡共用同一 builder + 同一 gmb 共享元素 id：
        // 展开时徽标从卡内底部飞到顶栏，收起时反向飞回
        Row() {
          this.groupCountBadge(section.messages.length);
        }
        .flexShrink(0)
        .geometryTransition(`gmb:${section.groupKey}`)
        .transition(TransitionEffect.OPACITY.animation({ duration: 200 }));
        // 箭头朝上（右箭头 -90°）仅作视觉指示，点击区域由整行统一处理；
        // 尺寸/颜色与 MineView 右箭头保持一致
        Image($r('app.media.arrow_right'))
          .width(20)
          .height(20)
          .objectFit(ImageFit.Contain)
          .fillColor($r('app.color.text_quinary_color'))
          .rotate({ angle: -90 })
          .flexShrink(0)
          .padding({ left: 4, top: 2, bottom: 2 });
      }
      .width('100%')
      .padding(12)
      .alignItems(VerticalAlign.Center);

      // 顶栏与首条消息之间的分隔线：左侧缩进 12vp 与文字对齐，右侧顶到卡片边缘
      // （与展开组内各行的分隔线保持同一终点，左滑删除时不错位）
      Divider()
        .color($r('app.color.divider_color'))
        .strokeWidth(0.5)
        .margin({ left: 12 });
    }
    .width('100%')
    .backgroundColor($r('app.color.card_background'))
    .borderRadius({ topLeft: 12, topRight: 12, bottomLeft: 0, bottomRight: 0 })
    // 点击整个顶栏：非编辑态收起分组，编辑态整组勾选（绑在根 Column，覆盖整行+分隔线）
    // hitTestBehavior(Block)：ListItemGroup header 左部触摸会被子 ListItem 的
    // swipeAction 手势层吞掉（只有右侧箭头区可点），Block 强制 header 自身消费整行触摸
    .hitTestBehavior(HitTestMode.Block)
    .onClick(() => {
      if (this.isEditing) {
        this.toggleGroupSelection(section.messages);
      } else {
        this.toggleGroupExpanded(section.groupKey);
      }
    })
    // 顶栏随展开态淡入淡出（徽标本身另有共享元素飞行动画）
    .transition(TransitionEffect.OPACITY.animation({ duration: 200 }));
  }

  // 展开态分组内的消息行：布局与普通消息卡片完全一致（上方标题/正文+右上 38vp 图标，下方时间居右），
  // 仅无独立圆角/底色，行下细分隔线，末行下方圆角。
  // 根节点用 Stack 单表面（分隔线以 BottomStart 叠加在表面内部），不要把 Divider 作为
  // 与内容并列的第二个子节点：swipeAction 的 end builder 用 height('100%') 匹配 ListItem 高度时，
  // Column(Row+Divider) 结构下百分比高度解析不到整行，删除按钮会比行矮一截、与分隔线错位
  // contentTransitionId 非空（仅组内第一条）时，上半标题/正文/icon Row 绑定共享元素转场，
  // 与折叠卡上半 Row 做一镜到底过渡（底部时间行不参与，两侧结构保持一致）
  @Builder
  groupMessageRow(m: NotifyMessage, isLast: boolean, contentTransitionId: string) {
    Stack({ alignContent: Alignment.BottomStart }) {
      Row({ space: 12 }) {
        if (this.isEditing) {
          Checkbox()
            .select(this.isSelected(m.id))
            .selectedColor($r('app.color.text_accent_color'))
            .shape(CheckBoxShape.CIRCLE)
            .flexShrink(0);
        }
        Column({ space: 6 }) {
          // 上：标题/副标题/正文（左占剩余空间）+ icon（右 38x38）
          Row({ space: 8 }) {
            Column() {
              if (m.title && m.title.length > 0) {
                Text(m.title)
                  .fontSize(15)
                  .fontWeight(FontWeight.Bold)
                  .fontColor($r('app.color.text_primary_color'))
                  .width('100%')
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis });
              }
              if (m.subtitle && m.subtitle.length > 0) {
                Text(m.subtitle)
                  .fontSize(13)
                  .fontColor($r('app.color.text_accent_color'))
                  .width('100%')
                  .maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis });
              }
              // 正文优先展示 extras.inboxcontent 多行摘要，无则回退普通正文（保留链接高亮能力）
              if (m.inboxContent.length > 0) {
                this.inboxRichTextList(m.inboxContent)
              } else if (m.body && m.body.length > 0) {
                this.bodyRichTextList(m.body)
              }
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start);

            if (m.image && m.image.length > 0) {
              Image(m.image)
                .width(38)
                .height(38)
                .borderRadius(12)
                .objectFit(ImageFit.Cover)
                .flexShrink(0)
                .alt($r('app.media.app_icon'));
            }
          }
          .width('100%')
          .alignItems(VerticalAlign.Top)
          // 仅第一条消息的上半 Row 与折叠卡上半 Row 做几何转场（其他行传空串不参与）；
          // 只包标题/正文/icon 行，两侧结构一一对应，飞行轨迹最自然
          .geometryTransition(contentTransitionId)
          .transition(TransitionEffect.OPACITY.animation({ duration: 200 }));

          // 下：时间居右（与普通消息卡片一致）
          Text(this.formatTime(m.timestamp))
            .fontSize(11)
            .fontColor($r('app.color.text_quinary_color'))
            .width('100%')
            .textAlign(TextAlign.End);
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start);
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)
      // 底部 22vp = 12vp 卡片边距 + 10vp 与分隔线间距（分隔线叠加在 Stack 底部，不占独立高度）
      .padding({ left: 12, right: 12, top: 12, bottom: 22 });

      // 非末行：分隔线贴卡片表面底边，左侧缩进 12vp 与文字对齐，右侧顶到卡片边缘——
      // 左滑某一行时红线（删除区）与相邻行的分隔线终点在同一竖边上，不错位
      if (!isLast) {
        Divider()
          .color($r('app.color.divider_color'))
          .strokeWidth(0.5)
          .width('100%')
          .margin({ left: 12 });
      }
    }
    .width('100%')
    .backgroundColor($r('app.color.card_background'))
    .borderRadius({
      topLeft: 0,
      topRight: 0,
      bottomLeft: isLast ? 12 : 0,
      bottomRight: isLast ? 12 : 0
    })
    // 圆角处裁剪：分隔线右侧顶边、左滑删除按钮都不能溢出圆角
    .clip(true)
    // 各行随分组展开淡入、收起淡出（第一条消息内容本身另走共享元素飞行）
    .transition(TransitionEffect.OPACITY.animation({ duration: 200 }))
    .onClick(() => {
      if (this.isEditing) {
        this.toggleSelect(m.id);
      } else {
        this.selectedMessage = m;
        this.showDetail = true;
      }
    });
  }

  // 左滑露出的删除按钮。topRadius/bottomRadius 为右侧圆角（vp），
  // 必须与卡片右侧圆角一致：普通卡片=12/12，展开分组内末行=0/12，其余行=0/0
  // （按钮在卡片背后滑出，圆角不匹配会在卡片弧线外侧露出灰底缺口）
  @Builder
  swipeDeleteBuilder(m: NotifyMessage, topRadius: number, bottomRadius: number) {
    Row() {
      Text('删除')
        .fontSize(15)
        .fontColor('#FFFFFF')
        .padding({ left: 20, right: 20 })
        .onClick(() => {
          this.confirmDeleteOne(m);
        });
    }
    .height('100%')
    .backgroundColor($r('app.color.text_error_color'))
    .borderRadius({
      topLeft: 0,
      topRight: topRadius,
      bottomLeft: 0,
      bottomRight: bottomRadius
    });
  }

  // 多选模式底部操作栏（需要加在 Refresh 外面）
  @Builder
  editActionBar() {
    Row() {
      Text('取消')
        .fontSize(15)
        .fontColor($r('app.color.text_tertiary_color'))
        .onClick(() => {
          this.exitEditMode();
        });
      Blank();
      Text(this.selectedIds.length === this.messages.length ? '取消全选' : '全选')
        .fontSize(15)
        .fontColor($r('app.color.text_tertiary_color'))
        .padding({ right: 16 })
        .onClick(() => {
          if (this.selectedIds.length === this.messages.length) {
            this.selectedIds = [];
          } else {
            const all: number[] = [];
            for (let i = 0; i < this.messages.length; i++) {
              all.push(this.messages[i].id);
            }
            this.selectedIds = all;
          }
        });
      // 导出选中：有选中时启用；导出中显示加载文案；未选中时点击提示
      Text(this.exportingSelected ? `导出中…` : `导出(${this.selectedIds.length})`)
        .fontSize(15)
        .fontColor(this.selectedIds.length > 0 && !this.exportingSelected ? $r('app.color.text_accent_color') :
          $r('app.color.text_quinary_color'))
        .padding({ right: 16 })
        .onClick(() => {
          if (this.exportingSelected) {
            return; // 导出中防重复触发
          }
          if (this.selectedIds.length > 0) {
            this.exportSelectedMessages();
          } else {
            showToast(this.getUIContext(), '请先选择要导出的消息');
          }
        });
      Text(`删除(${this.selectedIds.length})`)
        .fontSize(15)
        .fontColor(this.selectedIds.length > 0 ? $r('app.color.text_error_color') : $r('app.color.text_quinary_color'))
        .onClick(() => {
          if (this.selectedIds.length > 0) {
            this.confirmDeleteSelected();
          } else {
            showToast(this.getUIContext(), '请先选择要删除的消息');
          }
        });
    }
    .width('100%')
    // 底部补导航条高度：沉浸式布局下操作栏贴近屏幕底，避让手势条
    .padding({
      left: 16,
      right: 16,
      top: 12,
      bottom: SUPPORTS_IMMERSIVE_MATERIAL && this.immersiveLightEnabled ? this.navBarHeight + 72 :
        this.navBarHeight + 64
    })
    .backgroundBlurStyle(resolveBlurStyle('bar')!)
    .backgroundColor($r('app.color.index_page_top_glass_background'));
  }

  @Builder
  detailTitleBar() {
    Column() {
      Row() {
        Text('消息详情')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary_color'))
          .layoutWeight(1);
        Image($r('app.media.close'))
          .width(28)
          .height(28)
          .objectFit(ImageFit.Contain)
          .fillColor($r('app.color.text_tertiary_color'))
          .padding(2)
          .onClick(() => {
            this.showDetail = false;
          });
      }
      .width('100%')
      .padding(16)
      .alignItems(VerticalAlign.Center);
    }
    .width('100%')
    .padding({ top: this.statusBarHeight })
    // bindContentCover 模态不参与 HdsNavigation 沉浸光感，统一用 blur + 半透明底色的毛玻璃
    .backgroundBlurStyle(resolveBlurStyle('bar')!)
    .backgroundColor($r('app.color.index_page_top_glass_background'));
  }

  // 消息详情全屏模态视图：完整展示标题/副标题/正文/时间，不截断
  @Builder
  detailBuilder() {
    Column() {
      // Stack 层叠：详情内容在下、标题栏在上，滚动时内容从标题栏下方穿过
      Stack({ alignContent: Alignment.Top }) {
        // 内容区（可滚动，先声明位于下层）
        Scroll() {
          Column({ space: 12 }) {
            // 顶部占位：随内容一起滚动，详情才能滑入标题栏毛玻璃下方（padding 是硬边界做不到）
            // 模态全屏布局从屏幕顶 y=0 开始，占位 = 状态栏高度 + 标题栏高度 + 余量
            Row()
              .width('100%')
              .height(this.statusBarHeight + 72);

            if (this.selectedMessage) {
              // 标题行：标题（左占剩余空间）+ icon（右 38x38，与列表样式一致）
              Row({ space: 8 }) {
                if (this.selectedMessage.title && this.selectedMessage.title.length > 0) {
                  Text(this.selectedMessage.title)
                    .fontSize(18)
                    .fontWeight(FontWeight.Bold)
                    .fontColor($r('app.color.text_primary_color'))
                    .layoutWeight(1);
                }
                if (this.selectedMessage.image && this.selectedMessage.image.length > 0) {
                  Image(this.selectedMessage.image)
                    .width(38)
                    .height(38)
                    .borderRadius(12)
                    .objectFit(ImageFit.Cover)
                    .flexShrink(0)
                    .alt($r('app.media.app_icon'));
                }
              }
              .width('100%')
              .alignItems(VerticalAlign.Top);

              if (this.selectedMessage.subtitle && this.selectedMessage.subtitle.length > 0) {
                Text(this.selectedMessage.subtitle)
                  .fontSize(14)
                  .fontColor($r('app.color.text_accent_color'))
                  .width('100%');
              }
              // 正文优先展示 extras.inboxcontent（每条一段完整展示），无则回退普通正文
              if (this.selectedMessage.inboxContent.length > 0) {
                this.inboxRichTextDetail(this.selectedMessage.inboxContent)
              } else if (this.selectedMessage.body && this.selectedMessage.body.length > 0) {
                this.bodyRichTextDetail(this.selectedMessage.body)
              }

              // 下：时间居右
              Text(this.formatTime(this.selectedMessage.timestamp))
                .fontSize(12)
                .fontColor($r('app.color.text_quinary_color'))
                .width('100%')
                .textAlign(TextAlign.End);
            }
          }
          .width('100%')
          // 顶部避让由首项占位实现（可滚动穿透标题栏）；底部补导航条高度避让手势条
          .padding({ left: 16, right: 16, bottom: 24 + this.navBarHeight });
        }
        .align(Alignment.TopStart)
        .width('100%')
        .height('100%')
        .edgeEffect(EdgeEffect.Spring)
        .scrollBar(BarState.Off);

        // 标题栏（后声明覆盖在上层）：毛玻璃 + 半透明底色，状态栏高度手动避让
        this.detailTitleBar()
      }
      .width('100%')
      .height('100%');
    }
    .width('100%')
    .height('100%')
    // 沉浸式布局下模态全屏铺满，灰色底色自然覆盖导航条区域，实现底部沉浸
    .backgroundColor($r('app.color.index_page_body_background'));
  }

  /** aboutToAppear 是同步签名，这里 fire-and-forget 初始化链 */
  private async initAfterServerManagerReady(): Promise<void> {
    try {
      await ServerManager.getInstance().ensureLoaded();
      this.refresh();
      // 缓存优先：先从本地 RDB 读最新一页立即渲染，避免冷启动白屏等网络
      const deviceKey: string = await ServerManager.getInstance().getCurrentDeviceKey(null);
      if (deviceKey && deviceKey.length > 0) {
        const cached: NotifyMessage[] = await MessageCacheStore.loadLatest(deviceKey, 100);
        if (cached.length > 0) {
          this.messages = cached;
          this.hasMore = true;
        }
      }
      // 后台增量同步服务端（合并新消息 + 删除事件）
      this.syncFromServer(false);
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      hilog.warn(DOMAIN, TAG, '初始化失败：%{public}s', msg);
    }
  }

  // ====== 正文富文本：URL 点击打开系统浏览器 ======
  private openUrl(url: string): void {
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const want: Want = {
        action: 'ohos.want.action.viewData',
        uri: url,
      };
      ctx.startAbility(want).catch((err: BusinessError) => {
        hilog.warn(DOMAIN, TAG, '打开链接失败：code=%{public}d msg=%{public}s', err.code, err.message);
        showToast(this.getUIContext(), '无法打开链接');
      });
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      hilog.warn(DOMAIN, TAG, 'openUrl 异常：%{public}s', msg);
      showToast(this.getUIContext(), '无法打开链接');
    }
  }

  // ====== 正文富文本：验证码点击复制到剪贴板 ======
  private async copyCode(code: string): Promise<void> {
    try {
      const data: pasteboard.PasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, code);
      const sys: pasteboard.SystemPasteboard = pasteboard.getSystemPasteboard();
      await sys.setData(data);
      showToast(this.getUIContext(), `已复制 ${code}`, 1500);
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      hilog.warn(DOMAIN, TAG, '复制验证码失败：%{public}s', msg);
      showToast(this.getUIContext(), '复制失败');
    }
  }

  // 正文富文本共享片段：URL/验证码高亮可点击，普通段用次级文本色；
  // fontSize 由调用方按场景指定（列表 14fp / 详情 15fp），必须内联在 Text 容器内使用
  @Builder
  richTextSpans(text: string, fontSize: number) {
    ForEach(parseTextSegments(text), (seg: TextSegment, index: number) => {
      if (seg.type === SEG_URL) {
        Span(seg.text)
          .fontColor($r('app.color.text_accent_color'))
          .fontSize(fontSize)
          .onClick(() => { this.openUrl(seg.text); });
      } else if (seg.type === SEG_CODE) {
        Span(seg.text)
          .fontColor($r('app.color.text_accent_color'))
          .fontSize(fontSize)
          .onClick(() => { this.copyCode(seg.text); });
      } else {
        Span(seg.text)
          .fontColor($r('app.color.text_secondary_color'))
          .fontSize(fontSize);
      }
    }, (seg: TextSegment, index: number) => `${index}_${seg.type}_${seg.text}`)
  }

  // 列表项正文富文本：URL/验证码高亮可点击，maxLines(4) + 省略号
  @Builder
  bodyRichTextList(text: string) {
    Text() {
      this.richTextSpans(text, 14)
    }
    .width('100%')
    .maxLines(4)
    .textOverflow({ overflow: TextOverflow.Ellipsis })
    .lineHeight(21) // 1.5 倍行距（14fp × 1.5）
    .margin({ top: 4 }); // 与上方标题/副标题拉开间距
  }

  // 列表项 inboxContent 富文本：每条独占一行、单行超出省略号，最多展示 INBOX_LIST_MAX_LINES 行
  // （与普通正文 maxLines(4) 对齐）；每行仍保留 URL/验证码高亮可点击
  @Builder
  inboxRichTextList(items: string[]) {
    Column() {
      ForEach(items, (line: string, index: number) => {
        if (index < INBOX_LIST_MAX_LINES) {
          Text() {
            this.richTextSpans(line, 14)
          }
          .width('100%')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .lineHeight(21); // 1.5 倍行距（14fp × 1.5）
        }
      }, (line: string, index: number) => `${index}_${line}`)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .margin({ top: 4 }); // 与上方标题/副标题拉开间距
  }

  // 详情页正文富文本：URL/验证码高亮可点击，不限制行数
  @Builder
  bodyRichTextDetail(text: string) {
    Text() {
      this.richTextSpans(text, 15)
    }
    .width('100%')
    .lineHeight(22.5); // 1.5 倍行距（15fp × 1.5）
  }

  // 详情页 inboxContent 富文本：每条独占一段、长文自动换行完整展示，段落间留间距
  @Builder
  inboxRichTextDetail(items: string[]) {
    Column({ space: 8 }) {
      ForEach(items, (line: string, index: number) => {
        Text() {
          this.richTextSpans(line, 15)
        }
        .width('100%')
        .lineHeight(22.5); // 1.5 倍行距（15fp × 1.5）
      }, (line: string, index: number) => `${index}_${line}`)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start);
  }

  // 未配置 client token 或未注册 → 引导到"我的"页配置
  private needGuideToConfig(): boolean {
    return !this.loading && !this.hasClientToken && this.errorMsg.length > 0;
  }

  // ====== 多选模式控制 ======
  private enterEditMode(): void {
    this.isEditing = true;
    this.selectedIds = [];
  }

  private exitEditMode(): void {
    this.isEditing = false;
    this.selectedIds = [];
  }

  // Tab 切换监听（homeTabIndex 的 @Watch 回调）：切走「通知」Tab 后列表不可见，
  // 多选状态保留无意义，自动退出编辑；切回「通知」Tab 时全量刷新，
  // 且仅在页面可见（未被其它页面覆盖/未退后台）时恢复前台轮询
  private onHomeTabIndexChanged(): void {
    if (this.isEditing) {
      this.exitEditMode();
    }
    if (this.homeTabIndex === 0) {
      this.loadMessages();
      if (this.indexPageVisible) {
        this.startPolling();
      }
    } else {
      this.stopPolling();
    }
  }

  // 页面显隐监听（indexPageVisible 的 @Watch 回调）：Index 被 router 跳转其它页面覆盖或应用
  // 退后台时停止轮询；返回页面/回前台且停留在「通知」Tab 时恢复轮询
  private onPageVisibleChanged(): void {
    if (this.indexPageVisible) {
      if (this.homeTabIndex === 0) {
        this.startPolling();
      }
    } else {
      this.stopPolling();
    }
  }

  // 刷新信号监听（refreshSignal 的 @Watch 回调）：App 回前台或点击通知拉起时自动刷新列表
  private onRefreshSignalChanged(): void {
    this.loadMessages();
  }

  // ====== 前台轮询（「通知」Tab 可见期间保持列表增量更新）======

  // 启动轮询：幂等，重复调用不会叠加定时器
  private startPolling(): void {
    if (this.pollingEnabled) {
      return;
    }
    this.pollingEnabled = true;
    this.scheduleNextPoll();
  }

  // 停止轮询：清除待执行任务并关闭开关，飞行中的请求完成后不再续排
  private stopPolling(): void {
    this.pollingEnabled = false;
    if (this.pollTimer >= 0) {
      clearTimeout(this.pollTimer);
      this.pollTimer = -1;
    }
  }

  // 调度下一轮轮询：15s 后执行一次增量拉取，请求完成后再续排，
  // 间隔从请求结束时起算，慢网络下不会出现请求堆积
  private scheduleNextPoll(): void {
    this.pollTimer = setTimeout(() => {
      this.pollTimer = -1;
      this.pollNewMessages().finally(() => {
        if (this.pollingEnabled) {
          this.scheduleNextPoll();
        }
      });
    }, POLL_INTERVAL_MS);
  }

  // 静默增量拉取：走 after + deletedSince 协议，只拉本地没有的新消息并应用删除事件，
  // 不清空列表/不重置分页；失败静默，等下一轮
  private async pollNewMessages(): Promise<void> {
    // 有全量请求/翻页/轮询进行中 → 本轮跳过；未配置 Token 的引导态 → 不发无谓请求
    if (this.pollInFlight || this.loading || this.loadingMore || this.needGuideToConfig()) {
      return;
    }
    this.pollInFlight = true;
    try {
      await this.syncFromServer(false);
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      hilog.warn(DOMAIN, TAG, '轮询异常：%{public}s', msg);
    } finally {
      this.pollInFlight = false;
    }
  }

  // 编辑态变化监听（isEditing 的 @Watch 回调）：任何来源退出编辑（自身退出/Tab 切换/
  // Index.onBackPress 返回拦截）时，同步清空选中项，保证状态一致
  private onIsEditingChanged(): void {
    if (!this.isEditing && this.selectedIds.length > 0) {
      this.selectedIds = [];
    }
  }

  // 顶栏「多选」按钮的点击逻辑：无消息时提示不可多选；
  // 非编辑态进入多选；编辑态有选中时清空选择，无选中时退出编辑
  private handleMultiSelectClicked(): void {
    // 空列表无可多选，避免进入编辑态后底部操作栏不显示的"假编辑"状态
    if (this.messages.length === 0) {
      showToast(this.getUIContext(), '暂无可多选的消息');
      return;
    }
    if (this.isEditing) {
      // 多选模式下，选中有内容时清空，全选时取消全选，否则退出编辑
      if (this.selectedIds.length === this.messages.length) {
        this.selectedIds = [];
      } else if (this.selectedIds.length > 0) {
        this.selectedIds = [];
      } else {
        this.exitEditMode();
      }
    } else {
      this.enterEditMode();
    }
  }

  // 顶栏删除胶囊按钮的点击逻辑：非编辑态清空全部消息（二次确认）；
  // 编辑态删除选中消息（有选中才触发，未选中时提示，与底部「删除(N)」按钮一致）
  private handleDeletePillClicked(): void {
    if (this.isEditing) {
      if (this.selectedIds.length > 0) {
        this.confirmDeleteSelected();
      } else {
        showToast(this.getUIContext(), '请先选择要删除的消息');
      }
    } else {
      this.confirmDeleteAll();
    }
  }

  private isSelected(id: number): boolean {
    return this.selectedIds.indexOf(id) >= 0;
  }

  private toggleSelect(id: number): void {
    const idx: number = this.selectedIds.indexOf(id);
    if (idx >= 0) {
      const arr: number[] = [...this.selectedIds];
      arr.splice(idx, 1);
      this.selectedIds = arr;
    } else {
      this.selectedIds = [...this.selectedIds, id];
    }
  }

  // ====== group 分组展示 ======

  // 依据当前消息顺序构建展示分组：messages 已按时间倒序维护，分组位置取组内最新消息首次出现的位置；
  // 这是渲染层唯一的分组顺序来源，轮询/分页/删除后均重新从 messages 派生，避免多处各自排序造成漂移
  private buildSections(): NotifySection[] {
    const sections: NotifySection[] = [];
    const sectionIndexMap: Map<string, number> = new Map<string, number>();
    for (let i = 0; i < this.messages.length; i++) {
      const m: NotifyMessage = this.messages[i];
      if (m.group.length === 0) {
        const single: NotifySection = {
          key: `single:${m.id}`,
          groupKey: '',
          messages: [m],
          grouped: false
        };
        sections.push(single);
        continue;
      }
      const existIndex: number | undefined = sectionIndexMap.get(m.group);
      if (existIndex === undefined) {
        sectionIndexMap.set(m.group, sections.length);
        const section: NotifySection = {
          key: `group:${m.group}`,
          groupKey: m.group,
          messages: [m],
          // 先按普通卡片占位；后续遇到同组消息时再升级为折叠分组
          grouped: false
        };
        sections.push(section);
      } else {
        const section: NotifySection = sections[existIndex];
        section.messages.push(m);
        section.grouped = true;
      }
    }
    return sections;
  }

  private isGroupExpanded(groupKey: string): boolean {
    return this.expandedGroups.indexOf(groupKey) >= 0;
  }

  // 缓存某个分组主卡片的实测高度（vp）；不可变更新 Map 以触发空壳层重渲染
  private updateGroupCardHeight(groupKey: string, heightVp: number): void {
    if (heightVp <= 0) {
      return;
    }
    const prev: number = this.groupCardHeights.get(groupKey) ?? 0;
    // 亚像素级抖动不更新，避免无意义重渲染
    if (Math.abs(prev - heightVp) < 0.5) {
      return;
    }
    const next: Map<string, number> = new Map<string, number>(this.groupCardHeights);
    next.set(groupKey, heightVp);
    this.groupCardHeights = next;
  }

  // 设置某个分组的展开状态（展开态数组不可变更新，确保 ForEach 刷新）
  private setGroupExpanded(groupKey: string, expanded: boolean): void {
    const exists: boolean = this.isGroupExpanded(groupKey);
    if (exists === expanded) {
      return;
    }
    if (expanded) {
      this.expandedGroups = [...this.expandedGroups, groupKey];
    } else {
      this.expandedGroups = this.expandedGroups.filter((g: string) => g !== groupKey);
    }
  }

  // 切换分组展开/收起，并在动画上下文中更新状态：
  // animateTo 期间 ListItemGroup 子 ListItem 的增删由 List 插值布局（高度展开/下方项让位），
  // header 内折叠卡/展开顶栏两形态通过各自的 TransitionEffect 交叉淡入淡出
  private toggleGroupExpanded(groupKey: string): void {
    const nextExpanded: boolean = !this.isGroupExpanded(groupKey);
    this.getUIContext().animateTo({ duration: 280, curve: Curve.EaseInOut }, () => {
      this.setGroupExpanded(groupKey, nextExpanded);
    });
  }

  // 分组头内容区点击：编辑态整组勾选；非编辑态折叠时展开，已展开时打开最新消息详情
  private handleGroupHeaderClick(section: NotifySection): void {
    if (this.isEditing) {
      this.toggleGroupSelection(section.messages);
      return;
    }
    if (this.isGroupExpanded(section.groupKey)) {
      this.selectedMessage = section.messages[0];
      this.showDetail = true;
    } else {
      this.toggleGroupExpanded(section.groupKey);
    }
  }

  // 分组复选框是否应显示为选中：组内消息全部选中才选中
  private isGroupAllSelected(groupMessages: NotifyMessage[]): boolean {
    if (groupMessages.length === 0) {
      return false;
    }
    for (let i = 0; i < groupMessages.length; i++) {
      if (!this.isSelected(groupMessages[i].id)) {
        return false;
      }
    }
    return true;
  }

  // 整组勾选/取消勾选：全选状态下取消整组，否则补齐组内未选中的消息
  private toggleGroupSelection(groupMessages: NotifyMessage[]): void {
    if (this.isGroupAllSelected(groupMessages)) {
      const groupIdSet: Set<number> = new Set<number>();
      for (let i = 0; i < groupMessages.length; i++) {
        groupIdSet.add(groupMessages[i].id);
      }
      this.selectedIds = this.selectedIds.filter((id: number) => !groupIdSet.has(id));
    } else {
      const next: number[] = [...this.selectedIds];
      for (let i = 0; i < groupMessages.length; i++) {
        const id: number = groupMessages[i].id;
        if (!this.isSelected(id)) {
          next.push(id);
        }
      }
      this.selectedIds = next;
    }
  }

  // 从本地列表移除（UI 即时更新，不刷新整个列表）
  private removeFromList(ids: number[]): void {
    const idSet: Set<number> = new Set<number>(ids);
    const newList: NotifyMessage[] = [];
    for (let i = 0; i < this.messages.length; i++) {
      if (!idSet.has(this.messages[i].id)) {
        newList.push(this.messages[i]);
      }
    }
    this.messages = newList;
    // 清理已不存在，或删到只剩 1 条（已退回普通卡片）的分组展开状态，
    // 避免后续再次聚合成组时意外沿用展开态
    const groupCountMap: Map<string, number> = new Map<string, number>();
    for (let i = 0; i < this.messages.length; i++) {
      const g: string = this.messages[i].group;
      if (g.length > 0) {
        groupCountMap.set(g, (groupCountMap.get(g) ?? 0) + 1);
      }
    }
    this.expandedGroups = this.expandedGroups.filter((g: string) => (groupCountMap.get(g) ?? 0) >= 2);
    // 如果删光了，退出编辑模式
    if (this.messages.length === 0) {
      this.exitEditMode();
    }
  }

  // ====== 删除确认与执行 ======
  private confirmDeleteOne(m: NotifyMessage): void {
    const uiCtx: UIContext = this.getUIContext();
    uiCtx.getPromptAction().showDialog({
      title: '确认删除',
      message: `确定要删除这条消息吗？${m.title && m.title.length > 0 ? '\n「' + m.title + '」' : ''}`,
      buttons: [
        { text: '取消', color: '#666666' },
        { text: '删除', color: '#F53F3F' },
      ],
    }, async (err: BusinessError, result: promptAction.ShowDialogSuccessResponse) => {
      if (err || result.index !== 1) {
        return;
      }
      const svc = NotifyMessageService.getInstance();
      const errMsg: string = await svc.deleteMessage(m.id);
      if (errMsg.length > 0) {
        showToast(uiCtx, errMsg);
        return;
      }
      // 同步删除本地缓存
      await ServerManager.getInstance().ensureLoaded();
      const deviceKey: string = await ServerManager.getInstance().getCurrentDeviceKey(null);
      if (deviceKey && deviceKey.length > 0) {
        await MessageCacheStore.deleteByIds(deviceKey, [m.id]);
      }
      this.removeFromList([m.id]);
      this.exitEditMode();
      showToast(uiCtx, '已删除');
    });
  }

  // 折叠态分组卡片左滑删除：删除该分组内全部消息
  private confirmDeleteGroup(section: NotifySection): void {
    const uiCtx: UIContext = this.getUIContext();
    const ids: number[] = [];
    for (let i = 0; i < section.messages.length; i++) {
      ids.push(section.messages[i].id);
    }
    const count: number = ids.length;
    uiCtx.getPromptAction().showDialog({
      title: '删除整个分组',
      message: `确定要删除该分组的 ${count} 条消息吗？此操作不可恢复。`,
      buttons: [
        { text: '取消', color: '#666666' },
        { text: '全部删除', color: '#F53F3F' },
      ],
    }, async (err: BusinessError, result: promptAction.ShowDialogSuccessResponse) => {
      if (err || result.index !== 1) {
        return;
      }
      // 多条逐个删（服务端无批量删除 API）；失败的 id 收集后提示
      const svc = NotifyMessageService.getInstance();
      let failCount = 0;
      for (let i = 0; i < ids.length; i++) {
        const errMsg: string = await svc.deleteMessage(ids[i]);
        if (errMsg.length > 0) {
          failCount++;
          hilog.warn(DOMAIN, TAG, '删除分组消息 %{public}d 失败：%{public}s', ids[i], errMsg);
        }
      }
      this.removeFromList(ids);
      if (failCount > 0) {
        showToast(uiCtx, `删除完成，${failCount} 条失败`);
      } else {
        showToast(uiCtx, `已删除 ${count} 条`);
      }
    });
  }

  private confirmDeleteSelected(): void {
    const uiCtx: UIContext = this.getUIContext();
    const count: number = this.selectedIds.length;
    uiCtx.getPromptAction().showDialog({
      title: '确认删除',
      message: `确定要删除选中的 ${count} 条消息吗？此操作不可恢复。`,
      buttons: [
        { text: '取消', color: '#666666' },
        { text: '全部删除', color: '#F53F3F' },
      ],
    }, async (err: BusinessError, result: promptAction.ShowDialogSuccessResponse) => {
      if (err || result.index !== 1) {
        return;
      }
      const ids: number[] = [...this.selectedIds];
      // 多条逐个删（服务端无批量删除 API）；失败的 id 收集后跳过
      const svc = NotifyMessageService.getInstance();
      let failCount = 0;
      for (let i = 0; i < ids.length; i++) {
        const errMsg: string = await svc.deleteMessage(ids[i]);
        if (errMsg.length > 0) {
          failCount++;
          hilog.warn(DOMAIN, TAG, '删除消息 %{public}d 失败：%{public}s', ids[i], errMsg);
        }
      }
      // 同步删除本地缓存（成功删除的 id 才删缓存；失败的保留，下次同步由删除流水兜底）
      await ServerManager.getInstance().ensureLoaded();
      const deviceKey: string = await ServerManager.getInstance().getCurrentDeviceKey(null);
      if (deviceKey && deviceKey.length > 0) {
        await MessageCacheStore.deleteByIds(deviceKey, ids);
      }
      this.removeFromList(ids);
      this.exitEditMode();
      if (failCount > 0) {
        showToast(uiCtx, `删除完成，${failCount} 条失败`);
      } else {
        showToast(uiCtx, `已删除 ${ids.length} 条`);
      }
    });
  }

  // 清空全部消息：弹窗二次确认并重点提示不可恢复，确认后调用服务端删除全部消息接口
  private confirmDeleteAll(): void {
    const uiCtx: UIContext = this.getUIContext();
    // 本地无消息时无需调用清空接口
    if (this.messages.length === 0) {
      showToast(uiCtx, '暂无可删除的消息');
      return;
    }
    uiCtx.getPromptAction().showDialog({
      title: '清空全部消息',
      message: `将删除当前设备的全部消息（包括未加载的历史消息），删除后无法找回。\n\n注意：此操作不可恢复！`,
      buttons: [
        { text: '取消', color: '#666666' },
        { text: '全部删除', color: '#F53F3F' },
      ],
    }, async (err: BusinessError, result: promptAction.ShowDialogSuccessResponse) => {
      if (err || result.index !== 1) {
        return;
      }
      const svc = NotifyMessageService.getInstance();
      const errMsg: string = await svc.deleteAllMessages();
      if (errMsg.length > 0) {
        showToast(uiCtx, errMsg);
        return;
      }
      // 清空成功：移除本地列表、清空本地缓存并退出多选模式
      await ServerManager.getInstance().ensureLoaded();
      const deviceKey: string = await ServerManager.getInstance().getCurrentDeviceKey(null);
      if (deviceKey && deviceKey.length > 0) {
        await MessageCacheStore.clearDevice(deviceKey);
      }
      this.exitEditMode();
      this.messages = [];
      this.expandedGroups = [];
      this.groupCardHeights = new Map<string, number>();
      showToast(uiCtx, '已清空全部消息');
    });
  }

  private refresh(): void {
    const cur: ServerEntry | null = ServerManager.getInstance().getCurrentServer();
    if (cur && cur.name && cur.name.length > 0) {
      this.title = cur.name;
    } else {
      this.title = ServerManager.getInstance().getCurrentHostDisplay();
    }
  }

  private async loadMessages(): Promise<void> {
    if (this.loading) {
      this.refreshing = false;
      // 已有请求在跑（如切换服务器时旧请求未完成）：排队补拉，保证新服务器数据最终被拉取
      this.loadQueued = true;
      return;
    }
    this.loading = true;
    // 请求代际：响应到达时与最新代际不符（期间已切换服务器/发起新请求）→ 过期丢弃
    const seq: number = ++this.loadSeq;
    // 清空旧错误，避免短暂闪烁旧错误态
    this.errorMsg = '';
    try {
      await this.syncFromServer(true, seq);
      // 是否有可用 client token（用户自定义 or 内置默认），用于引导态判断
      this.hasClientToken = await NotifyMessageService.getInstance().hasEffectiveClientToken();
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      hilog.warn(DOMAIN, TAG, 'loadMessages 异常：%{public}s', msg);
      if (seq === this.loadSeq) {
        this.errorMsg = '加载失败';
      }
    } finally {
      this.loading = false;
      this.refreshing = false;
      if (this.loadQueued) {
        this.loadQueued = false;
        this.loadMessages(); // 补拉：消费排队期间产生的最新拉取需求
      }
    }
  }

  /**
   * 与服务端同步（增量协议）。
   * - forceFull=true：清空本地缓存，从 after=0 重新播种最新一页（下拉刷新/切服务器用）
   * - forceFull=false：以本地 maxId 为 after、delCursor 为 deletedSince，只拉新消息 + 删除事件
   * expectedSeq：请求代际，与 this.loadSeq 不符则丢弃结果（服务器切换防串数据）
   */
  private async syncFromServer(forceFull: boolean, expectedSeq: number = -1): Promise<void> {
    const svc = NotifyMessageService.getInstance();
    await ServerManager.getInstance().ensureLoaded();
    const deviceKey: string = await ServerManager.getInstance().getCurrentDeviceKey(null);
    if (!deviceKey || deviceKey.length === 0) {
      return;
    }

    // 代际校验：期间已切换服务器 → 丢弃
    if (expectedSeq >= 0 && expectedSeq !== this.loadSeq) {
      return;
    }

    // 读取同步基线
    let after: number = 0;
    let delCursor: number = 0;
    if (forceFull) {
      await MessageCacheStore.clearDevice(deviceKey);
    } else {
      const meta = await MessageCacheStore.getMeta(deviceKey);
      after = meta.maxId;
      delCursor = meta.delCursor;
      if (after === 0) {
        after = await MessageCacheStore.getMaxId(deviceKey);
      }
    }

    let newMaxId: number = after;
    let newDelCursor: number = delCursor;

    // 增量翻页循环（after 升序），最多 20 页防异常死循环
    const MAX_PAGES: number = 20;
    for (let page = 0; page < MAX_PAGES; page++) {
      if (expectedSeq >= 0 && expectedSeq !== this.loadSeq) {
        return;
      }
      const result = await svc.getMessages(null, 0, 100, after, newDelCursor);
      if (!result.ok) {
        // 失败：保留本地缓存，静默结束；forceFull 且本地为空时透出错误
        hilog.warn(DOMAIN, TAG, 'syncFromServer 失败：%{public}s', result.errorMsg);
        if (forceFull && this.messages.length === 0) {
          this.errorMsg = result.errorMsg;
        }
        return;
      }

      // 处理删除事件
      if (result.reset) {
        // 游标落在流水保留期缺口：清空本地重新播种
        hilog.info(DOMAIN, TAG, 'syncFromServer reset：清空本地缓存重新播种');
        await MessageCacheStore.clearDevice(deviceKey);
        after = 0;
        newMaxId = 0;
      } else {
        if (result.deletionIds.length > 0) {
          await MessageCacheStore.deleteByIds(deviceKey, result.deletionIds);
        }
        if (result.purges.length > 0) {
          let maxCeiling: number = 0;
          for (let i = 0; i < result.purges.length; i++) {
            if (result.purges[i] > maxCeiling) {
              maxCeiling = result.purges[i];
            }
          }
          if (maxCeiling > 0) {
            await MessageCacheStore.purgeBefore(deviceKey, maxCeiling);
          }
        }
      }
      if (result.delCursor > 0) {
        newDelCursor = result.delCursor;
      }

      // 写入新消息并推进 maxId
      if (result.messages.length > 0) {
        await MessageCacheStore.upsertMessages(deviceKey, result.messages);
        for (let i = 0; i < result.messages.length; i++) {
          if (result.messages[i].id > newMaxId) {
            newMaxId = result.messages[i].id;
          }
        }
      }

      if (!result.hasMore) {
        break;
      }
      // 下一页：用当前最大 id 作 after，删除游标只在首请求拉一次即可
      after = newMaxId;
    }

    // 持久化同步元信息
    await MessageCacheStore.saveMeta(deviceKey, newMaxId, newDelCursor);

    // 代际校验后从缓存重新加载列表（含删除结果，与本地一致）
    if (expectedSeq >= 0 && expectedSeq !== this.loadSeq) {
      return;
    }
    const refreshed: NotifyMessage[] = await MessageCacheStore.loadLatest(deviceKey, 100);
    this.messages = refreshed;
    this.hasMore = refreshed.length > 0;
    this.errorMsg = '';
  }

  // 触底加载更多：优先读本地缓存（秒出），缓存不足一页再走服务端 since 翻页并落库
  // limit 默认 100，返回少于 100 条说明已到底，置 hasMore=false
  private async loadMore(): Promise<void> {
    if (this.loadingMore || !this.hasMore || this.messages.length === 0) {
      return;
    }
    const oldest: NotifyMessage = this.messages[this.messages.length - 1];
    if (!oldest || oldest.id <= 0) {
      this.hasMore = false;
      return;
    }
    this.loadingMore = true;
    const PAGE_SIZE: number = 100;
    try {
      const deviceKey: string = await ServerManager.getInstance().getCurrentDeviceKey(null);
      const existingIds: Set<number> = new Set<number>();
      for (let i = 0; i < this.messages.length; i++) {
        existingIds.add(this.messages[i].id);
      }

      // 1) 优先从本地缓存读更老的消息
      let cached: NotifyMessage[] = [];
      if (deviceKey && deviceKey.length > 0) {
        cached = await MessageCacheStore.loadOlder(deviceKey, oldest.id, PAGE_SIZE);
      }
      const cachedDeduped: NotifyMessage[] = [];
      for (let i = 0; i < cached.length; i++) {
        if (!existingIds.has(cached[i].id)) {
          cachedDeduped.push(cached[i]);
          existingIds.add(cached[i].id);
        }
      }
      if (cachedDeduped.length > 0) {
        this.messages = this.messages.concat(cachedDeduped);
      }

      // 2) 缓存不足一页 → 走网络 since 翻页补齐，并落库供下次离线浏览
      if (cached.length < PAGE_SIZE) {
        const result = await NotifyMessageService.getInstance().getMessages(null, oldest.id, PAGE_SIZE);
        if (result.ok) {
          const newItems: NotifyMessage[] =
            result.messages.sort((a: NotifyMessage, b: NotifyMessage) => b.timestamp - a.timestamp);
          const deduped: NotifyMessage[] = [];
          for (let i = 0; i < newItems.length; i++) {
            if (!existingIds.has(newItems[i].id)) {
              deduped.push(newItems[i]);
              existingIds.add(newItems[i].id);
            }
          }
          if (deduped.length > 0) {
            this.messages = this.messages.concat(deduped);
            if (deviceKey && deviceKey.length > 0) {
              await MessageCacheStore.upsertMessages(deviceKey, deduped);
            }
          }
          if (newItems.length < PAGE_SIZE) {
            this.hasMore = false;
          }
        }
        // loadMore 失败不弹错误提示，避免打扰用户；日志已由 service 层打印
      }
      // 缓存满一页 → 仍可能有更多缓存，保持 hasMore=true 让用户继续下拉
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      hilog.warn(DOMAIN, TAG, 'loadMore 异常：%{public}s', msg);
    } finally {
      this.loadingMore = false;
    }
  }

  private formatTime(ts: number): string {
    if (!ts) {
      return '';
    }
    const d = new Date(ts);
    const y: number = d.getFullYear();
    const mo: string = String(d.getMonth() + 1).padStart(2, '0');
    const da: string = String(d.getDate()).padStart(2, '0');
    const h: string = String(d.getHours()).padStart(2, '0');
    const mi: string = String(d.getMinutes()).padStart(2, '0');
    return `${y}-${mo}-${da} ${h}:${mi}`;
  }

  private handleMoreClicked(): void {
    try {
      this.dialogController.open();
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      hilog.warn(DOMAIN, TAG, 'dialog open 失败：%{public}s', msg);
      showToast(this.getUIContext(), '弹窗无法打开');
    }
  }

  // 获取 UIAbilityContext（DocumentViewPicker 需要）
  private getAbilityContext(): common.UIAbilityContext | null {
    try {
      const ctx = this.getUIContext().getHostContext();
      return ctx as common.UIAbilityContext;
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      hilog.warn(DOMAIN, TAG, 'getHostContext 失败：%{public}s', msg);
      return null;
    }
  }

  // 生成导出文件名时间后缀：yyyyMMdd_HHmmss
  private formatExportTime(d: Date): string {
    const p = (n: number): string => (n < 10 ? '0' + n : String(n));
    return `${d.getFullYear()}${p(d.getMonth() + 1)}${p(d.getDate())}_${p(d.getHours())}${p(d.getMinutes())}${p(
      d.getSeconds())}`;
  }

  // 将 NotifyMessage 转为可 JSON 序列化的原始对象（严格匹配服务端全量导出格式）
  // 字段：id, appid, title, message, priority, extras{device_key, subtitle?}, date
  private messageToRaw(m: NotifyMessage, deviceKey: string): Object {
    const raw: Record<string, Object> = {
      'id': m.id,
      'appid': m.appid,
      'title': m.title,
      'message': m.body,
      'priority': m.priority,
      'date': m.date.length > 0 ? m.date : (m.createdAt.length > 0 ? m.createdAt : ''),
    };
    // extras：固定放 device_key（与服务端一致）；有 subtitle 时也补在 extras 下
    const extras: Record<string, Object> = { 'device_key': deviceKey };
    if (m.subtitle && m.subtitle.length > 0) {
      extras['subtitle'] = m.subtitle;
    }
    raw['extras'] = extras as Object;
    return raw as Object;
  }

  // 导出当前选中的消息：
  // 1. 读取当前 device_key（放入 extras，与服务端全量导出格式一致）
  // 2. 从 this.messages 按 selectedIds 过滤
  // 3. 转为与全量导出同结构的 JSON 数组文本（2 空格缩进）
  // 4. DocumentViewPicker 拉起系统保存对话框（无需权限），用户选择位置后写入 txt
  private async exportSelectedMessages(): Promise<void> {
    if (this.exportingSelected || this.selectedIds.length === 0) {
      return; // 防重复触发
    }
    const uiCtx: UIContext = this.getUIContext();
    this.exportingSelected = true;
    try {
      // 预先加载 device_key：ServerManager 可能还在初始化，先 ensureLoaded
      await ServerManager.getInstance().ensureLoaded();
      const deviceKey: string = await ServerManager.getInstance().getCurrentDeviceKey(null);
      if (!deviceKey || deviceKey.length === 0) {
        showToast(uiCtx, '设备未注册，无法导出');
        return;
      }

      // 按 selectedIds 过滤当前列表中的消息（保持列表原有展示顺序：新→旧）
      const idSet: Set<number> = new Set<number>(this.selectedIds);
      const selected: NotifyMessage[] = [];
      for (let i = 0; i < this.messages.length; i++) {
        if (idSet.has(this.messages[i].id)) {
          selected.push(this.messages[i]);
        }
      }
      if (selected.length === 0) {
        showToast(uiCtx, '没有可导出的消息');
        return;
      }

      // 转成原始对象数组后 JSON 序列化（字段与服务端全量导出一致）
      const rawArr: Object[] = [];
      for (let i = 0; i < selected.length; i++) {
        rawArr.push(this.messageToRaw(selected[i], deviceKey));
      }
      const text: string = JSON.stringify(rawArr, null, 2);

      // 系统保存对话框：预设文件名 + txt 过滤；Picker 保存无需申请权限
      const saveOptions = new picker.DocumentSaveOptions();
      saveOptions.newFileNames = [`timelynotify_selected_${this.formatExportTime(new Date())}.txt`];
      saveOptions.fileSuffixChoices = ['文档|.txt'];
      const abilityCtx = this.getAbilityContext();
      if (!abilityCtx) {
        showToast(uiCtx, '上下文获取失败');
        return;
      }
      const docPicker = new picker.DocumentViewPicker(abilityCtx);
      const uris: string[] = await docPicker.save(saveOptions);
      if (uris.length === 0) {
        return; // 用户取消保存，静默结束
      }

      // Picker 返回的 URI 需以 READ_WRITE 模式打开后写入
      const file = fileIo.openSync(uris[0], fileIo.OpenMode.READ_WRITE);
      try {
        fileIo.writeSync(file.fd, text);
      } finally {
        fileIo.closeSync(file);
      }

      showToast(uiCtx, `已导出 ${selected.length} 条消息`, 1500);
      hilog.info(DOMAIN, TAG, '选中消息导出完成：count=%{public}d', String(selected.length));
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      hilog.warn(DOMAIN, TAG, '导出选中消息失败：%{public}s', msg);
      showToast(uiCtx, '导出失败');
    } finally {
      this.exportingSelected = false;
    }
  }
}
