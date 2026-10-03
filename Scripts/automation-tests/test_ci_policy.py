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
    def test_existing_commands_matrices_and_resource_budgets_are_retained(self):
        for key,old in self.old['jobs'].items():
            current=self.ci['jobs'][key]
            for field in ['name','runs-on','timeout-minutes','strategy','permissions']:
                self.assertEqual(current.get(field),old.get(field),(key,field))
            old_steps=[s for s in old['steps'] if not s.get('uses','').startswith('actions/checkout@')]
            new_steps=[s for s in current['steps'] if not s.get('uses','').startswith('actions/checkout@')]
            # Retain the original lane; only noninteractive, locked package
            # flags may differ after the hosted macro-approval failure.
            if key == 'platform-build':
                old_steps = copy.deepcopy(old_steps)
                build = next(s for s in old_steps if s['name'] == 'Build with xcodebuild')
                flags = ['-skipMacroValidation', '-onlyUsePackageVersionsFromResolvedFile',
                         '-clonedSourcePackagesDirPath .build']
                new_build = next(s for s in new_steps if s['name'] == 'Build with xcodebuild')
                lines = new_build['run'].splitlines(keepends=True)
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
    def test_codeql_has_one_change_owner_and_keeps_scheduled_security_scan(self):
        if 'codeql' not in self.old:return
        code=yaml(ROOT/'.github/workflows/codeql.yml')
        self.assertEqual(set(code['true'] if 'true' in code else code[True]),{'workflow_call','workflow_dispatch','schedule'})
        self.assertEqual(self.ci['jobs']['codeql']['uses'],'./.github/workflows/codeql.yml')
        for k,old in self.old['codeql'].items():
            current=copy.deepcopy(code['jobs'][k]);original=copy.deepcopy(old)
            for job in [current,original]:
                for step in job['steps']:
                    if step.get('uses','').startswith('actions/checkout@'):step.pop('with',None)
            self.assertEqual(current,original)
    def test_release_validation_commands_stay_fresh(self):
        jobs=yaml(ROOT/'.github/workflows/release.yml')['jobs']
        for key,old in self.old['release'].items():
            if key.startswith('publish'):continue
            if 'codeql' in self.old:
                changed = {'Validate tagged release ref', 'Prepare tagged source archive'}
                current = {s.get('name'): s for s in jobs[key]['steps']}
                for step in old['steps']:
                    if step.get('name') not in changed:
                        self.assertEqual(current[step.get('name')], step)
                names = [s.get('name') for s in jobs[key]['steps']]
                self.assertEqual(names[names.index('Publish GitHub release') - 1],
                                 'Revalidate release identity immediately before publication')
                self.assertIn('$RELEASE_COMMIT_SHA', current['Prepare tagged source archive']['run'])
                self.assertEqual(current['Validate tagged release ref']['env']['RELEASE_EXPECTED_SHA'], '${{ github.sha }}')
            else:
                self.assertEqual([s for s in jobs[key]['steps'] if 'run' in s], [s for s in old['steps'] if 'run' in s])
        if 'codeql' not in self.old:
            release=jobs['publish-release'];self.assertEqual(release['needs'],'validate-release')
            notes=next(s for s in release['steps'] if s.get('id')=='notes')
            self.assertNotIn('${{',notes['run']);self.assertIn('RELEASE_VERSION',notes['env'])
            with tempfile.TemporaryDirectory() as d:
                for version in ['1.2.3','1.2.3-rc.1','$(touch owned)','../../etc/passwd','1.2.3\ninjected=yes']:
                    result=subprocess.run(['bash','-c',notes['run']],cwd=d,env={**os.environ,'RELEASE_VERSION':version,'GITHUB_OUTPUT':str(Path(d)/'output')},capture_output=True)
                    self.assertEqual(result.returncode==0,version in ['1.2.3','1.2.3-rc.1'])
                self.assertFalse((Path(d)/'owned').exists())
