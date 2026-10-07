#!/usr/bin/env python3
"""Produce independent coherent release states; never assume the host is Draft."""
import argparse
from pathlib import Path
import shutil


def create(root: Path, state: str, version: str = '6.1.1'):
    major = version.split('.')[0]
    files = {
        'RELEASE_VERSION': version+'\n',
        'docs/ROADMAP.md': '# Roadmap\n## Release Boundary\n## Follow-up Scope\n',
        'README.md': '[Roadmap](docs/ROADMAP.md)\n'+f'`{version}` is '+(
            'an unpublished release candidate.\n' if state=='draft' else 'ready for publication.\n'),
        'API_STABILITY.md': f'# API Stability ({major}.x'+(' candidate' if state=='draft' else '')+')\n',
        'SECURITY.md': f'After publication, the latest `{major}.x` minor is the actively supported line.\n',
        'CHANGELOG.md': '# Changelog\n'+('' if state=='draft' else f'## [{version}] - 2026-10-07\n'),
        f'docs/releases/{version}.md': f'<!-- release-status: {state} -->\n'+(
            'Status: Release candidate (unpublished)\nRelease date: Not scheduled\n' if state=='draft'
            else 'Status: Ready for release\nRelease date: 2026-10-07\n'),
    }
    for name,value in files.items():
        file=root/name;file.parent.mkdir(parents=True,exist_ok=True);file.write_text(value)
    scripts=root/'Scripts';scripts.mkdir(exist_ok=True)
    source=Path(__file__).resolve().parents[1]
    shutil.copyfile(source/'validate_docs_release_state.sh',scripts/'validate_docs_release_state.sh')


if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('root',type=Path);p.add_argument('state',choices=['draft','ready']);p.add_argument('--version',default='6.1.1')
    a=p.parse_args();create(a.root,a.state,a.version)
