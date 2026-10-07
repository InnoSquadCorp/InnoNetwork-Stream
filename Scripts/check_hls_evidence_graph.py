#!/usr/bin/env python3
"""Bind the exporter's active SwiftPM graph and clean remote checkouts to the root lock."""
import argparse
import json
from pathlib import Path
import subprocess


def check(root, graph):
    root=root.resolve()
    pins={p['identity']:p for p in json.loads((root/'Package.resolved').read_text())['pins']}
    seen={}
    saw_stream=False
    def walk(node):
        nonlocal saw_stream
        for dep in node.get('dependencies',[]):
            path=Path(dep['path']).resolve()
            if path==root:
                saw_stream=True
            else:
                pin=pins.get(dep['identity'])
                if not pin or dep.get('url')!=pin['location'] or dep.get('version')!=pin['state']['version']:
                    raise ValueError('exporter active remote dependency differs from root lock')
                revision=subprocess.check_output(['git','-C',str(path),'rev-parse','HEAD'],text=True).strip()
                if revision!=pin['state']['revision']:
                    raise ValueError('exporter dependency checkout revision differs')
                dirty=subprocess.check_output(['git','--no-optional-locks','-C',str(path),'status','--porcelain','--untracked-files=all'],text=True)
                if dirty:
                    raise ValueError('exporter dependency checkout is dirty')
                subprocess.run(['git','-C',str(path),'fsck','--no-dangling','--connectivity-only'],check=True,
                               stdout=subprocess.DEVNULL,stderr=subprocess.PIPE)
                seen[dep['identity']]=pin
            walk(dep)
    walk(graph)
    if not saw_stream or 'innonetwork' not in seen:
        raise ValueError('exporter did not use this Stream checkout and published Core')
    return {'source_commit':subprocess.check_output(['git','-C',str(root),'rev-parse','HEAD'],text=True).strip(),
            'active_clean_pins':[seen[key] for key in sorted(seen)]}


if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--root',type=Path,required=True);p.add_argument('--graph',type=Path,required=True)
    a=p.parse_args()
    print(json.dumps(check(a.root,json.loads(a.graph.read_text())),sort_keys=True))
