import base64
import json
import os
import subprocess
import tempfile
import unittest
import urllib.error

from scripts.asc_client import RETRY_ATTEMPTS, ASCError, Client, _decode_body


def _b64u_decode(segment):
    return base64.urlsafe_b64decode(segment + "=" * (-len(segment) % 4))


class FromEnvTests(unittest.TestCase):
    def setUp(self):
        self._saved = {k: os.environ.get(k) for k in ("ASC_KEY_PATH", "ASC_KEY_ID", "ASC_ISSUER_ID")}
        for k in self._saved:
            os.environ.pop(k, None)

    def tearDown(self):
        for k, v in self._saved.items():
            if v is None:
                os.environ.pop(k, None)
            else:
                os.environ[k] = v

    def test_missing_env_names_every_missing_variable(self):
        os.environ["ASC_KEY_ID"] = "KEYID"
        with self.assertRaises(ASCError) as ctx:
            Client.from_env()
        message = str(ctx.exception)
        self.assertIn("ASC_KEY_PATH", message)
        self.assertIn("ASC_ISSUER_ID", message)
        self.assertNotIn("ASC_KEY_ID", message)


class TokenTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.key_path = os.path.join(self.tmp.name, "key.p8")
        subprocess.run(
            ["openssl", "ecparam", "-name", "prime256v1", "-genkey", "-noout", "-out", self.key_path],
            check=True, capture_output=True,
        )

    def tearDown(self):
        self.tmp.cleanup()

    def test_token_is_es256_jwt_with_expected_claims(self):
        client = Client(self.key_path, "KEYID123", "ISSUER456")
        header_b64, payload_b64, signature_b64 = client.token().split(".")

        header = json.loads(_b64u_decode(header_b64))
        self.assertEqual(header["alg"], "ES256")
        self.assertEqual(header["kid"], "KEYID123")

        payload = json.loads(_b64u_decode(payload_b64))
        self.assertEqual(payload["iss"], "ISSUER456")
        self.assertEqual(payload["aud"], "appstoreconnect-v1")
        self.assertEqual(payload["exp"] - payload["iat"], 600)

        self.assertEqual(len(_b64u_decode(signature_b64)), 64)


class DecodeBodyTests(unittest.TestCase):
    def test_empty_204_body_is_not_parsed_as_json(self):
        # b"" is a substring of b"{[", so the old membership test sent an empty
        # 204 body -- link_build's success path -- into json.loads.
        self.assertEqual(_decode_body(b""), b"")

    def test_json_object_and_array_bodies_are_parsed(self):
        self.assertEqual(_decode_body(b'{"data": 1}'), {"data": 1})
        self.assertEqual(_decode_body(b"[1, 2]"), [1, 2])

    def test_non_json_body_is_returned_untouched(self):
        self.assertEqual(_decode_body(b"plain text"), b"plain text")


class RecordingClient(Client):
    """Client whose single-shot request is scripted instead of networked."""

    def __init__(self, outcomes):
        super().__init__("unused.p8", "KEYID", "ISSUER")
        self.outcomes = list(outcomes)
        self.attempts = 0

    def _request_once(self, method, path, body=None):
        self.attempts += 1
        outcome = self.outcomes.pop(0)
        if isinstance(outcome, Exception):
            raise outcome
        return outcome


class RetryTests(unittest.TestCase):
    def test_retries_past_a_transient_network_error(self):
        client = RecordingClient([
            urllib.error.URLError("connection reset"),
            (200, {"data": []}),
        ])
        slept = []
        self.assertEqual(client.request("GET", "/v1/builds", sleep=slept.append), (200, {"data": []}))
        self.assertEqual(client.attempts, 2)
        self.assertEqual(slept, [5])

    def test_retries_a_503_then_succeeds(self):
        client = RecordingClient([(503, b"busy"), (200, {"data": []})])
        self.assertEqual(client.request("GET", "/v1/builds", sleep=lambda _: None), (200, {"data": []}))
        self.assertEqual(client.attempts, 2)

    def test_gives_up_as_an_asc_error_not_a_raw_urlerror(self):
        client = RecordingClient([urllib.error.URLError("down")] * RETRY_ATTEMPTS)
        with self.assertRaises(ASCError) as ctx:
            client.request("GET", "/v1/builds", sleep=lambda _: None)
        self.assertIn("after %d attempts" % RETRY_ATTEMPTS, str(ctx.exception))
        self.assertEqual(client.attempts, RETRY_ATTEMPTS)

    def test_a_client_error_is_returned_without_retrying(self):
        client = RecordingClient([(409, {"errors": []})])
        self.assertEqual(client.request("PATCH", "/v1/x", sleep=lambda _: None), (409, {"errors": []}))
        self.assertEqual(client.attempts, 1)


if __name__ == "__main__":
    unittest.main()
