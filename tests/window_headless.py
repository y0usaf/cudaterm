"""Isolated Wayland presentation and same-compositor memory comparison."""
import argparse
import base64
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time
import zlib


def child(folder, color):
    rgba = bytes((255,0,0,255) if color == 'red' else (0,0,255,255))*1000*40
    payload = base64.b64encode(zlib.compress(rgba))
    os.write(1,b'\x1b[?25l\x1b[H\x1b_Ga=T,f=32,o=z,s=1000,v=40,i=7,p=1,C=1,q=2;'+payload+b'\x1b\\')
    os.write(1,'\x1b[5;1HFinix — café / 中 /  / λ / é\r\n0123456789  []{}()  => !='.encode())
    Path(folder, color+'.ready').touch()
    while not Path(folder,'stop').exists(): time.sleep(.05)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--weston',required=True)
    parser.add_argument('--seat',required=True)
    parser.add_argument('--terminal',required=True)
    parser.add_argument('--idle-probe',required=True)
    parser.add_argument('--reference')
    parser.add_argument('--ekko')
    parser.add_argument('--output-dir',default='bench')
    parser.add_argument('--cols',type=int,default=318)
    parser.add_argument('--rows',type=int,default=89)
    args=parser.parse_args()
    output=Path(args.output_dir).resolve(); output.mkdir(parents=True,exist_ok=True)
    report={'terminal':os.path.realpath(args.terminal),'scope':'private headless Weston, no user desktop',
            'samples':{}}
    with tempfile.TemporaryDirectory(prefix='cudaterm-display-') as directory:
        root=Path(directory)
        env=dict(os.environ,XDG_RUNTIME_DIR=directory,WAYLAND_DISPLAY='wayland-cuda')
        env.pop('DISPLAY',None)
        with (root/'weston.log').open('w') as log:
            compositor=subprocess.Popen([args.weston,'--backend=headless','--renderer=gl','--shell=desktop',
                '--socket=wayland-cuda','--no-config','--debug','--modules='+args.seat,
                '--width=2800','--height=1600'],env=env,stdout=log,stderr=log)
            terminal=None
            try:
                end=time.monotonic()+5
                while not (root/'wayland-cuda').exists():
                    if compositor.poll() is not None or time.monotonic()>end:
                        raise RuntimeError('headless compositor failed')
                    time.sleep(.05)
                # Both binaries see exactly the same compositor and geometry.
                for label,binary in [('reference',args.reference),('current',args.terminal)]:
                    if not binary: continue
                    result=subprocess.run([sys.executable,args.idle_probe,'--terminal',binary,
                        '--terminal-arg=--cols',f'--terminal-arg={args.cols}','--terminal-arg=--rows',
                        f'--terminal-arg={args.rows}','--terminal-arg=-e','--repeat','3','--seconds','1'],
                        env=env,stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=30,check=True)
                    report['samples'][label]=json.loads(result.stdout)
                    for sample in report['samples'][label]['samples']:
                        assert sample['geometry']=={'cols':args.cols,'rows':args.rows},sample
                command=[sys.executable,str(Path(__file__).resolve()),'--child',directory,'red']
                if args.ekko:
                    command=[args.ekko,'run','--session','window-test',*command,':::',sys.executable,
                             str(Path(__file__).resolve()),'--child',directory,'blue']
                with (root/'terminal.log').open('w') as terminal_log:
                    terminal=subprocess.Popen([args.terminal,'--cols','120','--rows','40','-e',*command],
                                               env=env,stdout=terminal_log,stderr=terminal_log)
                    end=time.monotonic()+10
                    expected=['red','blue'] if args.ekko else ['red']
                    while not all((root/(c+'.ready')).exists() for c in expected):
                        if terminal.poll() is not None or time.monotonic()>end:
                            raise RuntimeError('window child failed: '+(root/'terminal.log').read_text())
                        time.sleep(.05)
                    time.sleep(.5)
                    shooter=Path(args.weston).with_name('weston-screenshooter')
                    capture=subprocess.run([str(shooter)],env=env,cwd=directory,stdout=subprocess.PIPE,
                                           stderr=subprocess.PIPE,timeout=5)
                    images=list(root.glob('*.png'))
                    if capture.returncode or not images:
                        raise RuntimeError('capture failed: '+capture.stderr.decode())
                    from PIL import Image
                    with Image.open(images[0]) as image:
                        colors=image.convert('RGB').getcolors(image.width*image.height)
                    for wanted in [(255,0,0)]+([(0,0,255)] if args.ekko else []):
                        count=sum(n for n,c in colors if all(abs(a-b)<=2 for a,b in zip(c,wanted)))
                        assert count>1000,(wanted,count)
                    shutil.copyfile(images[0],output/'headless-window.png')
                    if args.ekko:
                        subprocess.run([args.ekko,'stop','window-test'],env=env,check=True,timeout=5)
                    else:(root/'stop').touch()
                    assert terminal.wait(timeout=5)==0
                    assert not (root/'terminal.log').read_text().strip(),(root/'terminal.log').read_text()
                report['presentation']='passed'
                report['ekko']=args.ekko
                (output/'headless-window.json').write_text(json.dumps(report,indent=2)+'\n')
                print(json.dumps(report))
            finally:
                if args.ekko:
                    subprocess.run([args.ekko,'stop','window-test'],env=env,stdout=subprocess.DEVNULL,
                                   stderr=subprocess.DEVNULL,timeout=5)
                if terminal and terminal.poll() is None: terminal.terminate();terminal.wait(timeout=5)
                compositor.terminate();compositor.wait(timeout=5)
                shutil.copyfile(root/'weston.log',output/'headless-weston.log')


if __name__=='__main__':
    if len(sys.argv)>1 and sys.argv[1]=='--child':child(sys.argv[2],sys.argv[3])
    else:main()
