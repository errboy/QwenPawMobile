/**
 * One chat bubble.
 *
 * The item is @ObjectLink, not a @Prop copy: a token delta mutates the observed
 * UiMessage in place and only this bubble redraws. v1 rebuilt the whole list per
 * frame, which is what made long generations stutter.
 *
 * Every colour, radius and font here is a token; none of them is a literal.
 */
import { AppColor, AppLine, AppRadius, AppSize, AppSpace, AppType, AppWidth } from '../../theme/Theme';
import { NoticeTone, UiKind, UiMessage } from '../../state/UiMessage';
import { Role } from '../../core/Wire';
import { Copy } from '../../l10n/Copy';
import { Parts } from '../../model/Parts';
import { image } from '@kit.ImageKit';

@Component
export struct Bubble {
  @ObjectLink item: UiMessage;
  onRecall: (key: string) => void = (): void => {};

  private errorTone(): boolean {
    return this.item.tone === NoticeTone.ERROR;
  }

  private imageSource(): image.PixelMap | string {
    const value = this.item.image;
    if (value === undefined) {
      return '';
    }
    return value.map === undefined ? value.url : value.map;
  }

  private imageReady(): boolean {
    const value = this.item.image;
    return value !== undefined && !value.failed && !value.isEmpty();
  }

  private imageBroken(): boolean {
    const value = this.item.image;
    return value !== undefined && value.failed;
  }

  @Builder
  imageBlock() {
    if (this.imageReady()) {
      Image(this.imageSource())
        .objectFit(ImageFit.Contain)
        .borderRadius(AppRadius.card)
        .constraintSize({ maxWidth: AppWidth.bubble_max, maxHeight: AppSize.image_max })
    } else if (this.imageBroken()) {
      Text(Copy.chat_image_unavailable)
        .fontSize(AppType.caption)
        .fontColor(AppColor.text_tertiary)
    } else {
      Text(Copy.chat_image_loading)
        .fontSize(AppType.caption)
        .fontColor(AppColor.text_tertiary)
    }
  }

  @Builder
  videoBlock() {
    if (Parts.isDirectUrl(this.item.videoRef)) {
      Video({ src: this.item.videoRef, previewUri: '' })
        .controls(true)
        .borderRadius(AppRadius.card)
        .constraintSize({ maxWidth: AppWidth.bubble_max, maxHeight: AppSize.image_max })
    } else {
      Text(Copy.chat_video_unavailable)
        .fontSize(AppType.caption)
        .fontColor(AppColor.text_tertiary)
    }
  }

  @Builder
  audioBlock() {
    if (this.item.audioRef.length > 0) {
      Row({ space: AppSpace.xxs }) {
        Text(Copy.chat_audio_label)
          .fontSize(AppType.caption)
          .fontColor(AppColor.text_secondary)
      }
      .backgroundColor(AppColor.surface_subtle)
      .padding(AppSpace.sm)
      .borderRadius(AppRadius.card)
      .constraintSize({ maxWidth: AppWidth.bubble_max })
    }
  }

