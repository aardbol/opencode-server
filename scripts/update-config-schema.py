#!/usr/bin/env python3
"""Inline the opencode config schema into chart/values.schema.json.

Downloads https://opencode.ai/config.json, strips the remote models.dev `$ref`s
(so custom models still validate), and embeds the resulting `$defs` into
chart/values.schema.json so Helm can validate `config.content` at install time.

Helm's validator registers values.schema.json at "file:///values.schema.json"
(filesystem root), so a relative `$ref` to a sibling schema file can never
resolve — the schema must be inlined.

Usage: scripts/update-config-schema.py [--offline]
  --offline   reuse the last fetched schema from the cache instead of re-downloading.
"""
import argparse
import json
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CHART = ROOT / "chart"
VALUES_SCHEMA = CHART / "values.schema.json"
CACHE = ROOT / ".cache" / "config-schema.json"

UPSTREAM = "https://opencode.ai/config.json"
MODEL_REF = "https://models.dev/model-schema.json#/$defs/Model"
VALUES_SCHEMA_VERSION = "https://json-schema.org/draft/2020-12/schema"


def strip_remote_model_refs(node: dict) -> None:
    """Remove the external models.dev `$ref`s (siblings keep `"type": "string"`).

    The upstream schema restricts `model`/`small_model`/`agent.model` to an enum
    of known model ids. Bundling that enum would reject valid custom or
    self-hosted models, so the ref is dropped and the string type is kept.
    """
    if isinstance(node, dict):
        for key, value in list(node.items()):
            if key == "$ref" and value == MODEL_REF:
                del node[key]
            else:
                strip_remote_model_refs(value)
    elif isinstance(node, list):
        for item in node:
            strip_remote_model_refs(item)


def fetch_schema(offline: bool) -> dict:
    if offline:
        print(f"Using cached schema from {CACHE.relative_to(ROOT)}")
        return json.loads(CACHE.read_text())
    print(f"Fetching {UPSTREAM}")
    req = urllib.request.Request(
        UPSTREAM,
        headers={"User-Agent": "opencode-helm-chart/1.0 schema-update"},
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        schema = json.load(resp)
    strip_remote_model_refs(schema)
    CACHE.parent.mkdir(parents=True, exist_ok=True)
    with CACHE.open("w") as f:
        json.dump(schema, f, indent=2)
        f.write("\n")
    print(f"Cached schema to {CACHE.relative_to(ROOT)}")
    return schema


def inline_into_values_schema(config_schema: dict) -> None:
    values_schema = json.loads(VALUES_SCHEMA.read_text())

    values_schema["$schema"] = VALUES_SCHEMA_VERSION
    values_schema["$defs"] = config_schema["$defs"]
    content = values_schema["properties"]["config"]["properties"]["content"]
    content["$ref"] = "#/$defs/Config"

    with VALUES_SCHEMA.open("w") as f:
        json.dump(values_schema, f, indent=2)
        f.write("\n")
    print(f"Wrote {VALUES_SCHEMA.relative_to(ROOT)}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--offline", action="store_true")
    args = parser.parse_args()
    try:
        inline_into_values_schema(fetch_schema(args.offline))
    except Exception as exc:  # noqa: BLE001 - report and exit cleanly
        print(f"error: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
