#!/usr/bin/env python3
import json
import os
import pathlib
import shlex
import subprocess
import sys

BASE = pathlib.Path(__file__).resolve().parent
PROFILE_DIR = BASE / "model-profiles"
SETTINGS_PATH = pathlib.Path.home() / ".factory" / "settings.json"
STATE_PATH = BASE / ".droid-managed-models.json"
REMOVED_STATE_PATH = BASE / ".droid-removed-models.json"


def load_env_profile(path: pathlib.Path) -> dict[str, str]:
    cmd = [
        "bash",
        "-lc",
        f"set -a; source {shlex.quote(str(path))}; env -0",
    ]
    data = subprocess.check_output(cmd)
    env = {}
    for item in data.decode().split("\0"):
        if not item or "=" not in item:
            continue
        k, v = item.split("=", 1)
        env[k] = v
    return env


def build_entry(env: dict[str, str]) -> dict:
    host = env.get("HOST", "127.0.0.1")
    base_url = f"http://{host}:{env['PORT']}/v1"
    extra_args = {}
    if env.get("DROID_TEMPERATURE"):
        extra_args["temperature"] = float(env["DROID_TEMPERATURE"])
    entry = {
        "displayName": env["DISPLAY_NAME"],
        "model": env["REQUEST_MODEL"],
        "baseUrl": base_url,
        "apiKey": "not-needed",
        "provider": "generic-chat-completion-api",
        "maxOutputTokens": int(env.get("DROID_MAX_OUTPUT_TOKENS", "8192")),
        "noImageSupport": True,
    }
    if extra_args:
        entry["extraArgs"] = extra_args
    return entry


def slug(display_name: str) -> str:
    allowed = []
    for ch in display_name:
        if ch.isalnum() or ch in ".+-_()$[] ":
            allowed.append(ch)
        else:
            allowed.append("-")
    return "-".join("".join(allowed).split())


def droid_id_for(env: dict[str, str]) -> str:
    return env.get("DROID_ID") or f"custom:{slug(env['DISPLAY_NAME'])}-0"


profiles = []
for path in sorted(PROFILE_DIR.glob("*.env")):
    env = load_env_profile(path)
    if env.get("SYNC_TO_DROID") != "1":
        continue
    profiles.append(env)

managed_names = {env["DISPLAY_NAME"] for env in profiles}
managed_ids = {droid_id_for(env) for env in profiles}

if SETTINGS_PATH.exists():
    data = json.loads(SETTINGS_PATH.read_text())
else:
    data = {}

if STATE_PATH.exists():
    previous_state = json.loads(STATE_PATH.read_text())
else:
    previous_state = {}

if REMOVED_STATE_PATH.exists():
    removed_state = json.loads(REMOVED_STATE_PATH.read_text())
else:
    removed_state = {}

previous_names = set(previous_state.get("names", []))
removed_names = set(removed_state.get("names", []))
removed_ids = set(removed_state.get("ids", []))
custom_models = data.get("customModels", [])

replace_names = set()
replace_name_to_entry = {}
for env in profiles:
    for name in env.get("REPLACES_DISPLAY_NAMES", "").split(","):
        name = name.strip()
        if name:
            replace_names.add(name)

filtered_custom_models = []
for model in custom_models:
    name = model.get("displayName")
    if name in removed_names or model.get("id") in removed_ids:
        continue
    if name in previous_names and name not in managed_names:
        continue
    if name in replace_names:
        replace_name_to_entry[name] = model
        continue
    filtered_custom_models.append(model)
custom_models = filtered_custom_models

index_by_name = {m.get("displayName"): i for i, m in enumerate(custom_models)}
max_index = max((int(m.get("index", -1)) for m in custom_models), default=-1)
summary = []
for env in profiles:
    entry = build_entry(env)
    name = entry["displayName"]
    desired_id = droid_id_for(env)
    if name in index_by_name:
        existing = custom_models[index_by_name[name]]
        entry["id"] = desired_id
        entry["index"] = existing.get("index", index_by_name[name])
        custom_models[index_by_name[name]] = entry
    else:
        replacement = None
        for old_name in env.get("REPLACES_DISPLAY_NAMES", "").split(","):
            old_name = old_name.strip()
            if old_name and old_name in replace_name_to_entry:
                replacement = replace_name_to_entry[old_name]
                break
        if replacement is not None:
            entry["id"] = desired_id
            entry["index"] = replacement.get("index", max_index + 1)
        else:
            max_index += 1
            entry["id"] = desired_id
            entry["index"] = max_index
        index_by_name[name] = len(custom_models)
        custom_models.append(entry)
    summary.append((name, entry["model"], entry["baseUrl"], entry["id"]))

data["customModels"] = custom_models
SETTINGS_PATH.parent.mkdir(parents=True, exist_ok=True)
SETTINGS_PATH.write_text(json.dumps(data, indent=2) + "\n")
STATE_PATH.write_text(
    json.dumps(
        {
            "names": sorted(managed_names),
            "ids": sorted(managed_ids),
        },
        indent=2,
    )
    + "\n"
)

print("displayName | model | baseUrl | droidId")
print("--- | --- | --- | ---")
for row in summary:
    print(" | ".join(row))
