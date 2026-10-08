#!/usr/bin/env python3
"""Collect local Apple-tool evidence; verify maintainer-approved evidence in CI.

Approval is supplied OUTSIDE the bundle. Hashes bind bytes, not truth: a trusted
maintainer must review the real run before approving its manifest digest.
"""
from __future__ import annotations
import argparse
import datetime as dt
import hashlib
import importlib.util
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import subprocess
import sys
import tempfile
from urllib.parse import urlsplit

EVIDENCE_PREFIX = 'ReleaseEvidence/apple-hls/'
CASES = tuple(f'{mode}-{kind}' for mode in ('offline', 'dvr')
              for kind in ('transport-stream', 'fragmented-mp4', 'audio-fmp4'))
MAX_FILES, MAX_FILE, MAX_TOTAL = 2000, 64 * 1024 * 1024, 256 * 1024 * 1024
MAX_ENTRIES, MAX_DEPTH = 4000, 24
SOURCE_INPUTS = ('Tests/InnoNetworkHLSTests/HLSMediaFixtures.swift',)


def fail(message):
    raise ValueError(message)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def git(root, *args):
    return subprocess.check_output(['git', '-C', str(root), *args], stderr=subprocess.PIPE).rstrip(b'\n')


def load_json(path):
    if path.stat().st_size > MAX_FILE:
        fail('JSON exceeds byte budget')
    def unique(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                fail('duplicate JSON key')
            result[key] = value
        return result
    return json.loads(path.read_text(), object_pairs_hook=unique)


def safe_file(root, relative):
    if not isinstance(relative, str) or '\\' in relative:
        fail('invalid relative path')
    path = PurePosixPath(relative)
    if path.is_absolute() or not path.parts or any(x in ('', '.', '..') for x in path.parts):
        fail('unsafe relative path')
    if str(path) != relative:
        fail('noncanonical relative path')
    result = root
    for part in path.parts:
        result = result / part
        if result.is_symlink():
            fail('symlink in evidence')
    if not result.is_file() or result.stat().st_size > MAX_FILE:
        fail('missing or oversized evidence file')
    return result


def bounded_entries(root):
    # Bound enumeration before sorting or hashing, including empty directories.
    stack, count = [(root, 0)], 0
    while stack:
        directory, depth = stack.pop()
        with os.scandir(directory) as entries:
            for entry in entries:
                count += 1
                if count > MAX_ENTRIES or depth + 1 > MAX_DEPTH:
                    fail('evidence exceeds directory entry/depth budget')
                path = Path(entry.path)
                if entry.is_symlink():
                    fail('symlink in evidence')
                if entry.is_dir(follow_symlinks=False):
                    stack.append((path, depth + 1))
                elif not entry.is_file(follow_symlinks=False):
                    fail('nonregular evidence entry')
                yield path


def inventory(root, exclude_manifest=True):
    result, total = {}, 0
    for path in bounded_entries(root):
        if path.is_symlink():
            fail('symlink in evidence')
        if not path.is_file():
            continue
        relative = path.relative_to(root).as_posix()
        if exclude_manifest and relative == 'manifest.json':
            continue
        size = path.stat().st_size
        total += size
        if size > MAX_FILE or total > MAX_TOTAL or len(result) >= MAX_FILES:
            fail('evidence exceeds file/byte budget')
        result[relative] = {'sha256': sha(path.read_bytes()), 'bytes': size}
    return result


def source_fingerprint(root, ref):
    # All tracked files count, including build scripts, docs, lock and fixtures.
    # Only the fixed, data-only evidence directory is exempt to permit the
    # follow-up commit that adds reports without a circular commit hash.
    entries = git(root, 'ls-tree', '-rz', '--full-tree', ref).split(b'\0')
    entries = [entry for entry in entries if entry and not
               entry.split(b'\t', 1)[1].decode().startswith(EVIDENCE_PREFIX)]
    return sha(b'\0'.join(entries))


def require_clean(root):
    changed = git(root, 'status', '--porcelain', '--untracked-files=all').decode().splitlines()
    if any(not line[3:].startswith(EVIDENCE_PREFIX) for line in changed):
        fail('commit candidate changes before collecting/verifying evidence')


def source_input_hashes(root):
    if (root / 'Tests/Fixtures/HLSRuntime/audio-fmp4').is_symlink():
        fail('symlink in source fixture directory')
    for name in (*SOURCE_INPUTS, 'Tests/Fixtures/HLSRuntime/audio-fmp4/index.m3u8'):
        safe_file(root, name)
    paths = [root / p for p in SOURCE_INPUTS]
    paths += sorted((root / 'Tests/Fixtures/HLSRuntime/audio-fmp4').rglob('*'))
    return {p.relative_to(root).as_posix(): sha(safe_file(root, p.relative_to(root).as_posix()).read_bytes())
            for p in paths if p.is_file()}


def expected_input_inventory(root):
    with tempfile.TemporaryDirectory(prefix='stream-evidence-inputs-') as temp:
        target = Path(temp)
        subprocess.run([sys.executable, str(root / 'Scripts/materialize_hls_conformance_fixtures.py'),
                        str(root / SOURCE_INPUTS[0]), str(target)], check=True, stdout=subprocess.DEVNULL)
        shutil.copytree(root / 'Tests/Fixtures/HLSRuntime/audio-fmp4', target / 'audio-fmp4')
        return {'inputs/' + name: value for name, value in inventory(target).items()}



def report_checker(root):
    spec = importlib.util.spec_from_file_location('apple_report', root / 'Scripts/check_apple_hls_report.py')
    module = importlib.util.module_from_spec(spec)
    # Verification must not mutate the candidate checkout with bytecode caches.
    previous = sys.dont_write_bytecode
    try:
        sys.dont_write_bytecode = True
        spec.loader.exec_module(module)
    finally:
        sys.dont_write_bytecode = previous
    return module


def check_local_output_playlists(bundle):
    for playlist in (bundle / 'outputs').rglob('*.m3u8'):
        text = playlist.read_text()
        references = re.findall(r'URI="([^"]+)"', text)
        references += [line.strip() for line in text.splitlines()
                       if line.strip() and not line.startswith('#')]
        for reference in references:
            parsed = urlsplit(reference)
            if parsed.scheme or parsed.netloc or parsed.query or parsed.fragment or reference.startswith('/'):
                fail('SDK evidence output must not fetch external resources')
            relative = playlist.parent.relative_to(bundle) / reference
            safe_file(bundle, relative.as_posix())


def execute(command, root, log, env=None, timeout=900):
    with log.open('wb') as stream:
        result = subprocess.run(command, cwd=root, env=env, stdout=stream,
                                stderr=subprocess.STDOUT, timeout=timeout)
    if log.stat().st_size > MAX_FILE:
        fail('command log exceeds byte budget')
    if result.returncode:
        fail(f'command failed ({result.returncode}); inspect {log.name}')


def generate_sdk_outputs(root, bundle):
    inputs, outputs = bundle / 'inputs', bundle / 'outputs'
    execute([sys.executable, 'Scripts/materialize_hls_conformance_fixtures.py',
             SOURCE_INPUTS[0], str(inputs)], root, bundle / 'materialization.log')
    shutil.copytree(root / 'Tests/Fixtures/HLSRuntime/audio-fmp4', inputs / 'audio-fmp4')
    env = dict(os.environ, HLS_EVIDENCE_INPUT_ROOT=str(inputs))
    env.pop('INNONETWORK_LOCAL_PATH', None)
    execute(['xcrun', 'swift', '--version'], root, bundle / 'swift-version.log', env)
    execute(['xcodebuild', '-version'], root, bundle / 'xcode-version.log', env)
    execute(['bash', 'Scripts/check_innonetwork_dependency.sh'], root, bundle / 'dependency.log', env)
    execute(['bash', 'Scripts/check_hls_evidence_consumer.sh', 'prepare'], root, bundle / 'consumer-resolution.log', env, timeout=3600)
    shutil.copyfile(root / 'Package.resolved', bundle / 'candidate-Package.resolved')
    shutil.copyfile(root / 'Tests/HLSReleaseEvidence/Package.resolved', bundle / 'consumer-Package.resolved')
    candidate_pins = load_json(root / 'Package.resolved')['pins']
    consumer_pins = load_json(root / 'Tests/HLSReleaseEvidence/Package.resolved')['pins']
    if sorted(candidate_pins, key=lambda p: p['identity']) != sorted(consumer_pins, key=lambda p: p['identity']):
        fail('exporter dependency graph differs from candidate lock; resolve deliberately before collection')
    prepared = load_json(root / '.build/release-evidence-prepared.json')
    command = [prepared['binary_path'], str(outputs)]
    execute(command, root, bundle / 'generation.log', env, timeout=3600)
    execute(['bash', 'Scripts/check_hls_evidence_consumer.sh', 'verify'], root, bundle / 'consumer-post-generation.log', env, timeout=3600)
    provenance = load_json(root / '.build/release-evidence-consumer-provenance.json')
    provenance.pop('binary_path', None)  # Local paths are not needed by release reviewers.
    (bundle / 'consumer-provenance.json').write_text(json.dumps(provenance, sort_keys=True) + '\n')
    playlists = load_json(outputs / 'playlists.json')
    if set(playlists) != set(CASES):
        fail('SDK exporter did not produce every required offline/DVR case')
    inventory(bundle)
    check_local_output_playlists(bundle)
    return playlists


def collect(args):
    root, bundle = args.root.resolve(), args.bundle.absolute()
    require_clean(root)
    source_inputs = source_input_hashes(root)
    if bundle.exists():
        fail('bundle destination already exists; preserve earlier evidence')
    if not args.submitter.strip() or not args.tool_release.strip():
        fail('submitter and official tool release label are required')
    tools = {}
    for name in ('validator', 'reporter'):
        value = getattr(args, name)
        path = Path(shutil.which(value) or value).resolve(strict=True)
        if not path.is_file() or not os.access(path, os.X_OK):
            fail(f'{name} is not executable')
        tools[name] = {'file_name': path.name, 'sha256': sha(path.read_bytes()),
                       'release': args.tool_release, 'path': str(path)}
    commit = git(root, 'rev-parse', 'HEAD').decode()
    fingerprint = source_fingerprint(root, commit)
    bundle.mkdir(parents=True)
    inputs, outputs, reports = (bundle / p for p in ('inputs', 'outputs', 'reports'))
    inputs.mkdir(); outputs.mkdir(); reports.mkdir()
    playlists = generate_sdk_outputs(root, bundle)
    checker, results = report_checker(root), []
    for case in CASES:
        playlist = safe_file(outputs, playlists[case])
        json_path, html_path = reports / f'{case}.json', reports / f'{case}.html'
        validator_log, reporter_log = reports / f'{case}-validator.log', reports / f'{case}-reporter.log'
        execute([tools['validator']['path'], '-O', str(json_path), str(playlist)], root, validator_log)
        load_json(json_path)
        if re.search(r'\berror\b|must\s+fix', validator_log.read_text(), re.I):
            fail('validator reported a blocking issue')
        execute([tools['reporter']['path'], '-o', str(html_path), str(json_path)], root, reporter_log)
        checker.validate(html_path)
        results.append({'case': case, 'playlist': 'outputs/' + playlists[case],
                        'json': f'reports/{case}.json', 'html': f'reports/{case}.html',
                        'validator_log': f'reports/{case}-validator.log',
                        'reporter_log': f'reports/{case}-reporter.log',
                        'validator_exit': 0, 'reporter_exit': 0})
    require_clean(root)
    if source_fingerprint(root, 'HEAD') != fingerprint or git(root, 'rev-parse', 'HEAD').decode() != commit:
        fail('candidate changed while collecting evidence')
    for tool in tools.values():
        if sha(Path(tool['path']).read_bytes()) != tool['sha256']:
            fail('official tool bytes changed during collection')
        tool.pop('path')
    manifest = {'schema': 1, 'status': 'executed', 'scope': 'sdk-generated-offline-dvr',
                'source_commit': commit, 'source_fingerprint': fingerprint,
                'source_inputs': source_inputs, 'tools': tools,
                'executed_at': dt.datetime.now(dt.timezone.utc).isoformat(),
                'platform': os.uname().sysname + ' ' + os.uname().release + ' ' + os.uname().machine,
                'submitter_claim': args.submitter, 'generator_exit': 0,
                'results': results, 'files': inventory(bundle)}
    data = (json.dumps(manifest, indent=2, sort_keys=True) + '\n').encode()
    (bundle / 'manifest.json').write_bytes(data)
    print(f'Local evidence collected, NOT APPROVED: manifest SHA256 {sha(data)}')
    print('A maintainer must review source/inputs/tool versions/raw reports before approving this digest.')


def smoke(args):
    root, bundle = args.root.resolve(), args.bundle.absolute()
    require_clean(root)
    before = source_fingerprint(root, 'HEAD')
    if bundle.exists():
        fail('smoke destination already exists')
    for name in ('inputs', 'outputs'):
        (bundle/name).mkdir(parents=True)
    playlists = generate_sdk_outputs(root, bundle)
    require_clean(root)
    if source_fingerprint(root, 'HEAD') != before:
        fail('source changed during SDK-output smoke')
    print(f'hls-sdk-output-smoke: OK ({len(playlists)} actual offline/DVR outputs)')
    print('Official Apple HLS conformance: NOT RUN by this smoke check.')


def verify(args):
    if args.bundle.is_symlink():
        fail('bundle root cannot be a symlink')
    root, bundle = args.root.resolve(), args.bundle.resolve()
    require_clean(root)
    if not re.fullmatch(r'[0-9a-f]{64}', args.approved_digest or '') or not re.fullmatch(
            r'[A-Za-z0-9][A-Za-z0-9-]{0,38}', args.approved_by or ''):
        fail('independent maintainer approval digest and GitHub login are required')
    manifest_path = safe_file(bundle, 'manifest.json')
    if sha(manifest_path.read_bytes()) != args.approved_digest:
        fail('manifest does not match independently approved digest')
    m = load_json(manifest_path)
    if not isinstance(m, dict) or type(m.get('schema')) is not int or type(m.get('generator_exit')) is not int:
        fail('invalid manifest schema or generator result type')
    if (m.get('schema'), m.get('status'), m.get('scope'), m.get('generator_exit')) != (
            1, 'executed', 'sdk-generated-offline-dvr', 0):
        fail('missing actual SDK-generated execution evidence')
    commit = m.get('source_commit', '')
    if not re.fullmatch(r'[0-9a-f]{40}', commit):
        fail('invalid tested commit')
    subprocess.run(['git', '-C', str(root), 'merge-base', '--is-ancestor', commit, 'HEAD'], check=True)
    if m.get('source_fingerprint') != source_fingerprint(root, commit) or \
            m['source_fingerprint'] != source_fingerprint(root, 'HEAD'):
        fail('candidate changed outside the data-only evidence directory; rerun locally')
    if m.get('source_inputs') != source_input_hashes(root):
        fail('source fixture hashes changed')
    if not isinstance(m.get('files'), dict) or any(not isinstance(v, dict) or type(v.get('bytes')) is not int
            or not re.fullmatch(r'[0-9a-f]{64}', v.get('sha256', '')) for v in m['files'].values()):
        fail('invalid file inventory')
    if m.get('files') != inventory(bundle):
        fail('missing, extra, oversized, symlinked or changed evidence files')
    actual_inputs = {path: value for path, value in m['files'].items() if path.startswith('inputs/')}
    if actual_inputs != expected_input_inventory(root):
        fail('missing or changed materialized SDK inputs')
    if not m.get('submitter_claim') or not m.get('platform'):
        fail('missing operator/platform evidence')
    when = dt.datetime.fromisoformat(m.get('executed_at', ''))
    if when.tzinfo is None or when > dt.datetime.now(dt.timezone.utc) + dt.timedelta(minutes=5):
        fail('invalid execution timestamp')
    for name in ('validator', 'reporter'):
        tool = m.get('tools', {}).get(name, {})
        if not tool.get('file_name') or not tool.get('release') or not re.fullmatch(r'[0-9a-f]{64}', tool.get('sha256', '')):
            fail('missing official tool version/hash record')
    results = m.get('results', [])
    if not isinstance(results, list) or len(results) != len(CASES) or {r.get('case') for r in results} != set(CASES):
        fail('missing/duplicate required SDK output case')
    playlists = load_json(safe_file(bundle, 'outputs/playlists.json'))
    if set(playlists) != set(CASES):
        fail('exported output index differs')
    check_local_output_playlists(bundle)
    checker = report_checker(root)
    for result in results:
        case = result['case']
        if any(type(result.get(field)) is not int or result[field] != 0
               for field in ('validator_exit', 'reporter_exit')):
            fail('tool did not execute successfully')
        expected = {'playlist': 'outputs/' + playlists[case], 'json': f'reports/{case}.json',
                    'html': f'reports/{case}.html', 'validator_log': f'reports/{case}-validator.log',
                    'reporter_log': f'reports/{case}-reporter.log'}
        for field, relative in expected.items():
            if result.get(field) != relative or relative not in m['files']:
                fail('result path mismatch')
            safe_file(bundle, relative)
        if not result['playlist'].startswith(f'outputs/{case}/'):
            fail('case points outside its SDK output')
        load_json(safe_file(bundle, result['json']))
        checker.validate(safe_file(bundle, result['html']))
        if re.search(r'\berror\b|must\s+fix', safe_file(bundle, result['validator_log']).read_text(), re.I):
            fail('validator reported a blocking issue')
    candidate_lock = load_json(safe_file(bundle, 'candidate-Package.resolved'))
    consumer_lock = load_json(safe_file(bundle, 'consumer-Package.resolved'))
    if candidate_lock != load_json(root / 'Package.resolved'):
        fail('evidence candidate dependency lock differs')
    if sorted(candidate_lock['pins'], key=lambda p: p['identity']) != sorted(consumer_lock['pins'], key=lambda p: p['identity']):
        fail('evidence consumer dependency graph differs')
    provenance = load_json(safe_file(bundle, 'consumer-provenance.json'))
    if not re.fullmatch(r'[0-9a-f]{64}', provenance.get('binary_sha256', '')):
        fail('missing executed exporter binary hash')
    for key, filename in (('candidate_lock_sha256', 'candidate-Package.resolved'),
                          ('consumer_lock_sha256', 'consumer-Package.resolved')):
        if provenance.get(key) != sha(safe_file(bundle, filename).read_bytes()):
            fail('prepared exporter lock fingerprint differs')
    if provenance.get('source_commit') != commit or not provenance.get('active_clean_pins'):
        fail('missing clean active consumer graph evidence')
    pins = {p['identity']: p for p in candidate_lock['pins']}
    if not any(p.get('identity') == 'innonetwork' for p in provenance['active_clean_pins']):
        fail('active consumer graph omits Core')
    if any(pins.get(p.get('identity')) != p for p in provenance['active_clean_pins']):
        fail('active consumer graph differs from candidate lock')
    for log in ('dependency.log', 'consumer-resolution.log', 'consumer-post-generation.log', 'generation.log', 'materialization.log', 'swift-version.log', 'xcode-version.log'):


        safe_file(bundle, log)
    print(f'apple-hls-evidence: APPROVED LOCAL EXECUTION (reviewer {args.approved_by}; source {commit})')
    print('The tools were not executed on this CI runner. Approval attests provenance; hashes bind bytes.')


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[1])
    sub = p.add_subparsers(dest='command', required=True)
    collect_p = sub.add_parser('collect')
    collect_p.add_argument('--bundle', type=Path, required=True)
    collect_p.add_argument('--validator', default='mediastreamvalidator')
    collect_p.add_argument('--reporter', default='hlsreport')
    collect_p.add_argument('--tool-release', required=True)
    collect_p.add_argument('--submitter', required=True)
    smoke_p = sub.add_parser('smoke')
    smoke_p.add_argument('--bundle', type=Path, required=True)
    verify_p = sub.add_parser('verify')
    verify_p.add_argument('--bundle', type=Path, default=Path('ReleaseEvidence/apple-hls'))
    verify_p.add_argument('--approved-digest', default=os.environ.get('APPLE_HLS_APPROVED_EVIDENCE_SHA256', ''))
    verify_p.add_argument('--approved-by', default=os.environ.get('APPLE_HLS_APPROVED_BY', ''))
    args = p.parse_args()
    try:
        {'collect': collect, 'verify': verify, 'smoke': smoke}[args.command](args)
    except (ValueError, OSError, KeyError, TypeError, subprocess.SubprocessError) as error:
        print(f'apple-hls-evidence: FAIL: {error}', file=sys.stderr)
        raise SystemExit(1)


if __name__ == '__main__':
    main()
