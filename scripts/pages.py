#!/usr/bin/env python3
"""Generates the GitHub Pages site that installs Ad Hoc builds over the air (standard library only).

Commands:
  build   Writes manifest.plist, build.json and index.html into a build folder that already contains the IPA
          and the 57 px / 512 px icons.
  index   Prunes old branch builds, re-renders every build page from its build.json and writes the home page.
"""

import argparse
import datetime
import html
import json
import pathlib
import plistlib
import re
import shutil
import urllib.parse

IPA_NAME = "Itinerary.ipa"
ICON_SMALL = "icon-57.png"
ICON_LARGE = "icon-512.png"

STYLE = """
:root { color-scheme: light dark; --bg: #f2f2f7; --card: #ffffff; --text: #1c1c1e; --muted: #6e6e73;
        --accent: #4f46e5; --accent-text: #ffffff; --stable: #15803d; --branch: #b45309; --border: #d1d1d6; }
@media (prefers-color-scheme: dark) {
  :root { --bg: #000000; --card: #1c1c1e; --text: #f2f2f7; --muted: #98989d; --accent: #818cf8;
          --accent-text: #0b0b0f; --stable: #4ade80; --branch: #fbbf24; --border: #38383a; }
}
* { box-sizing: border-box; }
body { margin: 0; background: var(--bg); color: var(--text);
       font: 16px/1.45 -apple-system, BlinkMacSystemFont, "SF Pro Text", "Segoe UI", Roboto, sans-serif; }
main { max-width: 680px; margin: 0 auto; padding: 32px 16px 48px; }
header { display: flex; align-items: center; gap: 16px; margin-bottom: 24px; }
.icon { width: 72px; height: 72px; border-radius: 16px; box-shadow: 0 4px 14px rgba(0, 0, 0, .18); }
.icon.large { width: 120px; height: 120px; border-radius: 27px; }
h1 { font-size: 26px; margin: 0; }
h2 { font-size: 15px; text-transform: uppercase; letter-spacing: .04em; color: var(--muted); margin: 32px 0 8px; }
p { margin: 6px 0; }
.muted { color: var(--muted); }
.card { background: var(--card); border-radius: 14px; padding: 16px; margin: 10px 0; border: 1px solid var(--border); }
.button { display: inline-block; background: var(--accent); color: var(--accent-text); text-decoration: none;
          font-weight: 600; padding: 12px 22px; border-radius: 12px; }
.button.small { padding: 8px 14px; font-size: 14px; border-radius: 10px; }
.button.wide { display: block; text-align: center; font-size: 18px; padding: 15px; }
.badge { display: inline-block; font-size: 12px; font-weight: 600; padding: 2px 8px; border-radius: 999px;
         border: 1px solid currentColor; vertical-align: middle; }
.badge.stable { color: var(--stable); }
.badge.branch { color: var(--branch); }
.title { font-weight: 600; margin: 6px 0; overflow-wrap: anywhere; }
.row { display: flex; align-items: center; justify-content: space-between; gap: 12px; flex-wrap: wrap; }
.meta { font-size: 13px; color: var(--muted); overflow-wrap: anywhere; }
dl { display: grid; grid-template-columns: max-content 1fr; gap: 6px 14px; margin: 0; font-size: 14px; }
dt { color: var(--muted); }
dd { margin: 0; overflow-wrap: anywhere; }
a { color: var(--accent); }
.center { text-align: center; }
"""


def escape(value):
    return html.escape(str(value), quote=True)


def page(title, body):
    return f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex">
