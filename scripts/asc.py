#!/usr/bin/env python3
"""App Store Connect helper for the CI workflow.

Only the Python standard library and the `openssl` command line tool are used. The JWT is signed with
ES256 by `openssl dgst`, whose DER signature is converted to the raw `r || s` form that JWS expects.

Environment:
  ASC_KEY_ID      Key ID of the App Store Connect API key.
  ASC_ISSUER_ID   Issuer ID of the team.
  ASC_KEY_PATH    Path to the .p8 private key, or
  ASC_KEY_P8      Contents of the .p8 private key.

Commands:
  write-key PATH                Writes ASC_KEY_P8 (PEM, escaped newlines or base64) to PATH.
  check                         Verifies the key and that at least one iOS device is registered.
  keychain-serials              Prints the serial numbers of the "Apple Development" certificates in the keychain.
  revoke-new-dev-certs FILE     Revokes, through the API, development certificates in the keychain that are not in FILE.
  verify-ipa IPA                Checks that every bundle in the IPA embeds an Ad Hoc provisioning profile.
"""

import base64
import json
import os
import pathlib
import plistlib
import re
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
import zipfile

API_ROOT = "https://api.appstoreconnect.apple.com"


class ApiError(Exception):
    def __init__(self, status, body):
        super().__init__(f"HTTP {status}: {body}")
        self.status = status
        self.body = body


def fail(message):
    print(f"::error::{message}")
    sys.exit(1)


def github_output(name, value):
    path = os.environ.get("GITHUB_OUTPUT")
    if path:
        with open(path, "a", encoding="utf-8") as handle:
            handle.write(f"{name}={value}\n")


# --- Key and token -------------------------------------------------------------------------------------


def normalize_key(content):
    """Accepts a PEM key, a PEM key with literal \\n sequences, or a base64 encoded PEM/DER key."""
    text = content.strip()
    if "\\n" in text and "\n" not in text:
        text = text.replace("\\n", "\n")
    if "BEGIN" not in text:
        try:
            decoded = base64.b64decode(text, validate=False).decode("utf-8")
            if "BEGIN" in decoded:
                text = decoded.strip()
        except (ValueError, UnicodeDecodeError):
            pass
    if "BEGIN" not in text:
        body = re.sub(r"\s+", "", text)
        lines = [body[index:index + 64] for index in range(0, len(body), 64)]
        text = "-----BEGIN PRIVATE KEY-----\n" + "\n".join(lines) + "\n-----END PRIVATE KEY-----"
    return text + "\n"


def write_key(path):
    content = os.environ.get("ASC_KEY_P8", "")
    if not content.strip():
        fail("ASC_KEY_P8 is empty.")
    target = pathlib.Path(path)
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(normalize_key(content), encoding="utf-8")
    target.chmod(0o600)
    print(f"Wrote App Store Connect key to {target}")


def key_path():
    path = os.environ.get("ASC_KEY_PATH")
    if path and os.path.exists(path):
        return path
    content = os.environ.get("ASC_KEY_P8")
    if not content:
        fail("Set ASC_KEY_PATH or ASC_KEY_P8.")
    handle = tempfile.NamedTemporaryFile("w", suffix=".p8", delete=False)
    handle.write(normalize_key(content))
    handle.close()
    os.chmod(handle.name, 0o600)
    return handle.name


def b64url(data):
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def der_to_raw_signature(der, size=32):
    """Converts an ECDSA-Sig-Value (SEQUENCE { r INTEGER, s INTEGER }) into r || s."""

    def read_length(buffer, index):
        first = buffer[index]
        index += 1
        if first < 0x80:
            return first, index
        count = first & 0x7F
        return int.from_bytes(buffer[index:index + count], "big"), index + count

    if not der or der[0] != 0x30:
        raise ValueError("Unexpected signature format")
    _, index = read_length(der, 1)
    raw = b""
    for _ in range(2):
        if der[index] != 0x02:
            raise ValueError("Unexpected signature integer")
        length, index = read_length(der, index + 1)
        value = der[index:index + length].lstrip(b"\x00")
        index += length
        if len(value) > size:
            raise ValueError("Signature integer too long")
        raw += value.rjust(size, b"\x00")
    return raw


