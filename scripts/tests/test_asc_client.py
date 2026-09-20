import base64
import json
import os
import subprocess
import tempfile
import unittest

from scripts.asc_client import ASCError, Client


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


if __name__ == "__main__":
    unittest.main()
