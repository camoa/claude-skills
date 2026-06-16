# Behavioral Contract Verification

The second pass after existence verification: confirm the call produces what the caller assumes.

## Why existence is not enough

A method existing and resolving is zero evidence it behaves as assumed. The caller makes assumptions about every field it accesses, every type it coerces, every error mode it handles (or doesn't). Existence verification catches AI hallucinations of method names. Behavioral verification catches the larger category: wrong assumptions about what the method produces.

Cross-discipline grounding: consumer-driven contract testing (Pact), Design-by-Contract postconditions, OpenAPI response validation, and security taint analysis all share the same unifying principle — *demand a declared contract as the minimum evidence; treat anything without a verified contract as untrusted.*

---

## B1 — Code / Library Calls

Run after existence verification for every external call.

**Step 1.** Enumerate every assumption the CALLER makes about the return:
- Fields accessed on the return value (e.g., `$response->status`, `result['id']`)
- Assumed type of each field (string? int? object? array?)
- Presence assumption: required (always present) vs optional (may be absent)
- Value shape: non-empty? in a specific enum? within a numeric range?
- Null-checked? (`if ($result !== null)` before access — or not?)
- Error / exception modes: does the caller handle exceptions? wrap in try/catch? check return for error sentinel?
- Side effects the caller relies on (cache warm, DB write, email sent)

**Step 2.** Locate the declared contract, in priority order:
1. Type stub (`.d.ts` / `.pyi` / typeshed) — the strongest machine-verifiable contract
2. OpenAPI `responses` object for the endpoint + status code being consumed
3. Official method docs / SDK reference
4. `@returns` / `@throws` docblock in the source
5. Changelog or release notes as an observed-behavior proxy (weakest; note when used)

**Step 3.** Extract declared output:
- Required vs optional fields (use `?` / `nullable` / `Optional[T]` markers)
- Exact types for each field
- Documented exceptions and when they are thrown
- Documented error sentinels (returns `false`, `null`, empty array on failure)

**Step 4.** DIFF caller assumption vs declared contract — flag each miss:
- Field accessed but NOT declared → behavioral gap
- Field declared optional but accessed without null check → behavioral gap
- Type assumed as non-null but declared nullable → behavioral gap
- Error mode handled differently from what docs declare → behavioral gap
- Exception documented as thrown but no try/catch in caller → behavioral gap

**Step 5. Chained-object rule.** When a call returns an object, trace EVERY property and method the caller invokes on it and verify each against the contract. Do not stop at the first return type. Example: `$response->getBody()->getContents()` — verify `getBody()` return type, then verify `getContents()` on THAT type. Each link in the chain is a separate behavioral assumption.

**Step 6. Closed-source / no-contract fallback.**
- Mark: "postcondition unknown — behavioral contract unverified."
- Apply the **TAINT STANCE**: assume the return could be null, hostile, or malformed. Ask: does the code fail safely if the return is null? An empty array? An unexpected object? If no validation wrapper exists, the answer is usually no.
- Require a validation wrapper before the return is consumed.
- Flag the dependency as a **behavioral gap** if no wrapper exists.
- Use this label: `EXISTENCE VERIFIED / BEHAVIOR UNVERIFIED — taint stance applied`.

---

## B2 — Plugin / MCP / Hook / Skill References

Run in skill-mode (when the target is a skill, command, agent, or config file).

**Step 1.** Enumerate what the calling plugin assumes the capability PRODUCES:
- Output fields the calling step reads from the capability's response
- Types assumed for each field
- Success-vs-failure handling: does the calling step check whether the capability succeeded?
- Assumed side effects (file written, DB updated, message sent)

**Step 2.** Locate the capability's declared output contract, in priority order:
1. MCP tool `inputSchema` + declared output (read `.mcp.json` for the server + tool definition)
2. Referenced SKILL.md: check `description`, output format sections, declared return behavior
3. Agent `description` field in the agent definition file
4. Hook event payload schema (check `hooks.json` + any referenced hook documentation)

**Step 3.** Extract declared outputs from the contract source.

**Step 4.** DIFF caller assumption vs declaration (same checks as B1 step 4):
- Field consumed but not declared in capability output → behavioral gap
- Capability declared as potentially returning nothing (no match, empty) but calling step doesn't handle that case → behavioral gap
- Type mismatch between declared output and caller's assumed input type → behavioral gap

**Step 5. False-confidence check.**
- Does the calling step verify the capability PRODUCES the expected output, or only that the reference RESOLVES?
- A check like "skill exists in the plugin" is an existence gate, not a behavioral gate.
- Also check: cross-plugin skill resolution (is the skill installed?) and MCP server configuration existence (`.mcp.json` present with the server configured?).
- Flag any gate that checks availability only.

**Step 6. No-contract fallback.**
- Mark: "capability drift risk — behavioral conformance unverified."
- The capability could silently change its output format without the calling plugin knowing.
- Flag as a behavioral gap.
