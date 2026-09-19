from pathlib import Path
import argparse
import sys
root=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(root/"server"))
from archive_backend.bundle import build
if __name__ == "__main__":
    parser=argparse.ArgumentParser(description="Build immutable archive settlement bundle")
    parser.add_argument("--output", type=Path)
    parser.add_argument("--no-game-config", action="store_true", help="Do not change the running game's bundle hash")
    args=parser.parse_args()
    print("ARCHIVE_BUNDLE_BUILT",build(root,args.output,not args.no_game_config))
