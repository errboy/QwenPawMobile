/**
 * A deliberately small Markdown parser for agent output.
 *
 * The desktop console renders full GFM through react-markdown, while the phone
 * rendered every bubble as raw text, so '**bold**' arrived on screen with its
 * asterisks. This covers the handful of constructs an agent actually emits:
 * fenced code, headings, bullet and numbered lists, quotes, rules, tables, and
 * inline bold / italic / strike / code / link.
 *
 * Anything outside that subset stays literal text. That is the point: an unusual
 * document degrades to exactly what the bubble used to show, never to garbage.
 *
 * Two known limits, both deliberate. A link keeps its label and drops its target,
 * because a Span cannot be tapped on its own. And '_italic_' is only read at word
 * boundaries, so snake_case identifiers survive intact.
 */

/** Block kinds. Strings, like every other tag in this app. */
export class MdKind {
  static readonly para: string = 'para';
  static readonly head: string = 'head';
  static readonly code: string = 'code';
  static readonly list: string = 'list';
  static readonly quote: string = 'quote';
  static readonly rule: string = 'rule';
  static readonly table: string = 'table';
}

/** How a table column places its cells, read off the delimiter row. */
export class MdAlign {
  static readonly center: string = 'c';
  static readonly right: string = 'r';
}

/** One run of same-styled text inside a block. */
export class MdRun {
  text: string = '';
  bold: boolean = false;
  italic: boolean = false;
  strike: boolean = false;
  link: boolean = false;
  code: boolean = false;
}

/** One table cell. Its column's alignment is carried per cell so the view
 *  never has to reach back into the block by index while rendering a row. */
export class MdCell {
  runs: MdRun[] = [];
  align: string = '';
}

export class MdRow {
  cells: MdCell[] = [];
  head: boolean = false;
}

export class MdBlock {
  kind: string = MdKind.para;
  runs: MdRun[] = [];
  /** Code body, kept per line so a long paste wraps where the reader stops. */
  lines: string[] = [];
  /** Table rows, header first. Empty for every other kind. */
  rows: MdRow[] = [];
  /** Bullet or number drawn in front of a list item. */
  marker: string = '';
  /** Heading level, 1 to 6. */
  depth: number = 0;
}

/** List marker plus how much of the line it consumed. */
class MarkerInfo {
  found: boolean = false;
  text: string = '';
  cut: number = 0;
}

/** A table plus how many source lines it consumed, so the parser can skip them. */
class TableHit {
  block: MdBlock = new MdBlock();
  taken: number = 0;
}

export class Markdown {
  /**
   * GFM backslash escapes only ASCII punctuation. Escaping anything (the old
   * behaviour) ate the separator of every Windows path the desktop puts in
   * tool output and in its own attachment notices: `C:\Users\x` rendered as
   * `C:Usersx`. The desktop's react-markdown keeps `\U`, so this is parity.
   */
  private static readonly ESCAPABLE: string = '!"#$%&\'()*+,-./:;<=>?@[\\]^_`{|}~';

  private static isEscapable(c: string): boolean {
    return c.length === 1 && Markdown.ESCAPABLE.indexOf(c) >= 0;
  }

