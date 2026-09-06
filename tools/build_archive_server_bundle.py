from pathlib import Path
import sys
root=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(root/"server"))
from archive_backend.bundle import build
print("ARCHIVE_BUNDLE_BUILT",build(root))
