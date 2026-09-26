import { fail } from './failure.js';

/** Reads JSON while rejecting duplicate keys, nulls, invalid UTF-8 and excessive nesting. */
export function strictJSON(data: Uint8Array): unknown {
  try {
    const text = new TextDecoder('utf-8', { fatal: true, ignoreBOM: true }).decode(data);
    let position = 0;
    const whitespace = () => { while (/[\x20\t\r\n]/.test(text[position] ?? '\0')) position++; };
    const string = (): string => {
      const start = position++;
      while (position < text.length) {
        const character = text[position++];
        if (character === '\\') position++;
        else if (character === '"') return JSON.parse(text.slice(start, position)) as string;
      }
      throw new Error('invalid');
    };
    const value = (depth: number): void => {
      if (depth > 16) throw new Error('depth');
      whitespace();
      const character = text[position];
      if (character === '"') { string(); return; }
      if (character === '{' || character === '[') {
        position++;
        const end = character === '{' ? '}' : ']';
        const keys = new Set<string>();
        whitespace();
        if (text[position] === end) { position++; return; }
        for (;;) {
          whitespace();
          if (character === '{') {
            if (text[position] !== '"') throw new Error('key');
            const key = string();
            if (keys.has(key)) throw new Error('duplicate');
            keys.add(key);
            whitespace();
            if (text[position++] !== ':') throw new Error('colon');
          }
          value(depth + 1);
          whitespace();
          const separator = text[position++];
          if (separator === end) return;
          if (separator !== ',') throw new Error('separator');
        }
      }
      const scalar = /^(?:true|false|-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?)/.exec(text.slice(position));
      if (!scalar) throw new Error('scalar');
      position += scalar[0].length;
    };
    value(0);
    whitespace();
    if (position !== text.length) throw new Error('trailing');
    return JSON.parse(text) as unknown;
  } catch { return fail(400, 'invalid_request'); }
}
