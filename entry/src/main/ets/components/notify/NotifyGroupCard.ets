import { displayGroupTitle, formatNotifyTime, NOTIFY_SEGMENT_CODE, NOTIFY_SEGMENT_URL, NotifySection, NotifyTextSegment, parseNotifyTextSegments } from './NotifyViewTypes';
import { NotifyGroupCountBadge, NotifyGroupShellLayer } from './NotifyGroupVisuals';
import { NotifyMessage } from '../../model/NotifyMessage';

/** 折叠态分组卡片，页面负责持有展开状态、高度和实际操作。 */
@Component
export struct NotifyGroupCard {
  @Prop section: NotifySection = { key: '', groupKey: '', messages: [], grouped: false, total: 0 };
  @Prop isEditing: boolean = false;
  @Prop groupSelected: boolean = false;
  // 当前内存中已选的消息数；真实总数仍由 section.total 提供。
  @Prop selectedCount: number = 0;
  @Prop cardHeight: number = 0;
  onToggleSelection: () => void = () => {};
  onOpen: () => void = () => {};
  onHeightChange: (height: number) => void = (_height: number) => {};
  onOpenUrl: (url: string) => void = (_url: string) => {};
  onCopyCode: (code: string) => void = (_code: string) => {};

  @Builder
  private spans(text: string) {
    ForEach(parseNotifyTextSegments(text), (segment: NotifyTextSegment, index: number) => {
      if (segment.type === NOTIFY_SEGMENT_URL) {
        Span(segment.text).fontSize(14).fontColor($r('app.color.color_link')).onClick(() => this.onOpenUrl(segment.text));
      } else if (segment.type === NOTIFY_SEGMENT_CODE) {
        Span(segment.text).fontSize(14).fontColor($r('app.color.color_brand')).onClick(() => this.onCopyCode(segment.text));
      } else {
        Span(segment.text).fontSize(14).fontColor($r('app.color.color_text_secondary'));
      }
    }, (segment: NotifyTextSegment, index: number) => `${index}_${segment.type}_${segment.text}`)
  }

  @Builder
  private body(message: NotifyMessage) {
    if (message.inboxContent.length > 0) {
      Column() {
        ForEach(message.inboxContent, (line: string, index: number) => {
          if (index < 4) {
            Text() { this.spans(line) }.width('100%').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).lineHeight(21);
          }
        }, (line: string, index: number) => `${index}_${line}`)
      }.width('100%').margin({ top: 4 });
    } else if (message.body.length > 0) {
      Text() { this.spans(message.body) }.width('100%').maxLines(4).textOverflow({ overflow: TextOverflow.Ellipsis }).lineHeight(21).margin({ top: 4 });
    }
  }

  /** 多选时明确展示已选的已加载消息与分组真实总数，避免将局部选择误认为整组操作。 */
  @Builder
  private groupCount() {
    if (this.isEditing) {
      Text(`已选 ${this.selectedCount} / ${this.section.total}`).fontSize(10).fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.color_text_badge')).padding({ left: 8, right: 8, top: 2, bottom: 2 })
        .borderRadius(10).backgroundColor($r('app.color.color_bg_badge'));
    } else {
      NotifyGroupCountBadge({ count: this.section.total });
    }
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.section.messages.length >= 3 && this.cardHeight > 0) {
        NotifyGroupShellLayer({ shellHeight: this.cardHeight, inset: 16, yOffset: 18,
          shellColor: $r('app.color.color_bg_stack_deep') });
      }
      if (this.section.messages.length >= 2 && this.cardHeight > 0) {
        NotifyGroupShellLayer({ shellHeight: this.cardHeight, inset: 8, yOffset: 9,
          shellColor: $r('app.color.color_bg_stack_shallow') });
      }
      Row({ space: 12 }) {
        if (this.isEditing) {
          Checkbox().select(this.groupSelected).selectedColor($r('app.color.color_brand'))
            .shape(CheckBoxShape.CIRCLE);
        }
        Column({ space: 6 }) {
          // 首条预览的标题、正文和图标必须作为同一共享节点，才能在展开后完整落到第一条组内消息。
          Column({ space: 6 }) {
            // 折叠分组预览与普通通知统一：标题和最新通知时间同行。
            Row({ space: 8 }) {
              if (this.section.messages[0].title.length > 0) {
                Text(this.section.messages[0].title).fontSize(15).fontWeight(FontWeight.Bold)
                  .fontColor($r('app.color.color_text_primary')).layoutWeight(1).maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis });
              } else { Blank().layoutWeight(1); }
              Text(formatNotifyTime(this.section.messages[0].timestamp)).fontSize(11)
                .fontColor($r('app.color.color_text_hint')).flexShrink(0);
            }.width('100%').alignItems(VerticalAlign.Center);
            // 图标只与正文并列，不再压缩标题与时间。
            Row({ space: 8 }) {
              Column() {
                if (this.section.messages[0].subtitle.length > 0) {
                  Text(this.section.messages[0].subtitle).fontSize(13).fontColor($r('app.color.color_brand'))
                    .width('100%').maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis });
                }
                this.body(this.section.messages[0]);
              }.layoutWeight(1);
              if (this.section.messages[0].image.length > 0) {
                Image(this.section.messages[0].image).width(38).height(38).borderRadius(12).objectFit(ImageFit.Cover).alt($r('app.media.app_icon'));
              }
            }
            .width('100%').alignItems(VerticalAlign.Top);
          }
          .width('100%').geometryTransition(`gmc:${this.section.groupKey}`)
          .transition(TransitionEffect.OPACITY.animation({ duration: 200 }));
          Row() {
            Row() { this.groupCount(); }
              .geometryTransition(`gmb:${this.section.groupKey}`);
            Blank();
          }.width('100%');
        }.layoutWeight(1);
      }
      .width('100%').padding({ left: 14, right: 14, top: 16, bottom: 16 }).backgroundColor($r('app.color.color_bg_surface')).borderRadius(12)
      .onAreaChange((_old: Area, value: Area) => this.onHeightChange(value.height as number))
      .onClick(() => this.isEditing ? this.onToggleSelection() : this.onOpen());
    }
    .width('100%').padding({ bottom: this.section.messages.length >= 3 ? 18 : 9 });
  }
}
