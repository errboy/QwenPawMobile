"""
Check every `Something.ets:NNN` reference the docs make against the code.

docs/05, /07 and /08 point at source lines so a reader can jump to the rule being
described. Those numbers drift the moment code moves above them, and a ref that
lands three functions away is worse than no ref: it reads as verified. This walks
every markdown file of the mobile app, resolves each reference to its .ets file,
and reports the ones that are out of range, land on blank lines, or have lost the
identifier the sentence names next to them.

Forms accepted, because the docs use all of them:
  Foo.ets:12      a single line
  Foo.ets:21-22   a range
  Foo.ets:160,185 several sites in one ref
  `:635`          a bare line: the file the previous ref in this paragraph named

Names are scoped, not gathered per line. A table row keeps its code ref in the last
column while the identifier it documents sits in another one; prose wraps, so a
sentence can break anywhere. Reading the whole line would flag both as drift, and a
gate that cries wolf is a gate nobody runs. A reference is therefore held against
the names written next to it: its own cell, or the few characters around it.

Relative markdown links get checked in the same pass, for the same reason: a doc
that links to a file nobody has reads as verified but jumps nowhere. Backticked
paths are deliberately not checked -- those name build outputs, on-device runtime
files, and prose examples as often as they name repo files, so a path-existence
gate would report thirty false problems per run.

The pass after that one checks code against itself: every `Copy.fill*` call site
against the placeholder count of the copy constant it names. It lives here rather
than in a script of its own because a second command is a second gate nobody runs.

Run from the repository root:  python tools/doc_line_check.py
Exit code is the number of problems, so it drops straight into a gate.
"""
import io
import os
import re
import sys

SITES = r'\d{1,5}(?:-\d{1,5})?(?:,\d{1,5}(?:-\d{1,5})?)*'
# The bare form only ever appears inside backticks. Without that fence, every port
# number and every `127.0.0.1:8088` in the docs would read as a line reference.
FULL = re.compile(r'([A-Za-z0-9_]+\.ets):(' + SITES + r')')
BARE = re.compile(r'`:(' + SITES + r')`')
NAME = re.compile(r'`([A-Za-z][A-Za-z0-9_.]*)(?:\(\))?')
LINK = re.compile(r'\[[^]\n]*\]\(([^)\s]+)')
WINDOW = 3
# Prose names the symbol and then cites it, so the lookback is generous and the
# lookahead short: only what the next few characters say can speak for a ref.
BACK = 60
AHEAD = 14


def refs_of(line):
    """Every (column, file or None, site spec) this doc line cites."""
    out = [(m.start(), m.group(1), m.group(2)) for m in FULL.finditer(line)]
    out += [(m.start(), None, m.group(1)) for m in BARE.finditer(line)]
    out.sort()
    return out


def link_problems(doc, text):
    """Relative markdown links whose target is not on disk."""
    out = []
    for no, line in enumerate(text.split('\n'), start=1):
        for m in LINK.finditer(line):
            target = m.group(1)
            if '://' in target or target.startswith(('mailto:', '#')):
                continue
            path = os.path.normpath(
                os.path.join(os.path.dirname(doc), target.split('#')[0]))
            if not os.path.exists(path):
                out.append('%s:%d: link %s points at nothing' % (doc, no, target))
    return out


def sources(root):
    """Map a file name to every path with that name under the ArkTS source tree."""
    out = {}
    base = os.path.join(root, 'entry', 'src', 'main', 'ets')
    for dirpath, _dirs, files in os.walk(base):
        for f in files:
            if f.endswith('.ets'):
                out.setdefault(f, []).append(os.path.join(dirpath, f))
    return out


def docs_of(root):
    out = []
    for folder in ['docs', '.']:
        for f in sorted(os.listdir(os.path.join(root, folder))):
            if f.endswith('.md'):
                out.append(os.path.join(root, folder, f))
    return out


def paragraphs(lines):
    """Yield (first line number, joined text) for each blank-line separated block."""
    start = None
    buf = []
    for i, line in enumerate(lines, start=1):
        if line.strip():
            if start is None:
                start = i
            buf.append(line)
        elif start is not None:
            yield start, '\n'.join(buf)
            start = None
            buf = []
    if start is not None:
        yield start, '\n'.join(buf)


