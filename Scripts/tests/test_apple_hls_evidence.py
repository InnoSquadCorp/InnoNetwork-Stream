"""Synthetic protocol controls, never Apple-tool acceptance evidence."""
import argparse
import contextlib
import datetime as dt
import importlib.util
import io
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('evidence', ROOT / 'Scripts/apple_hls_evidence.py')
e = importlib.util.module_from_spec(spec); spec.loader.exec_module(e)


class EvidenceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        for file in ['Scripts/check_apple_hls_report.py', 'Scripts/materialize_hls_conformance_fixtures.py', *e.SOURCE_INPUTS]:
            dest = self.root / file; dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / file, dest)
        audio = self.root / 'Tests/Fixtures/HLSRuntime/audio-fmp4'
        audio.mkdir(parents=True); (audio / 'index.m3u8').write_text('#EXTM3U\n')
        (self.root/'Package.resolved').write_text(json.dumps({'pins':[{'identity':'innonetwork','location':'https://fixture.invalid/Core','state':{'version':'6.1.1','revision':'0'*40}}]}))
        self.run_git('init', '-q'); self.run_git('config', 'user.name', 'Fixture')
        self.run_git('config', 'user.email', 'fixture@example.invalid')
        self.run_git('add', '.'); self.run_git('-c', 'commit.gpgsign=false', 'commit', '-qm', 'source')
        self.commit = e.git(self.root, 'rev-parse', 'HEAD').decode()
        self.bundle = self.root / e.EVIDENCE_PREFIX
        self.bundle.mkdir(parents=True)
        subprocess.run(['python3', str(self.root/'Scripts/materialize_hls_conformance_fixtures.py'),
                        str(self.root/e.SOURCE_INPUTS[0]), str(self.bundle/'inputs')], check=True, capture_output=True)
        shutil.copytree(audio, self.bundle/'inputs/audio-fmp4')
        playlists = {case: case + '/index.m3u8' for case in e.CASES}
        for case, path in playlists.items():
            file = self.bundle / 'outputs' / path; file.parent.mkdir(parents=True)
            file.write_text('#EXTM3U\n#EXT-X-ENDLIST\n')
        (self.bundle / 'outputs/playlists.json').write_text(json.dumps(playlists))
        reports = self.bundle / 'reports'; reports.mkdir()
        results = []
        for case in e.CASES:
            (reports / f'{case}.json').write_text('{"synthetic_test_fixture":true}')
            (reports / f'{case}.html').write_text('<h2>Must Fix Issues</h2>None<h2>Report Information</h2>')
            for name in ('validator', 'reporter'):
                (reports / f'{case}-{name}.log').write_text('Synthetic unit-test control, not official output.\n')
            results.append({'case':case,'playlist':'outputs/' + playlists[case],
                'json':f'reports/{case}.json','html':f'reports/{case}.html',
                'validator_log':f'reports/{case}-validator.log','reporter_log':f'reports/{case}-reporter.log',
                'validator_exit':0,'reporter_exit':0})
        for lock in ('candidate-Package.resolved','consumer-Package.resolved'):
            shutil.copyfile(self.root/'Package.resolved',self.bundle/lock)
        (self.bundle/'consumer-provenance.json').write_text(json.dumps({
            'source_commit':self.commit, 'binary_sha256':'0'*64,
            'candidate_lock_sha256':e.sha((self.root/'Package.resolved').read_bytes()),
            'consumer_lock_sha256':e.sha((self.root/'Package.resolved').read_bytes()),
            'active_clean_pins':json.loads((self.root/'Package.resolved').read_text())['pins']}))
        for log in ('dependency.log', 'consumer-resolution.log', 'consumer-post-generation.log', 'generation.log', 'materialization.log', 'swift-version.log', 'xcode-version.log'):


            (self.bundle / log).write_text('synthetic test control\n')
        self.manifest = {'schema':1,'status':'executed','scope':'sdk-generated-offline-dvr',
            'source_commit':self.commit,'source_fingerprint':e.source_fingerprint(self.root,'HEAD'),
            'source_inputs':e.source_input_hashes(self.root),
            'tools':{name:{'file_name':name,'release':'UNIT-TEST-NOT-APPLE','sha256':'0'*64}
                     for name in ('validator','reporter')},
            'executed_at':dt.datetime.now(dt.timezone.utc).isoformat(),
            'platform':'UNIT TEST','submitter_claim':'fixture','generator_exit':0,
            'results':results,'files':e.inventory(self.bundle)}
        self.approve()

    def tearDown(self): self.temp.cleanup()

    def run_git(self, *args):
        subprocess.run(['git','-C',str(self.root),*args], check=True, capture_output=True)

    def approve(self):
        self.manifest['files'] = e.inventory(self.bundle)
        data = (json.dumps(self.manifest, sort_keys=True) + '\n').encode()
        (self.bundle / 'manifest.json').write_bytes(data)
        self.args = argparse.Namespace(root=self.root,bundle=self.bundle,
                                       approved_digest=e.sha(data),approved_by='trusted-maintainer')

    def verify(self):
        with contextlib.redirect_stdout(io.StringIO()): e.verify(self.args)

    def reject(self):
        with self.assertRaises((ValueError, subprocess.SubprocessError, SystemExit)): self.verify()

    def test_valid_candidate_and_evidence_only_commit(self):
        self.verify()
        self.run_git('add','ReleaseEvidence'); self.run_git('-c','commit.gpgsign=false','commit','-qm','evidence only')
        self.verify()
        # Porcelain starts with a space for a tracked worktree modification.
        # Evidence-only edits remain permitted when their new digest is approved.
        (self.bundle/'generation.log').write_text('updated synthetic control\n')
        self.approve(); self.verify()

    def test_independent_approval_is_required(self):
        self.args.approved_digest = ''; self.reject()
        self.approve(); self.args.approved_by = ''; self.reject()
        self.approve(); self.args.approved_digest = '1'*64; self.reject()

    def test_manifest_cannot_self_approve(self):
        self.manifest['approved_by']='trusted-maintainer'; self.approve()
        self.args.approved_by=''; self.reject()

    def test_changed_source_commit_and_dirty_source_rejected(self):
        file = self.root / e.SOURCE_INPUTS[0]
        file.write_text(file.read_text()+'\n// changed\n'); self.reject()
        self.run_git('add',str(file)); self.run_git('-c','commit.gpgsign=false','commit','-qm','source changed')
        self.reject()

    def test_missing_extra_and_changed_report_rejected(self):
        file = self.bundle/'reports/offline-transport-stream.json'
        old=file.read_bytes(); file.unlink(); self.reject(); file.write_bytes(old)
        file.write_bytes(old+b' '); self.reject(); file.write_bytes(old)
        (self.bundle/'unexpected.txt').write_text('unlisted'); self.reject()

    def test_missing_or_altered_input_fails_even_with_new_approval(self):
        file = self.bundle/'inputs/transport-stream/segment-0.ts'
        data=file.read_bytes();file.unlink();self.approve();self.reject()
        file.write_bytes(data+b'wrong');self.approve();self.reject()

    def test_consumer_lock_or_resolution_evidence_cannot_be_omitted(self):
        file=self.bundle/'consumer-resolution.log';data=file.read_bytes();file.unlink();self.approve();self.reject()
        file.write_bytes(data)
        file=self.bundle/'consumer-Package.resolved';file.write_text('{"pins":[]}');self.approve();self.reject()

    def test_approved_manifest_still_requires_complete_exporter_provenance(self):
        file=self.bundle/'consumer-provenance.json'
        original=json.loads(file.read_text())
        for key,value in [('binary_sha256',''),('candidate_lock_sha256','0'*64),
                          ('consumer_lock_sha256','0'*64),('source_commit','0'*40),
                          ('active_clean_pins',[])]:
            changed=dict(original);changed[key]=value
            file.write_text(json.dumps(changed));self.approve();self.reject()
        file.write_text(json.dumps(original));self.approve();self.verify()

    def test_external_or_missing_output_reference_is_rejected(self):
        file=self.bundle/'outputs/offline-transport-stream/index.m3u8'
        for reference in ['https://private.invalid/video.ts','missing.ts','../escape.ts']:
            file.write_text('#EXTM3U\n#EXTINF:1,\n'+reference+'\n')
            self.approve();self.reject()

    def test_boolean_result_is_not_an_executed_exit_status(self):
        self.manifest['generator_exit']=False;self.approve();self.reject()
        self.manifest['generator_exit']=0
        self.manifest['results'][0]['validator_exit']=False;self.approve();self.reject()

    def test_unexecuted_and_fixture_only_are_not_accepted(self):
        for key,value in [('status','not-run'),('scope','fixed-fixtures'),('generator_exit',1)]:
            old=self.manifest[key]; self.manifest[key]=value; self.approve(); self.reject()
            self.manifest[key]=old

    def test_failed_case_missing_case_and_must_fix_rejected(self):
        self.manifest['results'][0]['validator_exit']=1; self.approve(); self.reject()
        self.manifest['results'][0]['validator_exit']=0
        saved=self.manifest['results'].pop(); self.approve(); self.reject()
        self.manifest['results'].append(saved)
        (self.bundle/'reports/offline-transport-stream.html').write_text(
            '<h2>Must Fix Issues</h2>Invalid media<h2>Report Information</h2>')
        self.approve(); self.reject()

    def test_duplicate_json_keys_and_symlinks_rejected(self):
        file=self.bundle/'manifest.json'; text=file.read_text()
        file.write_text(text.replace('{','{"schema":1,',1))
        self.args.approved_digest=e.sha(file.read_bytes()); self.reject()
        self.approve()
        file=self.bundle/'reports/offline-transport-stream.json'; file.unlink()
        file.symlink_to(self.root/e.SOURCE_INPUTS[0]); self.reject()

    def test_bad_path_and_result_redirect_rejected(self):
        self.manifest['results'][0]['playlist']='../outside.m3u8'; self.approve(); self.reject()

    def test_collector_missing_tools_cannot_write_passing_manifest(self):
        target=self.root/'ReleaseEvidence/apple-hls/new'
        args=argparse.Namespace(root=self.root,bundle=target,submitter='fixture',tool_release='synthetic',
                                validator='/nonexistent-official-validator',reporter='/nonexistent-reporter')
        with self.assertRaises((ValueError,OSError)): e.collect(args)
        self.assertFalse((target/'manifest.json').exists())


