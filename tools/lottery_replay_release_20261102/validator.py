"""Read-only authority for0203: the UI hotfix plus the reviewed archive wire fix.

Only a SHA-pinned private0202 adapter is reused. Every source transformation
has one exact match; the old file, policy and runtime acceptance remain intact.
Import is metadata-only, never a package/native/SDK operation.
"""
from pathlib import Path
import hashlib
from types import ModuleType

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
PARENT = ROOT / "tools/lottery_hotfix_release_20261102/validator.py"
PARENT_SHA256 = "70fb19bc302967dd527e28e80eca58a00d63254a11d6766a2e23d909835b716b"
NATIVE_ADMISSION_SHA256 = "f1e88a6f688bd7c3256bde1b1e20b9f4e6faf93c81e21b6fee3f3763aed3482c"

raw = PARENT.read_bytes()
if hashlib.sha256(raw).hexdigest() != PARENT_SHA256:
    raise ValueError("Frozen0202 authority adapter changed")
source = raw.decode("utf-8")
TRANSFORMS = (
    ("RELEASE_SEQUENCE = 2026110202", "RELEASE_SEQUENCE = 2026110204"),
    ('    "scripts/vscripts/ui/ui_request_router.lua",\n))',
     '    "scripts/vscripts/ui/ui_request_router.lua",\n    "scripts/vscripts/systems/archive_service.lua",\n    "scripts/vscripts/systems/archive_http_adapter.lua",\n    "scripts/vscripts/systems/lottery_http_service.lua",\n))'),
    ('NATIVE_ADMISSION_SHA256 = "935f0958a188dce736baa08282b3b4cd2cd30794767ddb9e8060527600c7a8ab"',
     "NATIVE_ADMISSION_SHA256 = _REGISTERED_NATIVE_SHA256"),
    ("canonical_lottery_hotfix_0202_builder", "canonical_lottery_snapshot_0203_builder"),
    ("canonical_lottery_hotfix_0202_checks", "canonical_lottery_snapshot_0203_checks"),
    ("lottery_hotfix_0202_native_admission", "lottery_snapshot_0203_native_admission"),
    ("Exact four-resource hotfix recipe required", "Exact seven-resource replay recipe required"),
    ("Only this exact four-resource candidate sequence is registered", "Only this exact seven-resource candidate sequence is registered"),
    ("BUILT_SIGNED_PENDING_NATIVE_LOTTERY_ACCEPTANCE", "BUILT_SIGNED_PENDING_NATIVE_LOTTERY_SNAPSHOT_ACCEPTANCE"),
    ('len(report.get("trusted_review_pins", {})) == 19', 'len(report.get("trusted_review_pins", {})) == 22'),
    ("Exact four-resource, two-compiled, nineteen-review signed hotfix required",
     "Exact seven-resource, two-compiled, twenty-two-review signed replay hotfix required"),
    ("# Parent18 already contains ui_request_router: replace that review and add\n    # production_ui_service, preserving the other17. Two updates yield19 keys.",
     "# Parent18 contains router: preserve17, replace router and add production\n    # plus archive_service. Three explicitly scoped updates yield20 keys."),
)
for old, new in TRANSFORMS:
    if source.count(old) != 1:
        raise ValueError("Frozen0202 authority transform no longer matches exactly once")
    source = source.replace(old, new)

p = ModuleType("lottery_snapshot_0203_private_authority")
p.__file__ = str(Path(__file__).resolve())
p.__dict__["_REGISTERED_NATIVE_SHA256"] = NATIVE_ADMISSION_SHA256
exec(compile(source, str(PARENT) + "::verified0203", "exec"), p.__dict__)
RELEASE_SEQUENCE = p.RELEASE_SEQUENCE
PAYLOADS = p.PAYLOADS
OWNER, APP = p.OWNER, p.APP
NATIVE_ADMISSION_MODULE = p.NATIVE_ADMISSION_MODULE
context = p.context
validate_bootstrap = p.validate_bootstrap
validate_release = p.validate_release
same_plan = p.same_plan


def __getattr__(name):
    return getattr(p, name)
