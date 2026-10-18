"""Verify the immutable one-file candidate without contacting any server."""
from pathlib import Path
import ast
import copy
import hashlib
import json
import shutil
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'output/shop_promo_gcoin_20261018/hosted_checkout'


def script(path):
    tree = ast.parse(path.read_bytes())
    return next(node.value.value for node in tree.body if isinstance(node, ast.Assign)
        and any(isinstance(target, ast.Name) and target.id == 'JS' for target in node.targets))


class CheckoutCandidateTests(unittest.TestCase):
    def test_manifest_has_only_the_reviewed_service_change(self):
        plan = json.loads((OUT / 'release/plan.json').read_bytes())
        base = json.loads((OUT / 'baseline/manifest.json').read_bytes())
        folder = OUT / 'release' / plan['candidate']
        candidate = json.loads((folder / 'manifest.json').read_bytes())
        self.assertEqual(set(candidate), set(base))
        self.assertEqual([name for name in candidate if base[name] != candidate[name]], ['payment_backend/service.py'])
        for name, digest in candidate.items():
            self.assertEqual(hashlib.sha256((folder / name).read_bytes()).hexdigest(), digest)
        before = ast.parse((OUT / 'baseline/payment_backend/service.py').read_bytes())
        after = ast.parse((folder / 'payment_backend/service.py').read_bytes())
        for tree in (before, after):
            for node in tree.body:
                if isinstance(node, ast.Assign) and any(isinstance(target, ast.Name) and target.id == 'JS' for target in node.targets):
                    node.value = ast.Constant('hosted checkout display script')
        self.assertEqual(ast.dump(before, include_attributes=False), ast.dump(after, include_attributes=False))

    @unittest.skipUnless(shutil.which('node'), 'Node is required for the browser-free script regression')
    def test_visible_title_changes_without_modifying_frozen_status_payloads(self):
        plan = json.loads((OUT / 'release/plan.json').read_bytes())
        scripts = dict(before=script(OUT / 'baseline/payment_backend/service.py'),
            after=script(OUT / 'release' / plan['candidate'] / 'payment_backend/service.py'))
        cases = []
        for title in ('U币充值', 'U币礼包 · 赠送U币', '签到月卡（30天）'):
            for state in ('pending', 'delivered'):
                cases.append(dict(title=title, state=state, provider='wechat', amount_fen=5800,
                    order_id='synthetic_display_only', expired=False))
        runner=r'''const fs=require("node:fs"),vm=require("node:vm");
const payload=JSON.parse(fs.readFileSync(0,"utf8"));
function freeze(value){if(value&&typeof value==="object"){Object.values(value).forEach(freeze);Object.freeze(value);}}
async function render(source,input){const response=JSON.parse(JSON.stringify(input)),nodes={};freeze(response);
const before=JSON.stringify(response),element=id=>nodes[id]||(nodes[id]={textContent:"",style:{}});
vm.runInNewContext(source,{location:{search:"?synthetic=test"},document:{getElementById:element},
setInterval:()=>0,fetch:()=>Promise.resolve({ok:true,json:()=>Promise.resolve(response)})});
await new Promise(setImmediate);return {title:element("title").textContent,status:element("status").textContent,
price:element("price").textContent,order:element("order").textContent,unchanged:JSON.stringify(response)===before};}
(async()=>{const rows=[];for(const input of payload.cases)rows.push({
before:await render(payload.scripts.before,input),after:await render(payload.scripts.after,input)});
process.stdout.write(JSON.stringify(rows));})();'''
        original = copy.deepcopy(cases)
        result = subprocess.run([shutil.which('node'), '-e', runner], input=json.dumps(dict(scripts=scripts,cases=cases), ensure_ascii=False),
            text=True, encoding='utf-8', capture_output=True, timeout=15, check=True)
        rows = json.loads(result.stdout)
        self.assertEqual(len(rows), 6)
        for row in rows:
            self.assertTrue(row['before']['unchanged'] and row['after']['unchanged'])
            expected = copy.deepcopy(row['before'])
            for field in ('title', 'status'):
                expected[field] = expected[field].replace('U币', 'G币')
            self.assertEqual(row['after'], expected)
            self.assertEqual(row['after']['price'], '¥58.00')
        self.assertEqual(cases, original)


if __name__ == '__main__':
    unittest.main()
