"""Compiler planning helpers only: no compiler, external file, Git or SDK writes."""
from pathlib import Path
from unittest import mock
import importlib.util,struct,tempfile,unittest

spec=importlib.util.spec_from_file_location('release_compile_scope',Path(__file__).with_name('release_compile_scope.py'))
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)

class CompileScopeTests(unittest.TestCase):
    def test_exact_checkout_only(self):
        self.assertEqual(m.checkout_binding(b'a\nb\n',b'a\r\nb\r\n',True),'GIT_LF_TO_COMPILER_CRLF_ONLY')
        self.assertEqual(m.checkout_binding(b'a\r\n',b'a\r\n',True),'IDENTITY')
        self.assertEqual(m.checkout_binding(b'\x89PNG\0',b'\x89PNG\0',False),'IDENTITY')
        for bad in (b'a \r\nb\r\n',b'a\r\nb\n',b'a\nb\nextra'):
            with self.assertRaises(ValueError):m.checkout_binding(b'a\nb\n',bad,True)
        with self.assertRaises(ValueError):m.checkout_binding(b'a\nb',b'a\r\nb',False)

    def test_official_source_and_svg_mappings(self):
        for resource,source in [('panorama/scripts/x.vjs_c','panorama/scripts/x.js'),('panorama/layout/x.vxml_c','panorama/layout/x.xml'),('panorama/styles/x.vcss_c','panorama/styles/x.css'),('panorama/images/x.vtex_c','panorama/images/x.vtex'),('panorama/images/x.vsvg_c','panorama/images/x.svg')]:
            self.assertEqual(m.content_source(resource),source);self.assertEqual(m.artifact_for(source),resource)
        self.assertEqual(m.inventory._resource('content','panorama/images/x.svg',{})[0],'panorama/images/x.vsvg_c')
        self.assertEqual(m.inventory._resource('game','panorama/src/images/x.svg',{})[0],'panorama/images/x.vsvg_c')
        for bad in ('../x.vtex_c','panorama/../x.vtex_c','panorama\\x.vtex_c','maps/x.vpk'):
            with self.assertRaises(ValueError):m.content_source(bad)

    def test_vtex_binds_actual_pixel_inputs(self):
        raw=b'"m_fileName" "string" "panorama/images/a.png"\n"m_fileName" "string" "panorama/images/b.png"'
        self.assertEqual(m.dependencies('panorama/images/a.vtex',raw)[0],['panorama/images/a.png','panorama/images/b.png'])
        for bad in (b'"m_fileName" "string" "../outside.png"',b'"m_fileName" "string" "https://x/a.png"',b'no actual pixels'):
            with self.assertRaises(ValueError):m.dependencies('panorama/images/a.vtex',bad)

    def test_decoder_probe_runtime_css_binds_the_actual_content_author(self):
        path='panorama/scripts/custom_game/lottery_cinematic_v1.js'
        raw=b"var DECODER_PROBE_MOVIE='file://{resources}/styles/custom_game/lottery_cinematic_v1.vcss_c';\nPreviewDecoderProbe:previewDecoderProbe"
        self.assertEqual(m.dependencies(path,raw),(['panorama/styles/custom_game/lottery_cinematic_v1.css'],[]))
        self.assertEqual(m.dependencies(path,b'normalMoviePlayback();'),([],[]))
        for bad in (raw.replace(b'lottery_cinematic_v1.vcss_c',b'missing.vcss_c'),b'PreviewDecoderProbe:unbound'):
            with self.assertRaises(ValueError):m.dependencies(path,bad)

    def test_explicit_include_graph_and_unknown_refs(self):
        children,engine=m.dependencies('panorama/layout/x.xml',b'<root><include src="file://{resources}/scripts/custom_game/a.js"/><include src="s2r://panorama/layout/hud.vxml"/></root>')
        self.assertEqual(children,['panorama/scripts/custom_game/a.js']);self.assertEqual(engine,['s2r://panorama/layout/hud.vxml'])
        with self.assertRaises(ValueError):m.dependencies('panorama/layout/x.xml',b'<include src="../../escape.xml"/>')

    def test_manifest_layoutfile_and_xml_images_are_real_dependencies(self):
        children,engine=m.dependencies('panorama/layout/custom_game/custom_ui_manifest.xml',
            b'<root><CustomUIElement layoutfile="file://{resources}/layout/custom_game/archive.xml"/>'
            b'<Image src="file://{images}/ui/page_assets/header.png"/></root>')
        self.assertEqual(children,['panorama/images/ui/page_assets/header.png','panorama/layout/custom_game/archive.xml'])
        self.assertEqual(engine,[])

    def test_css_all_image_urls_imports_and_empty_weakrefs(self):
        raw=b'''/* url("file://{images}/not_active.png") */
        @import url("file://{resources}/styles/custom_game/common.css");
        .a{background-image:url("file://{images}/custom_game/a.png");}
        .b{background-image:url(file://{images}/custom_game/b.png);}
        .c{background-image:url('s2r://panorama/images/masks/softedge_box_png.vtex');}'''
        children,engine=m.dependencies('panorama/styles/custom_game/archive.css',raw)
        self.assertEqual(children,['panorama/images/custom_game/a.png','panorama/images/custom_game/b.png',
                                   'panorama/styles/custom_game/common.css'])
        self.assertEqual(engine,['s2r://panorama/images/masks/softedge_box_png.vtex'])
        for url in (b'url("")',b"url('')",b'url( )'):
            with self.assertRaisesRegex(ValueError,'css_empty_url'):m.dependencies('panorama/styles/a.css',url)
        with self.assertRaisesRegex(ValueError,'compiler_dependency_unreviewed'):
            m.dependencies('panorama/styles/a.css',b'url("https://remote/image.png")')

    def test_immutable_compiler_bytes_ignore_physical_mixed_eol(self):
        for immutable in (b'a\nb\n',b'a\r\nb\r\n',b'a\r\nb\n'):
            payload,normalization=m.compiler_bytes(immutable,True)
            self.assertEqual(payload,b'a\r\nb\r\n')
            self.assertIn(normalization,('GIT_IDENTITY','IMMUTABLE_GIT_TEXT_TO_COMPILER_CRLF_ONLY'))
        self.assertEqual(m.compiler_bytes(b'\x89PNG\0\r\n',False),(b'\x89PNG\0\r\n','BINARY_GIT_IDENTITY'))
        with self.assertRaisesRegex(ValueError,'lone_cr'):m.compiler_bytes(b'a\rb',True)

    def test_raw_movie_stages_exactly_in_both_trees_without_other_runtime_copies(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder);content=root/'content';game=root/'game'
            path='panorama/videos/custom_game/lottery_cinematic_v1/map.webm'
            raw=b'\x1aE\xdf\xa3\0binary\r\nmovie'
            m.stage_source(content,game,path,raw)
            self.assertEqual((content/path).read_bytes(),raw)
            self.assertEqual((game/path).read_bytes(),raw)
            m.stage_source(content,game,'panorama/layout/a.xml',b'<root/>')
            self.assertFalse((game/'panorama/layout/a.xml').exists())
            with self.assertRaises(FileExistsError):m.stage_source(content,game,path,raw)
            for bad in ('../outside.webm','panorama/videos/../outside.webm'):
                with self.assertRaises(ValueError):m.stage_source(content,game,bad,raw)
        for path in ('panorama/images/x.webm','panorama/videos/x.mp4'):
            self.assertFalse(m.runtime_raw_dependency(path))

    def test_complete_dependency_plan_uses_git_without_any_physical_source_read(self):
        revision='a'*40;root=Path('Z:/not_a_checkout/compiler_test')
        blobs={
            'panorama/layout/custom_game/custom_ui_manifest.xml':b'<root><CustomUIElement layoutfile="file://{resources}/layout/custom_game/a.xml"/></root>\n',
            'panorama/layout/custom_game/a.xml':b'<root><include src="file://{resources}/styles/custom_game/a.css"/><MoviePanel src="file://{resources}/videos/custom_game/map.webm"/></root>\n',
            'panorama/styles/custom_game/a.css':b'.a{background-image:url("file://{images}/custom_game/a.png");}\n',
            'panorama/images/custom_game/a.png':b'\x89PNG\0',
            'panorama/images/custom_game/a.vtex':b'"m_fileName" "string" "panorama/images/custom_game/a.png"\n',
            'panorama/videos/custom_game/map.webm':b'\x1aE\xdf\xa3immutable raw movie',
        }
        trees={'content':{p:{}for p in blobs},'game':{p if m.runtime_raw_dependency(p) else 'panorama/src/'+p[len('panorama/'):]:{}for p in blobs}}
        class Reader:
            used=0;requests=0
            def __init__(self,*args):pass
            def get(self,role,path):
                relative=path if role=='content'or m.runtime_raw_dependency(path) else'panorama/'+path[len('panorama/src/'):]
                raw=blobs[relative]
                return dict(repo=role,path=path,oid='b'*40,raw=raw,git_blob=m.checks(raw),content=m.checks(raw),lfs=False)
            def close(self):pass
        scope={'decisions':[dict(resource='panorama/layout/custom_game/custom_ui_manifest.vxml_c',
            inventory_status='UNBOUND_COMPILED_ARTIFACT',review_decision='IMMUTABLE_AUTHORS_AVAILABLE_RECOMPILE_OR_VALIDATE_EMBEDDED_BINDING')]}
        original=Path.read_bytes
        def guarded(path):
            if str(path).startswith(str(root)):raise AssertionError('physical source was read')
            return original(path)
        with mock.patch.object(m,'Reader',Reader),mock.patch.object(m,'immutable'),mock.patch.object(m.inventory,'git_tree',side_effect=lambda repo,*args:trees['game'if repo.name=='game'else'content']),mock.patch.object(Path,'read_bytes',guarded):
            plan=m.make_plan(scope,'c'*64,{'game':revision,'content':revision},{'game':root/'game','content':root/'content'})
        self.assertEqual(plan['counts'],{'READY_FOR_ISOLATED_OFFICIAL_COMPILE':1})
        self.assertEqual(set(plan['inputs']),set(blobs))
        self.assertEqual(plan['inputs']['panorama/styles/custom_game/a.css']['compiler_input'],m.checks(blobs['panorama/styles/custom_game/a.css'].replace(b'\n',b'\r\n')))
        self.assertEqual(plan['inputs']['panorama/videos/custom_game/map.webm']['game_author']['path'],'panorama/videos/custom_game/map.webm')
        self.assertFalse(plan['publication_ready'])

    def test_cli_requires_immutable_operator_before_reading_scope(self):
        with mock.patch.object(m,'read_json')as read,mock.patch('sys.stderr'):
            with self.assertRaises(SystemExit):m.main(['plan','--scope','x','--scope-sha256','a'*64,'--game-source','b'*40,'--content-source','c'*40,'--out','x'])
            read.assert_not_called()

    def test_loaded_operator_bytes_must_match_commit_not_only_later_disk(self):
        def git(repo,*args):return (m.ROOT/args[-1].split(':',1)[1]).read_bytes()
        with mock.patch.object(m,'immutable'),mock.patch.object(m,'run_git',side_effect=git):
            binding=m.operator_binding('a'*40)
            self.assertEqual(binding['revision'],'a'*40)
            with mock.patch.object(m,'EXECUTED_INVENTORY_LF_SHA256','0'*64):
                with self.assertRaisesRegex(ValueError,'loaded_operator_tool_differs'):
                    m.operator_binding('a'*40)

    def test_compiled_js_exact_data_and_native_block_bounds(self):
        source=b'var immutable=true;\r\n'
        artifact=struct.pack('<IHHII4sII',28+len(source),12,1,8,1,b'DATA',8,len(source))+source
        proof=m.compiled_binding('panorama/scripts/a.vjs_c',artifact,source)
        self.assertTrue(proof['compiled_js_DATA_equals_input'])
        with self.assertRaisesRegex(ValueError,'compiled_js_data_differs'):
            m.compiled_binding('panorama/scripts/a.vjs_c',artifact,source.replace(b'true',b'null'))
        with self.assertRaisesRegex(ValueError,'header_invalid'):
            m.compiled_binding('panorama/scripts/a.vjs_c',artifact+b'garbage',source)
        corrupted=bytearray(artifact);struct.pack_into('<I',corrupted,20,len(artifact)+1)
        with self.assertRaisesRegex(ValueError,'block_invalid'):
            m.compiled_binding('panorama/scripts/a.vjs_c',bytes(corrupted),source)

    def test_scope_never_treats_history_or_unknown_as_compiled(self):
        rows=m.selected_rows({'decisions':[{'resource':'panorama/a.vjs_c','inventory_status':'UNBOUND_COMPILED_ARTIFACT','review_decision':'IMMUTABLE_AUTHORS_AVAILABLE_RECOMPILE_OR_VALIDATE_EMBEDDED_BINDING'}, {'resource':'panorama/b.vjs_c','review_decision':'LOCAL_HISTORICAL_MANIFEST_BYTES_MATCH_INPUT_BINDING_STILL_REQUIRED'}, {'resource':'panorama/c.vsvg_c','inventory_status':'UNMAPPED_SOURCE_PENDING'}]})
        self.assertEqual(len(rows),2);self.assertTrue(all('status'not in r for r in rows))

    def test_texture_image_payload_follows_bounded_resource_metadata(self):
        data=b'actual texture metadata'
        metadata=struct.pack('<IHHII4sII',28+len(data),12,1,8,1,b'DATA',8,len(data))+data
        pixels=b'\x01\x02\x03\xff'*16
        proof=m.compiled_binding('panorama/images/a.vtex_c',metadata+pixels,b'vtex recipe')
        self.assertEqual(proof['resource_metadata_bytes'],len(metadata))
        self.assertEqual(proof['texture_external_payload_bytes'],len(pixels))
        self.assertEqual(proof['texture_external_payload_sha256'],m.sha(pixels))
        with self.assertRaisesRegex(ValueError,'header_invalid'):
            m.compiled_binding('panorama/images/a.vsvg_c',metadata+pixels,b'svg')
        # A block cannot use image payload bytes to escape its metadata bounds.
        malformed=bytearray(metadata+pixels);struct.pack_into('<I',malformed,24,len(data)+1)
        with self.assertRaisesRegex(ValueError,'block_invalid'):
            m.compiled_binding('panorama/images/a.vtex_c',bytes(malformed),b'vtex recipe')

if __name__=='__main__':unittest.main()
