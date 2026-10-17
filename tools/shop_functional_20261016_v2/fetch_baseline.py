"""Read-only pinned public baseline for the functional shop expansion."""
from pathlib import Path
import importlib.util
ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('prior_fetch',ROOT/'tools/shop_catalog_20261016/fetch_baseline.py')
module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
module.OUT=ROOT/'design_refs/shop_functional_20261016/deployment_v2'
if __name__=='__main__':module.main()