  static parse(src: string): MdBlock[] {
    const out: MdBlock[] = [];
    const para: string[] = [];
    let code: string[] | undefined = undefined;
    const lines: string[] = src.split('\n');
    for (let i = 0; i < lines.length; i++) {
      const raw: string = lines[i];
      const line: string = Markdown.rtrim(raw);
      if (code !== undefined) {
        if (Markdown.isFence(line)) {
          out.push(Markdown.codeBlock(code));
          code = undefined;
        } else {
          code.push(raw);
        }
        continue;
      }
      if (Markdown.isFence(line)) {
        Markdown.flushPara(out, para);
        code = [];
        continue;
      }
      if (line.length === 0) {
        Markdown.flushPara(out, para);
        continue;
      }
      const depth: number = Markdown.headingDepth(line);
      if (depth > 0) {
        Markdown.flushPara(out, para);
        const block = new MdBlock();
        block.kind = MdKind.head;
        block.depth = depth;
        block.runs = Markdown.inline(Markdown.trim(line.substring(depth)));
        out.push(block);
        continue;
      }
      if (Markdown.isRule(line)) {
        Markdown.flushPara(out, para);
        const block = new MdBlock();
        block.kind = MdKind.rule;
        out.push(block);
        continue;
      }
      const marker = Markdown.listOf(line);
      if (marker.found) {
        Markdown.flushPara(out, para);
        const block = new MdBlock();
        block.kind = MdKind.list;
        block.marker = marker.text;
        block.runs = Markdown.inline(Markdown.trim(raw.substring(marker.cut)));
        out.push(block);
        continue;
      }
      if (Markdown.isQuote(line)) {
        Markdown.flushPara(out, para);
        const block = new MdBlock();
        block.kind = MdKind.quote;
        block.runs = Markdown.inline(Markdown.trim(line.substring(1)));
        out.push(block);
        continue;
      }
      const table = Markdown.tableAt(lines, i);
      if (table !== undefined) {
        Markdown.flushPara(out, para);
        out.push(table.block);
        i += table.taken - 1;
        continue;
      }
      para.push(line);
    }
    Markdown.flushPara(out, para);
    // A stream caught inside a fence still shows as code, not as stray backticks.
    if (code !== undefined) {
      out.push(Markdown.codeBlock(code));
    }
    return out;
  }

  static inline(src: string): MdRun[] {
    const out: MdRun[] = [];
    Markdown.scan(src, out, false, false, false, false, false);
    return out;
  }

  private static scan(s: string, out: MdRun[], bold: boolean, italic: boolean,
    strike: boolean, link: boolean, code: boolean): void {
    let text: string = '';
    let i: number = 0;
    while (i < s.length) {
      const c: string = s.charAt(i);
      if (c === '\\' && i + 1 < s.length && Markdown.isEscapable(s.charAt(i + 1))) {
        text += s.charAt(i + 1);
        i += 2;
        continue;
      }
      if (c === '`') {
        const end: number = s.indexOf('`', i + 1);
        if (end > i) {
          Markdown.emit(out, text, bold, italic, strike, link, code);
          Markdown.emit(out, s.substring(i + 1, end), bold, italic, strike, link, true);
          text = '';
          i = end + 1;
          continue;
        }
      }
      if (c === '~' && s.startsWith('~~', i)) {
        const end: number = s.indexOf('~~', i + 2);
        if (end > i + 1) {
          Markdown.emit(out, text, bold, italic, strike, link, code);
          text = '';
          Markdown.scan(s.substring(i + 2, end), out, bold, italic, true, link, code);
          i = end + 2;
          continue;
        }
      }
      if (c === '*' && s.startsWith('**', i)) {
        const end: number = s.indexOf('**', i + 2);
        if (end > i + 1) {
          Markdown.emit(out, text, bold, italic, strike, link, code);
          text = '';
          Markdown.scan(s.substring(i + 2, end), out, true, italic, strike, link, code);
          i = end + 2;
          continue;
        }
      }
      if (c === '*') {
        const end: number = s.indexOf('*', i + 1);
        if (end > i) {
          Markdown.emit(out, text, bold, italic, strike, link, code);
          text = '';
          Markdown.scan(s.substring(i + 1, end), out, bold, true, strike, link, code);
          i = end + 1;
          continue;
        }
      }
      if (c === '_' && Markdown.atEdge(s, i - 1)) {
        const end: number = s.indexOf('_', i + 1);
        if (end > i && Markdown.atEdge(s, end + 1)) {
          Markdown.emit(out, text, bold, italic, strike, link, code);
          text = '';
          Markdown.scan(s.substring(i + 1, end), out, bold, true, strike, link, code);
          i = end + 1;
          continue;
        }
      }
      if (c === '[') {
        const close: number = s.indexOf(']', i + 1);
        if (close > i && s.charAt(close + 1) === '(') {
          const stop: number = s.indexOf(')', close + 2);
          if (stop > close) {
            Markdown.emit(out, text, bold, italic, strike, link, code);
            text = '';
            Markdown.scan(s.substring(i + 1, close), out, bold, italic, strike, true, code);
            i = stop + 1;
            continue;
          }
        }
      }
      text += c;
      i += 1;
    }
    Markdown.emit(out, text, bold, italic, strike, link, code);
  }

