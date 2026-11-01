"""Revalidate immutable3102 parent and exact signed six-path admission child."""
from pathlib import Path
import re
import build_release as build

def validated_package(report_sha256,*,full=False):
 b=build;path=b.REPORT/'package.json'
 b.need(re.fullmatch(r'[0-9a-f]{64}',report_sha256 or '') and b.pack.runtime.digest(path)==report_sha256,'Exact completed report SHA required')
 report=b.load(path)
 b.need(report['status']=='BUILT_SIGNED_FIVE_ACCOUNT_PENDING_NATIVE_AND_SERVER' and report['signature_valid'] is True
  and report['full_runtime_validator_passed'] is True and report['dry_run'] is False and report['payload_changed'] is False
  and report['release_sequence']==b.SEQUENCE and report['workshop_upload_performed'] is False,'Completed immutable five-account package required')
 for n,pin in report['auxiliary_input_pins'].items():b.need(b.checks((b.ROOT/n).read_bytes())==pin,'Frozen operator dependency drift: '+n)
 # Parent authenticates in its original four-account context; no historical guard is weakened.
 base,old=b.baseline(full=full,require_current_journal=False)
 values,bindings,diffs=b.payloads(report['source_revision'])
 after,changed=b.legacy.projected(old,values)
 b.need(set(changed)==set(b.PAYLOADS) and report['target_pins']=={n:b.checks(v) for n,v in sorted(values.items())}
  and report['source_bindings']==bindings and report['reviewed_runtime_diff']==diffs,'Exact reviewed six-file projection required')
 b.need(report['approved_steamids64']==list(b.APPROVED) and report['added_steamid64']==b.ADDED and report['max_players']==4,'Admission scope drift')
 manifest,document,_=b.inc.metadata(b.VIEW)
 b.need(manifest==after and manifest['content_sha256']==report['content_sha256'] and manifest['file_count']==6917,'Signed child manifest differs')
 with b.scene_maps(),b.admission_context(values),b.inc.trusted_source(b.TRUSTED):
  policy,public=b.pack.handoff.trusted_policy(b.pack.handoff.POLICY)
  signature=b.pack.verify_signed_snapshot(manifest,document,public,policy['integrity']['minimum_release_sequence'],policy['integrity']['trusted_key_id'])
  b.pack.handoff.require_single_map(b.VIEW)
  b.pack.handoff.require_reviewed_gate(b.VIEW,manifest)
  b.need(b.pack.handoff.configured_ids(b.VIEW)==sorted(b.APPROVED),'Signed roster must contain exact five IDs')
  if full:
   _,checked,signed,_=b.pack.authenticate(b.VIEW)
   b.need(checked==manifest and signed==signature,'Full signed candidate authentication failed')
 b.need(signature['release_sequence']==b.SEQUENCE,'Wrong new signed sequence')
 expected=b.trusted_reviews(base,values)
 b.need(report['trusted_review_pins']==expected,'Trusted18 review scope drift')
 for n,pin in expected.items():b.need(b.checks((b.TRUSTED/n).read_bytes())==pin,'Explicit review source changed: '+n)
 allowed={'output/release_test_handoff/'+b.ADDON+'/'+n for n in (b.pack.handoff.MANIFEST,b.pack.handoff.SIGNATURE,'handoff.json')}
 b.need(b.inc.all_files(b.TRUSTED)-set(expected)<=allowed,'Unknown trusted-source additions')
 if full:
  b.need(b.pack.package_inventory(b.OUTPUT/(b.ITEM+'.vpk'))==report['package_files'],'Final VPK inventory drift')
  with b.scene_maps():b.pack.verify_vpk(b.OUTPUT/(b.ITEM+'.vpk'),manifest)
 return report,manifest,signature
