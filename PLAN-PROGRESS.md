# 178 progress

- [x] Task 1: a refusal before the undo changes nothing
  - Mutation 1, read moved below the undo: `FAIL: A refused Ship failure must leave the pull request ready`
  - Mutation 2, pre-flight moved below the undo: `FAIL: A Ship failure whose push is refused must leave the pull request ready`
- [x] Task 2: the progress file comes from this item's own closure
  - Mutation 1, old newest-deletion search: `FAIL: The progress file must not hold another item's lines, with another item's closure in history`
  - Mutation 2, lookup always starts a new file: `FAIL: A Ship failure must restore the progress file Ship deleted`
  - Mutation 3, lookup moved below the undo: `FAIL: A refused Ship failure must leave the pull request ready`
- [x] Local review round 1: 9 findings, 4 fixed in d915e3ed (byte-exact restore, one divergence check, undo refusal text, one hook helper), 5 pushed back
