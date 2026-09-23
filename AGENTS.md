# Repository instructions

## Contributor pull requests

- PRs from contributors other than `kristofferR` must include `AI models used: None`
  if no AI helped create or edit the contribution. Otherwise, list every
  model used to create or edit code, tests, or PR text by its most specific
  available name and version, for example `AI models used: GPT-6 Astra`.
- Include each model's reasoning level or effort when the tool exposes it, for
  example `Reasoning levels: GPT-6 Astra: high`. If unavailable, say
  `Reasoning levels: Unavailable (not exposed by tool)`. Never guess.
  Missing or unavailable reasoning levels do not block a PR.
- Routine automated review bots need not be listed. Put this disclosure in
  the PR description, never in commit authorship or co-author trailers.

## Development

- At the end of any turn that adds, edits, or deletes TypeScript files, run `bun run fmt` from the repository root after the final code edits and before committing or responding.
