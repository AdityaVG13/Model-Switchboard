# Controller API Conformance Coverage

Specification source: `Sources/ModelSwitchboardControllerCore/ControllerRouter.swift` and `Sources/ModelSwitchboardCore/ControllerClient.swift`.

| Section | MUST Clauses | SHOULD Clauses | Tested | Passing | Divergent | Score |
|---|---:|---:|---:|---:|---:|---:|
| Authentication | 2 | 0 | 2 | 2 | 0 | 100% |
| Benchmark API | 1 | 0 | 1 | 1 | 0 | 100% |
| Controller read API | 3 | 1 | 4 | 4 | 0 | 100% |
| Mutating action API | 4 | 1 | 5 | 5 | 0 | 100% |
| Request validation | 3 | 0 | 3 | 3 | 0 | 100% |

MUST coverage: 13/13. SHOULD coverage: 2/2.

The harness intentionally tests observable HTTP behavior only. Implementation details, log text, and private helper structure are out of scope.
