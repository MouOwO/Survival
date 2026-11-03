"""Compiler planning helpers only: no compiler, external file, Git or SDK writes."""
from pathlib import Path
import importlib.util,unittest

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

    def test_explicit_include_graph_and_unknown_refs(self):
        children,engine=m.dependencies('panorama/layout/x.xml',b'<root><include src="file://{resources}/scripts/custom_game/a.js"/><include src="s2r://panorama/layout/hud.vxml"/></root>')
        self.assertEqual(children,['panorama/scripts/custom_game/a.js']);self.assertEqual(engine,['s2r://panorama/layout/hud.vxml'])
        with self.assertRaises(ValueError):m.dependencies('panorama/layout/x.xml',b'<include src="../../escape.xml"/>')

    def test_scope_never_treats_history_or_unknown_as_compiled(self):
        rows=m.selected_rows({'decisions':[{'resource':'panorama/a.vjs_c','inventory_status':'UNBOUND_COMPILED_ARTIFACT','review_decision':'IMMUTABLE_AUTHORS_AVAILABLE_RECOMPILE_OR_VALIDATE_EMBEDDED_BINDING'}, {'resource':'panorama/b.vjs_c','review_decision':'LOCAL_HISTORICAL_MANIFEST_BYTES_MATCH_INPUT_BINDING_STILL_REQUIRED'}, {'resource':'panorama/c.vsvg_c','inventory_status':'UNMAPPED_SOURCE_PENDING'}]})
        self.assertEqual(len(rows),2);self.assertTrue(all('status'not in r for r in rows))

if __name__=='__main__':unittest.main()
