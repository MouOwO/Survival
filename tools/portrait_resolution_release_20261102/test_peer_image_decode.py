"""Bounded codec contract, native process mocked; no actual GUI/codec/SDK call."""
from pathlib import Path
from unittest.mock import patch
from types import SimpleNamespace
import importlib.util,json,struct,tempfile,unittest

HERE=Path(__file__).resolve().parent
s=importlib.util.spec_from_file_location('peer_decode_contract',HERE/'native_admission.py')
x=importlib.util.module_from_spec(s);s.loader.exec_module(x)


class DecodeContract(unittest.TestCase):
    def png_header(self,folder,width=1600,height=1000,name='peer.png'):
        path=Path(folder)/name
        path.write_bytes(b'\x89PNG\r\n\x1a\n'+struct.pack('>I',13)+b'IHDR'+struct.pack('>II',width,height))
        return path

    def test_png_and_jpeg_dimensions_are_bounded_before_codec(self):
        with tempfile.TemporaryDirectory() as folder:
            path=self.png_header(folder)
            self.assertEqual(x.peer_image_header(path),(1600,1000))
            jpeg=Path(folder)/'peer.jpg'
            jpeg.write_bytes(b'\xff\xd8\xff\xc0\x00\x08\x08'+struct.pack('>HH',1000,1600)+b'\x01')
            self.assertEqual(x.peer_image_header(jpeg),(1600,1000))

    def test_huge_header_refuses_before_any_native_codec(self):
        with tempfile.TemporaryDirectory() as folder,patch.object(x.subprocess,'run',side_effect=AssertionError('No codec')):
            path=self.png_header(folder,100000,100000)
            with self.assertRaisesRegex(ValueError,'raster budget'):x.decode_peer_images([path])

    def test_truncated_or_unrelated_payload_refuses(self):
        with tempfile.TemporaryDirectory() as folder:
            for raw in (b'not image',b'\xff\xd8',b'\xff\xd8\xff\xe1\xff\xff'):
                path=Path(folder)/'bad.jpg';path.write_bytes(raw)
                with self.subTest(raw=raw),self.assertRaises(ValueError):x.peer_image_header(path)

    def test_real_decoder_call_shape_is_fixed_and_paths_only_json_stdin(self):
        with tempfile.TemporaryDirectory() as folder:
            path=self.png_header(folder,name="peer'; echo UNAPPROVED.png")
            output=[dict(width=1600,height=1000,format='PNG',decoded=True)]
            with patch.object(x.subprocess,'run',return_value=SimpleNamespace(returncode=0,stdout=json.dumps(output).encode())) as run:
                self.assertEqual(x.decode_peer_images([path]),output)
            args=run.call_args.args[0]
            self.assertEqual(args,['powershell.exe','-NoProfile','-NonInteractive','-Command',x.IMAGE_DECODE_PS])
            self.assertNotIn(str(path),args[-1])
            self.assertEqual(json.loads(run.call_args.kwargs['input']),[str(path)])
            self.assertEqual(run.call_args.kwargs['timeout'],20)

    def test_codec_failure_wrong_count_format_or_dimensions_cannot_pass(self):
        outputs=[SimpleNamespace(returncode=1,stdout=b''),
            SimpleNamespace(returncode=0,stdout=b'[]'),
            SimpleNamespace(returncode=0,stdout=b'[{"decoded":true,"width":1600,"height":1000,"format":"BMP"}]'),
            SimpleNamespace(returncode=0,stdout=b'[{"decoded":true,"width":1600,"height":900,"format":"PNG"}]')]
        with tempfile.TemporaryDirectory() as folder:
            path=self.png_header(folder)
            for output in outputs:
                with self.subTest(output=output.stdout),patch.object(x.subprocess,'run',return_value=output),self.assertRaises(ValueError):x.decode_peer_images([path])


if __name__=='__main__':unittest.main()
