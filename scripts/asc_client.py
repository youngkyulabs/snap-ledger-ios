"""App Store Connect REST client. Standard library only; ES256 JWT via openssl."""
from __future__ import annotations

import base64
import json
import os
import subprocess
import time
import urllib.error
import urllib.request

BASE = "https://api.appstoreconnect.apple.com"
TOKEN_LIFETIME_S = 600


class ASCError(RuntimeError):
    """Anything that went wrong talking to App Store Connect."""


def _b64u(raw):
    return base64.urlsafe_b64encode(raw).rstrip(b"=")


def _der_to_raw(der):
    """ECDSA DER SEQUENCE{INTEGER r, INTEGER s} -> fixed-width r||s (JOSE)."""
    if not der or der[0] != 0x30:
        raise ASCError("openssl returned a signature that is not DER")
    idx = 2 if der[1] < 0x80 else 2 + (der[1] & 0x7F)
    out = b""
    for _ in range(2):
        if der[idx] != 0x02:
            raise ASCError("openssl returned a malformed DER integer")
        length = der[idx + 1]
        value = der[idx + 2: idx + 2 + length]
        out += value.lstrip(b"\x00").rjust(32, b"\x00")
        idx += 2 + length
    return out


class Client:
    def __init__(self, key_path, key_id, issuer_id):
        self.key_path = key_path
        self.key_id = key_id
        self.issuer_id = issuer_id

    @classmethod
    def from_env(cls):
        names = ("ASC_KEY_PATH", "ASC_KEY_ID", "ASC_ISSUER_ID")
        missing = [n for n in names if not os.environ.get(n)]
        if missing:
            raise ASCError("missing environment variables: " + ", ".join(missing))
        return cls(os.environ["ASC_KEY_PATH"], os.environ["ASC_KEY_ID"], os.environ["ASC_ISSUER_ID"])

    def token(self):
        now = int(time.time())
        header = {"alg": "ES256", "kid": self.key_id, "typ": "JWT"}
        payload = {
            "iss": self.issuer_id,
            "iat": now,
            "exp": now + TOKEN_LIFETIME_S,
            "aud": "appstoreconnect-v1",
        }
        signing_input = (
            _b64u(json.dumps(header, separators=(",", ":")).encode())
            + b"."
            + _b64u(json.dumps(payload, separators=(",", ":")).encode())
        )
        proc = subprocess.run(
            ["openssl", "dgst", "-sha256", "-sign", self.key_path],
            input=signing_input, capture_output=True,
        )
        if proc.returncode != 0:
            raise ASCError("openssl could not sign with %s: %s" % (self.key_path, proc.stderr.decode(errors="replace")))
        return (signing_input + b"." + _b64u(_der_to_raw(proc.stdout))).decode()

    def request(self, method, path, body=None):
        url = path if path.startswith("http") else BASE + path
        data = json.dumps(body).encode() if body is not None else None
        req = urllib.request.Request(url, data=data, method=method)
        req.add_header("Authorization", "Bearer " + self.token())
        if data is not None:
            req.add_header("Content-Type", "application/json")
        try:
            with urllib.request.urlopen(req) as resp:
                raw = resp.read()
                return resp.status, (json.loads(raw) if raw[:1] in b"{[" else raw)
        except urllib.error.HTTPError as err:
            raw = err.read()
            try:
                return err.code, json.loads(raw)
            except ValueError:
                return err.code, raw.decode(errors="replace")
