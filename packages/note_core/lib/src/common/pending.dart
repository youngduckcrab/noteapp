// Internal: the body of a 2nd-round contract member that is declared but not implemented
// yet (02-core 8.1 'B2 상태' — B2-α declares every public member, the named CORE task
// fills it in). The message always carries the task number.

/// Throws `UnimplementedError('CORE <task>: <member>')`.
Never notYet(String task, String member) =>
    throw UnimplementedError('CORE $task: $member');
