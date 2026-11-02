"""Exact0203 official-download adapter; zero-effect default, no upload API."""
from pathlib import Path
import importlib.util

HERE=Path(__file__).resolve().parent
_s=importlib.util.spec_from_file_location('snapshot0203_download_adapt',HERE/'adapt.py')
a=importlib.util.module_from_spec(_s);_s.loader.exec_module(a)
impl=a.frozen('verify_download','cc10665eade3591c6355bf8b1e6429c1b8e9ede8d6b65dbe515cb7e023ed7004')
checks=a.local('release_checks');impl.checks=checks;impl.b=checks.b;impl.need=checks.b.need
for _name in ('require_family_identity','validated_package'):
    changes=[('== 2026110202','== 2026110301'),('len(b.PAYLOADS) == 4','len(b.PAYLOADS) == 8')]
    if _name=='validated_package':changes.append((')) == 19',')) == 22'))
    a.function(impl,_name,changes)
_parent_plan=impl.static_plan


def static_plan():
    result=_parent_plan();result.update(status='STATIC_SNAPSHOT0203_OFFICIAL_DOWNLOAD_PLAN_NO_EFFECTS',
        release_sequence=2026110301,scoped_runtime_paths=8,trusted_reviews=22)
    return result


impl.static_plan=static_plan
def __getattr__(name):return getattr(impl,name)
if __name__=='__main__':raise SystemExit(impl.main())
