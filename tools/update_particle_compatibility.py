"""Migrate obsolete lifetime/rotation initializers in addon particle sources.

Field IDs and degree units match the installed native Monkey King particles.
Run with --write, then compile the printed sources with resourcecompiler.
"""
import argparse
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CONTENT = ROOT.parents[2] / "content/dota_addons/Survival"
BLOCK = re.compile(r'(?m)^(\s*)\{\s*\n\s*_class = "(C_INIT_RandomLifeTime|C_INIT_RandomRotation|C_INIT_RandomRotationSpeed)"\s*\n([^{}]*)\}')


def migrate(text):
    def replace(match):
        indent, kind, body = match.groups()
        indent = indent.lstrip("\r\n")
        fields = dict(re.findall(r'(\w+)\s*=\s*([^\s]+)', body))
        if kind == "C_INIT_RandomLifeTime":
            low = fields.pop("m_fLifetimeMin", "1.0")
            high = fields.pop("m_fLifetimeMax", "1.0")
            field, flip = 1, None
        else:
            low = fields.pop("m_flDegreesMin", "0.0")
            high = fields.pop("m_flDegreesMax", "360.0")
            field = 5 if kind.endswith("Speed") else 4
            flip = fields.pop("m_bRandomlyFlipDirection", "true")
        if fields:
            raise ValueError(f"Unmapped {kind} fields: {fields}")
        lines = ["{", '\t_class = "C_INIT_InitFloat"', f"\tm_nOutputField = {field}",
                 "\tm_InputValue =", "\t{"]
        if float(low) == float(high) and flip != "true":
            lines += ['\t\tm_nType = "PF_TYPE_LITERAL"', f"\t\tm_flLiteralValue = {low}"]
        else:
            lines += ['\t\tm_nType = "PF_TYPE_RANDOM_UNIFORM"',
                      f"\t\tm_flRandomMin = {low}", f"\t\tm_flRandomMax = {high}",
                      '\t\tm_nRandomMode = "PF_RANDOM_MODE_CONSTANT"']
        if flip is not None:
            lines += [f"\t\tm_bHasRandomSignFlip = {flip}"]
        lines += ["\t}", "}"]
        return indent + ("\n" + indent).join(lines)
    return BLOCK.sub(replace, text)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--write", action="store_true")
    args = parser.parse_args()
    count = 0
    for path in sorted((CONTENT / "particles").rglob("*.vpcf")):
        old = path.read_text(encoding="utf-8-sig")
        new = migrate(old)
        if old == new:
            continue
        if args.write:
            path.write_text(new, encoding="utf-8", newline="\n")
        print(path.relative_to(CONTENT))
        count += 1
    print(f"{'Updated' if args.write else 'Pending'}: {count}")


if __name__ == "__main__":
    main()
