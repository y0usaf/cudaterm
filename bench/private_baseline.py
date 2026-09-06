#!/usr/bin/env python3
"""Private headless Weston idle resource baseline."""
import argparse, hashlib, json, os, shutil, subprocess, sys, tempfile, time
from pathlib import Path
import xml.etree.ElementTree as ET

FOOT = "/nix/store/ls22769pvdl3c28rg16gqc5psckf6kxx-foot-1.27.0/bin/foot"
MONSTAR = "/nix/store/h8q9vhbxzpsla7m2hqgqygyw6wd0pjny-monstar-1.1.0/bin/monstar"
CHILD = r'''import json,os,pathlib,sys,time
root=pathlib.Path(sys.argv[1]); os.write(1,b'baseline ready\r\n'); time.sleep(.5)
cols,rows=os.get_terminal_size(); geometry={'cols':cols,'rows':rows}
(root/'ready').write_text(json.dumps(geometry)); samples=[]
while not (root/'stop').exists():
    samples.append({'time_ns':time.monotonic_ns(),'cols':os.get_terminal_size().columns,'rows':os.get_terminal_size().lines})
    time.sleep(.1)
(root/'final').write_text(json.dumps({'geometry':{'cols':os.get_terminal_size().columns,'rows':os.get_terminal_size().lines},'samples':samples}))
'''

def sha256(path):
    h=hashlib.sha256()
    with open(path,'rb') as f:
        for block in iter(lambda:f.read(1024*1024),b''): h.update(block)
    return h.hexdigest()

def stop_process(process):
    if process.poll() is not None: return
    process.terminate()
    try: process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        process.kill(); process.wait(timeout=5)

def proc_sample(pid):
    mem={}
    for line in Path(f'/proc/{pid}/smaps_rollup').read_text().splitlines():
        key,sep,value=line.partition(':')
        if sep and value.strip().endswith('kB'): mem[key]=int(value.split()[0])*1024
    group_fields=Path(f'/proc/{pid}/stat').read_text().rsplit(')',1)[1].split()
    cpu_ticks=int(group_fields[11])+int(group_fields[12]); switches={'voluntary_ctxt_switches':0,'nonvoluntary_ctxt_switches':0}; threads={}
    incomplete=False
    for stat_path in Path(f'/proc/{pid}/task').glob('*/stat'):
        tid=stat_path.parent.name
        try: fields=stat_path.read_text().rsplit(')',1)[1].split()
        except FileNotFoundError: incomplete=True; continue
        ticks=int(fields[11])+int(fields[12]); threads[tid]={'cpu_ticks':ticks}
        status_path=stat_path.parent/'status'
        try: lines=status_path.read_text().splitlines()
        except FileNotFoundError: incomplete=True; continue
        for line in lines:
            key,sep,value=line.partition(':')
            if sep and key in switches: switches[key] += int(value); threads[tid][key]=int(value)
    ticks=os.sysconf('SC_CLK_TCK')
    return {'rss_bytes':mem['Rss'],'pss_bytes':mem['Pss'],
            'private_bytes':mem['Private_Clean']+mem['Private_Dirty'],
            'cpu_seconds':cpu_ticks/ticks,'thread_stats':threads,'thread_snapshot_incomplete':incomplete, **switches}

def nvidia_sample(pid):
    command=shutil.which('nvidia-smi')
    if not command: return {'memory_bytes':None,'raw_xml':None,'error':'nvidia-smi unavailable'}
    try: raw=subprocess.check_output([command,'-q','-x'],text=True,stderr=subprocess.STDOUT,timeout=15)
    except (OSError,subprocess.CalledProcessError,subprocess.TimeoutExpired) as e:
        return {'memory_bytes':None,'raw_xml':None,'error':str(e)}
    memory=None; matching=None; gpu_metadata={}
    try:
        root=ET.fromstring(raw); gpu=root.find('.//gpu'); gpu_metadata={'driver_version':root.findtext('driver_version'), 'gpu_id':gpu.get('id') if gpu is not None else None, 'product_name':gpu.findtext('product_name') if gpu is not None else None}
        for gpu in root.findall('.//gpu'):
            for process in gpu.findall('./processes/process_info'):
                if (process.findtext('pid') or '') == str(pid):
                    used=process.findtext('used_memory'); memory=int(used.split()[0])*1024*1024 if used else None
                    matching=ET.tostring(process,encoding='unicode')
    except (ET.ParseError,ValueError): pass
    return {'memory_bytes':memory,'gpu_metadata':gpu_metadata,'process_info_xml':matching,'error':None}

