#!/usr/bin/env python3
"""Bind the exporter's active SwiftPM graph and clean remote checkouts to the root lock."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess


def check(root, graph):
    root=root.resolve()
    pins={p['identity']:p for p in json.loads((root/'Package.resolved').read_text())['pins']}
    seen={}
    checked_paths={}
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
                identity=dep['identity']
                if identity in checked_paths:
                    if checked_paths[identity] != path:
                        raise ValueError('duplicate dependency identity uses another checkout')
                    walk(dep)
                    continue
                checked_paths[identity]=path
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


def digest(path):
    hasher = hashlib.sha256()
    with path.open('rb') as handle:
        for chunk in iter(lambda: handle.read(65536), b''):
            hasher.update(chunk)
    return hasher.hexdigest()


def prepare(root, graph_path, binary):
    root, binary = root.resolve(), binary.resolve(strict=True)
    if not binary.is_file():
        raise ValueError('missing compiled exporter')
    result = check(root, json.loads(graph_path.read_text()))
    result.update(binary_path=str(binary), binary_sha256=digest(binary),
                  graph_sha256=digest(graph_path),
                  candidate_lock_sha256=digest(root/'Package.resolved'),
                  consumer_lock_sha256=digest(root/'Tests/HLSReleaseEvidence/Package.resolved'))
    return result


def verify_prepared(root, graph_path, prepared):
    expected = json.loads(prepared.read_text())
    actual = prepare(root, graph_path, Path(expected['binary_path']))
    if actual != expected:
        raise ValueError('prepared exporter, source, lock or active graph changed; prepare again')
    return actual


if __name__=='__main__':
    p=argparse.ArgumentParser()
    p.add_argument('--root',type=Path,required=True)
    p.add_argument('--graph',type=Path,required=True)
    mode=p.add_mutually_exclusive_group()
    mode.add_argument('--binary',type=Path)
    mode.add_argument('--prepared',type=Path)
    a=p.parse_args()
    if a.prepared:
        result=verify_prepared(a.root,a.graph,a.prepared)
    elif a.binary:
        result=prepare(a.root,a.graph,a.binary)
    else:
        result=check(a.root,json.loads(a.graph.read_text()))
    print(json.dumps(result,sort_keys=True))
