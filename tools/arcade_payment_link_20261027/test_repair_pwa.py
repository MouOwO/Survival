"""Pure tests for the real leading-space systemd unit failure."""
from pathlib import PurePosixPath
import unittest
from unittest.mock import patch
import repair_pwa
import repair_pwa_remote as repair

class RepairTests(unittest.TestCase):
    def setUp(self):
        self.release=PurePosixPath('/opt/goufayu-ws4-web/releases/20261027-payment-'+repair.ORIGINAL[:20])
        self.old=(b' [Unit]\n Description=original unchanged\n [Service]\n User=goufayu-ws4-web\n Group=goufayu-ws4-web\n'
                  b' WorkingDirectory=/opt/goufayu-ws4-web/releases/original\n EnvironmentFile=/etc/goufayu-ws4-web/auth.env\n'
                  b' ExecStart=/usr/bin/python3.11 -B -m player_web_auth.run\n ProtectSystem=strict\n ReadWritePaths=/var/lib/goufayu-ws4-web\n')

    def test_real_leading_space_preserves_every_unrelated_byte(self):
        after=repair.repaired_unit(self.old,self.release)
        self.assertEqual(after,self.old.replace(b'WorkingDirectory=/opt/goufayu-ws4-web/releases/original',
                                                ('WorkingDirectory='+str(self.release)).encode()))

    def test_crlf_tabs_and_assignment_spaces_remain_intact(self):
        before=self.old.replace(b' WorkingDirectory=',b'\t WorkingDirectory = ').replace(b'\n',b'\r\n')
        result=repair.repaired_unit(before,self.release)
        self.assertEqual(result.replace(str(self.release).encode(),b'/opt/goufayu-ws4-web/releases/original'),before)

    def test_unknown_identity_duplicate_executable_and_retarget_are_rejected(self):
        for bad in (self.old.replace(b'User=goufayu-ws4-web',b'User=root'),
                    self.old+b' User=goufayu-ws4-web\n',
                    self.old.replace(b'ExecStart=/usr/bin/python3.11',b'ExecStart=/other/python'),
                    self.old.replace(b'EnvironmentFile=/etc/goufayu-ws4-web/auth.env',b'EnvironmentFile=/etc/other.env')):
            with self.assertRaises(RuntimeError):repair.repaired_unit(bad,self.release)
        with self.assertRaisesRegex(RuntimeError,'repair_fixed_pwa_release_required'):
            repair.repaired_unit(self.old,PurePosixPath('/opt/other'))

    def test_default_never_uses_ssh_or_mutates_when_inspection_is_missing(self):
        with patch.object(repair_pwa.INSPECTION.__class__,'exists',return_value=False),patch.object(repair_pwa,'remote') as remote,patch('builtins.print'):
            repair_pwa.main([])
        remote.assert_not_called()

    def test_original_candidate_sources_remain_unmodified(self):
        capsule=repair_pwa.original()
        root=repair_pwa.ROOT
        import hashlib
        for name in ('activation_remote.py','activate.py','remote_review.py'):
            data=(root/'tools/arcade_payment_link_20261027'/name).read_bytes().replace(b'\r\n',b'\n')
            self.assertEqual(hashlib.sha256(data).hexdigest(),capsule['candidate']['source_hashes']['review_tools/'+name])

if __name__=='__main__':unittest.main()