def command(kind,binary,cols,rows,folder,controlled=False):
    if kind=='foot':
        opts=[binary]
        if controlled: opts += ['--config','/dev/null']
        opts += ['-o','font=DejaVu Sans Mono:size=11','-o','line-height=16px','-o','scrollback.lines=4096','--window-size-chars',f'{cols}x{rows}','-e']
    elif kind=='monstar':
        opts=[binary]
        if controlled: opts += ['--config','/dev/null']
        opts += ['--font','DejaVu Sans Mono','-o','font-size=17px','-o','adjust-cell-height=-6','-o','scrollback-limit=50000000','--window-size-chars',f'{cols}x{rows}','-e']
    else: opts=[binary,'--cols',str(cols),'--rows',str(rows),'-e']
    return [*opts,sys.executable,'-c',CHILD,folder]

def font_probe(kind, env):
    pattern={'foot':'DejaVu Sans Mono:size=11','monstar':'DejaVu Sans Mono:pixelsize=17'}.get(kind)
    if pattern is None: return {'kind':'not-applicable','actual_client_font':False}
    executable=shutil.which('fc-match',path=env.get('PATH')) or shutil.which('fc-match')
    if not executable: return {'kind':'fontconfig-resolver-proxy','actual_client_font':False,'requested_pattern':pattern,'error':'fc-match unavailable'}
    fmt='%{family}\n%{style}\n%{file}\n%{index}\n%{pixelsize}\n'
    try: raw=subprocess.check_output([executable,'-f',fmt,pattern],env=env,text=True,stderr=subprocess.STDOUT,timeout=10)
    except (OSError,subprocess.CalledProcessError,subprocess.TimeoutExpired) as error:
        return {'kind':'fontconfig-resolver-proxy','actual_client_font':False,'requested_pattern':pattern,'executable':os.path.realpath(executable),'error':str(error)}
    values=raw.rstrip('\n').split('\n')
    executable=os.path.realpath(executable)
    result={'kind':'fontconfig-resolver-proxy','actual_client_font':False,'requested_pattern':pattern,'executable':executable,
            'family':values[0] if len(values)>0 else None,'style':values[1] if len(values)>1 else None,
            'file':values[2] if len(values)>2 else None,'index':values[3] if len(values)>3 else None,
            'pixelsize':values[4] if len(values)>4 else None}
    result['executable_sha256']=sha256(executable)
    if result['file'] and os.path.isfile(result['file']): result['fontfile_sha256']=sha256(result['file'])
    return result

def child_environment(env, config_root, controlled, fontconfig=None):
    result=dict(env)
    if controlled:
        result['XDG_CONFIG_HOME']=str(config_root)
        result.pop('FONTCONFIG_FILE',None); result.pop('FONTCONFIG_PATH',None)
        if fontconfig: result['FONTCONFIG_FILE']=os.path.realpath(fontconfig)
    return result

