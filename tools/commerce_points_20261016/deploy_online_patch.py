"""Offline, exact-hash patch for the reviewed online service; no deployment or network.

Supports only the downloaded cd6c baseline, preserving every outside byte and
mixed line ending. Writes a new output exclusively; reverse requires exact
patched hash and restores exact baseline bytes.
"""
from pathlib import Path
import argparse,ast,hashlib,json
BASELINE_SHA256='cd6c95a9ec829ade90401dbbd3484ada39ea43adaf789e404f82079ca6067ca6'
PATCHED_SHA256='3f87fd4b219c20fedac5176c2ea7153f4e639dced48badc571781019755b6993'
HUNKS=[{'id': 'starjoy_progress_receipt_key', 'old': b'        database_id=self.app._database_account_id(account)\r\n        self.app._ensure_gameplay_stats(database_id)\r\n        fingerprint=hashlib.sha256(json.dumps(command,sort_keys=True,separators=(",",":"),ensure_ascii=False).encode()).hexdigest()\r\n', 'new': b'        database_id=self.app._database_account_id(account)\r\n        self.app._ensure_gameplay_stats(database_id)\r\n        if command[\'kind\'] == \'starjoy_reconcile\':\r\n            # Cash grants can cross several tiers during one match. Derive a\r\n            # stable receipt from saved progress, never a client-supplied score.\r\n            # profile() also resolves earlier pending operations before reading.\r\n            trusted = self.profile({\'account_id\': account})\r\n            stats = trusted.get(\'save\', {}).get(\'gameplay_stats\', {})\r\n            score = max(0, *(int(stats.get(key) or 0) for key in\r\n                            (\'starjoy_points_earned\', \'starjoy_points\')))\r\n            command[\'id\'] += \':earned:\' + str(score)\r\n        fingerprint=hashlib.sha256(json.dumps(command,sort_keys=True,separators=(",",":"),ensure_ascii=False).encode()).hexdigest()\r\n'}, {'id': 'pause_uncommitted_shop_gold_online', 'old': b'            result=reducer.settle(profile,command,prepared["has_pass"])\r\n', 'new': b'            product = self.bundle.tables.get(\'commerce_catalog\', {}).get(command.get(\'sku\'), {})\r\n            if command[\'kind\'] == \'commerce_purchase\' and product.get(\'currency\') == \'shop_gold\':\r\n                # A currency pause applies to uncommitted older-client intents too.\r\n                # Completed receipts already returned above and remain immutable.\r\n                result = {\'ok\': False, \'error\': \'shop_gold_not_open\'}\r\n            else:\r\n                result=reducer.settle(profile,command,prepared["has_pass"])\r\n'}, {'id': 'snapshot_matches_recorded_lottery_currency', 'old': b'        projected=self.settle(profile,{"id":"lottery_snapshot","kind":"lottery_snapshot"},False)\r\n', 'new': b'        reducer=self\r\n        if requested_hash != self.bundle.hash:\r\n            # Advertise the same currency/rates that this client\'s recorded\r\n            # draw reducer uses, until the game joins the new bundle version.\r\n            reducer=ArchiveService(self.app,Bundle(self.bundle.directory.parent/requested_hash),self.lua)\r\n        projected=reducer.settle(profile,{"id":"lottery_snapshot","kind":"lottery_snapshot"},False)\r\n'}]

def sha(raw):return hashlib.sha256(raw).hexdigest()

def transform(raw,reverse=False):
    expected=PATCHED_SHA256 if reverse else BASELINE_SHA256
    if sha(raw)!=expected:raise ValueError('source_sha256_mismatch_refuse_patch')
    result=raw
    for hunk in reversed(HUNKS) if reverse else HUNKS:
        old=hunk['new'] if reverse else hunk['old']
        new=hunk['old'] if reverse else hunk['new']
        if result.count(old)!=1:raise ValueError('exact_context_mismatch:'+hunk['id'])
        result=result.replace(old,new,1)
    target=BASELINE_SHA256 if reverse else PATCHED_SHA256
    if sha(result)!=target:raise ValueError('patched_sha256_mismatch')
    ast.parse(result.decode('utf-8'))
    compile(result.decode('utf-8'),'<reviewed-online-service>','exec')
    return result

def main():
    ap=argparse.ArgumentParser(description='No network, activation, or in-place writes. Exact cd6c reviewed online baseline only.')
    ap.add_argument('--source',type=Path,required=True)
    ap.add_argument('--output',type=Path)
    ap.add_argument('--reverse',action='store_true')
    a=ap.parse_args();raw=a.source.read_bytes();result=transform(raw,a.reverse)
    assert transform(result,not a.reverse)==raw,'reverse_not_byte_exact'
    if a.output:
        if a.output.resolve()==a.source.resolve():raise ValueError('in_place_write_refused')
        if a.output.exists():raise ValueError('output_already_exists')
        with a.output.open('xb') as handle:handle.write(result)
    print(json.dumps({'status':'PASS','source_sha256':sha(raw),'output_sha256':sha(result),
        'reverse':a.reverse,'reverse_byte_exact':True,'compiled_in_memory':True,
        'written':str(a.output) if a.output else None,'deployment_performed':False,'external_requests':0}))
if __name__=='__main__':main()
