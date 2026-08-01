.PHONY: install dev run test lint format docker-build docker-run compose-up compose-down clean

PYTHON := python3
UV := uv
APP := hermes_local_web_extract.main:app
PORT := 8090

install:
	$(UV) pip install -r requirements.txt -e .

dev:
	$(UV) pip install -r requirements-dev.txt -e .

run:
	$(UV) run uvicorn $(APP) --host 0.0.0.0 --port $(PORT) --reload

test:
	$(UV) run pytest tests/ -v

lint:
	$(UV) run ruff check src/ tests/

format:
	$(UV) run ruff format src/ tests/

docker-build:
	docker build -t hermes-local-web-extract:latest .

docker-run:
	docker run --rm -p $(PORT):$(PORT) --env-file .env hermes-local-web-extract:latest

compose-up:
	docker compose up -d

compose-down:
	docker compose down

clean:
	find . -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true
	find . -type f -name "*.pyc" -delete 2>/dev/null || true
	rm -rf .pytest_cache .ruff_cache htmlcov .coverage dist build *.egg-info