<title>{escape(title)}</title>
<style>{STYLE}</style>
</head>
<body>
<main>
{body}
</main>
</body>
</html>
"""


def badge(channel):
    if channel == "stable":
        return '<span class="badge stable">Stable</span>'
    return '<span class="badge branch">Branch build</span>'


def format_date(value):
    try:
        parsed = datetime.datetime.fromisoformat(value.replace("Z", "+00:00"))
    except (AttributeError, ValueError):
        return value or ""
    return parsed.strftime("%Y-%m-%d %H:%M UTC")


def render_build_page(folder, data):
    commit_url = f"https://github.com/{data['repository']}/commit/{data['commit_sha']}" if data.get("repository") else ""
    commit = (f'<a href="{escape(commit_url)}">{escape(data["commit_sha"][:7])}</a>'
              if commit_url else escape(data["commit_sha"][:7]))
    run = f'<dt>Workflow run</dt><dd><a href="{escape(data["run_url"])}">#{escape(data["build_number"])}</a></dd>' \
        if data.get("run_url") else ""
    devices = f'<dt>Devices</dt><dd>{escape(data["devices"])}</dd>' if data.get("devices") not in (None, "") else ""
    body = f"""
<div class="center">
  <img class="icon large" src="{ICON_LARGE}" alt="">
  <h1 style="margin-top:16px">{escape(data['app_name'])}</h1>
  <p class="muted">{escape(data['version'])} ({escape(data['build_number'])}) {badge(data['channel'])}</p>
  <p class="title">{escape(data['commit_title'])}</p>
  <p style="margin:24px 0"><a class="button wide" href="{escape(data['install_url'])}">Install on iPhone</a></p>
  <p class="meta">Open this page in Safari on an iPhone whose UDID is registered in the Apple Developer account.</p>
</div>
<div class="card">
  <dl>
    <dt>Tag</dt><dd>{escape(data['tag'])}</dd>
    <dt>Branch</dt><dd>{escape(data['branch'])}</dd>
    <dt>Commit</dt><dd>{commit}</dd>
    <dt>Built</dt><dd>{escape(format_date(data.get('created_at')))}</dd>
    {devices}
    {run}
    <dt>Bundle ID</dt><dd>{escape(data['bundle_id'])}</dd>
  </dl>
</div>
<p class="center"><a href="../">All builds</a></p>
"""
    (folder / "index.html").write_text(page(f"{data['app_name']} {data['tag']}", body), encoding="utf-8")


def command_build(args):
    folder = pathlib.Path(args.dir)
    base_url = args.base_url if args.base_url.endswith("/") else args.base_url + "/"
    folder_url = base_url + urllib.parse.quote(args.tag) + "/"
    manifest_url = folder_url + "manifest.plist"
    data = {
        "tag": args.tag,
        "channel": args.channel,
        "app_name": args.app_name,
        "bundle_id": args.bundle_id,
        "version": args.version,
        "build_number": int(args.build_number),
        "commit_title": args.commit_title,
        "commit_sha": args.commit_sha,
        "branch": args.branch,
        "repository": args.repository,
        "run_url": args.run_url,
        "devices": args.devices,
        "created_at": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "page_url": folder_url,
        "ipa_url": folder_url + IPA_NAME,
        "manifest_url": manifest_url,
        "install_url": "itms-services://?action=download-manifest&url=" + urllib.parse.quote(manifest_url, safe=""),
    }
    manifest = {
        "items": [{
            "assets": [
                {"kind": "software-package", "url": data["ipa_url"]},
                {"kind": "display-image", "url": folder_url + ICON_SMALL},
                {"kind": "full-size-image", "url": folder_url + ICON_LARGE},
            ],
            "metadata": {
                "bundle-identifier": args.bundle_id,
                "bundle-version": args.version,
                "kind": "software",
                "title": args.app_name,
            },
        }]
    }
    for required in (IPA_NAME, ICON_SMALL, ICON_LARGE):
        if not (folder / required).exists():
            raise SystemExit(f"{folder / required} is missing")
    (folder / "manifest.plist").write_bytes(plistlib.dumps(manifest))
    (folder / "build.json").write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    render_build_page(folder, data)
    print(f"Build page ready: {folder_url}")


def stable_order(data):
    match = re.fullmatch(r"(\d+)\.(\d+)\.(\d+)", data.get("tag", ""))
    numbers = tuple(int(part) for part in match.groups()) if match else (0, 0, 0)
    return numbers, data.get("created_at", "")


def build_card(data):
    return f"""
