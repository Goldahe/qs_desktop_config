import importlib.util, json, pathlib, subprocess, unittest
spec = importlib.util.spec_from_file_location('router', pathlib.Path(__file__).resolve().parents[1] / 'close-window.py')
router = importlib.util.module_from_spec(spec); spec.loader.exec_module(router)
class RouterTest(unittest.TestCase):
    def exercise(self, reply, instances, expected):
        calls=[]
        def run(*args):
            calls.append(args)
            text=''
            if args[1] == 'activewindow': text=json.dumps({'address':'0x123'})
            elif args[1] == 'ipc': text=reply
            elif args[1] == 'list': text=json.dumps(instances)
            return subprocess.CompletedProcess(args,0,text,'')
        router.run=run; router.main()
        dispatched=[x for x in calls if x[1]=='dispatch']
        self.assertEqual(bool(dispatched),expected,calls)
        if dispatched: self.assertIn('address:0x123',dispatched[0][2])
    def test_popup_consumes(self): self.exercise('closed',[{}],False)
    def test_busy_or_unknown_main_fails_closed(self): self.exercise('',[{}],False)
    def test_confirmed_absent_main_falls_back(self): self.exercise('',[],True)
    def test_no_popup_targets_original_address(self): self.exercise('none',[{}],True)
if __name__ == '__main__': unittest.main()
