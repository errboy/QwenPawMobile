/**
 * `JSON.parse(raw) as ChatSpec[]` asserts a shape, it does not check one. A 200
 * whose body is an object — a proxy's error page, a gateway answering for a dead
 * upstream — was then stored as a list, and the first `for..of` over it ended the
 * process. Every list this layer hands upward comes through here, so a store can
 * only ever hold a real array.
 */
import { Copy } from '../l10n/Copy';
import { Failure } from '../core/Failure';

export function expectList<T>(value: Object, what: string): T[] {
  if (!Array.isArray(value)) {
    throw Failure.parse(Copy.fill(Copy.notice_not_a_list, what));
  }
  return value as T[];
}