<div class="card">
  <div class="row">
    <div><strong>{escape(data['tag'])}</strong> {badge(data['channel'])}</div>
    <a class="button small" href="{escape(data['install_url'])}">Install</a>
  </div>
  <p class="title">{escape(data['commit_title'])}</p>
  <p class="meta">{escape(data['version'])} ({escape(data['build_number'])}) · {escape(data['branch'])} ·
    {escape(format_date(data.get('created_at')))} · <a href="{escape(urllib.parse.quote(data['tag']))}/">Details</a></p>
</div>"""


def command_index(args):
    site = pathlib.Path(args.site)
    builds = []
    for build_file in sorted(site.glob("*/build.json")):
        try:
            data = json.loads(build_file.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            continue
        data["_folder"] = build_file.parent
        builds.append(data)

    stable = sorted((b for b in builds if b.get("channel") == "stable"), key=stable_order, reverse=True)
    branch = sorted(
        (b for b in builds if b.get("channel") != "stable"),
        key=lambda b: (int(b.get("build_number", 0)), b.get("created_at", "")),
        reverse=True,
    )
    for removed in branch[args.max_branch_builds:]:
        print(f"Removing old branch build {removed['tag']}")
        shutil.rmtree(removed["_folder"])
    branch = branch[:args.max_branch_builds]

    for data in stable + branch:
        render_build_page(data["_folder"], data)

    if stable:
        latest = stable[0]
        hero = f"""
<div class="card">
  <p class="muted">Latest stable version</p>
  <p><strong>{escape(latest['version'])}</strong> {badge('stable')}</p>
  <p class="title">{escape(latest['commit_title'])}</p>
  <p style="margin-top:14px"><a class="button wide" href="{escape(latest['install_url'])}">Install latest stable ({escape(latest['version'])})</a></p>
</div>"""
    else:
        hero = '<div class="card"><p class="muted">There is no stable version yet. Builds from <code>main</code> appear here.</p></div>'

    stable_html = "".join(build_card(b) for b in stable) or '<p class="muted">None yet.</p>'
    branch_html = "".join(build_card(b) for b in branch) or '<p class="muted">None yet.</p>'
    newest = stable + branch
    icon = (f'<img class="icon" src="{escape(urllib.parse.quote(newest[0]["tag"]))}/{ICON_LARGE}" alt="">'
            if newest else "")
    body = f"""
<header>
  {icon}
  <div>
    <h1>{escape(args.app_name)}</h1>
    <p class="muted">Ad Hoc builds. Open this page in Safari on a registered iPhone.</p>
  </div>
</header>
{hero}
<h2>Stable versions</h2>
{stable_html}
<h2>Branch builds (last {args.max_branch_builds})</h2>
{branch_html}
"""
    (site / "index.html").write_text(page(args.app_name, body), encoding="utf-8")
    print(f"Home page lists {len(stable)} stable and {len(branch)} branch build(s).")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = parser.add_subparsers(dest="command", required=True)

    build = commands.add_parser("build")
    build.add_argument("--dir", required=True)
    build.add_argument("--base-url", required=True)
    build.add_argument("--tag", required=True)
    build.add_argument("--channel", choices=["stable", "branch"], required=True)
    build.add_argument("--app-name", required=True)
    build.add_argument("--bundle-id", required=True)
    build.add_argument("--version", required=True)
    build.add_argument("--build-number", required=True)
    build.add_argument("--commit-title", required=True)
    build.add_argument("--commit-sha", required=True)
    build.add_argument("--branch", required=True)
    build.add_argument("--repository", default="")
    build.add_argument("--run-url", default="")
    build.add_argument("--devices", default="")
    build.set_defaults(handler=command_build)

    index = commands.add_parser("index")
    index.add_argument("--site", required=True)
    index.add_argument("--app-name", required=True)
    index.add_argument("--max-branch-builds", type=int, default=20)
    index.set_defaults(handler=command_index)

    args = parser.parse_args()
    args.handler(args)


if __name__ == "__main__":
    main()
