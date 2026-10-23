import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from auth import Policy, handler


class AuthTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.pins, self.pending = self.root / "pins.json", self.root / "pending.json"
        self.key = "ValveGeneratedServerKey" * 3
        self.digest = hashlib.sha256(self.key.encode()).hexdigest()
        self.now = 2000
        self.policy = Policy(self.pins, self.pending, clock=lambda: self.now)

    def approve(self, **changes):
        value = {"workshop_id": "3824360109", "sha256": [self.digest]}
        value.update(changes)
        self.pins.write_text(json.dumps(value))
        self.pins.chmod(0o600)

    def test_unapproved_only_records_digest_and_never_self_authorizes(self):
        for _ in range(3):
            self.assertEqual(self.policy.check("Bearer " + self.key), (False, self.digest[:16]))
        raw = self.pending.read_text()
        self.assertNotIn(self.key, raw)
        self.assertEqual(json.loads(raw), {self.digest: self.now})
        self.assertFalse(self.pins.exists())

    def test_operator_pin_approves_exact_key_and_reload_revokes(self):
        self.approve()
        self.assertEqual(self.policy.check("Bearer " + self.key), (True, None))
        self.assertFalse(self.pending.exists())
        self.assertFalse(self.policy.check("Bearer " + self.key + "x")[0])
        self.approve(sha256=[])
        self.assertFalse(self.policy.check("Bearer " + self.key)[0])

    def test_bad_headers_and_invalid_valve_results_are_rejected_without_recording(self):
        for value in (None, "", "Basic x", "Bearer short", "Bearer " + "x" * 257,
                      "Bearer Invalid_NotOnDedicatedServer", "Bearer " + "x" * 24 + "\n"):
            with self.subTest(value=value):
                self.assertEqual(self.policy.check(value), (False, None))
        self.assertFalse(self.pending.exists())

    def test_wrong_workshop_corrupt_pin_and_bad_digest_fail_closed(self):
        for changes in ({"workshop_id": "1"}, {"sha256": ["not a digest"]}, {"sha256": self.digest}):
            self.approve(**changes)
            self.assertFalse(self.policy.check("Bearer " + self.key)[0])
        self.pins.write_text("broken")
        self.assertFalse(self.policy.check("Bearer " + self.key)[0])

    def test_pending_is_bounded_and_expired_entries_are_removed(self):
        for index in range(40):
            self.policy.check("Bearer " + self.key + str(index))
        self.assertEqual(len(json.loads(self.pending.read_text())), 32)
        self.assertLessEqual(len(self.policy.last_recorded), 32)
        self.now += 1801
        self.policy.check("Bearer " + self.key)
        self.assertEqual(json.loads(self.pending.read_text()), {self.digest: self.now})

    def test_handler_does_not_authorize_on_registration(self):
        class Base:
            headers = {"Authorization": "Bearer " + self.key}
            def _send(instance, status, body):
                instance.response = status, body
        wrapped = handler(Base, self.policy)()
        self.assertFalse(wrapped._authorized())
        self.assertEqual(wrapped.response[0], 403)
        self.assertEqual(wrapped.response[1]["pairing_fingerprint"], self.digest[:16])
        self.approve()
        self.assertTrue(wrapped._authorized())

    def test_unwritable_pending_state_denies_without_breaking_http_response(self):
        with patch('auth.os.open',side_effect=PermissionError):
            self.assertEqual(self.policy.check('Bearer '+self.key),(False,None))
        self.assertFalse(self.pins.exists())


if __name__ == "__main__":
    unittest.main()