def make_token():
    key_id = os.environ.get("ASC_KEY_ID", "").strip()
    issuer_id = os.environ.get("ASC_ISSUER_ID", "").strip()
    if not key_id or not issuer_id:
        fail("ASC_KEY_ID and ASC_ISSUER_ID are required.")
    now = int(time.time())
    header = {"alg": "ES256", "kid": key_id, "typ": "JWT"}
    payload = {"iss": issuer_id, "iat": now, "exp": now + 15 * 60, "aud": "appstoreconnect-v1"}
    signing_input = ".".join(
        b64url(json.dumps(part, separators=(",", ":")).encode("utf-8")) for part in (header, payload)
    )
    result = subprocess.run(
        ["openssl", "dgst", "-sha256", "-sign", key_path()],
        input=signing_input.encode("ascii"),
        capture_output=True,
        check=False,
    )
    if result.returncode != 0:
        fail("openssl could not sign the token. Check that ASC_KEY_P8 contains the .p8 file: "
             + result.stderr.decode("utf-8", "replace").strip())
    return signing_input + "." + b64url(der_to_raw_signature(result.stdout))


# --- API -----------------------------------------------------------------------------------------------


def request(method, path_or_url, token, params=None):
    url = path_or_url if path_or_url.startswith("http") else API_ROOT + path_or_url
    if params:
        url += "?" + urllib.parse.urlencode(params)
    req = urllib.request.Request(url, method=method, headers={
        "Authorization": f"Bearer {token}",
        "Accept": "application/json",
    })
    try:
        with urllib.request.urlopen(req, timeout=60) as response:
            body = response.read()
            return json.loads(body) if body else None
    except urllib.error.HTTPError as error:
        raise ApiError(error.code, error.read().decode("utf-8", "replace")) from None


def list_all(path, token, params):
    items, url, query = [], path, params
    while url:
        page = request("GET", url, token, query)
        items.extend(page.get("data", []))
        url = (page.get("links") or {}).get("next")
        query = None
    return items


def explain(error):
    if error.status == 401:
        return ("App Store Connect rejected the API key (401). Check ASC_KEY_ID, ASC_ISSUER_ID and ASC_KEY_P8, "
                "and that the key is a Team key that has not been revoked.")
    if error.status == 403:
        return "The API key does not have enough permissions (403). Use a Team key with the Admin role."
    return f"App Store Connect API error: {error}"


def check():
    token = make_token()
    try:
        devices = list_all("/v1/devices", token, {
            "filter[platform]": "IOS",
            "filter[status]": "ENABLED",
            "limit": "200",
        })
    except ApiError as error:
        fail(explain(error))
    print("App Store Connect API key works.")
    if not devices:
        fail("No enabled iOS devices are registered in the Apple Developer account. "
             "Register the UDID of at least one iPhone at https://developer.apple.com/account/resources/devices/list")
    print(f"Registered iOS devices: {len(devices)}")
    for device in devices:
        attributes = device.get("attributes", {})
        udid = attributes.get("udid", "")
        print(f"  - {attributes.get('name', '?')} ({attributes.get('deviceClass', '?')}, …{udid[-6:]})")
    github_output("devices", len(devices))


# --- Certificates --------------------------------------------------------------------------------------


def normalize_serial(serial):
    value = serial.strip().upper().replace(":", "")
    return value.lstrip("0") or "0"


def keychain_serials():
    result = subprocess.run(
        ["security", "find-certificate", "-a", "-c", "Apple Development", "-p"],
        capture_output=True,
        text=True,
        check=False,
    )
    pems = re.findall(r"-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----", result.stdout, re.S)
    serials = {}
    for pem in pems:
        info = subprocess.run(
            ["openssl", "x509", "-noout", "-serial", "-subject"],
            input=pem,
            capture_output=True,
            text=True,
            check=False,
        )
        match = re.search(r"serial=([0-9A-Fa-f:]+)", info.stdout)
        if match:
            subject = next((line for line in info.stdout.splitlines() if line.startswith("subject")), "")
            serials[normalize_serial(match.group(1))] = subject
    return serials


