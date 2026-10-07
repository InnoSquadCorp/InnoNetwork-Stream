"""Real diff, event routing, negative aggregates and preserved validation owners."""
import copy
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
ACTION_PINS = {
    'actions/checkout': '3d3c42e5aac5ba805825da76410c181273ba90b1',
    'github/codeql-action/init': '2892aa5e19bbd11bc0cff5427e3b750a04d9e3c2',
    'github/codeql-action/analyze': '2892aa5e19bbd11bc0cff5427e3b750a04d9e3c2',
}


def reviewed_action_pins(steps):
    """Apply reviewed action updates without replacing the legacy gate bodies."""
    steps = copy.deepcopy(steps)
    for step in steps:
        action = step.get('uses', '').partition('@')[0]
        if action in ACTION_PINS:
            step['uses'] = action + '@' + ACTION_PINS[action]
    return steps


def failure_artifact(name):
    return {
        'name': 'Preserve HLS startup and runtime failures',
        'if': 'failure()',
        'uses': 'actions/upload-artifact@043fb46d1a93c77aae656e7c1c64a875d1fc6a0a',
        'with': {'name': name, 'path': '.build/hls-runtime-diagnostics/',
                 'if-no-files-found': 'ignore'},
    }


def module(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / 'Scripts' / (name + '.py'))
    result = importlib.util.module_from_spec(spec); spec.loader.exec_module(result); return result
p = module('ci-policy')
def yaml(path):
    return json.loads(subprocess.check_output(['ruby', '-ryaml', '-rjson', '-e',
        'puts YAML.safe_load(File.read(ARGV[0])).to_json', str(path)], text=True))
def event(labels=(), author='contributor', action='opened'):
    return {'action': action, 'changes': {'base': {'ref': {'from': 'develop'}}} if action == 'edited' else {},
            'pull_request': {'user': {'login': author}, 'labels': [{'name': x} for x in labels]}}
def results(plan):
    return {'ci-plan': {'result': 'success'}, **{k: {'result': 'success' if v else 'skipped'} for k,v in plan['jobs'].items()}}

