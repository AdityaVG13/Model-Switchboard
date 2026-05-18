# Controller Fuzzing Fixtures

`Controller/tests/test_profile_fuzzing.py` replays these seed corpora, then expands them with deterministic random fuzz cases from seed `0x5EED2026`.

Covered boundaries:

- declarative `.env` profile parsing
- JSON profile normalization
- profile-derived URL validation
- dashboard JSON request parsing
- non-HTTP URL rejection before network calls

Run only this harness:

```sh
uv run python3 -m unittest Controller.tests.test_profile_fuzzing
```

The harness is deterministic and writes only to temporary directories. If a random case fails, the test output includes the seed and case number needed to reproduce it.
