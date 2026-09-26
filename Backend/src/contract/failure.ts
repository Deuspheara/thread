/** A bounded API failure category safe to return and log. */
export class DecisionFailure extends Error {
  constructor(readonly status: number, readonly category: string) { super(category); }
}
export function fail(status: number, category: string): never { throw new DecisionFailure(status, category); }