  @Builder
  fileBlock() {
    if (this.item.fileRef.length > 0 || this.item.fileName.length > 0) {
      Row({ space: AppSpace.xxs }) {
        Text(`📄 ${this.item.fileName.length > 0 ? this.item.fileName : Copy.chat_file_unavailable}`)
          .fontSize(AppType.caption)
          .fontColor(AppColor.text_secondary)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .backgroundColor(AppColor.surface_subtle)
      .padding(AppSpace.sm)
      .borderRadius(AppRadius.card)
      .border({ width: AppLine.thin, color: AppColor.border_subtle })
      .constraintSize({ maxWidth: AppWidth.bubble_max })
    }
  }

  build() {
    if (this.item.kind === UiKind.NOTICE) {
      Row() {
        Text(this.item.text)
          .fontSize(AppType.caption)
          .fontColor(this.errorTone() ? AppColor.error_text : AppColor.text_tertiary)
          .maxLines(3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
    } else if (this.item.kind === UiKind.QUEUED) {
      Column({ space: AppSpace.xxs }) {
        Text(this.item.text)
          .fontSize(AppType.message)
          .fontColor(AppColor.accent_text)
          .backgroundColor(AppColor.accent_soft)
          .padding(AppSpace.sm)
          .borderRadius(AppRadius.card)
          .constraintSize({ maxWidth: AppWidth.bubble_max })
        Text(Copy.chat_queued_hint)
          .fontSize(AppType.caption)
          .fontColor(AppColor.text_tertiary)
      }
      .alignItems(HorizontalAlign.End)
      .width('100%')
      .onClick(() => {
        this.onRecall(this.item.key);
      })
    } else if (this.item.role === Role.USER) {
      Column({ space: AppSpace.xxs }) {
        if (this.item.imageRef.length > 0) {
          this.imageBlock()
        }
        if (this.item.videoRef.length > 0) {
          this.videoBlock()
        }
        if (this.item.audioRef.length > 0) {
          this.audioBlock()
        }
        if (this.item.fileRef.length > 0 || this.item.fileName.length > 0) {
          this.fileBlock()
        }
        if (this.item.text.length > 0) {
          Text(this.item.text)
            .fontSize(AppType.message)
            .fontColor(AppColor.text_inverse)
            .backgroundColor(AppColor.accent)
            .padding(AppSpace.sm)
            .borderRadius(AppRadius.card)
            .constraintSize({ maxWidth: AppWidth.bubble_max })
        }
      }
      .alignItems(HorizontalAlign.End)
      .width('100%')
    } else if (this.item.kind === UiKind.TOOL) {
      Column({ space: AppSpace.xxs }) {
        Text(Copy.fill(Copy.chat_tool_label, this.item.name))
          .fontSize(AppType.caption)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppColor.warning_text)
        Text(this.item.text)
          .fontSize(AppType.caption)
          .fontColor(AppColor.warning_text)
          .maxLines(4)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .backgroundColor(AppColor.warning_bg)
      .border({ width: AppLine.thin, color: AppColor.warning_border })
      .padding(AppSpace.sm)
      .borderRadius(AppRadius.card)
      .constraintSize({ maxWidth: AppWidth.tool_max })
    } else if (this.item.kind === UiKind.REASONING) {
      Column({ space: AppSpace.xxs }) {
        Text(Copy.chat_reasoning_label)
          .fontSize(AppType.caption)
          .fontColor(AppColor.text_tertiary)
        Text(this.item.text)
          .fontSize(AppType.caption)
          .fontStyle(FontStyle.Italic)
          .fontColor(AppColor.text_secondary)
          .maxLines(6)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .backgroundColor(AppColor.surface_subtle)
      .padding(AppSpace.sm)
      .borderRadius(AppRadius.card)
      .constraintSize({ maxWidth: AppWidth.tool_max })
    } else {
      Column({ space: AppSpace.xxs }) {
        if (this.item.imageRef.length > 0) {
          this.imageBlock()
        }
        if (this.item.videoRef.length > 0) {
          this.videoBlock()
        }
        if (this.item.audioRef.length > 0) {
          this.audioBlock()
        }
        if (this.item.fileRef.length > 0 || this.item.fileName.length > 0) {
          this.fileBlock()
        }
        if (this.item.text.length > 0) {
          Text(this.item.streaming ? `${this.item.text} ▍` : this.item.text)
            .fontSize(AppType.message)
            .fontColor(AppColor.text)
            .backgroundColor(AppColor.surface)
            .padding(AppSpace.sm)
            .borderRadius(AppRadius.card)
            .border({ width: AppLine.thin, color: AppColor.border_subtle })
            .constraintSize({ maxWidth: AppWidth.bubble_max })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
    }
  }
}
