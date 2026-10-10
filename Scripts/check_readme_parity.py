#!/usr/bin/env python3
"""Check seven-language quick-start structure, exact examples and local links.

This is a static guard, not a Swift compiler or a linguistic quality review.
"""
from pathlib import Path
import re
import sys

root = Path(__file__).resolve().parents[1]
files = [root / name for name in ('README.md', 'README.ko.md', 'README.es.md',
    'README.de.md', 'README.zh-Hans.md', 'README.ja.md', 'README.ru.md')]
errors = []
canonical = re.findall(r'```(?:swift|bash)\n(.*?)```', files[0].read_text(encoding='utf-8'), re.S)
for path in files:
    if not path.exists():
        errors.append(f'Missing {path.name}')
        continue
    text = path.read_text(encoding='utf-8')
    if re.findall(r'<!-- section:(\d+) -->', text) != [str(i) for i in range(1, 8)]:
        errors.append(f'{path.name}: expected seven ordered sections')
    if re.findall(r'```(?:swift|bash)\n(.*?)```', text, re.S) != canonical:
        errors.append(f'{path.name}: examples differ from English baseline')
    for sibling in files:
        if f']({sibling.name})' not in text:
            errors.append(f'{path.name}: missing language link {sibling.name}')
    if '/releases/tag/6.1.1' not in text:
        errors.append(f'{path.name}: missing stable release link')
# Check all Markdown paths, including historical evidence. External reachability
# and DocC symbol resolution are deliberately outside this no-network check.
count = 0
for path in list(root.glob('*.md')) + list((root / 'docs').rglob('*.md')):
    for target in re.findall(r'\]\(([^)\s]+)(?:\s+"[^"]*")?\)', path.read_text(encoding='utf-8')):
        if re.match(r'[a-zA-Z][\w+.-]*:', target) or target.startswith('#'):
            continue
        target = target.split('#', 1)[0]
        if not target:
            continue
        count += 1
        if not (path.parent / target).exists():
            errors.append(f'{path.relative_to(root)}: missing local target {target}')
if errors:
    print('\n'.join(errors), file=sys.stderr)
    sys.exit(1)
print(f'readme parity: OK (7 languages, {len(canonical)} shared code blocks, {count} local links)')