def sites_of(spec):
    """`21-22` and `160,185` both become a list of (first, last) spans."""
    spans = []
    for part in spec.split(','):
        if '-' in part:
            first, last = part.split('-')
            spans.append((int(first), int(last)))
        else:
            spans.append((int(part), int(part)))
    return spans


def names_near(text, offset):
    """The identifiers written around this reference, mostly behind it."""
    cut = text[max(0, offset - BACK):offset + AHEAD]
    # `core/Wire.ets` is a path, not two names: drop the directory part before
    # asking what a reference is about.
    found = []
    for m in NAME.finditer(cut):
        if m.end() < len(cut) and cut[m.end()] == '/':
            continue  # a path prefix such as core/ is not the rule cited
        token = m.group(1)
        if token.endswith('.ets'):
            continue
        name = token.split('.')[-1]
        if name not in found:
            found.append(name)
    return found


def names_of_cell(line, col):
    """For a table row: only the cell holding this ref speaks for it."""
    pos = 0
    for seg in line.split('|'):
        if pos <= col < pos + len(seg) + 1:
            return names_near(seg, col - pos)
        pos += len(seg) + 1
    return []


def mentioned(name, body, stem):
    if name == stem or name.lower() in body.lower():
        return True
    # Wire-style snake_case names are spelled differently in code (approval_level
    # sits next to approvalLevel), so any of their parts counts as a hit.
    if '_' in name:
        return any(len(f) > 3 and f.lower() in body.lower() for f in name.split('_'))
    return False


# All user copy sits in l10n/Copy.ets and is filled by shape-specific helpers,
# and String.replace('%s', x) replaces only the FIRST hit -- so a template that
# gained a placeholder, or a call site that lost one, puts a literal '%s' on the
# screen while ArkTS and the linter both stay quiet.
COPY_FILL = re.compile(r'Copy\.(fill2|fillN2|fillNums|fillN|fill)\('
                       r'\s*(?:Copy\.([A-Za-z0-9_]+)|([A-Za-z0-9_.]+))')
COPY_NEED = {'fill': {'%s': 1}, 'fill2': {'%s': 2}, 'fillN': {'%d': 1},
             'fillN2': {'%s': 1, '%d': 1}, 'fillNums': None}


def copy_arity_problems(root):
    """Report each Copy.fill* call whose placeholder count its template lacks.

    Returns (problems, notes): a call that fills a template built by another call
    is a note, not a problem, since counting placeholders there would be wrong.

    The other direction -- a copy constant carrying a placeholder nothing ever
    fills -- is deliberately NOT checked. Half the constants with placeholders
    are templates handed to another layer to fill (`Parts` for message bodies,
    `home_group_count` behind a nested fill), and the gate cannot tell those from
    a genuine leftover, so it would report noise on every run.
    """
    base = os.path.join(root, 'entry', 'src', 'main', 'ets')
    copy_path = os.path.join(base, 'l10n', 'Copy.ets')
    with io.open(copy_path, encoding='utf-8') as handle:
        copy_text = handle.read()
    templates = {}
    for m in re.finditer(r"^\s*(?:static\s+readonly\s+)?([a-zA-Z0-9_]+)\s*:\s*string\s*=\s*'(.*)';$",
                         copy_text, re.M):
        templates[m.group(1)] = m.group(2)
    problems = []
    notes = []
    for dirpath, _dirs, files in os.walk(base):
        for name in sorted(files):
            if not name.endswith('.ets'):
                continue
            path = os.path.join(dirpath, name)
            with io.open(path, encoding='utf-8') as handle:
                lines = handle.read().split('\n')
            for no, line in enumerate(lines, start=1):
                for m in COPY_FILL.finditer(line):
                    fn, const, other = m.group(1), m.group(2), m.group(3)
                    if const in COPY_NEED or other in COPY_NEED:
                        # A template built by another fill: the outer helper sees a
                        # finished string, so counting placeholders would be wrong.
                        notes.append('%s:%d: %s fills a template built one call out'
                                     % (path, no, fn))
                        continue
                    if const is None:
                        continue
                    if const not in templates:
                        problems.append('%s:%d: %s names a Copy constant that is not there (%s)'
                                        % (path, no, fn, const))
                        continue
                    tmpl = templates[const]
                    if COPY_NEED[fn] is None:
                        if '%d' not in tmpl:
                            problems.append('%s:%d: fillNums on Copy.%s, which has no %%d'
                                            % (path, no, const))
                        continue
                    for token, want in COPY_NEED[fn].items():
                        got = tmpl.count(token)
                        if got != want:
                            problems.append('Copy.%s has %d %s but %s:%d %s fills %d'
                                            % (const, got, token, path, no, fn, want))
    return problems, notes


