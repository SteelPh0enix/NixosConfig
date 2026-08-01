# Contributing

Thank you for your interest in contributing to hermes-local-web-extract.

## Ground rules

- Be respectful. See [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).
- This project prioritises security and privacy. Changes that weaken either require clear justification.
- Keep the base installation minimal. Optional features belong in extras or separate profiles.
- Do not add paid API dependencies, telemetry, or external tracking.

## How to contribute

### Reporting issues

Open a GitHub issue. For security vulnerabilities, read [SECURITY.md](SECURITY.md) first and report privately.

### Pull requests

1. Fork the repository and create a feature branch from `main`.
2. Install dev dependencies:
   ```bash
   uv pip install -r requirements-dev.txt -e .
   ```
3. Make your changes.
4. Run lint and tests:
   ```bash
   ruff check src/ tests/
   ruff format src/ tests/
   pytest tests/ -v
   ```
5. Ensure all 56 tests pass and no new lint errors are introduced.
6. Open a pull request. Describe what changed and why.

### Adding a new extractor

- Add a new module under `src/hermes_local_web_extract/extractors/`.
- Follow the `ExtractionResult` dataclass from `extractors/base.py`.
- Add it to the pipeline in `pipeline.py` with appropriate fallback logic.
- Write tests in `tests/test_html_extractors.py` or a new test file.
- Document it in `docs/architecture.md`.

### Adding a new API endpoint

- Add a router under `src/hermes_local_web_extract/routers/`.
- Register it in `main.py`.
- Add Pydantic models in `models.py`.
- Add tests.
- Document it in `docs/api-reference.md`.

## Code style

- Python 3.12+, type annotations on all public functions.
- Ruff for linting and formatting (`line-length = 100`).
- No comments that explain *what* the code does — only *why* when non-obvious.
- Small, focused functions.
- No global mutable state.

## Commit messages

Use clear, imperative present-tense subject lines. Example:
```
Add robots.txt best-effort checking
```

## Licence

By submitting a pull request you agree that your contribution will be licensed under the Apache-2.0 licence.
