/** Sizes the user reads, not the bytes the API returns. */
export function humanBytes(bytes: number): string {
  if (bytes < 1024) {
    return `${bytes} B`;
  }
  if (bytes < 1024 * 1024) {
    return `${(bytes / 1024).toFixed(1)} KB`;
  }
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

/**
 * A timestamp the way a list shows one: the year is dropped while it is the current
 * one, because every row in a chat shares it. The value is read, never parsed into
 * a Date — the server hands back ISO 8601 already normalised to the user's zone
 * (utils.py `_normalize_msg_timestamp`), and re-interpreting that through the
 * device's own clock is how a timestamp moves by an hour. Anything not shaped like
 * an ISO instant comes back as '' so a row shows no date rather than a mangled one.
 */
export function stampText(iso: string): string {
  if (iso.length < 16 || iso.charAt(4) !== '-' || iso.charAt(10) !== 'T') {
    return '';
  }
  const date = iso.substring(0, 10);
  const time = iso.substring(11, 16);
  const year = new Date().getFullYear().toString();
  return date.substring(0, 4) === year ? `${date.substring(5)} ${time}` : `${date} ${time}`;
}

/**
 * The same shape for a turn this phone just had in front of it, which no server
 * value describes yet. Local wall clock rather than `toISOString()`: history's
 * values are in the user's zone, so a UTC stamp here would show a live turn at one
 * time and itself at another after the next reload.
 */
export function nowStamp(): string {
  const d = new Date();
  const pad = (n: number): string => (n < 10 ? `0${n}` : `${n}`);
  return stampText(`${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`
    + `T${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`);
}
