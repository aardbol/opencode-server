SHELL := /bin/bash

CHART := chart
IMAGE_TAG ?= opencode
KUBECONFORM_OPTS ?= -summary -strict -ignore-missing-schemas

.PHONY: helm-lint helm-template helm-unit-tests kube-linter kubeconform schema-update all

## schema-update: refresh the bundled opencode config schema and inline it into values.schema.json
schema-update:
	python3 scripts/update-config-schema.py

## helm-lint: validate chart structure and values against values.schema.json
helm-lint:
	helm lint $(CHART)

## helm-template: smoke-render the chart with example value files
helm-template:
	helm template $(IMAGE_TAG) $(CHART) -f $(CHART)/examples/values-ingress.yaml
	helm template $(IMAGE_TAG) $(CHART) -f $(CHART)/examples/values-persistence.yaml

## helm-unit-tests: run template unit tests, installing the helm-unittest plugin if absent
helm-unit-tests:
	@if ! helm plugin list 2>/dev/null | grep -q unittest; then \
		echo "helm-unittest plugin not installed; installing..."; \
		helm plugin install https://github.com/helm-unittest/helm-unittest; \
	fi
	helm unittest $(CHART)

## kube-linter: run static best-practice/security checks on the templates
kube-linter:
	kube-linter lint $(CHART) --config .kube-linter.yaml

## kubeconform: validate rendered manifests against Kubernetes API schemas
kubeconform:
	@tmp=$$(mktemp -d); \
	trap 'rm -rf $$tmp' EXIT; \
	helm template $(IMAGE_TAG) $(CHART) > "$$tmp/default.yaml"; \
	helm template $(IMAGE_TAG) $(CHART) -f $(CHART)/examples/values-ingress.yaml > "$$tmp/ingress.yaml"; \
	helm template $(IMAGE_TAG) $(CHART) -f $(CHART)/examples/values-persistence.yaml > "$$tmp/persistence.yaml"; \
	kubeconform $(KUBECONFORM_OPTS) "$$tmp"/*.yaml

## all: run the full local validation suite
all: helm-lint helm-template helm-unit-tests kube-linter kubeconform
