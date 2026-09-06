"""Private-Weston functional search evidence; no latency/parity measurement."""
import argparse, hashlib, json, os, select, struct, subprocess, sys, tempfile, time
from pathlib import Path
from private_baseline import FOOT, MONSTAR, command

QUERY = 'needle'

def child(root, wrapped):
    import tty
    tty.setraw(0)
    root = Path(root)
    geometry = os.get_terminal_size(1)
    prefix = 'X' * (geometry.columns - 2) if wrapped else ''
    payload = (prefix + QUERY + '\r\n' + 'filler\r\n' * 60).encode()
    pending = payload
    while pending: pending = pending[os.write(1, pending):]
    (root/'ready').write_text(json.dumps({'cols':geometry.columns,'rows':geometry.lines,'payload_hex':payload.hex()}))
    received = bytearray()
    while not (root/'stop').exists():
        if select.select([0], [], [], .02)[0]:
            received.extend(os.read(0, 4096))
            (root/'input').write_bytes(received)

def wait(path, process):
    end = time.monotonic()+10
    while not path.exists():
        if process.poll() is not None: raise RuntimeError(f'process exited {process.returncode}')
        if time.monotonic()>end: raise TimeoutError(str(path))
        time.sleep(.02)

def run(args):
    report = {'scope':__doc__, 'query':QUERY, 'cases':[], 'status':'running'}
    output = Path(args.output)
    with tempfile.TemporaryDirectory(prefix='cudaterm-search-comparators-') as folder:
        root=Path(folder); os.mkfifo(root/'keys',0o600)
        env=dict(os.environ,XDG_RUNTIME_DIR=folder,WAYLAND_DISPLAY='search-comparators',CUDATERM_TEST_KEYS=str(root/'keys'))
        env.pop('DISPLAY',None)
        (root/'config').mkdir(); env['XDG_CONFIG_HOME']=str(root/'config')
        report['config_scope']='Empty private XDG_CONFIG_HOME; CLI font/grid/history options recorded per case.'
        cmd=[args.weston,'--backend=headless','--renderer=gl','--shell=desktop','--socket=search-comparators','--no-config','--debug','--modules='+args.seat,'--width=1200','--height=900']
        report['compositor_command']=cmd
        with output.with_suffix('.weston.log').open('w') as log:
            weston=subprocess.Popen(cmd,env=env,stdout=log,stderr=log)
            try:
                wait(root/'search-comparators',weston)
                for kind,binary in [('foot',FOOT),('monstar',MONSTAR)]:
                    for wrapped in (False,True):
                        case=root/f'{kind}-{int(wrapped)}';case.mkdir()
                        launch=command(kind,binary,40,24,str(case))[:-4]+[sys.executable,str(Path(__file__).resolve()),'--child',str(case),str(int(wrapped))]
                        if kind == 'foot': launch.insert(1,'--config=/dev/null')
                        rec={'terminal':kind,'binary_sha256':hashlib.sha256(Path(binary).read_bytes()).hexdigest(),'wrapped':wrapped,'command':launch}
                        report['cases'].append(rec)
                        with output.with_name(output.stem+f'-{kind}-{int(wrapped)}.log').open('w') as terminal_log:
                            proc=subprocess.Popen(launch,env=env,stdout=terminal_log,stderr=terminal_log)
                            try:
                                wait(case/'ready',proc);rec.update(json.loads((case/'ready').read_text()));time.sleep(.25)
                                subprocess.run([args.wl_copy],input=QUERY.encode(),env=env,check=True,timeout=5)
                                with (root/'keys').open('wb',buffering=0) as keys:
                                    def event(code,value):keys.write(struct.pack('=II',code,value))
                                    def chord(code):
                                        for k,v in [(29,1),(42,1),(code,1),(code,0),(42,0),(29,0)]:event(k,v)
                                    chord(19 if kind=='foot' else 33);time.sleep(.15)
                                    for code in (49,18,18,32,38,18):
                                        event(code,1);event(code,0);time.sleep(.03)
                                    time.sleep(.2)
                                    for old in root.glob('*.png'): old.unlink()
                                    subprocess.run([str(Path(args.weston).with_name('weston-screenshooter'))],env=env,cwd=root,check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,timeout=5)
                                    capture=next(root.glob('*.png')); capture_target=output.with_name(output.stem+f'-{kind}-{int(wrapped)}.png');capture_target.write_bytes(capture.read_bytes());rec['search_capture']=str(capture_target)
                                    subprocess.run([args.wl_copy],input=b'UNTOUCHED',env=env,check=True,timeout=5)
                                    if kind != 'foot':
                                        event(28,1);event(28,0);time.sleep(.15)
                                    chord(46);time.sleep(.15)
                                    copied=subprocess.run([args.wl_paste,'--no-newline'],env=env,capture_output=True,timeout=5)
                                    rec.update(copied_hex=copied.stdout.hex(),clipboard_exit=copied.returncode,clipboard_stderr=copied.stderr.decode(errors='replace'),input_during_search_hex=(case/'input').read_bytes().hex() if (case/'input').exists() else '')
                                    rec['pass']=copied.returncode==0 and copied.stdout==QUERY.encode() and rec['input_during_search_hex']==''
                                (case/'stop').touch();proc.wait(timeout=5)
                            except Exception as e:rec['error']=str(e);rec['pass']=False
                            finally:
                                if proc.poll() is None:proc.terminate();proc.wait(timeout=5)
                        output.write_text(json.dumps(report,indent=2)+'\n')
            finally:weston.terminate();weston.wait(timeout=5)
    report['status']='pass' if all(c.get('pass') for c in report['cases']) and len(report['cases'])==4 else 'fail'
    output.write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps({'status':report['status'],'cases':[{k:c.get(k) for k in ('terminal','wrapped','pass','error','copied_hex','input_during_search_hex')} for c in report['cases']]}))

if __name__=='__main__':
    if sys.argv[1]=='--child':child(sys.argv[2],bool(int(sys.argv[3])))
    else:
        p=argparse.ArgumentParser();p.add_argument('--weston',required=True);p.add_argument('--seat',required=True);p.add_argument('--wl-copy',required=True);p.add_argument('--wl-paste',required=True);p.add_argument('--output',required=True);run(p.parse_args())