class SmokeTests(unittest.TestCase):
    def test_missing_fixture_fails_before_any_apple_command(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory)/'repo';bundle=Path(directory)/'smoke'
            (root/'Scripts').mkdir(parents=True)
            shutil.copyfile(ROOT/'Scripts/materialize_hls_conformance_fixtures.py',
                            root/'Scripts/materialize_hls_conformance_fixtures.py')
            args=argparse.Namespace(root=root,bundle=bundle)
            output=io.StringIO()
            actual_execute=e.execute
            with patch.object(e,'require_clean'), patch.object(e,'source_fingerprint',return_value='same'), \
                    patch.object(e,'execute',wraps=actual_execute) as calls, contextlib.redirect_stdout(output):
                with self.assertRaisesRegex(ValueError,'materialization.log'): e.smoke(args)
            self.assertEqual(len(calls.call_args_list),1)
            self.assertIn('materialize_hls_conformance_fixtures.py',str(calls.call_args.args[0]))
            self.assertFalse((bundle/'manifest.json').exists())
            self.assertNotIn('OK',output.getvalue())
            self.assertIn('fixture source is missing:',(bundle/'materialization.log').read_text())

    def test_generation_failure_has_no_acceptance_manifest_or_success(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory); bundle=root/'smoke'
            args=argparse.Namespace(root=root,bundle=bundle)
            output=io.StringIO()
            with patch.object(e,'require_clean'), patch.object(e,'source_fingerprint',return_value='same'), \
                    patch.object(e,'generate_sdk_outputs',side_effect=ValueError('generator failed')), \
                    contextlib.redirect_stdout(output):
                with self.assertRaises(ValueError): e.smoke(args)
            self.assertFalse((bundle/'manifest.json').exists())
            self.assertNotIn('OK',output.getvalue())


class InventoryTests(unittest.TestCase):
    def test_empty_directories_and_depth_are_bounded(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name in ('a', 'b', 'c'): (root/name).mkdir()
            with patch.object(e, 'MAX_ENTRIES', 2):
                with self.assertRaises(ValueError): e.inventory(root)
            (root/'a/deep/deeper').mkdir(parents=True)
            with patch.object(e, 'MAX_DEPTH', 2):
                with self.assertRaises(ValueError): e.inventory(root)

    def test_file_and_byte_limits_remain_enforced(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory)
            for name in ('a','b','c'): (root/name).write_bytes(b'123')
            for limit,value in [('MAX_FILES',2),('MAX_FILE',2),('MAX_TOTAL',8)]:
                with patch.object(e,limit,value):
                    with self.assertRaises(ValueError): e.inventory(root)
            actual=e.inventory(root)
            for name in ('a','b','c'): (root/name).unlink()
            for name in ('c','b','a'): (root/name).write_bytes(b'123')
            self.assertEqual(actual,e.inventory(root))

if __name__ == '__main__': unittest.main()