def sample(kind,binary,cols,rows,seconds,env,controlled=False,fontconfig=None):
    with tempfile.TemporaryDirectory(prefix='cudaterm-private-baseline-') as folder:
        root=Path(folder); cmd=command(kind,binary,cols,rows,folder,controlled)
        config_root=root/'config'
        if controlled: config_root.mkdir()
        sample_env=child_environment(env,config_root,controlled,fontconfig)
        resolver=font_probe(kind,sample_env)
        start=time.monotonic_ns(); proc=subprocess.Popen(cmd,env=sample_env,stdout=subprocess.DEVNULL,stderr=subprocess.PIPE,text=True)
        try:
            deadline=time.monotonic()+15
            while not (root/'ready').exists():
                if proc.poll() is not None: raise RuntimeError('terminal exited before readiness')
                if time.monotonic()>deadline: raise TimeoutError('terminal did not become ready')
                time.sleep(.02)
            geometry=json.loads((root/'ready').read_text()); time.sleep(.5)
            gpu_before=nvidia_sample(proc.pid); before=proc_sample(proc.pid); begin=time.monotonic_ns(); time.sleep(seconds)
            after=proc_sample(proc.pid); end=time.monotonic_ns(); gpu_after=nvidia_sample(proc.pid); (root/'stop').touch()
            final_deadline=time.monotonic()+2
            while not (root/'final').exists() and time.monotonic()<final_deadline: time.sleep(.01)
            final=json.loads((root/'final').read_text())
            requested={'cols':cols,'rows':rows}
            if geometry != requested or final['geometry'] != requested or any({k:v for k,v in point.items() if k != 'time_ns'} != requested for point in final['samples']): raise RuntimeError(f'geometry changed: {geometry} -> {final}')
            if proc.wait(timeout=10)!=0: raise RuntimeError(proc.stderr.read())
            return {'command':cmd,'requested_geometry':{'cols':cols,'rows':rows},'actual_geometry':geometry,
                    'elapsed_seconds':(end-begin)/1e9,'launch_start_ns':start,'launch_end_ns':end,
                    'idle_payload':'baseline ready\\r\\n','idle_payload_bytes':16,
                    'before':before,'after':after,'cpu_seconds_delta':after['cpu_seconds']-before['cpu_seconds'],
                    'thread_set_stable':set(before['thread_stats']) == set(after['thread_stats']),
                    'context_switch_delta':({k:after[k]-before[k] for k in ('voluntary_ctxt_switches','nonvoluntary_ctxt_switches')} if set(before['thread_stats']) == set(after['thread_stats']) and not before['thread_snapshot_incomplete'] and not after['thread_snapshot_incomplete'] else None),
                    'geometry_samples':final['samples'],'nvidia_before':gpu_before,'nvidia_after':gpu_after,
                    'font_resolution_proxy':resolver}
        finally:
            stop_process(proc)

