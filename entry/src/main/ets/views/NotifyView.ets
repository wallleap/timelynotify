import { hilog } from '@kit.PerformanceAnalysisKit';
import { promptAction, UIContext } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';
import { fileIo, picker } from '@kit.CoreFileKit';
import { ServerEntry } from '../model/ServerEntry';
import { ServerManager } from '../services/ServerManager';
import { NotifyMessage } from '../model/NotifyMessage';
import { NotifyMessageService } from '../services/NotifyMessageService';
import { ServerSettingsDialog } from '../components/ServerSettingsDialog';
import { resolveBlurStyle, SUPPORTS_IMMERSIVE_MATERIAL } from '../utils/ImmersiveUtil';
import { hdsMaterial, HdsNavigation, HdsNavigationTitleMode, ScrollEffectType, TextStyleMode } from '@kit.UIDesignKit';
import { DOMAIN, KEY_HOME_TAB_INDEX, KEY_NOTIFY_EDITING } from '../common/Constant';
import showToast from '../components/showToast';

const TAG: string = 'NotifyView';

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
  // 左滑互斥：当前展开左滑的消息 ID（-1 表示无）
  // 状态栏高度（vp），详情模态标题栏顶部避让用；EntryAbility 沉浸式布局初始化时写入 AppStorage（键值见 ImmersiveUtil）
  @StorageProp('statusBarHeight') statusBarHeight: number = 36;
  // 底部导航条高度（vp），编辑操作栏与列表底部占位避让用
  @StorageProp('navBarHeight') navBarHeight: number = 0;
  // 主页当前选中 Tab 索引（Index 经 @StorageLink 写入）：切走「通知」Tab 时自动退出多选模式
  @StorageProp(KEY_HOME_TAB_INDEX) @Watch('onHomeTabIndexChanged') homeTabIndex: number = 0;
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
  private scroller: Scroller = new Scroller();

  aboutToAppear() {
    // ServerManager 可能还在异步 load，必须先 await ensureLoaded 再读当前 server，
    // 否则 currentId='' 会走兜底生产 URL，显示/请求错误的地址。
    this.initAfterServerManagerReady();
    this.onChange = (_list: ServerEntry[], _curId: string): void => {
      // 切换服务器后列表会整体刷新，selectedIds 属于旧服务器的消息 ID，继续操作会错删/报错，必须退出多选
      this.exitEditMode();
      this.refresh();
      // 服务器切换后重新拉取消息
      this.loadMessages();
    };
    ServerManager.getInstance().addChangeListener(this.onChange);
  }

  aboutToDisappear() {
    if (this.onChange) {
      ServerManager.getInstance().removeChangeListener(this.onChange);
    }
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
          .textOverflow({ overflow: TextOverflow.Ellipsis });

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
  // ⚠️ 内层 Row 全宽叠在标题栏上，与右侧系统 menu 槽位区域重叠：必须设 hitTestBehavior(None)
  // 让 Row 自身不参与触摸测试（默认 Default 会阻塞兄弟节点），否则点击 menu 的「多选/删除」会误触发 title 事件；
  // None 不阻塞子节点，标题文本/图标的 onClick 仍正常生效。
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
          // 点击标题文本打开服务器设置弹窗（热区仅文字宽度，不会盖住右侧 menu 按钮）
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
      .padding({ right: 48 })
      .alignItems(VerticalAlign.Center)
      // 自身不参与触摸测试，避免全宽 Row 拦截右侧系统 menu 槽位按钮的点击（子节点 onClick 不受影响）
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
    if (SUPPORTS_IMMERSIVE_MATERIAL) {
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
      Row().height(SUPPORTS_IMMERSIVE_MATERIAL ? 8 : this.statusBarHeight + 64 + 16);

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
      if (SUPPORTS_IMMERSIVE_MATERIAL) {
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

      ForEach(this.messages, (m: NotifyMessage) => {
        ListItem() {
          this.messageRow(m);
        }
        .swipeAction({
          end: {
            builder: () => {
              this.swipeDeleteBuilder(m);
            }
          }
        });
      }, (m: NotifyMessage) => `${m.id}|${m.timestamp}`);

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
          .height(SUPPORTS_IMMERSIVE_MATERIAL ? this.navBarHeight + 72 : this.navBarHeight + 64);
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
        if (m.body && m.body.length > 0) {
          Text(m.body)
            .fontSize(14)
            .fontColor($r('app.color.text_secondary_color'))
            .width('100%')
            .maxLines(4)
            .textOverflow({ overflow: TextOverflow.Ellipsis });
        }
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
    // 页面内卡片用半透明玻璃色（弹窗仍用不透明 card_background）
    .backgroundBlurStyle(resolveBlurStyle('bar')!)
    .backgroundColor($r('app.color.card_glass_background'))
    .borderRadius(10)
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

  // 左滑露出的删除按钮
  @Builder
  swipeDeleteBuilder(m: NotifyMessage) {
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
    .backgroundColor($r('app.color.text_error_color'));
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
      bottom: SUPPORTS_IMMERSIVE_MATERIAL ? this.navBarHeight + 72 : this.navBarHeight + 64
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
              if (this.selectedMessage.title && this.selectedMessage.title.length > 0) {
                Text(this.selectedMessage.title)
                  .fontSize(18)
                  .fontWeight(FontWeight.Bold)
                  .fontColor($r('app.color.text_primary_color'))
                  .width('100%');
              }
              if (this.selectedMessage.subtitle && this.selectedMessage.subtitle.length > 0) {
                Text(this.selectedMessage.subtitle)
                  .fontSize(14)
                  .fontColor($r('app.color.text_accent_color'))
                  .width('100%');
              }
              if (this.selectedMessage.body && this.selectedMessage.body.length > 0) {
                Text(this.selectedMessage.body)
                  .fontSize(15)
                  .fontColor($r('app.color.text_secondary_color'))
                  .width('100%');
              }
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
      this.loadMessages();
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      hilog.warn(DOMAIN, TAG, '初始化失败：%{public}s', msg);
    }
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
  // 多选状态保留无意义，自动退出编辑
  private onHomeTabIndexChanged(): void {
    if (this.isEditing) {
      this.exitEditMode();
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
      this.removeFromList([m.id]);
      this.exitEditMode();
      showToast(uiCtx, '已删除');
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
      // 清空成功：移除本地列表并退出多选模式
      this.exitEditMode();
      this.messages = [];
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
      return;
    }
    this.loading = true;
    // 清空旧错误，避免短暂闪烁旧错误态
    this.errorMsg = '';
    try {
      const result = await NotifyMessageService.getInstance().getMessages(null);
      if (result.ok) {
        // 按时间倒序（新消息在上）
        this.messages = result.messages.sort((a: NotifyMessage, b: NotifyMessage) => b.timestamp - a.timestamp);
        this.errorMsg = '';
        // 首次拉取/下拉刷新 → 重置分页状态，允许后续触底加载
        this.hasMore = this.messages.length > 0;
      } else {
        this.errorMsg = result.errorMsg;
        // 仅首次拉取失败清空列表；刷新失败保留旧数据
        if (this.messages.length === 0) {
          this.messages = [];
        }
      }
      // 是否有可用 client token（用户自定义 or 内置默认），用于引导态判断
      this.hasClientToken = await NotifyMessageService.getInstance().hasEffectiveClientToken();
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      hilog.warn(DOMAIN, TAG, 'loadMessages 异常：%{public}s', msg);
      this.errorMsg = '加载失败';
    } finally {
      this.loading = false;
      this.refreshing = false;
    }
  }

  // 触底加载更多：取当前列表末尾（最旧）消息的 ID 作 since，请求更老的消息
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
      const result = await NotifyMessageService.getInstance().getMessages(null, oldest.id, PAGE_SIZE);
      if (result.ok) {
        const newItems: NotifyMessage[] =
          result.messages.sort((a: NotifyMessage, b: NotifyMessage) => b.timestamp - a.timestamp);
        if (newItems.length === 0) {
          this.hasMore = false;
        } else {
          // 去重：过滤掉已经存在的 ID（避免后端返回包含 oldest.id 本身导致重复）
          const existingIds: Set<number> = new Set<number>();
          for (let i = 0; i < this.messages.length; i++) {
            existingIds.add(this.messages[i].id);
          }
          const deduped: NotifyMessage[] = [];
          for (let i = 0; i < newItems.length; i++) {
            const m: NotifyMessage = newItems[i];
            if (!existingIds.has(m.id)) {
              deduped.push(m);
            }
          }
          if (deduped.length === 0) {
            // 全部重复 → 后端实际没有更老消息
            this.hasMore = false;
          } else {
            // 列表按时间倒序（新→旧），追加到末尾保持顺序
            this.messages = this.messages.concat(deduped);
            // 返回不足一页（< limit）→ 已到底；否则保持 hasMore=true 允许继续翻
            if (newItems.length < PAGE_SIZE) {
              this.hasMore = false;
            }
          }
        }
      }
      // loadMore 失败不弹错误提示，避免打扰用户；日志已由 service 层打印
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
