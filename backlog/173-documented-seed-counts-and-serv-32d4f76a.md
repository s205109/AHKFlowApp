# 173 - Documented seed counts and service worker coverage are stale

## Metadata

- **Epic**: Development process
- **Type**: Process / documentation
- **Interfaces**: none (docs, one XML doc comment that reaches Swagger)
- **Difficulty**: moderate
- **Stage**: 3-plan

## Summary

Two documentation claims are wrong. The seed counts in `README.md` and in `DevController`'s XML
comment are stale, and the `DevController` one reaches the Swagger page. `testing-workflow.md`
lists service-worker behaviour as an E2E responsibility, which no local test can cover.

## User story

As a contributor, I want the documented counts and test responsibilities to match the code, so
that I do not derive an expected value from a stale document.

## Acceptance criteria

- [ ] `README.md` states the seed counts the catalogs actually produce, or states them as derived
      rather than fixed.
- [ ] `DevController`'s XML doc comment states the right hotkey count, so Swagger shows it.
- [ ] `docs/development/testing-workflow.md` says plainly that published service-worker caching
      is unreachable from a local run, and names what is reachable instead.

## Out of scope

- Making published service-worker caching testable. That needs a published build served from a
  non-local hostname, which is separate work.
- Changing the seed catalogs themselves.

## Notes / dependencies

- Found by the acceptance sweep on 2026-10-13, findings F8 and F9, both S4. Full evidence in
  `.superpowers/acceptance-sweep-2026-10-12/findings.md`, which is local and gitignored.
- **F8, the counts.** `README.md` says "12 hotstrings, 17 hotkeys, and 8 categories in one
  transaction". `DevController`'s XML comment says "Seeds 17 sample hotkeys for the authenticated
  user. Development only." The running endpoint returns
  `{"categoriesCount": 8, "hotstringsCount": 16, "hotkeysCount": 19}`. So hotstrings is 16, not
  12, and hotkeys is 19, not 17. Categories, 8, is right.
- AGENTS.md already requires deriving expected seed counts from the seed source rather than
  hard-coding them, so a document stating a number is the same trap one level up. Consider
  wording that cannot go stale.
- **F9, the service worker.** `docs/development/testing-workflow.md` lists service-worker and PWA
  behaviour as an E2E-mode responsibility. `wwwroot/js/registerServiceWorker.js` deliberately
  unregisters every service worker when the hostname is `localhost`, `127.0.0.1`, `::1` or
  `[::1]`, because workers destabilise Blazor and MSAL debugging. The real worker is
  `service-worker.published.js`, which only replaces the development no-op at publish time. So
  published caching is unreachable from an E2E run and from any local drive.
- What **is** reachable, and the sweep proved it correct: the local cleanup path unregisters the
  worker and reloads the page exactly once, guarded by a `sessionStorage` key, in all three
  states — a clean load, a controlled load, and a stale guard left set.
- This item could instead be closed inside a housekeeping round, which files no backlog item at
  all. It is filed so the finding is not lost; whoever picks it up may fold it into a round.
- Spec: none — documentation only.
- Plan: none — documentation only, so Execute can start from an inline plan at pickup.
