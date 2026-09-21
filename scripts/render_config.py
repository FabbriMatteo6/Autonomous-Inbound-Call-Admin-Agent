#!/usr/bin/env python3
"""
Render the ElevenLabs agent config, system prompt, and FAQ from a single
business profile. This is the white-label onboarding entry point:

    1. Edit  config/business-profile.yaml
    2. Run   python3 scripts/render_config.py
    3. Re-upload the regenerated files in elevenlabs/ to your ElevenLabs agent.

Dependency-free: uses PyYAML if installed, otherwise a small built-in loader
that supports the subset of YAML used by business-profile.yaml.
"""
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROFILE = os.path.join(ROOT, "config", "business-profile.yaml")
TEMPLATES = os.path.join(ROOT, "config", "templates")
OUT = os.path.join(ROOT, "elevenlabs")

RENDER_MAP = [
    ("agent-config.json.tmpl", "agent-config.json", True),   # validate as JSON
    ("agent-prompt.md.tmpl", "agent-prompt.md", False),
    ("business-faq.md.tmpl", "business-faq-template.md", False),
]


# --------------------------------------------------------------------------- #
# Minimal YAML loader (fallback when PyYAML is not installed)
# --------------------------------------------------------------------------- #
def _scalar(v):
    v = v.strip()
    if (v.startswith('"') and v.endswith('"')) or (v.startswith("'") and v.endswith("'")):
        return v[1:-1]
    if re.fullmatch(r"-?\d+", v):
        return int(v)
    if re.fullmatch(r"-?\d+\.\d+", v):
        return float(v)
    if v.lower() in ("true", "false"):
        return v.lower() == "true"
    return v


def _mini_yaml(text):
    lines = []
    for raw in text.splitlines():
        if not raw.strip() or raw.lstrip().startswith("#"):
            continue
        indent = len(raw) - len(raw.lstrip(" "))
        lines.append((indent, raw.strip()))
    pos = [0]

    def block(indent):
        if lines[pos[0]][1].startswith("- "):
            out = []
            while pos[0] < len(lines) and lines[pos[0]][0] == indent and lines[pos[0]][1].startswith("- "):
                out.append(_scalar(lines[pos[0]][1][2:]))
                pos[0] += 1
            return out
        out = {}
        while pos[0] < len(lines) and lines[pos[0]][0] == indent and not lines[pos[0]][1].startswith("- "):
            key, _, val = lines[pos[0]][1].partition(":")
            key, val = key.strip(), val.strip()
            pos[0] += 1
            if val == "":
                if pos[0] < len(lines) and lines[pos[0]][0] > indent:
                    out[key] = block(lines[pos[0]][0])
                else:
                    out[key] = None
            else:
                out[key] = _scalar(val)
        return out

    return block(lines[0][0])


def load_profile(path):
    with open(path, encoding="utf-8") as f:
        text = f.read()
    try:
        import yaml  # type: ignore
        return yaml.safe_load(text)
    except ImportError:
        return _mini_yaml(text)


# --------------------------------------------------------------------------- #
# Flatten to dotted keys + derived values
# --------------------------------------------------------------------------- #
def flatten(data, prefix=""):
    out = {}
    for k, v in data.items():
        key = f"{prefix}{k}"
        if isinstance(v, dict):
            out.update(flatten(v, key + "."))
        elif isinstance(v, list):
            out[key] = ", ".join(str(x) for x in v)
        else:
            out[key] = "" if v is None else str(v)
    return out


def build_context(profile):
    ctx = flatten(profile)
    hours = profile.get("hours", []) or []
    methods = (profile.get("payment", {}) or {}).get("methods", []) or []
    slots = (profile.get("scheduling", {}) or {}).get("slots", []) or []
    ctx["derived.hours_bullets"] = "\n".join(f"- {h}" for h in hours)
    ctx["derived.payment_bullets"] = "\n".join(f"- {m}" for m in methods)
    ctx["derived.slots_spoken"] = ", ".join(slots)
    return ctx


def sync_env(profile, ctx):
    """Set-or-update the business/scheduling keys in .env from the profile.
    Only the known keys are touched; every other line is preserved. Values are
    written unquoted (docker-compose reads them verbatim)."""
    env_path = os.path.join(ROOT, ".env")
    if not os.path.exists(env_path):
        print("  (skipped .env sync: .env not found — run setup.sh first)")
        return
    slots = (profile.get("scheduling", {}) or {}).get("slots", []) or []
    updates = {
        "BUSINESS_NAME": ctx.get("business.name", ""),
        "BUSINESS_TIMEZONE": ctx.get("business.timezone", ""),
        "GENERIC_TIMEZONE": ctx.get("business.timezone", ""),
        "APPOINTMENT_SLOTS": ",".join(slots),
        "BUSINESS_HOURS_START": ctx.get("scheduling.business_hours_start", ""),
        "BUSINESS_HOURS_END": ctx.get("scheduling.business_hours_end", ""),
    }
    lines = open(env_path, encoding="utf-8").read().splitlines()
    seen = set()
    for i, line in enumerate(lines):
        m = re.match(r"^([A-Z0-9_]+)=", line)
        if m and m.group(1) in updates:
            key = m.group(1)
            lines[i] = f"{key}={updates[key]}"
            seen.add(key)
    for key, val in updates.items():
        if key not in seen:
            lines.append(f"{key}={val}")
    open(env_path, "w", encoding="utf-8").write("\n".join(lines) + "\n")
    print(f"  synced .env keys: {', '.join(updates)}")


def render(template_text, ctx):
    missing = []

    def sub(m):
        key = m.group(1).strip()
        if key not in ctx:
            missing.append(key)
            return m.group(0)
        return ctx[key]

    result = re.sub(r"\$\{([^}]+)\}", sub, template_text)
    return result, missing


def main():
    if not os.path.exists(PROFILE):
        sys.exit(f"ERROR: profile not found: {PROFILE}")
    profile = load_profile(PROFILE)
    ctx = build_context(profile)

    errors = []
    for tmpl_name, out_name, is_json in RENDER_MAP:
        tmpl_path = os.path.join(TEMPLATES, tmpl_name)
        out_path = os.path.join(OUT, out_name)
        with open(tmpl_path, encoding="utf-8") as f:
            rendered, missing = render(f.read(), ctx)
        if missing:
            errors.append(f"{tmpl_name}: unknown placeholders {sorted(set(missing))}")
            continue
        if is_json:
            try:
                json.loads(rendered)
            except json.JSONDecodeError as e:
                errors.append(f"{out_name}: invalid JSON after render: {e}")
                continue
        with open(out_path, "w", encoding="utf-8") as f:
            f.write(rendered)
        print(f"  rendered  elevenlabs/{out_name}")

    if errors:
        print("\nRENDER FAILED:")
        for e in errors:
            print("  - " + e)
        sys.exit(1)

    sync_env(profile, ctx)

    print(f"\nDone. Business: {ctx.get('business.name')} | persona: {ctx.get('business.persona_name')}")
    print("Next:")
    print("  1. docker compose up -d --force-recreate   # load new scheduling env into n8n")
    print("  2. re-upload elevenlabs/agent-prompt.md, agent-config.json, business-faq-template.md to ElevenLabs")


if __name__ == "__main__":
    main()
