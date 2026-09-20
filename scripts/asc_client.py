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

# The release job polls for the better part of an hour, so a single stalled
# socket must not be able to hang it: urlopen without a timeout blocks forever.
REQUEST_TIMEOUT_S = 30
RETRY_ATTEMPTS = 3
RETRY_BACKOFF_S = 5
RETRY_STATUSES = frozenset([429, 500, 502, 503, 504])


class ASCError(RuntimeError):
    """Anything that went wrong talking to App Store Connect."""


class ASCTransportError(ASCError):
    """The request never produced a usable answer -- outlast it, do not abort.

    Kept distinct from ASCError so a polling loop can tolerate it while still
    failing immediately on a terminal answer (a build that came back INVALID).
    """


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


def _decode_body(raw):
    """Parse a response body, tolerating the empty one a 204 returns.

    `raw[:1] in b"{["` looks right but is a substring test, and b"" is a
    substring of everything -- which sent an empty 204 body into json.loads.
    """
    if raw[:1] in (b"{", b"["):
        return json.loads(raw)
    return raw


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

    def _request_once(self, method, path, body=None):
        url = path if path.startswith("http") else BASE + path
        data = json.dumps(body).encode() if body is not None else None
        req = urllib.request.Request(url, data=data, method=method)
        req.add_header("Authorization", "Bearer " + self.token())
        if data is not None:
            req.add_header("Content-Type", "application/json")
        try:
            with urllib.request.urlopen(req, timeout=REQUEST_TIMEOUT_S) as resp:
                return resp.status, _decode_body(resp.read())
        except urllib.error.HTTPError as err:
            raw = err.read()
            try:
                return err.code, json.loads(raw)
            except ValueError:
                return err.code, raw.decode(errors="replace")

    def request(self, method, path, body=None, sleep=time.sleep):
        """One request, retried past transient failures.

        The build poll makes well over a hundred calls across ~an hour; a single
        reset connection or 503 used to escape as an unhandled URLError and
        abort the release *after* deliver had already overwritten metadata.
        Every call here is idempotent (GETs, and a PATCH that sets a
        relationship to one specific build), so retrying is safe.
        """
        last_problem = None
        for attempt in range(RETRY_ATTEMPTS):
            if attempt:
                sleep(RETRY_BACKOFF_S * attempt)
            try:
                # HTTPError is handled inside _request_once, so anything caught
                # here is a genuine network/socket failure.
                status, payload = self._request_once(method, path, body)
            except OSError as error:
                last_problem = "%s: %s" % (type(error).__name__, error)
                continue
            if status in RETRY_STATUSES:
                # A 503 that outlives our attempts is as transient as a reset
                # socket, so it leaves by the same door and callers that poll
                # can keep waiting instead of failing the release.
                last_problem = "HTTP %s" % status
                continue
            return status, payload
        raise ASCTransportError("%s %s failed after %d attempts (%s)"
                                % (method, path, RETRY_ATTEMPTS, last_problem))