def print_keychain_serials():
    for serial in sorted(keychain_serials()):
        print(serial)


def revoke_new_dev_certs(before_file):
    path = pathlib.Path(before_file)
    if not path.exists():
        print(f"{before_file} does not exist; nothing to compare, so nothing is revoked.")
        return
    before = {normalize_serial(line) for line in path.read_text().split() if line.strip()}
    current = keychain_serials()
    new = {serial: subject for serial, subject in current.items() if serial not in before}
    if not new:
        print("No new Apple Development certificates were created in this run.")
        return
    print("New Apple Development certificates in the keychain:")
    for serial, subject in new.items():
        print(f"  - {serial} {subject}")

    token = make_token()
    try:
        certificates = list_all("/v1/certificates", token, {"limit": "200"})
    except ApiError as error:
        fail(explain(error))
    revoked = set()
    for certificate in certificates:
        serial = normalize_serial(certificate.get("attributes", {}).get("serialNumber", ""))
        if serial in new:
            try:
                request("DELETE", f"/v1/certificates/{certificate['id']}", token)
            except ApiError as error:
                print(f"::warning::Could not revoke certificate {serial}: {explain(error)}")
                continue
            revoked.add(serial)
            print(f"Revoked development certificate {serial} ({certificate.get('attributes', {}).get('name', '')}).")
    for serial in sorted(set(new) - revoked):
        print(f"::warning::Development certificate {serial} was not found in App Store Connect or could not be revoked.")


# --- IPA verification ----------------------------------------------------------------------------------


def verify_ipa(ipa):
    with tempfile.TemporaryDirectory() as directory:
        with zipfile.ZipFile(ipa) as archive:
            archive.extractall(directory)
        root = pathlib.Path(directory)
        bundles = sorted(
            path for path in root.rglob("*")
            if path.is_dir() and path.suffix in (".app", ".appex")
        )
        if not bundles:
            fail(f"No app bundles found in {ipa}.")
        device_counts = []
        for bundle in bundles:
            name = bundle.relative_to(root).as_posix()
            profile_path = bundle / "embedded.mobileprovision"
            if not profile_path.exists():
                fail(f"{name} does not contain embedded.mobileprovision.")
            decoded = subprocess.run(
                ["security", "cms", "-D", "-i", str(profile_path)],
                capture_output=True,
                check=True,
            ).stdout
            profile = plistlib.loads(decoded)
            devices = profile.get("ProvisionedDevices") or []
            entitlements = profile.get("Entitlements") or {}
            is_ad_hoc = (
                bool(devices)
                and not profile.get("ProvisionsAllDevices", False)
                and not entitlements.get("get-task-allow", False)
            )
            print(f"{name}")
            print(f"  profile:  {profile.get('Name')} ({profile.get('UUID')})")
            print(f"  team:     {', '.join(profile.get('TeamIdentifier', []))}")
            print(f"  app id:   {entitlements.get('application-identifier', '?')}")
            print(f"  expires:  {profile.get('ExpirationDate')}")
            print(f"  devices:  {len(devices)}")
            if not is_ad_hoc:
                fail(f"{name} is not signed with an Ad Hoc profile.")
            device_counts.append(len(devices))
        count = min(device_counts)
        print(f"All {len(bundles)} bundle(s) use Ad Hoc profiles that include {count} device(s).")
        github_output("devices", count)


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 1
    command, arguments = argv[1], argv[2:]
    if command == "write-key" and len(arguments) == 1:
        write_key(arguments[0])
    elif command == "check":
        check()
    elif command == "keychain-serials":
        print_keychain_serials()
    elif command == "revoke-new-dev-certs" and len(arguments) == 1:
        revoke_new_dev_certs(arguments[0])
    elif command == "verify-ipa" and len(arguments) == 1:
        verify_ipa(arguments[0])
    else:
        print(__doc__)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
