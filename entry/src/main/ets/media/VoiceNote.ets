/**
 * A recorded voice note, handed back as an ordinary attachment.
 *
 * Everything after `stop()` is the existing file path: UploadApi reads a sandbox
 * absolute path, and ChatApi turns an `audio/*` mime into the `{"type":"audio"}`
 * part the desktop console sends. Nothing here transcribes. Whether the clip becomes
 * text is the desktop's `audio_mode` decision, exactly as it is for a picked audio
 * file, so the phone stays out of a policy it cannot see.
 */
import { media } from '@kit.MediaKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import {
  abilityAccessCtrl,
  common,
  PermissionRequestResult,
  Permissions
} from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { Attachment } from '../model/Attachment';
import { Failure } from '../core/Failure';
import { Copy } from '../l10n/Copy';
import { Log } from '../core/Log';

const MIC: Permissions = 'ohos.permission.MICROPHONE';

/** AAC in an m4a container. 48 kHz is the rate Audio Kit's own mic-capture example uses. */
const SAMPLE_RATE: number = 48000;
const BIT_RATE: number = 48000;

/**
 * A take that never received one audio frame still finalizes into a box skeleton —
 * measured at 258 bytes with an empty mdat — so anything this small carries no sound.
 * One second of AAC at BIT_RATE is ~6000 bytes, well above the line.
 */
const SILENT_TAKE_BYTES: number = 512;

export class VoiceNote {
  private recorder: media.AVRecorder | undefined = undefined;
  private fd: number = -1;
  private path: string = '';

  isRecording(): boolean {
    return this.recorder !== undefined;
  }

  /** The file keeps its name after stop, so a send can happen a minute later. */
  filePath(): string {
    return this.path;
  }

  async start(ctx: common.UIAbilityContext): Promise<void> {
    if (this.recorder !== undefined) {
      return;
    }
    await VoiceNote.grantMicrophone(ctx);
    const path = `${ctx.cacheDir}/voice-${Date.now()}.m4a`;
    const file = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE);
    const fd = file.fd;
    let recorder: media.AVRecorder | undefined = undefined;
    try {
      recorder = await media.createAVRecorder();
      const profile: media.AVRecorderProfile = {
        audioBitrate: BIT_RATE,
        audioChannels: 1,
        audioCodec: media.CodecMimeType.AUDIO_AAC,
        audioSampleRate: SAMPLE_RATE,
        fileFormat: media.ContainerFormatType.CFT_MPEG_4A
      };
      const config: media.AVRecorderConfig = {
        audioSourceType: media.AudioSourceType.AUDIO_SOURCE_TYPE_MIC,
        profile: profile,
        url: `fd://${fd}`
      };
      await recorder.prepare(config);
      await recorder.start();
      // Ownership only moves once the engine is actually running, so every failure
      // path below can clean up what this call made without touching a live take.
      this.recorder = recorder;
      this.fd = fd;
      this.path = path;
      recorder = undefined;
    } catch (e) {
      const err = e as BusinessError;
      VoiceNote.log('start', err);
      if (recorder !== undefined) {
        await VoiceNote.release(recorder);
      }
      VoiceNote.close(fd);
      VoiceNote.unlink(path);
      throw Failure.local(VoiceNote.reason(err));
    }
  }

  /** Finish the take and describe it as the attachment the tray shows. */
  async stop(): Promise<Attachment> {
    const recorder = this.recorder;
    if (recorder === undefined) {
      throw Failure.local(Copy.notice_voice_none);
    }
    const path = this.path;
    const fd = this.fd;
    this.recorder = undefined;
    this.fd = -1;
    try {
      await recorder.stop();
    } catch (e) {
      VoiceNote.log('stop', e as BusinessError);
    }
    await VoiceNote.release(recorder);
    VoiceNote.close(fd);
    if (VoiceNote.sizeOf(path) < SILENT_TAKE_BYTES) {
      VoiceNote.unlink(path);
      throw Failure.local(Copy.notice_voice_empty);
    }
    const a = new Attachment();
    a.key = `voice_${Date.now()}`;
    a.uri = path;
    a.name = VoiceNote.nameOf(path);
    a.mime = 'audio/mp4';
    return a;
  }

  /** Throw the take away: the bar's other button, and any page popped mid-recording. */
  async discard(): Promise<void> {
    const recorder = this.recorder;
    const path = this.path;
    const fd = this.fd;
    this.recorder = undefined;
    this.fd = -1;
    if (recorder !== undefined) {
      try {
        await recorder.stop();
      } catch (e) {
        VoiceNote.log('discard', e as BusinessError);
      }
      await VoiceNote.release(recorder);
    }
    VoiceNote.close(fd);
    VoiceNote.unlink(path);
  }

  /**
   * A remembered denial shows no dialog, so asking again cannot succeed; the settings
   * page is the only way back.
   */
  private static async grantMicrophone(ctx: common.UIAbilityContext): Promise<void> {
    const atManager = abilityAccessCtrl.createAtManager();
    let result: PermissionRequestResult;
    try {
      result = await atManager.requestPermissionsFromUser(ctx, [MIC]);
    } catch (e) {
      VoiceNote.log('permission', e as BusinessError);
      throw Failure.local(Copy.notice_voice_denied);
    }
    const codes = result.authResults;
    if (codes.length > 0 && codes[0] === 0) {
      return;
    }
    const shown = result.dialogShownResults;
    if (shown !== undefined && shown.length > 0 && !shown[0]) {
      const states = await atManager.requestPermissionOnSetting(ctx, [MIC]);
      for (const state of states) {
        if (state === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED) {
          return;
        }
      }
    }
    throw Failure.local(Copy.notice_voice_denied);
  }

  private static log(stage: string, err: BusinessError): void {
    Log.warn(`voice ${stage} failed code=${err.code} ${err.message}`);
  }

  private static reason(err: BusinessError): string {
    const message = err.message;
    if (message !== undefined && message.length > 0) {
      return Copy.fill(Copy.notice_voice_failed, message);
    }
    return Copy.fillN(Copy.notice_voice_code, err.code);
  }

  private static async release(recorder: media.AVRecorder): Promise<void> {
    try {
      await recorder.release();
    } catch (e) {
      // A recorder that died on its own has nothing left to release.
    }
  }

  private static close(fd: number): void {
    if (fd < 0) {
      return;
    }
    try {
      fs.closeSync(fd);
    } catch (e) {
      // The upload opens the file by name, so a stuck fd is all that is lost.
    }
  }

  private static sizeOf(path: string): number {
    try {
      return fs.statSync(path).size;
    } catch (e) {
      return -1;
    }
  }

  private static unlink(path: string): void {
    if (path.length === 0) {
      return;
    }
    try {
      fs.unlinkSync(path);
    } catch (e) {
      // A take that never reached the disk has nothing to delete.
    }
  }

  private static nameOf(path: string): string {
    const slash = path.lastIndexOf('/');
    return slash >= 0 ? path.substring(slash + 1) : path;
  }
}
