"""Hold every colour pair the app paints at the store's contrast rule.

The app-store review report measures one control at a time and quotes a ratio: "body
text against its background must exceed 4.5:1, icons and titles 3:1". A palette picked
by eye fails that in more places than the one report named, and two mechanisms hide it
from a reader of color.json: an 8-digit `#AARRGGBB` value is semi-transparent, so what
it really is depends on the layer underneath, and a control dimmed with `.opacity()`
washes its fill and its label toward the page together.

So the pairs live here instead of in a screenshot review. Each row is one foreground
token over each background token the components actually put it on; a background that
carries alpha is scored over both the card and the page, because which one it lands on
is a runtime layout choice, and the worse of the two is the honest number.

Adding a colour means adding its pair here. Run from the repository root:
    python tools/contrast_check.py
Exit code is the number of problems, so it drops straight into a gate.
"""
import io
import json
import os
import sys

TEXT = 4.5
ICON = 3.0

# name, foreground token, background tokens, threshold
PAIRS = [
    ('primary button, live', 'on_action', ['accent_action'], TEXT),
    ('primary button, disabled', 'text_secondary', ['fill_strong'], TEXT),
    ('quiet button, live', 'text', ['surface_raised'], TEXT),
    ('foreground-session badge', 'on_action', ['accent_action'], TEXT),
    ('outgoing bubble body', 'text', ['bubble_mine'], TEXT),
    ('outgoing bubble second line', 'text_secondary', ['bubble_mine'], TEXT),
    ('body text on every layer', 'text',
     ['bg', 'surface', 'surface_subtle', 'surface_raised', 'surface_sunken',
      'accent_soft', 'accent_faint', 'warning_bg', 'error_bg', 'info_bg', 'bubble_mine'], TEXT),
    ('secondary text on every layer', 'text_secondary',
     ['bg', 'surface', 'surface_subtle', 'surface_raised', 'accent_soft', 'bubble_mine'], TEXT),
    ('tertiary text on every layer', 'text_tertiary',
     ['bg', 'surface', 'surface_subtle', 'surface_raised'], TEXT),
    ('quaternary text on every layer', 'text_quaternary',
     ['bg', 'surface', 'surface_subtle', 'surface_raised'], TEXT),
    ('accent text and markdown links', 'accent_text',
     ['bg', 'surface', 'surface_subtle', 'accent_soft', 'accent_faint', 'bubble_mine'], TEXT),
    ('action fill as a graphic', 'accent_action', ['bg', 'surface', 'surface_subtle'], ICON),
    ('status text (online / running / generating)', 'success',
     ['bg', 'surface', 'surface_subtle', 'surface_raised', 'accent_faint'], TEXT),
    ('control boundary (checkbox ring, quote rule)', 'border_strong',
     ['bg', 'surface', 'surface_raised'], ICON),
    ('warning text', 'warning_text', ['warning_bg', 'bg', 'surface'], TEXT),
    ('error text', 'error_text', ['error_bg', 'bg', 'surface'], TEXT),
    ('info text', 'info_text', ['info_bg', 'bg', 'surface'], TEXT),
    ('white text over the image scrim', 'text_inverse', ['scrim'], ICON),
]

MODES = {'light': 'base', 'dark': 'dark'}


def read_palette(root, folder):
    path = os.path.join(root, 'entry', 'src', 'main', 'resources', folder, 'element', 'color.json')
    with io.open(path, encoding='utf-8') as handle:
        entries = json.load(handle)['color']
    out = {}
    for entry in entries:
        name = entry['name']
        if name.startswith('app_'):
            name = name[4:]
        out[name] = entry['value'].upper()
    return out


def split(value):
    """'#RRGGBB' or '#AARRGGBB' -> (alpha 0..1, r, g, b)."""
    body = value[1:]
    if len(body) == 8:
        return int(body[0:2], 16) / 255.0, int(body[2:4], 16), int(body[4:6], 16), int(body[6:8], 16)
    return 1.0, int(body[0:2], 16), int(body[2:4], 16), int(body[4:6], 16)


def blend(top, bottom):
    """Source-over: `top` painted at its own alpha onto opaque `bottom`."""
    a, r, g, b = split(top)
    _, br, bg_, bb = split(bottom)
    return (a * r + (1 - a) * br, a * g + (1 - a) * bg_, a * b + (1 - a) * bb)


def luminance(rgb):
    def channel(v):
        s = v / 255.0
        return s / 12.92 if s <= 0.03928 else pow((s + 0.055) / 1.055, 2.4)
    r, g, b = rgb
    return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)


def contrast(one, two):
    first, second = luminance(one), luminance(two)
    hi, lo = max(first, second), min(first, second)
    return (hi + 0.05) / (lo + 0.05)


def to_hex(rgb):
    return '#%02X%02X%02X' % tuple(int(round(max(0.0, min(255.0, v)))) for v in rgb)


def backdrops(palette, token):
    """An alpha background is scored over each card it can sit on; a solid one once."""
    value = palette[token]
    if len(value[1:]) == 8:
        out = []
        for parent in ('surface', 'bg'):
            rgb = blend(value, palette[parent])
            out.append(('%s over %s' % (token, to_hex(rgb)), rgb, to_hex(rgb)))
        return out
    rgb = split(value)[1:]
    return [(token, rgb, value)]


def score(palette, fg, bg_tokens):
    worst = None
    for bg in bg_tokens:
        for label, rgb, hexvalue in backdrops(palette, bg):
            ratio = contrast(blend(palette[fg], hexvalue), rgb)
            if worst is None or ratio < worst[0]:
                worst = (ratio, '%s on %s' % (fg, label))
    return worst


def default_root():
    """The app sits under `QwenPawMobile/` in the private tree and at the root in the
    published one, so read the layout off the disk instead of asking for it."""
    app = os.path.join('entry', 'src', 'main', 'ets')
    return '.' if os.path.isdir(app) else 'QwenPawMobile'


def main():
    root = sys.argv[1] if len(sys.argv) > 1 else default_root()
    problems = 0
    for mode, folder in sorted(MODES.items()):
        palette = read_palette(root, folder)
        missing = sorted({tok for _, fg, bgs, _ in PAIRS for tok in [fg] + bgs if tok not in palette})
        for token in missing:
            print('%s: PAIRS names app_%s, which the palette does not define' % (mode, token))
            problems += 1
        if missing:
            continue
        print('\n== %s (page %s) ==' % (mode, palette['bg']))
        rows = []
        for name, fg, bgs, need in PAIRS:
            ratio, where = score(palette, fg, bgs)
            rows.append((ratio - need, ratio, need, name, where))
        for margin, ratio, need, name, where in sorted(rows):
            flag = 'ok  ' if margin >= 0 else 'FAIL'
            print('%s %5.2f (need %.1f)  %-46s %s' % (flag, ratio, need, name, where))
            if margin < 0:
                problems += 1
    print('\n%d problems' % problems)
    return problems


if __name__ == '__main__':
    sys.exit(main())
