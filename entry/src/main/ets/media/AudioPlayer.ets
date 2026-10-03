/**
 * Plays one voice note or audio message at a time.
 *
 * AVPlayer's only accepted local form is `fd://<fd>`: a bare sandbox path, a
 * file:// URI and a content:// URI are all refused, so the cached file is opened
 * for the length of the take and closed the moment playback ends. A direct
 * http(s) URL goes to the player itself, which fetches without our header.
 *
 * The player is a state machine that reports its own transitions. Assigning the
 * url only reaches 'initialized' asynchronously and prepare() is legal in no
 * other state, so every step after the url is taken from the state callback —
 * calling prepare() inline races it and fails with 'unsupport prepare operation'.
 */
import { media } from '@kit.MediaKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { Failure } from '../core/Failure';
import { Log } from '../core/Log';

export class AudioPlayer {
  private player: media.AVPlayer | undefined = undefined;
  private file: fs.File | undefined = undefined;
  /** Which bubble is holding the speaker; '' when nothing is playing. */
  private key: string = '';
  /** handed back so the bubble that started the take can drop its playing mark. */
  private onEnd: (key: string) => void = (): void => {};
  /** why a take never became sound, for the notice the page shows. */
  private onFail: (message: string) => void = (): void => {};

  current(): string {
    return this.key;
  }

  /** Settles once the take is running; every later failure reports through onFail. */
  async play(key: string, source: string, onEnd: (key: string) => void,
    onFail: (message: string) => void): Promise<void> {
    // Replacing a live take has to notify its own bubble, not just the new one.
    this.end();
    this.key = key;
    this.onEnd = onEnd;
    this.onFail = onFail;
    let file: fs.File | undefined = undefined;
    let url = source;
    let player: media.AVPlayer | undefined = undefined;
    try {
      if (source.startsWith('/')) {
        file = fs.openSync(source, fs.OpenMode.READ_ONLY);
        url = `fd://${file.fd}`;
      }
      player = await media.createAVPlayer();
      this.file = file;
      this.player = player;
      // Both handlers go in before the resource: a failure inside the handshake has
      // no other route to us, and a stuck 'prepared' would leave the bubble marked.
      player.on('stateChange', (state: media.AVPlayerState): void => {
        this.onState(state);
      });
      player.on('error', (err: BusinessError): void => {
        this.fail(AudioPlayer.reason(err));
      });
      player.url = url;
    } catch (e) {
      const message = AudioPlayer.reason(e as BusinessError);
      if (file !== undefined) {
        AudioPlayer.close(file);
      }
      if (player !== undefined) {
        await AudioPlayer.release(player);
      }
      this.report(message);
    }
  }

  /** Silence now: the second tap on a playing bubble, and every teardown path. */
  stop(): void {
    this.end();
  }

  private onState(state: string): void {
    const player = this.player;
    if (player === undefined) {
      return;
    }
    if (state === 'initialized') {
      player.prepare().catch((e: Object): void => {
        this.fail(AudioPlayer.reason(e as BusinessError));
      });
      return;
    }
    if (state === 'prepared') {
      player.play().catch((e: Object): void => {
        this.fail(AudioPlayer.reason(e as BusinessError));
      });
      return;
    }
    if (state === 'completed') {
      this.end();
    }
  }

  /**
   * A take that will not make sound: tell the caller while the session is still
   * theirs, then tear it down. end() clears the callbacks, so the report goes out
   * first and the bubble still loses its mark through the same call.
   */
  private fail(message: string): void {
    Log.warn(`audio failed: ${message}`);
    this.report(message);
    this.end();
  }

  private report(message: string): void {
    const onFail = this.onFail;
    this.onFail = (): void => {};
    onFail(message);
  }

  /**
   * One shot: the session is cleared before anything is torn down, so a state
   * event that arrives while the player is closing cannot fire the callback twice.
   */
  private end(): void {
    const key = this.key;
    const onEnd = this.onEnd;
    this.key = '';
    this.onEnd = (): void => {};
    this.onFail = (): void => {};
    const player = this.player;
    this.player = undefined;
    if (player !== undefined) {
      try {
        player.off('stateChange');
        player.off('error');
        player.stop().then(async (): Promise<void> => {
          await AudioPlayer.release(player);
        }).catch((): void => {
          // A player that died on its own has nothing left to stop.
        });
      } catch (e) {
        // Releasing is the only remedy for a player that refuses the commands.
        AudioPlayer.release(player).catch((): void => {});
      }
    }
    const file = this.file;
    this.file = undefined;
    if (file !== undefined) {
      AudioPlayer.close(file);
    }
    if (key.length > 0) {
      onEnd(key);
    }
  }

  private static reason(err: BusinessError): string {
    const message = err.message;
    return message === undefined || message.length === 0 ? `${err.code}` : `${err.code} ${message}`;
  }

  private static close(file: fs.File): void {
    try {
      fs.closeSync(file);
    } catch (e) {
      // The fd dies with the process at worst.
    }
  }

  private static async release(player: media.AVPlayer): Promise<void> {
    try {
      await player.release();
    } catch (e) {
      // Nothing to reclaim on a player already in the released state.
    }
  }
}
