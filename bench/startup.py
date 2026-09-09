#!/usr/bin/env python3
"""Paired startup phases and first GL-swap return; not physical presentation."""
import argparse, csv, json, os, pathlib, resource, shutil, statistics, subprocess, tempfile, time

p=argparse.ArgumentParser()
p.add_argument('--terminal',action='append',required=True,help='label=/absolute/path')
p.add_argument('--output',required=True)
p.add_argument('--samples',type=int,default=9)
p.add_argument('--cold-samples',type=int,default=2)
p.add_argument('--weston')
p.add_argument('--seat')
p.add_argument('--args',required=True,help='JSON array of terminal options, without a child command')
a=p.parse_args()
if a.samples < 1 or a.cold_samples < 0: p.error('samples must be positive; cold-samples cannot be negative')
if bool(a.weston) != bool(a.seat): p.error('--weston and --seat must be supplied together')
shell=shutil.which('sh')
if not shell: p.error('a POSIX shell is required')
terminals=[item.split('=',1) for item in a.terminal]
options=json.loads(pathlib.Path(a.args).read_text())
output=pathlib.Path(a.output);output.mkdir(parents=True,exist_ok=True)
rows=[]
with tempfile.TemporaryDirectory(prefix='cudaterm-startup-bench-') as folder:
 root=pathlib.Path(folder)
 env=dict(os.environ)
 weston=None
 if a.weston:
  env.update(XDG_RUNTIME_DIR=folder, WAYLAND_DISPLAY='startup-benchmark')
  env.pop('DISPLAY',None)
  weston_config=root/'weston.ini'
  weston_config.write_text('[shell]\nstartup-animation=none\n')
  log=(output/'weston.log').open('w')
  weston=subprocess.Popen([a.weston,'--backend=headless','--renderer=gl','--shell=desktop','--socket=startup-benchmark','--config='+str(weston_config),'--width=1500','--height=1000','--modules='+a.seat],env=env,stdout=log,stderr=log)
  deadline=time.monotonic()+20
  while not (root/'startup-benchmark').exists():
   if weston.poll() is not None or time.monotonic()>deadline:
    weston.terminate()
    try:weston.wait(timeout=5)
    except subprocess.TimeoutExpired:weston.kill();weston.wait()
    raise RuntimeError('compositor startup failed')
   time.sleep(.02)
  time.sleep(.5)
 try:
  def run(label,binary,mode,index):
   cache=root/label
   cache.mkdir(parents=True,exist_ok=True)
   if mode=='cold':shutil.rmtree(cache/'cudaterm/fonts',ignore_errors=True)
   trace=output/f'{label}-{mode}-{index}.csv'
   run_env=dict(env,XDG_CACHE_HOME=str(cache),CUDATERM_TRACE=str(trace))
   usage=resource.getrusage(resource.RUSAGE_CHILDREN)
   start=time.monotonic_ns()
   child=subprocess.Popen([binary,*options,'--title','Cudaterm startup benchmark','-e',shell,'-c',"printf '\\033[1mFont cache test\\033[0m \\033[3mitalic\\033[0m ✓\\n'; sleep 0.25"],env=run_env,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
   peak_rss=0
   swap_seen=None
   settled_memory={}
   while child.poll() is None:
    try:
     for line in pathlib.Path(f'/proc/{child.pid}/status').read_text().splitlines():
      if line.startswith('VmHWM:'):peak_rss=max(peak_rss,int(line.split()[1])*1024)
    except FileNotFoundError:pass
    if swap_seen is None:
     try:
      if 'gl_texture_swap' in trace.read_text(): swap_seen=time.monotonic()
     except FileNotFoundError: pass
    elif not settled_memory and time.monotonic()-swap_seen > .05:
     try:
      for line in pathlib.Path(f'/proc/{child.pid}/smaps_rollup').read_text().splitlines():
       key,_,value=line.partition(':')
       if key in ('Rss','Pss','Private_Clean','Private_Dirty','Anonymous'):
        settled_memory[key]=int(value.split()[0])*1024
     except FileNotFoundError: pass
    if time.monotonic_ns()-start>20_000_000_000:child.kill();child.communicate();raise RuntimeError('terminal timed out')
    time.sleep(.005)
   stdout,stderr=child.communicate()
   after=resource.getrusage(resource.RUSAGE_CHILDREN)
   if child.returncode:raise RuntimeError(f'{label}: {stderr.decode()}')
   events=list(csv.DictReader(trace.open()))
   swap=next(r for r in events if r['stage']=='gl_texture_swap')
   row=dict(label=label,mode=mode,index=index,first_swap_ms=(int(swap['end_ns'])-start)/1e6,
      cpu_ms=((after.ru_utime-usage.ru_utime)+(after.ru_stime-usage.ru_stime))*1000,
      peak_rss_bytes=peak_rss,settled_memory_bytes=settled_memory,stages_ms={r['stage']:(int(r['end_ns'])-int(r['start_ns']))/1e6 for r in events if r['stage'].startswith('startup_')},stderr=stderr.decode())
   rows.append(row)
   print(json.dumps(row),flush=True)
  for i in range(a.cold_samples):
   for label,binary in terminals:run(label,binary,'cold',i)
  for i in range(a.samples):
   for label,binary in (terminals if i%2==0 else reversed(terminals)):run(label,binary,'warm',i)
 finally:
  if weston:
   weston.terminate()
   try:weston.wait(timeout=5)
   except subprocess.TimeoutExpired:weston.kill();weston.wait()
 summary={}
 for label,_ in terminals:
  summary[label]={}
  for mode in ('cold','warm'):
   group=[r for r in rows if r['label']==label and r['mode']==mode]
   if not group:continue
   stages=group[0]['stages_ms']
   summary[label][mode]={'count':len(group),'first_swap_median_ms':statistics.median(r['first_swap_ms'] for r in group),'first_swap_min_ms':min(r['first_swap_ms'] for r in group),'first_swap_max_ms':max(r['first_swap_ms'] for r in group),'cpu_median_ms':statistics.median(r['cpu_ms'] for r in group),'peak_rss_median_bytes':statistics.median(r['peak_rss_bytes'] for r in group),'settled_pss_median_bytes':statistics.median(r['settled_memory_bytes']['Pss'] for r in group if 'Pss' in r['settled_memory_bytes']),'stages_median_ms':{s:statistics.median(r['stages_ms'][s] for r in group) for s in stages}}
 result=dict(terminals=terminals,options=options,limitations='Process launch to first GL swap return, not compositor presentation/scanout. Cold means font cache removed, not cold filesystem or GPU. VmHWM polled every 5 ms; settled PSS sampled at least 50 ms after observing the first swap. Fixed child command, no interactive-shell initialization.',rows=rows,summary=summary)
 (output/'results.json').write_text(json.dumps(result,indent=2))
 print(json.dumps(summary,indent=2))
