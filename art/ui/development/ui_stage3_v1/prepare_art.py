import csv,json
from pathlib import Path
root=Path(__file__).resolve().parents[4]
rows=[r for r in csv.DictReader((root/'data/csv/肉鸽奖励系统/rogue_reward_cards.csv').open(encoding='utf-8-sig')) if not r['card_id'].startswith('#')]
base='Use case: stylized-concept. Production game asset: one high resolution portrait 2:3 illustration, isolated on genuinely transparent alpha. Mature fantasy RPG painterly item illustration, refined champagne gold, jade ivory and deep teal materials, with restrained subject-specific colors. Large centered readable silhouette with delicate craft details, fits within central 80 percent and 8 percent transparent margins. Subject fills height, clean transparent contour, no ground rectangle, no checkerboard. This image goes INSIDE an existing gold/ivory card: do not draw any card frame, border, lettering, numbers, UI, logos or labels. No existing game icon copied. '
prompts=[dict(id=r['card_id'],name=r['display_name'],enabled=r['enabled']=='1',type=r['type'],description=r['description'],prompt=base+'Illustrate the concept '+r['display_name']+' ('+r['card_id']+'). Meaning from the actual game configuration, for visual symbolism only, DO NOT DRAW ANY TEXT OR NUMBERS: '+r['description']+' Give this concept its own specific subject, avoid substituting a generic star or gem.') for r in rows]
(root/'art/ui/development/ui_stage3_v1/art/prompts.json').write_text(json.dumps(prompts,ensure_ascii=False,indent=2),encoding='utf-8')
print(f'{len(prompts)} prompts from actual configuration; {sum(r["enabled"] for r in prompts)} active')
