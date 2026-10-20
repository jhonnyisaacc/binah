#!/usr/bin/env python3
"""Release checks for an Expo app. The app directory is the EAS upload root."""

import argparse
import fnmatch
import json
import re
import sys
from pathlib import Path

LOOPBACK = ("localhost", "127.0.0.1", "0.0.0.0", "10.0.2.2")
URL_RE = re.compile(r"https?://[^\s'\"`]+")
IMPORT_RE = re.compile(
    r"""(?:from|import|require)\s*\(?\s*['"]([^'"]+)['"]"""
)


def read_text(path: Path) -> str:
    if not path.is_file():
        return ""
    return path.read_text()


def loopback(url: str) -> bool:
    host = re.sub(r"^https?://", "", url).split("/")[0].split(":")[0]
    return host in LOOPBACK


def check_api_url(app: Path) -> list[str]:
    names = ("app.json", "app.config.js", "app.config.ts", "app.config.mjs")
    text = "\n".join(read_text(app / name) for name in names)
    if "EXPO_PUBLIC_API_URL" not in text and "apiUrl" not in text:
        return []
    urls = URL_RE.findall(text)
    if any(not loopback(url) for url in urls):
        return []
    return [
        "release config needs a non-loopback fallback for EXPO_PUBLIC_API_URL"
    ]


def ignore_patterns(text: str) -> list[str]:
    patterns = []
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        patterns.append(line)
    return patterns


def ignored(path: str, patterns: list[str]) -> bool:
    result = False
    for pat in patterns:
        neg = pat.startswith("!")
        body = pat[1:] if neg else pat
        body = body.lstrip("/")
        directory = body.endswith("/")
        body = body.rstrip("/")
        if directory:
            hit = path == body or path.startswith(body + "/")
        elif "*" in body or "?" in body:
            name = path.rsplit("/", 1)[-1]
            hit = fnmatch.fnmatch(path, body) or fnmatch.fnmatch(name, body)
        else:
            hit = path == body or path.startswith(body + "/")
        if hit:
            result = not neg
    return result


def source_files(app: Path) -> list[Path]:
    found = []
    for path in app.rglob("*"):
        if not path.is_file():
            continue
        if any(part in {"node_modules", ".git", "dist"} for part in path.parts):
            continue
        if path.suffix in {".js", ".jsx", ".ts", ".tsx", ".mjs", ".cjs"}:
            found.append(path)
    return found


def check_easignore(app: Path) -> list[str]:
    ignore_file = app / ".easignore"
    if not ignore_file.is_file():
        return []
    patterns = ignore_patterns(ignore_file.read_text())
    errors = []
    for source in source_files(app):
        for spec in IMPORT_RE.findall(source.read_text()):
            if spec.startswith("."):
                target = (source.parent / spec).resolve()
            elif (app / spec.split("/", 1)[0]).exists():
                target = (app / spec).resolve()
            else:
                continue
            try:
                rel = target.relative_to(app.resolve()).as_posix()
            except ValueError:
                errors.append(f"{source.name} imports {spec}, which is outside the EAS upload")
                continue
            if ignored(rel, patterns):
                errors.append(f".easignore drops {rel}, imported from {source.relative_to(app)}")
    return errors


def auto_publish(text: str) -> bool:
    if not re.search(r"\beas (build|submit)\b", text):
        return False
    push = re.search(r"(?m)^\s*push:\s*$", text) or re.search(r"\bon:\s*\[[^\]]*push", text)
    dispatch = "workflow_dispatch" in text
    release = re.search(r"(?m)^\s*release:\s*$", text)
    return bool(push or dispatch or release)


def check_platform(repo: Path) -> list[str]:
    errors = []
    workflow_dir = repo / ".github" / "workflows"
    if not workflow_dir.is_dir():
        return []
    for path in sorted(workflow_dir.glob("*.yml")) + sorted(workflow_dir.glob("*.yaml")):
        text = path.read_text()
        if not auto_publish(text):
            continue
        for line in text.splitlines():
            if "eas update" in line:
                continue
            if "eas build" not in line and "eas submit" not in line:
                continue
            match = re.search(r"--platform(?:=|\s+)(\S+)", line)
            if not match:
                errors.append(f"{path.name}: eas build needs --platform android")
                continue
            token = match.group(1).strip("\"'")
            if token == "android":
                continue
            errors.append(f"{path.name}: auto-publish platform is {token}, expected android")
    return errors


def check_versions(app: Path) -> list[str]:
    errors = []
    app_json = app / "app.json"
    if not app_json.is_file():
        return ["app.json is missing, so expo.version cannot be checked"]
    try:
        data = json.loads(app_json.read_text())
    except json.JSONDecodeError as exc:
        return [f"app.json is not valid JSON ({exc.msg})"]
    version = data.get("expo", {}).get("version", "")
    if not re.fullmatch(r"\d+\.\d+\.\d+", version or ""):
        errors.append("expo.version in app.json is manual and must be x.y.z")
    eas_path = app / "eas.json"
    if not eas_path.is_file():
        errors.append("eas.json is missing")
        return errors
    try:
        eas = json.loads(eas_path.read_text())
    except json.JSONDecodeError as exc:
        errors.append(f"eas.json is not valid JSON ({exc.msg})")
        return errors
    production = eas.get("build", {}).get("production", {})
    if production.get("autoIncrement") is not True:
        errors.append(
            "build.production.autoIncrement must be true. EAS then owns android.versionCode and ios.buildNumber"
        )
    return errors


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--app", required=True, type=Path)
    parser.add_argument("--repo", type=Path)
    args = parser.parse_args()
    app = args.app.resolve()
    repo = args.repo.resolve() if args.repo else app
    errors = []
    errors.extend(check_api_url(app))
    errors.extend(check_easignore(app))
    errors.extend(check_platform(repo))
    errors.extend(check_versions(app))
    for error in errors:
        print(error, file=sys.stderr)
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
