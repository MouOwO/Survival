"""Lobby purpose only removes cloud permissions; all auth remains real service code."""
from dataclasses import replace
import unittest

from . import test_service as fixtures
from .service import AuthError


class LobbyScopeTest(unittest.TestCase):
    def setUp(self):
        self.fixture = fixtures.ServiceTest()
        self.fixture.setUp()
        self.addCleanup(self.fixture.tearDown)

    def test_authorized_lobby_identity_cannot_forward_any_existing_cloud_read(self):
        f = self.fixture
        identity = dict(f.identity, match_session_id="lobby_fixture_session_123")
        _, grant, _ = f.approved(identity)
        token = grant["access_token"]
        self.assertEqual(f.service.principal(token, identity)["account"], f.account)
        for path in ("/v1/profile", "/v1/session/authenticate", "/v1/archive/config", "/v1/lottery/catalog"):
            with self.assertRaises(AuthError) as caught:
                f.service.proxy(path, token, identity, "peer")
            self.assertEqual(caught.exception.code, "player_route_not_allowed")
        self.assertEqual(f.forward_calls, [])
        with self.assertRaises(AuthError):
            f.service.proxy("/v1/profile", token, dict(identity, match_session_id="regular_game_session"), "peer")
        self.assertEqual(f.forward_calls, [])

    def test_lobby_scope_also_denies_local_progress_when_backend_allows_test_progress(self):
        f = self.fixture
        f.service.close()
        f.service = f.build(replace(f.settings, isolated_local_progress=True))
        identity = dict(f.identity, match_session_id="lobby_local_progress_session")
        _, grant, _ = f.approved(identity)
        for path in ("/v1/archive/command", "/v1/archive/endless-batch", "/v1/online-time/checkpoint"):
            with self.assertRaises(AuthError) as caught:
                f.service.proxy(path, grant["access_token"], identity, "peer")
            self.assertEqual(caught.exception.code, "player_route_not_allowed")
        self.assertEqual(f.forward_calls, [])

    def test_lobby_authorization_page_describes_identity_and_session_only_data(self):
        f = self.fixture
        started = f.start(dict(f.identity, match_session_id="lobby_fixture_session_123"))
        _, _, document = f.service.page(started["user_code"], None)
        text = document.decode("utf-8")
        self.assertIn("仅用于大厅建房", text)
        self.assertIn("不读取或写入云存档", text)
        self.assertNotIn("本次游戏可以读取你的测试存档", text)


if __name__ == "__main__":
    unittest.main()