  private static emit(out: MdRun[], text: string, bold: boolean, italic: boolean,
    strike: boolean, link: boolean, code: boolean): void {
    if (text.length === 0) {
      return;
    }
    const run = new MdRun();
    run.text = text;
    run.bold = bold;
    run.italic = italic;
    run.strike = strike;
    run.link = link;
    run.code = code;
    out.push(run);
  }

  private static codeBlock(lines: string[]): MdBlock {
    const block = new MdBlock();
    block.kind = MdKind.code;
    block.lines = lines;
    return block;
  }

  private static flushPara(out: MdBlock[], para: string[]): void {
    if (para.length === 0) {
      return;
    }
    const block = new MdBlock();
    block.runs = Markdown.inline(para.join('\n'));
    out.push(block);
    para.length = 0;
  }

  private static isFence(line: string): boolean {
    return Markdown.ltrim(line).startsWith('```');
  }

  private static isRule(line: string): boolean {
    const t: string = Markdown.trim(line);
    if (t.length < 3) {
      return false;
    }
    const c: string = t.charAt(0);
    if (c !== '-' && c !== '*' && c !== '_') {
      return false;
    }
    for (let i = 1; i < t.length; i++) {
      if (t.charAt(i) !== c) {
        return false;
      }
    }
    return true;
  }

  private static isQuote(line: string): boolean {
    return Markdown.ltrim(line).startsWith('>');
  }

  /**
   * Columns past this are left as text. A phone bubble is roughly two thirds of
   * the screen, and equal-weight columns at seven cells put every word on its own
   * line, which is the garbage this parser promises not to produce. The desktop
   * has the same table on a wider canvas, so the difference is space, not rules.
   */
  private static readonly MAX_COLS: number = 6;

  /**
   * Whether this text holds a table, asked by a bubble before it lays itself out.
   * A grid can only divide a width it is given, and a bubble that sizes to its
   * content gives none, so the caller has to know to stop sizing to content.
   */
  static hasTable(src: string): boolean {
    const lines: string[] = src.split('\n');
    for (let i = 0; i + 1 < lines.length; i++) {
      if (Markdown.isRow(lines[i]) && Markdown.isDelimiter(lines[i + 1])) {
        return true;
      }
    }
    return false;
  }

  /**
   * A GFM table is a piped row over a delimiter row (`| --- | :-: |`) plus piped
   * rows below it. Requiring the delimiter is what keeps a sentence that merely
   * contains a '|' out of this branch, and requiring the leading '|' keeps a
   * 'a | b' prose fragment out too.
   */
  private static tableAt(lines: string[], at: number): TableHit | undefined {
    if (at + 1 >= lines.length || !Markdown.isRow(lines[at])
      || !Markdown.isDelimiter(lines[at + 1])) {
      return undefined;
    }
    const marks: string[] = Markdown.splitCells(lines[at + 1]);
    const block = new MdBlock();
    block.kind = MdKind.table;
    block.rows = [Markdown.rowOf(Markdown.splitCells(lines[at]), marks, true)];
    let next: number = at + 2;
    while (next < lines.length && Markdown.isRow(lines[next])) {
      block.rows.push(Markdown.rowOf(Markdown.splitCells(lines[next]), marks, false));
      next += 1;
    }
    const hit = new TableHit();
    hit.block = block;
    hit.taken = next - at;
    return hit;
  }

  /** The column count comes from the delimiter row; extras drop, gaps stay empty. */
  private static rowOf(cells: string[], marks: string[], head: boolean): MdRow {
    const row = new MdRow();
    row.head = head;
    for (let i = 0; i < marks.length; i++) {
      const cell = new MdCell();
      cell.align = Markdown.alignOf(marks[i]);
      cell.runs = Markdown.inline(i < cells.length ? cells[i] : '');
      row.cells.push(cell);
    }
    return row;
  }

  private static isRow(line: string): boolean {
    const t: string = Markdown.trim(line);
    return t.startsWith('|') && Markdown.splitCells(t).length > 1;
  }

