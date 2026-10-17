"""Optional native-icon fit: schema, shared JS/adapter and Lua contracts.

Only temporary schemas and in-memory JS are evaluated. The production resource
table and generated runtime files are never changed or rebuilt by these tests.
"""
from pathlib import Path
import copy
import importlib.util
import json
import shutil
import subprocess
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[2]
SPEC=importlib.util.spec_from_file_location('resource_fit_builder',ROOT/'tools/build_item_resources.py')
BUILDER=importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(BUILDER)

def item(identity,**extra):
    return dict(id=identity,name=identity,kind='image',uri='file://{images}/items/quelling_blade.png',aliases=[],**extra)

def schema(records):
    return {'schema_version':1,'items':records}

class FitContractTests(unittest.TestCase):
    def test_fit_is_optional_and_only_contain_or_cover_is_allowed(self):
        for value in ('contain','cover',None,'','stretch',False,[]):
            with self.subTest(value=value),tempfile.TemporaryDirectory(prefix='resource-fit-schema-') as directory:
                root=Path(directory);path=root/BUILDER.SOURCE;path.parent.mkdir(parents=True)
                path.write_text(json.dumps(schema([item('fit_schema',fit=value)])),encoding='utf-8')
                if value in ('contain','cover'):
                    self.assertEqual(BUILDER.load(root)[1]['fit_schema']['fit'],value)
                else:
                    with self.assertRaisesRegex(AssertionError,'resource_fit:fit_schema'):BUILDER.load(root)
        with tempfile.TemporaryDirectory(prefix='resource-fit-default-') as directory:
            root=Path(directory);path=root/BUILDER.SOURCE;path.parent.mkdir(parents=True)
            path.write_text(json.dumps(schema([item('fit_default')])),encoding='utf-8')
            self.assertNotIn('fit',BUILDER.load(root)[1]['fit_default'])

    def test_runtime_and_lua_keep_explicit_fit_without_adding_a_default_field(self):
        source=schema([item('fit_native_rect',fit='contain',source_size=[88,64]),item('fit_default'),item('fit_explicit',fit='cover')])
        original=copy.deepcopy(source);runtime=BUILDER.runtime_rows(source)
        self.assertEqual(runtime[0]['fit'],'contain');self.assertEqual(runtime[0]['source_size'],[88,64])
        self.assertNotIn('fit',runtime[1]);self.assertEqual(runtime[2]['fit'],'cover')
        self.assertIn('["fit"]="contain"',BUILDER.lua(runtime[0]))
        self.assertNotIn('["fit"]',BUILDER.lua(runtime[1]))
        self.assertEqual(source,original,'The resource authority is not mutated by projection')

    def test_native_shape_default_resources_reuse_and_archive_adapter_share_fit(self):
        node=shutil.which('node');self.assertTrue(node,'Node.js is required for the shared runtime contract')
        source=json.loads((ROOT/BUILDER.SOURCE).read_bytes())
        fixtures=[item('fit_native_rect',fit='contain',source_size=[88,64]),
                  item('fit_default_item'),item('fit_explicit_cover',fit='cover')]
        source['items'].extend(fixtures);runtime=BUILDER.runtime_rows(source)
        js=BUILDER.JS_TEMPLATE.replace('@HASH@','isolated-fit-contract').replace('@ROWS@',json.dumps(runtime,ensure_ascii=False,separators=(',',':')))
        program=r'''
const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const input=JSON.parse(fs.readFileSync(0,'utf8')),cfg={};
const context=vm.createContext({GameUI:{CustomUIConfig:()=>cfg}});
vm.runInContext(input.js,context);vm.runInContext(input.adapter,context);
const resources=cfg.SurvivalItemResources,adapter=cfg.ArchiveV10Icons;
function icon(){return {style:{},calls:[],IsValid(){return true;},SetScaling(value){this.calls.push(value);}};}
const fit='stretch-to-fit-preserve-aspect',cover='stretch-to-cover-preserve-aspect';
let defaults=0,contained=0;
for(const row of resources.Rows()){
 const resolved=adapter.Resolve(row.id);
 assert.equal(resolved.fit,row.fit||(['image','hero'].includes(row.kind)?'cover':'contain'));
 if(!['image','hero'].includes(row.kind))continue;
 const panel=icon();resources.FillIcon(panel,{id:row.id});
 assert.equal(panel.calls.at(-1),row.fit==='contain'?fit:cover,row.id);
 if(row.fit==='contain')contained++;else if(row.fit===undefined)defaults++;
}
assert(defaults>1200,'All ordinary existing image/hero resources retain default cover');
const rect=icon();rect.__itemResourceId='fit_native_rect';
resources.FillIcon(rect);assert.equal(rect.calls.at(-1),fit,'An 88x64 icon keeps its complete shape in a square slot');
assert.equal(adapter.Resolve('fit_native_rect').fit,'contain');
resources.FillIcon(rect,{id:'fit_native_rect'});assert.equal(rect.calls.length,1,'Repeated unchanged fit does not reset scaling');
resources.FillIcon(rect,{id:'fit_default_item'});assert.equal(rect.calls.at(-1),cover,'Reusing a contained icon restores default cover');
resources.FillIcon(rect,{id:'fit_native_rect'});assert.equal(rect.calls.at(-1),fit,'Reusing again restores contain');
resources.FillIcon(rect,{id:'fit_explicit_cover'});assert.equal(rect.calls.at(-1),cover,'Explicit cover is also respected');
assert.equal(rect.calls.length,4);
assert.equal(adapter.Resolve('fit_default_item').fit,'cover');
assert.equal(adapter.Resolve('fit_explicit_cover').fit,'cover');
assert.equal(rect.style.padding,'0px');assert.equal(rect.style.margin,'0px');assert.equal(rect.style.overflow,'clip');
const invalid=icon();invalid.IsValid=()=>false;resources.FillIcon(invalid,{id:'fit_native_rect'});assert.equal(invalid.calls.length,0);
process.stdout.write(JSON.stringify({status:'PASS',default_images:defaults,contained_images:contained,reuse_transitions:4}));
'''
        result=subprocess.run([node,'-e',program],input=json.dumps({'js':js,'adapter':BUILDER.ARCHIVE_ADAPTER},ensure_ascii=False),
            text=True,encoding='utf-8',capture_output=True,check=False)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        self.assertEqual(json.loads(result.stdout)['status'],'PASS')

if __name__=='__main__':unittest.main()
