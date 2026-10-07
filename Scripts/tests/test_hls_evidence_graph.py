import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('graph',ROOT/'Scripts/check_hls_evidence_graph.py')
g=importlib.util.module_from_spec(spec);spec.loader.exec_module(g)

class GraphTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();base=Path(self.tmp.name)
        self.root=base/'stream';self.dep=base/'core'
        for p in (self.root,self.dep):
            p.mkdir();self.git(p,'init','-q');self.git(p,'config','user.name','Fixture')
            self.git(p,'config','user.email','fixture@example.invalid')
            (p/'source').write_text('original');self.git(p,'add','.');self.git(p,'-c','commit.gpgsign=false','commit','-qm','source')
        revision=self.git(self.dep,'rev-parse','HEAD').strip()
        pin={'identity':'innonetwork','kind':'remoteSourceControl','location':'https://fixture.invalid/Core.git',
             'state':{'revision':revision,'version':'6.1.1'}}
        (self.root/'Package.resolved').write_text(json.dumps({'pins':[pin]}))
        self.node={'identity':'innonetwork','url':pin['location'],'version':'6.1.1','path':str(self.dep),'dependencies':[]}
        self.graph={'dependencies':[{'path':str(self.root),'dependencies':[self.node]}]}
    def tearDown(self):self.tmp.cleanup()
    def git(self,path,*args):return subprocess.check_output(['git','-C',str(path),*args],text=True,stderr=subprocess.PIPE)
    def test_clean_graph_passes(self):self.assertEqual(g.check(self.root,self.graph)['active_clean_pins'][0]['identity'],'innonetwork')
    def test_dirty_and_untracked_dependency_fail(self):
        (self.dep/'source').write_text('dirty')
        with self.assertRaises(ValueError):g.check(self.root,self.graph)
        (self.dep/'source').write_text('original');(self.dep/'extra.swift').write_text('untracked')
        with self.assertRaises(ValueError):g.check(self.root,self.graph)
    def test_wrong_revision_version_and_url_fail(self):
        original=dict(self.node)
        for field,value in [('version','6.1.0'),('url','https://different.invalid/Core.git')]:
            self.node[field]=value
            with self.assertRaises(ValueError):g.check(self.root,self.graph)
            self.node.update(original)
        (self.dep/'source').write_text('changed');self.git(self.dep,'add','.');self.git(self.dep,'-c','commit.gpgsign=false','commit','-qm','change')
        with self.assertRaises(ValueError):g.check(self.root,self.graph)
    def test_missing_stream_or_core_fail(self):
        with self.assertRaises(ValueError):g.check(self.root,{'dependencies':[self.node]})
        self.graph['dependencies'][0]['dependencies']=[]
        with self.assertRaises(ValueError):g.check(self.root,self.graph)

if __name__=='__main__':unittest.main()
