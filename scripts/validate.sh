#!/usr/bin/env bash

set -euo pipefail

if ! command -v ruby >/dev/null 2>&1; then
  echo "Ruby is required for offline YAML parsing." >&2
  exit 1
fi

while IFS= read -r file; do
  ruby -e 'require "yaml"; YAML.load_stream(File.read(ARGV.fetch(0)))' "${file}"
done < <(find . -type f \( -name '*.yaml' -o -name '*.yml' \) \
  -not -path './charts/*/templates/*' \
  -not -path './.git/*' \
  -not -path './.idea/*' | sort)
echo "YAML syntax: passed"

ruby <<'RUBY'
require "yaml"

files = Dir.glob("**/*.{yaml,yml}").reject do |file|
  file.start_with?("charts/fl-nginx/templates/")
end

violations = files.flat_map do |file|
  YAML.load_stream(File.read(file)).filter_map do |document|
    next unless document.is_a?(Hash) && document["apiVersion"] && document["kind"]

    name = document.dig("metadata", "name")
    next if name.nil? || name.start_with?("fl-") || name == "argocd"

    "#{file}: #{document['kind']}/#{name} does not use the fl- prefix"
  end
end

abort violations.join("\n") unless violations.empty?
puts "Resource names: passed"
RUBY

bash -n scripts/bootstrap.sh scripts/validate.sh
echo "Shell syntax: passed"

if command -v helm >/dev/null 2>&1; then
  helm lint charts/fl-nginx --values charts/fl-nginx/values-demo.yaml
  helm template fl-helm-nginx charts/fl-nginx \
    --values charts/fl-nginx/values-demo.yaml \
    --set service.port=8080 \
    --set ingress.enabled=true \
    --set ingress.host=helm.fl.local >/dev/null
  echo "Helm render: passed"
else
  echo "Helm render: skipped (helm is not installed)"
fi

if command -v kustomize >/dev/null 2>&1; then
  for overlay in app-of-apps/overlays/{dev,prod}/{nginx,echo}; do
    kustomize build "${overlay}" >/dev/null
  done
  echo "Kustomize render: passed"
else
  echo "Kustomize render: skipped (kustomize is not installed)"
fi