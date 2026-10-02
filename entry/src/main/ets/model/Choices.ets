/**
 * One option in a composer selector, and one selector chip.
 *
 * The loop, model and approval pickers all reduce to the same shape: a short
 * label on the chip and a menu of options behind it. Keeping it in one type lets
 * the composer render three selectors without three copies of the same widget.
 */
export class Choice {
  id: string = '';
  label: string = '';
  /** Secondary text shown after the label, e.g. a loop mode's description. */
  hint: string = '';
  selected: boolean = false;
}

export class SelectorSpec {
  /** Which picker a tap belongs to: `loop`, `model` or `approval`. */
  key: string = '';
  /** Chip text: the current selection, not the picker's name. */
  title: string = '';
  /**
   * The chosen option's own identity, which can be the same text as the chip's.
   * ArkUI rebuilds a ForEach item only when its key changes, and a chip's menu is
   * built along with that item, so without this the checkmark stays parked on
   * whichever option was selected when the chip was first created.
   */
  selected: string = '';
  choices: Choice[] = [];
}

export class SelectorKey {
  static readonly LOOP: string = 'loop';
  static readonly MODEL: string = 'model';
  static readonly APPROVAL: string = 'approval';
}
