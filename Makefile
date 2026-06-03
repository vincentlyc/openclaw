COMPOSE ?= docker compose
ENV_FILE ?= .env

.PHONY: init install-docker deploy up down logs ps health chat demo compose-config test

init:
	@test -f $(ENV_FILE) || cp .env.example $(ENV_FILE)
	@echo "Created $(ENV_FILE). Edit it before starting the stack."

install-docker:
	./scripts/install-docker-ubuntu.sh

deploy:
	COMPOSE="$(COMPOSE)" ENV_FILE="$(ENV_FILE)" ./scripts/deploy.sh

up:
	$(COMPOSE) --env-file $(ENV_FILE) up -d --build

down:
	$(COMPOSE) --env-file $(ENV_FILE) down

logs:
	$(COMPOSE) --env-file $(ENV_FILE) logs -f --tail=200

ps:
	$(COMPOSE) --env-file $(ENV_FILE) ps

health:
	./scripts/healthcheck.sh

compose-config:
	ENV_FILE="$(ENV_FILE)" ./scripts/compose-config.sh >/tmp/openclaw-compose.yml

chat:
	curl -sS http://localhost:$${GUARDRAILS_PORT:-8001}/v1/chat/completions \
	  -H 'Content-Type: application/json' \
	  -d '{"model":"local-nemotron","messages":[{"role":"user","content":"用繁體中文簡短介紹你自己。"}],"guardrails":{"config_id":"nemoclaw"}}' | python3 -m json.tool

demo:
	./scripts/demo.sh

test: compose-config
	ruby -e 'require "yaml"; Dir["configs/*/config.yml"].each { |path| YAML.load_file(path); puts "validated #{path}" }'
