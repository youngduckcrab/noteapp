// Who may call recognizeMath (docs/plans/m5-7/07-sync.md 6.8.2 step 2, contract 7.3.2 F-1): a
// signed-in uid on the OWNER_UIDS list. The list is closed by default — empty → nobody.

/** OWNER_UIDS → uids: comma separated, each trimmed, empty entries dropped. */
export function parseOwnerUids(raw: string): string[] {
  return raw
    .split(",")
    .map((uid) => uid.trim())
    .filter((uid) => uid !== "");
}

/** Exact match (uids are case-sensitive); no wildcard. An empty [owners] lets nobody in. */
export function isOwner(uid: string, owners: readonly string[]): boolean {
  return uid !== "" && owners.includes(uid);
}
