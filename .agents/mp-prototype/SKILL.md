---
name: mp-prototype
description: Use when a design question needs a throwaway prototype — sanity-check a state model, or explore UI options before committing.
---

<!--
AHKFlow adaptation of mattpocock/skills (MIT), pinned at commit 6acc160e4e0cd062dbbbd7a1b26ae92855edf07e.
Update policy: manual-selective-merge — do not bulk-sync with upstream.
-->

# Prototype

A prototype is **throwaway code that answers a question**. The question decides the shape.

## Pick a branch

Identify which question is being answered — from the user's prompt, the surrounding code, or by asking if the user is around:

- **"Does this logic / state model feel right?"** → [LOGIC.md](LOGIC.md). Build a single shareable HTML file — free-play buttons plus tabbed guided walkthroughs — that pushes the state machine through cases that are hard to reason about on paper, and that a non-developer can drive.
- **"What should this look like?"** → [UI.md](UI.md). Generate several radically different UI variations on a single route, switchable via a URL search param and a floating bottom bar.

The two branches produce very different artifacts — getting this wrong wastes the whole prototype. If the question is genuinely ambiguous and the user isn't reachable, default to whichever branch better matches the surrounding code (a backend module → logic; a page or component → UI) and state the assumption at the top of the prototype.

## Rules that apply to both

1. **Throwaway from day one, and clearly marked as such.** Locate the prototype code close to where it will actually be used (next to the module or page it's prototyping for) so context is obvious — but name it so a casual reader can see it's a prototype, not production. For throwaway UI routes, obey whatever routing convention the project already uses; don't invent a new top-level structure.
2. **Trivial to run.** A UI prototype starts from one command in the project's task runner — `pnpm <name>`, `python <path>`, `bun <path>`, etc. A logic demo is a single HTML file the user double-clicks. Either way, no thinking required to start it.
3. **No persistence by default.** State lives in memory. Persistence is the thing the prototype is _checking_, not something it should depend on. If the question explicitly involves a database, hit a scratch DB or a local file with a clear "PROTOTYPE — wipe me" name.
4. **Skip the polish.** No unit tests, no error handling beyond what makes the prototype _runnable_, no abstractions. The point is to learn something fast.

   In this repo, "no tests" does **not** mean "no verification". **Verification After Implementation** in `AGENTS.md` lists three exemptions — docs-only, internal-only, and pure refactor — and a prototype matches none of them. So before handing anything over:

   - **Always** build it and exercise it yourself. A prototype the user cannot run wastes their time instead of saving it. State that you ran it.
   - **UI prototype:** drive the variants in a browser with the `playwright-cli` skill and attach a screenshot of each. That is the row `AGENTS.md` sends visual and exploratory work to, and a UI prototype is exactly that.
   - **Logic prototype:** open the HTML file in a browser with the `playwright-cli` skill, click through the free-play buttons and each guided walkthrough, and attach a screenshot of the resulting state after each.

   What the prototype skips is the *durable* artifact. That arrives with the rewrite in rule 6, when the validated decision is folded into real code and picks up the E2E or integration test its surface calls for.
5. **Surface the state.** After every action (logic) or on every variant switch (UI), print or render the full relevant state so the user can see what changed.
6. **Capture it when done — capture first, fold second.** Order matters, because folding deletes things. Start by capturing the prototype itself as a **primary source**: commit the complete prototype to a throwaway branch, out of main, and leave a context pointer to that branch on the implementation issue. Capture the answer too — the verdict and the question it settled — in the issue or a commit. Only then fold the validated decision into the real code and clean up main. Folding in the other order destroys the losing variants before anything preserved them. The main branch keeps only the validated decision.