class PlanningTests(unittest.TestCase):
    def test_source_dependency_workflow_and_unknown_require_all_gates(self):
        for path in ['Sources/X.swift', 'Sources/README.md', 'Tests/README.md', 'Examples/X/Package.swift',
                     'Package.swift', 'Package.resolved', 'Scripts/script.sh', '.github/workflows/ci.yml',
                     '.github/dependabot.yml', '.github/actionlint.yaml', 'docs/new-tool.py', 'future-path']:
            plan = p.make_plan('pull_request', event(), [path]); self.assertTrue(all(plan['jobs'].values()), path)
            p.evaluate(plan, results(plan))
            for key in p.JOBS:
                reduced=copy.deepcopy(plan); reduced['jobs'][key]=False
                with self.assertRaises(ValueError): p.evaluate(reduced, results(reduced))
    def test_only_explicit_docs_narrow_validation(self):
        for paths in [['README.md'], ['docs/guide.md'], ['docs/release.md', 'CONTRIBUTING.md']]:
            plan=p.make_plan('pull_request',event(),paths)
            self.assertEqual({k for k,v in plan['jobs'].items() if v}, {'policy', *p.DOC_JOBS})
            p.evaluate(plan,results(plan))
        self.assertTrue(all(p.make_plan('pull_request',event(),['README.md','Sources/X.swift'])['jobs'].values()))
    def test_full_event_empty_bot_and_case_insensitive_label(self):
        for action in p.PR_ACTIONS:
            for e in [event(['release-validation'],action=action), event(['RELEASE-VALIDATION'],action=action),
                      event(author='dependabot[bot]',action=action)]:
                plan=p.make_plan('pull_request',e,['README.md']);self.assertTrue(all(plan['jobs'].values()));p.evaluate(plan,results(plan))
        for name,e in [('push',{'ref':'refs/heads/main'}),('merge_group',{'action':'checks_requested'}),('workflow_dispatch',{})]:
            plan=p.make_plan(name,e,[])
            self.assertEqual({j for j,v in plan['jobs'].items() if v},set(p.JOBS)-p.NON_PR_SKIP);p.evaluate(plan,results(plan))
        plan=p.make_plan('pull_request',event(),[]);self.assertTrue(all(plan['jobs'].values()));p.evaluate(plan,results(plan))
        for name,e in [('pull_request',event(action='ready_for_review')),('pull_request',event(action='closed')),('push',{'ref':'refs/heads/other'}),('schedule',{})]:
            with self.assertRaises(ValueError):p.make_plan(name,e,['README.md'])
        e=event(action='edited');e.pop('changes')
        with self.assertRaises(ValueError):p.make_plan('pull_request',e,['README.md'])
    def test_failed_cancelled_skipped_missing_and_unknown_results_reject(self):
        for paths in [['README.md'],['Package.swift']]:
            plan=p.make_plan('pull_request',event(),paths);good=results(plan);p.evaluate(plan,good)
            for key in good:
                for state in ['failure','cancelled','skipped','success',None]:
                    if state==good[key]['result']:continue
                    bad=copy.deepcopy(good);bad[key]['result']=state
                    with self.assertRaises(ValueError):p.evaluate(plan,bad)
                bad=copy.deepcopy(good);bad.pop(key)
                with self.assertRaises(ValueError):p.evaluate(plan,bad)
            bad=copy.deepcopy(good);bad['unexpected']={'result':'success'}
            with self.assertRaises(ValueError):p.evaluate(plan,bad)
        with self.assertRaises(ValueError):p.evaluate({}, {})
    def test_real_git_delete_rename_cli_and_retarget(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d)
            def git(*args):return subprocess.check_output(['git','-C',d,*args],text=True).strip()
            git('init','-q');git('config','user.name','CI Test');git('config','user.email','ci@example.invalid')
            (root/'Sources').mkdir();(root/'docs').mkdir();(root/'Sources/old.swift').write_text('source\n'*50)
            (root/'Package.swift').write_text('manifest');git('add','.');git('commit','-qm','base');base=git('rev-parse','HEAD')
            git('mv','Sources/old.swift','docs/guide.md');git('rm','Package.swift');git('commit','-qm','rename and delete');head=git('rev-parse','HEAD')
            paths=p.changed_paths(root,base,head);self.assertEqual(set(paths),{'Sources/old.swift','docs/guide.md','Package.swift'})
            e=event(action='edited');e['pull_request'].update(base={'sha':base},head={'sha':head})
            ep=root/'event.json';ep.write_text(json.dumps(e));out=root/'plan.json'
            proc=subprocess.run(['python3',str(ROOT/'Scripts/ci-policy.py'),'plan','--event',str(ep),'--root',d,'--output',str(out)],env={**os.environ,'GITHUB_EVENT_NAME':'pull_request'},capture_output=True,text=True)
            self.assertEqual(proc.returncode,0,proc.stderr);self.assertTrue(all(json.loads(out.read_text())['jobs'].values()))
    def test_untrusted_paths_and_plan_shapes_reject(self):
        for path in ['', '/absolute', '../escape','a/../b','a//b','a\\b','bad\nname',None]:
            with self.assertRaises(ValueError):p.path_impact(path)
        for change in [lambda x:x.update(schema=True),lambda x:x['jobs'].update(policy='true'),lambda x:x.update(extra=1),lambda x:x['changes'][0].update(reason='forged')]:
            plan=p.make_plan('pull_request',event(),['README.md']);change(plan)
            with self.assertRaises(ValueError):p.validate_plan(plan)

class WorkflowTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.ci=yaml(ROOT/'.github/workflows/ci.yml');cls.old=json.loads((Path(__file__).parent/'legacy-workflows.json').read_text())
    def test_graph_has_exact_inventory_no_bypass_and_bounded_runners(self):
        jobs=self.ci['jobs'];self.assertEqual(set(jobs),set(p.JOBS)|{'ci-plan','ci-required'})
        self.assertEqual(set(jobs['ci-required']['needs']),set(p.JOBS)|{'ci-plan'})
        self.assertIn('always()',jobs['ci-required']['if']);self.assertEqual(self.ci['permissions'],{'contents':'read'})
        for key,job in jobs.items():
            self.assertNotIn('continue-on-error',job)
            if key not in {'ci-plan','ci-required'}:
                self.assertEqual(job['needs'],'ci-plan')
                if key!='policy':self.assertEqual(job['if'],'fromJSON(needs.ci-plan.outputs.plan).jobs.'+key)
            if 'runs-on' in job:self.assertGreater(job['timeout-minutes'],0)
            for step in job.get('steps',[]):
                self.assertNotIn('continue-on-error',step)
                if step.get('uses','').startswith('actions/checkout@'):self.assertIs(step['with']['persist-credentials'],False)
                if 'uses' in step:self.assertRegex(step['uses'],r'@[0-9a-f]{40}$')
    def test_reviewed_action_pins_and_read_only_checkout_in_every_workflow(self):
        seen = set()
        for path in sorted((ROOT / '.github/workflows').glob('*.yml')):
            workflow = yaml(path)
            for job in workflow['jobs'].values():
                for step in job.get('steps', []):
                    if 'uses' not in step:
                        self.assertNotIn('--development', step.get('run', ''))
                        continue
                    self.assertRegex(step['uses'], r'@[0-9a-f]{40}$')
                    action, _, ref = step['uses'].partition('@')
                    if action in ACTION_PINS:
                        self.assertEqual(ref, ACTION_PINS[action], (path.name, action))
                        seen.add(action)
                    if action == 'actions/checkout':
                        self.assertIs(step['with']['persist-credentials'], False)
        self.assertEqual(seen, set(ACTION_PINS))
    def test_existing_commands_matrices_and_resource_budgets_are_retained(self):
        for key,old in self.old['jobs'].items():
            current=self.ci['jobs'][key]
            for field in ['name','runs-on','timeout-minutes','strategy','permissions']:
                self.assertEqual(current.get(field),old.get(field),(key,field))
            old_steps=[s for s in old['steps'] if not s.get('uses','').startswith('actions/checkout@')]
            new_steps=[s for s in current['steps'] if not s.get('uses','').startswith('actions/checkout@')]
            # Keep the frozen legacy gates and explicitly enumerate the
            # reviewed SwiftPM, DocC, and diagnostic additions from PR #4.
            old_steps = copy.deepcopy(old_steps)
            if key == 'lint':
                old_steps.extend([
                    {'name': 'Prepare formatting diagnostics', 'if': 'failure()',
                     'run': 'mkdir -p .build/format-diagnostics\nbash Scripts/format.sh\n'
                            'git diff -- Sources Tests > .build/format-diagnostics/swift-format.patch\n'},
                    {'name': 'Preserve formatting diagnostics', 'if': 'failure()',
                     'uses': 'actions/upload-artifact@043fb46d1a93c77aae656e7c1c64a875d1fc6a0a',
                     'with': {'name': 'swift-format-diagnostics', 'path': '.build/format-diagnostics/',
                              'if-no-files-found': 'ignore'}},
                ])
            if key == 'build-and-test':
                next(s for s in old_steps if s['name'] == 'Run tests')['run'] = (
                    'bash Scripts/swiftpm.sh test --force-resolved-versions --parallel')
                old_steps.append({
                    'name': 'Compile UIKit background integration',
                    'run': 'bash Scripts/check_uikit_background_consumer.sh',
                })
                old_steps.append({
                    'name': 'Compile local HLS evidence exporter',
                    'run': 'bash Scripts/check_hls_evidence_consumer.sh',
                })
            if key == 'contracts':
                validation = next(s for s in old_steps if s['name'] == 'Validate scripts and documentation')
                validation['run'] = validation['run'].replace(
                    'python3 -m py_compile Scripts/*.py\n',
                    'python3 -m py_compile Scripts/*.py\n'
                    'ruby Scripts/check_codeql_contract.rb\n'
                    'ruby Scripts/tests/test_codeql_contract.rb\n'
                    'python3 Scripts/tests/test_hls_fixture_readiness.py\n'
                    'python3 Scripts/tests/test_swiftpm_scratch.py\n')
                validation['run'] = validation['run'].replace(
                    'bash Scripts/validate_docs_release_state.sh --expect draft\n',
                    'bash Scripts/tests/test_run_affected_tests.sh\n'
                    'python3 Scripts/tests/test_public_signatures.py\n'
                    'python3 Scripts/tests/test_apple_hls_evidence.py\n'
                    'bash Scripts/validate_docs_release_state.sh\n')
                next(s for s in old_steps if s['name'] == 'Validate public API')['run'] = (
                    'bash Scripts/check_public_api_contract.sh\n'
                    'bash Scripts/check_docc.sh --skip-build\n')
                old_steps.append({
                    'name': 'Preserve generated API diagnostics', 'if': 'always()',
                    'uses': 'actions/upload-artifact@043fb46d1a93c77aae656e7c1c64a875d1fc6a0a',
                    'with': {'name': 'public-api-diagnostics', 'path': '.build/api-contract-diagnostics/',
                             'if-no-files-found': 'ignore'},
                })
                old_steps.append(failure_artifact('hls-runtime-diagnostics'))
            # Noninteractive locked package flags must occur exactly once;
            # all original xcodebuild arguments and other steps still match.
            if key == 'platform-build':
                build = next(s for s in old_steps if s['name'] == 'Build with xcodebuild')
                flags = ['-skipMacroValidation', '-onlyUsePackageVersionsFromResolvedFile',
                         '-clonedSourcePackagesDirPath "$dependency_scratch"']
                new_build = next(s for s in new_steps if s['name'] == 'Build with xcodebuild')
                lines = new_build['run'].splitlines(keepends=True)
                self.assertEqual(lines.pop(0),
                                 'dependency_scratch="$(python3 Scripts/swiftpm_scratch_path.py "$PWD")"\n')
                for flag in flags:
                    matches = [line for line in lines if line.strip().removesuffix('\\').strip() == flag]
                    self.assertEqual(len(matches), 1, flag)
                    lines.remove(matches[0])
                self.assertEqual(''.join(lines), build['run'])
                new_steps = copy.deepcopy(new_steps)
                next(s for s in new_steps if s['name'] == 'Build with xcodebuild')['run'] = build['run']
                names = [s['name'] for s in new_steps]
                self.assertLess(names.index('Verify published InnoNetwork dependency'),
                                names.index('Build with xcodebuild'))
            self.assertEqual(new_steps,old_steps,key)
    def test_xcodebuild_reuses_the_dependency_gates_scoped_checkouts(self):
        # Exercise the actual workflow command and wrapper with a controlled
        # toolchain identity. This is argument forwarding, not an Apple build.
        command = next(s['run'] for s in self.ci['jobs']['platform-build']['steps']
                       if s.get('name') == 'Build with xcodebuild')
        command = command.replace('${{ matrix.destination }}', 'platform=macOS')
        command = command.replace('${{ matrix.runtime }}', 'macOS')
        with tempfile.TemporaryDirectory() as directory:
            scratch = Path(directory)
            package = scratch / 'package with spaces'
            (package / 'Scripts').mkdir(parents=True)
            (package / 'Package.swift').write_text('// command forwarding fixture\n')
            (package / 'Scripts/swiftpm_scratch_path.py').write_bytes(
                (ROOT / 'Scripts/swiftpm_scratch_path.py').read_bytes())
            sdk = scratch / 'test.sdk'
            sdk.mkdir()
            xcrun = scratch / 'xcrun'
            xcrun.write_text(
                '#!/bin/sh\ncase "$1:$2" in\n'
                ' --sdk:macosx) printf "%s\\n" "$TEST_SDK" ;;\n'
                ' --find:swift) printf "%s\\n" "$TEST_SWIFT" ;;\n'
                ' swift:--version) printf "Apple Swift version 6.4\\n" ;;\n'
                ' *) printf "%s\\n" "$@" > "$SWIFTPM_ARGUMENTS" ;;\nesac\n')
            xcrun.chmod(0o755)
            xcodebuild = scratch / 'xcodebuild'
            xcodebuild.write_text('#!/bin/sh\nprintf "%s\\n" "$@" > "$XCODEBUILD_ARGUMENTS"\n')
            xcodebuild.chmod(0o755)
            swift_arguments = scratch / 'swift-arguments'
            xcode_arguments = scratch / 'xcode-arguments'
            environment = {**os.environ, 'PATH': str(scratch) + os.pathsep + os.environ['PATH'],
                           'TEST_SDK': str(sdk), 'TEST_SWIFT': str(scratch / 'swift'),
                           'SWIFTPM_ARGUMENTS': str(swift_arguments),
                           'XCODEBUILD_ARGUMENTS': str(xcode_arguments)}
            subprocess.run(['bash', str(ROOT / 'Scripts/swiftpm.sh'), 'package',
                            '--force-resolved-versions', 'show-dependencies', '--format', 'json'],
                           cwd=package, env=environment, check=True)
            subprocess.run(['bash', '-eu', '-o', 'pipefail', '-c', command],
                           cwd=package, env=environment, check=True)
            swift = swift_arguments.read_text().splitlines()
            xcode = xcode_arguments.read_text().splitlines()
            verified_path = swift[swift.index('--scratch-path') + 1]
            self.assertEqual(xcode[xcode.index('-clonedSourcePackagesDirPath') + 1], verified_path)
            self.assertEqual(Path(verified_path).parent, package / '.build/swiftpm')
            self.assertRegex(Path(verified_path).name, r'^scope-[0-9a-f]{24}$')
            for flag in ['-clonedSourcePackagesDirPath', '-skipMacroValidation',
                         '-onlyUsePackageVersionsFromResolvedFile']:
                self.assertEqual(xcode.count(flag), 1)
    def test_codeql_has_one_change_owner_and_keeps_scheduled_security_scan(self):
        code=yaml(ROOT/'.github/workflows/codeql.yml')
        self.assertEqual(set(code['true'] if 'true' in code else code[True]),{'workflow_call','workflow_dispatch','schedule'})
        self.assertEqual(self.ci['jobs']['codeql']['uses'],'./.github/workflows/codeql.yml')
        for k,old in self.old['codeql'].items():
            current=copy.deepcopy(code['jobs'][k]);original=copy.deepcopy(old)
            original['steps'] = reviewed_action_pins(original['steps'])
            for step in original['steps']:
                if step.get('uses', '').startswith('actions/checkout@'):
                    step['with'] = {'persist-credentials': False}
                if step['name'] == 'Build':
                    step['run'] = 'bash Scripts/swiftpm.sh build --force-resolved-versions'
            dependency = next(i for i, step in enumerate(original['steps'])
                              if step['name'] == 'Verify published InnoNetwork dependency')
            original['steps'].insert(dependency, {
                'name': 'Verify coupled CodeQL action pins',
                'run': 'ruby Scripts/check_codeql_contract.rb',
            })
            self.assertEqual(current,original)
    def test_release_validation_commands_stay_fresh(self):
        release = yaml(ROOT/'.github/workflows/release.yml')
        jobs = release['jobs']
        self.assertEqual(release['true'], {'push': {'tags': ['*.*.*']}, 'workflow_dispatch': None})
        self.assertEqual(release['concurrency'], {'group': 'release-${{ github.ref }}', 'cancel-in-progress': False})
        self.assertEqual(set(jobs), set(self.old['release']))
        for key,old in self.old['release'].items():
            expected = copy.deepcopy(old)
            expected['steps'] = reviewed_action_pins(expected['steps'])
            steps = expected['steps']
            tagged = next(s for s in steps if s['name'] == 'Validate tagged release ref')
            tagged['id'] = 'release-ref'
            tagged['env'].update(RELEASE_VERIFY_REMOTE='1', RELEASE_EXPECTED_SHA='${{ github.sha }}')
            archive = next(s for s in steps if s['name'] == 'Prepare tagged source archive')
            archive['env']['RELEASE_COMMIT_SHA'] = '${{ steps.release-ref.outputs.commit_sha }}'
            archive['run'] = archive['run'].replace('  "$RELEASE_TAG"\n', '  "$RELEASE_COMMIT_SHA"\n')
            revalidate = {
                'name': 'Revalidate the tested release identity',
                'if': "github.event_name == 'push'",
                'env': {
                    'RELEASE_TAG': '${{ github.ref_name }}',
                    'RELEASE_TAG_REF': '${{ github.ref }}',
                    'RELEASE_EXPECTED_SHA': '${{ steps.release-ref.outputs.commit_sha }}',
                    'RELEASE_EXPECTED_TAG_OBJECT': '${{ steps.release-ref.outputs.tag_object }}',
                    'RELEASE_VERIFY_REMOTE': '1',
                },
                'run': 'bash Scripts/validate_release_ref.sh',
            }
            preflight = next(i for i, s in enumerate(steps) if s['name'] == 'Run full release preflight')
            steps[preflight]['env'] = {
                'APPLE_HLS_APPROVED_EVIDENCE_SHA256': '${{ vars.APPLE_HLS_APPROVED_EVIDENCE_SHA256 }}',
                'APPLE_HLS_APPROVED_BY': '${{ vars.APPLE_HLS_APPROVED_BY }}',
            }
            artifact = next(s for s in steps if s['name'] == 'Upload release validation artifacts')
            artifact['with']['path'] = artifact['with']['path'].replace(
                '.build/local-release-preflight/apple-hls/', 'ReleaseEvidence/apple-hls/')
            steps[preflight + 1:preflight + 1] = [failure_artifact('release-hls-runtime-diagnostics'), revalidate]
            before_publish = copy.deepcopy(revalidate)
            before_publish['name'] = 'Revalidate release identity immediately before publication'
            publish = next(i for i, s in enumerate(steps) if s['name'] == 'Publish GitHub release')
            steps.insert(publish, before_publish)
            # Full equality also protects event guards, token scope, archive
            # identity, exact revalidation order, scripts, and job budgets.
            self.assertEqual(jobs[key], expected)
