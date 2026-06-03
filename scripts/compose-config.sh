#!/usr/bin/env bash
set -euo pipefail

COMPOSE_BIN=${COMPOSE:-docker compose}
ENV_FILE=${ENV_FILE:-.env.example}
OUTPUT=${OUTPUT:-}

if [ ! -f "$ENV_FILE" ] && [ "$ENV_FILE" = ".env" ] && [ -f .env.example ]; then
  ENV_FILE=.env.example
fi

run_compose() {
  # shellcheck disable=SC2086 # COMPOSE_BIN intentionally supports "docker compose".
  $COMPOSE_BIN --env-file "$ENV_FILE" config
}

if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
  if [ -n "$OUTPUT" ]; then
    run_compose >"$OUTPUT"
  else
    run_compose
  fi
  exit 0
fi

ruby -ryaml -e '
  env_file = ENV.fetch("ENV_FILE", ".env.example")
  output = ENV["OUTPUT"]

  env = {}
  if File.file?(env_file)
    File.readlines(env_file, chomp: true).each do |line|
      next if line.strip.empty? || line.lstrip.start_with?("#")
      key, value = line.split("=", 2)
      next if key.nil? || value.nil?
      env[key.strip] = value.strip
    end
  end

  interpolate = lambda do |text|
    text.gsub(/\$\{([A-Za-z_][A-Za-z0-9_]*)(?:(:-|-)([^}]*))?\}/) do
      key = Regexp.last_match(1)
      op = Regexp.last_match(2)
      default = Regexp.last_match(3)
      value = ENV.key?(key) ? ENV[key] : env[key]

      if op == ":-"
        value.nil? || value.empty? ? default.to_s : value
      elsif op == "-"
        value.nil? ? default.to_s : value
      else
        value.to_s
      end
    end
  end

  raw = File.read("docker-compose.yml")
  rendered = interpolate.call(raw)
  config = YAML.safe_load(rendered, aliases: true)

  unless config.is_a?(Hash) && config["services"].is_a?(Hash) && !config["services"].empty?
    warn "docker-compose.yml must define at least one service"
    exit 1
  end

  required_services = %w[vllm guardrails]
  missing = required_services.reject { |service| config["services"].key?(service) }
  unless missing.empty?
    warn "docker-compose.yml is missing required services: #{missing.join(", ")}"
    exit 1
  end

  rendered_yaml = YAML.dump(config)
  if output && !output.empty?
    File.write(output, rendered_yaml)
  else
    puts rendered_yaml
  end
' 