  private static isDelimiter(line: string): boolean {
    if (!Markdown.trim(line).startsWith('|')) {
      return false;
    }
    const cells: string[] = Markdown.splitCells(line);
    if (cells.length < 2 || cells.length > Markdown.MAX_COLS) {
      return false;
    }
    for (const cell of cells) {
      if (!Markdown.isDashCell(cell)) {
        return false;
      }
    }
    return true;
  }

  /** A delimiter cell is dashes with optional colons on either end. */
  private static isDashCell(cell: string): boolean {
    const t: string = Markdown.trim(cell);
    if (t.indexOf('-') < 0) {
      return false;
    }
    for (let i = 0; i < t.length; i++) {
      const c: string = t.charAt(i);
      if (c !== '-' && c !== ':') {
        return false;
      }
    }
    return true;
  }

  private static alignOf(mark: string): string {
    const t: string = Markdown.trim(mark);
    const left: boolean = t.startsWith(':');
    const right: boolean = t.endsWith(':');
    if (left && right) {
      return MdAlign.center;
    }
    return right ? MdAlign.right : '';
  }

  /** Split a piped line into trimmed cells. An escaped '|' stays inside its cell. */
  private static splitCells(line: string): string[] {
    const t: string = Markdown.trim(line);
    const body: string = t.endsWith('|') ? t.substring(0, t.length - 1) : t;
    const out: string[] = [];
    let cur: string = '';
    for (let i = 1; i < body.length; i++) {
      const c: string = body.charAt(i);
      if (c === '\\' && body.charAt(i + 1) === '|') {
        cur += '|';
        i += 1;
        continue;
      }
      if (c === '|') {
        out.push(Markdown.trim(cur));
        cur = '';
        continue;
      }
      cur += c;
    }
    out.push(Markdown.trim(cur));
    return out;
  }

  private static headingDepth(line: string): number {
    const t: string = Markdown.ltrim(line);
    let n: number = 0;
    while (n < t.length && t.charAt(n) === '#') {
      n += 1;
    }
    if (n === 0 || n > 6) {
      return 0;
    }
    return t.charAt(n) === ' ' ? n : 0;
  }

  private static listOf(line: string): MarkerInfo {
    const info = new MarkerInfo();
    const t: string = Markdown.ltrim(line);
    const indent: number = line.length - t.length;
    if (indent > 3 || t.length < 2) {
      return info;
    }
    const c: string = t.charAt(0);
    if ((c === '-' || c === '*' || c === '+') && t.charAt(1) === ' ') {
      info.found = true;
      info.text = '•';
      info.cut = indent + 2;
      return info;
    }
    let i: number = 0;
    while (i < t.length && Markdown.digit(t.charAt(i))) {
      i += 1;
    }
    if (i > 0 && t.charAt(i) === '.' && t.charAt(i + 1) === ' ') {
      info.found = true;
      info.text = `${t.substring(0, i)}.`;
      info.cut = indent + i + 2;
    }
    return info;
  }

  /** True for a position that opens or closes a word: edge, space or punctuation. */
  private static atEdge(s: string, at: number): boolean {
    if (at < 0 || at >= s.length) {
      return true;
    }
    const c: string = s.charAt(at);
    return c === ' ' || c === '\n' || c === '\t' || c === '(' || c === ')' ||
      c === '[' || c === ']' || c === '，' || c === '。' || c === '；' || c === '：';
  }

  private static digit(c: string): boolean {
    return c >= '0' && c <= '9';
  }

  private static trim(s: string): string {
    return Markdown.rtrim(Markdown.ltrim(s));
  }

  private static ltrim(s: string): string {
    let i: number = 0;
    while (i < s.length && Markdown.space(s.charAt(i))) {
      i += 1;
    }
    return s.substring(i);
  }

  private static rtrim(s: string): string {
    let i: number = s.length;
    while (i > 0 && Markdown.space(s.charAt(i - 1))) {
      i -= 1;
    }
    return s.substring(0, i);
  }

  private static space(c: string): boolean {
    return c === ' ' || c === '\t' || c === '\r';
  }
}