def main(args):
    terminals=[('foot',args.foot),('monstar',args.monstar),('cudaterm',args.cudaterm)]
    for _,binary in terminals:
        if not os.path.isfile(binary) or not os.access(binary,os.X_OK): raise SystemExit(f'executable not found: {binary}')
    for path in (args.weston,args.seat):
        if not os.path.exists(path): raise SystemExit(f'file not found: {path}')
    if args.fontconfig and not args.controlled_config: raise SystemExit('--fontconfig requires --controlled-config')
    if args.fontconfig and not os.path.isfile(args.fontconfig): raise SystemExit(f'file not found: {args.fontconfig}')
    weston_command=[args.weston,'--backend=headless','--renderer=gl','--shell=desktop','--socket=wayland-private-baseline','--no-config','--debug','--modules='+args.seat,'--width=2800','--height=1600']
    try: weston_version=subprocess.check_output([args.weston,'--version'],text=True,stderr=subprocess.STDOUT,timeout=10).strip()
    except Exception as error: weston_version=f'unavailable: {error}'
    cpu_model=next((line.split(':',1)[1].strip() for line in Path('/proc/cpuinfo').read_text().splitlines() if line.startswith('model name')), 'unknown')
    output=Path(args.output); output.parent.mkdir(parents=True,exist_ok=True)
    uname=os.uname(); host_uname={key:getattr(uname,key) for key in ('sysname','nodename','release','version','machine')}
    controlled_config = None
    if args.controlled_config:
        controlled_config={'enabled':True,'fontconfig_file':os.path.realpath(args.fontconfig) if args.fontconfig else None,
                           'fontconfig_sha256':sha256(args.fontconfig) if args.fontconfig else None,
                           'terminal_config':'/dev/null for Foot and Monstar; isolated XDG_CONFIG_HOME',
                           'fontconfig_environment':'clear inherited FONTCONFIG_FILE and FONTCONFIG_PATH; set FONTCONFIG_FILE only when supplied'}
    report={'benchmark':'private-headless-idle-resources','status':'running','scope':'private headless Weston; terminal parent only; initialized with baseline ready marker before settling; no user desktop',
            'weston_command':weston_command,'weston_version':weston_version,'host_uname':host_uname,'cpu_model':cpu_model,'seconds':args.seconds,'repeats':args.repeat,
            'geometries':[{'cols':80,'rows':24},{'cols':318,'rows':89}],'terminals':{},'controlled_config':controlled_config}
    with tempfile.TemporaryDirectory(prefix='cudaterm-private-weston-') as folder:
        root=Path(folder); env=dict(os.environ,XDG_RUNTIME_DIR=folder,WAYLAND_DISPLAY='wayland-private-baseline'); env.pop('DISPLAY',None)
        if args.controlled_config:
            env.pop('FONTCONFIG_FILE',None)
            env.pop('FONTCONFIG_PATH',None)
            if args.fontconfig: env['FONTCONFIG_FILE']=os.path.realpath(args.fontconfig)
        log=(root/'weston.log').open('w'); compositor=subprocess.Popen(weston_command,env=env,stdout=log,stderr=log)
        try:
            deadline=time.monotonic()+15; socket=root/'wayland-private-baseline'
            while not socket.exists():
                if compositor.poll() is not None or time.monotonic()>deadline: raise RuntimeError('private Weston failed to start')
                time.sleep(.05)
            for geometry in ((80,24),(318,89)):
              for repeat in range(args.repeat):
                for kind,binary in terminals[repeat % len(terminals):]+terminals[:repeat % len(terminals)]:
                  if kind not in report['terminals']:
                    report['terminals'][kind]={'path':os.path.realpath(binary),'sha256':sha256(binary),
                       'scrollback':'Foot scrollback.lines=4096; Monstar scrollback-limit=50000000; cudaterm fixed 4096 rows','samples':[]}
                  entry=report['terminals'][kind]
                  try:
                    measured=sample(kind,binary,*geometry,args.seconds,env,args.controlled_config,args.fontconfig)
                  except Exception as error:
                    report['status']='failed'
                    entry['samples'].append({'geometry':{'cols':geometry[0],'rows':geometry[1]},'error':str(error)})
                    output.write_text(json.dumps(report,indent=2)+'\n')
                    raise
                  entry['samples'].append({'geometry':{'cols':geometry[0],'rows':geometry[1]},'sample':measured})
                  output.write_text(json.dumps(report,indent=2)+'\n')
        finally:
            stop_process(compositor); log.close()
            output=Path(args.output); output.parent.mkdir(parents=True,exist_ok=True)
            report['weston_log']=str(output.with_suffix('.weston.log'))
            shutil.copyfile(root/'weston.log',output.with_suffix('.weston.log'))
    report['status']='passed'; output.write_text(json.dumps(report,indent=2)+'\n'); print(json.dumps({'output':str(output)}))

if __name__=='__main__':
    p=argparse.ArgumentParser(); p.add_argument('--weston',required=True); p.add_argument('--seat',required=True); p.add_argument('--cudaterm',required=True); p.add_argument('--foot',default=FOOT); p.add_argument('--monstar',default=MONSTAR); p.add_argument('--output',required=True); p.add_argument('--seconds',type=float,default=3); p.add_argument('--repeat',type=int,default=3); p.add_argument('--controlled-config',action='store_true',help='isolate terminal config and record fontconfig resolver evidence'); p.add_argument('--fontconfig',help='optional FONTCONFIG_FILE used with --controlled-config'); a=p.parse_args()
    if not 3<=a.seconds<=60 or a.repeat<3: p.error('seconds must be in [3,60] and repeat at least 3')
    main(a)