def default_root():
    """The tree to check, for whoever ran the command without saying.

    Two layouts run this gate: the private one, where the app sits under
    `QwenPawMobile/`, and the published repository, where the same directories are
    the root. The line above promises a bare `python tools/doc_line_check.py`, and
    a stranger has no second layout to name, so read the layout off the disk
    instead of asking for it. `entry/src/main/ets` is what makes a directory this
    app rather than the outer repo, which has a `docs/` of its own.
    """
    app = os.path.join('entry', 'src', 'main', 'ets')
    return '.' if os.path.isdir(app) else 'QwenPawMobile'


def main():
    root = sys.argv[1] if len(sys.argv) > 1 else default_root()
    src = sources(root)
    cache = {}
    problems = 0
    checked = 0
    for doc in docs_of(root):
        with io.open(doc, encoding='utf-8') as handle:
            lines = handle.read().split('\n')
        for msg in link_problems(doc, '\n'.join(lines)):
            print(msg)
            problems += 1
        # Paragraph text plus where each of its lines starts, so a wrapped sentence
        # still reads as one sentence when a reference is placed in it.
        places = {}
        for start, text in paragraphs(lines):
            offset = 0
            for i in range(start, start + text.count('\n') + 1):
                places[i] = (text, offset)
                offset += len(lines[i - 1]) + 1
        current = None
        for no, line in enumerate(lines, start=1):
            if not line.strip():
                current = None
            row = line.lstrip().startswith('|')
            for col, fname, spec in refs_of(line):
                if fname is None:
                    fname = current
                    if fname is None:
                        print('%s:%d: bare :%s has no file to belong to' % (doc, no, spec))
                        problems += 1
                        continue
                else:
                    current = fname
                checked += 1
                paths = src.get(fname, [])
                if len(paths) != 1:
                    print('%s:%d: %s matches %d files' % (doc, no, fname, len(paths)))
                    problems += 1
                    continue
                if fname not in cache:
                    with io.open(paths[0], encoding='utf-8') as handle:
                        cache[fname] = handle.read().split('\n')
                code = cache[fname]
                bad = False
                for first, last in sites_of(spec):
                    if first < 1 or last > len(code) or last < first:
                        print('%s:%d: %s:%s is out of range (%d lines)'
                              % (doc, no, fname, spec, len(code)))
                        bad = True
                        break
                    if not any(x.strip() for x in code[first - 1:last]):
                        print('%s:%d: %s:%s lands on blank lines' % (doc, no, fname, spec))
                        bad = True
                        break
                if bad:
                    problems += 1
                    continue
                lo = max(0, first - 1 - WINDOW)
                body = '\n'.join(code[lo:min(len(code), last + WINDOW)])
                if row:
                    wanted = names_of_cell(line, col)
                else:
                    text, base = places.get(no, (line, 0))
                    wanted = names_near(text, base + col)
                wanted = [n for n in wanted if len(n) > 3]
                if wanted and not any(mentioned(n, body, fname[:-len('.ets')]) for n in wanted):
                    print('%s:%d: %s:%s has none of %s within %d lines'
                          % (doc, no, fname, spec, wanted, WINDOW))
                    problems += 1
    arity, notes = copy_arity_problems(root)
    for msg in notes:
        print('%s (note: checked by eye, not counted)' % msg)
    for msg in arity:
        print(msg)
        problems += 1
    print('%d references checked, %d problems' % (checked, problems))
    return problems


if __name__ == '__main__':
    sys.exit(main())
