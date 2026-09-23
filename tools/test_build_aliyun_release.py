"""Linux release payload regressions, independent of deployment credentials."""
from pathlib import Path
import tempfile
import unittest

from build_aliyun_release import copy_linux_deploy


class LinuxPayloadTests(unittest.TestCase):
    def test_shell_unit_logrotate_and_extensionless_client_use_lf(self):
        with tempfile.TemporaryDirectory() as directory:
            source, target = Path(directory)/'source', Path(directory)/'target'
            source.mkdir()
            (source/'pg-bin').mkdir()
            samples = {
                'prepare.sh': b'#!/bin/bash\r\nset -eu\r\n',
                'goufayu-api.service': b'[Service]\r\nUser=goufayu\r\n',
                'goufayu.logrotate': b'/var/log/goufayu/api.log {\r\n daily\r\n}\r\n',
                'pg-bin/pg_dump': b'#!/bin/sh\r\nexec python3.11 "$@"\r\n',
                'manage.py': b'example = "\\r\\n"\r\n',
            }
            for name, content in samples.items():
                (source/name).write_bytes(content)
            copy_linux_deploy(source, target)
            for name, content in samples.items():
                self.assertEqual((target/name).read_bytes(), content.replace(b'\r\n',b'\n'))
                self.assertEqual((source/name).read_bytes(), content)

    def test_non_text_payload_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory)/'source'
            source.mkdir()
            (source/'unexpected.bin').write_bytes(b'\xff\xfe\x80')
            with self.assertRaises(UnicodeDecodeError):
                copy_linux_deploy(source, Path(directory)/'target')


if __name__ == '__main__':
    unittest.main()
