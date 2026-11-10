"""Independent re-derivation of the pure projection, never package authority."""
from pathlib import Path
import sys
TOOLS = Path(__file__).resolve().parents[1]
if str(TOOLS) not in sys.path:
    sys.path.insert(0, str(TOOLS))
from complete_delivery_pack_2026111005_53969b import build_release, ledger

def validate_projection(report, **inputs):
    expected = build_release.project(**inputs)
    ledger.need(ledger.canonical(report) == ledger.canonical(expected), 'complete_projection_differs_from_independent_rederivation')
    ledger.need(report['coverage_ledger']['coverage_complete'] is True and (not report['publication_ready']) and (not report['signature_valid']) and (not report['signed_package']), 'projection_cannot_claim_signed_or_published_authority')
    return {'status': 'COMPLETE_DECLARED_PROJECTION_REDERIVED_NOT_PACKAGE_AUTHORITY', 'projection_sha256': expected['projection_sha256'], 'source_revisions': expected['source_revisions'], 'files': expected['files'], 'coverage_complete': True, 'signature_verified': False, 'native_admission_verified': False, 'publication_ready': False}

def validate_release(*args, **kwargs):
    raise ValueError('complete_signed_package_and_native_release_validator_not_implemented_preserve_pending')

def validate_bootstrap(*args, **kwargs):
    raise ValueError('complete_canonical_parent_authority_adapter_not_implemented_preserve_journal')
