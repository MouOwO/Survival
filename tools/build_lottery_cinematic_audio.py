"""Generate original stereo summon soundtracks. No audio sampled from reference games."""
from pathlib import Path
import sys,json,wave,subprocess
sys.path.insert(0,str(Path('output/lottery_cinematic_20260929/deps').resolve()))
import numpy as np
RATE=48000;DURATION=7.;N=int(RATE*DURATION);rng=np.random.default_rng(929)
OUT=Path('output/lottery_cinematic_20260929/audio');OUT.mkdir(parents=True,exist_ok=True)
def tone(freq,dur,decay=2,amp=.1):
 t=np.arange(int(dur*RATE))/RATE
 return amp*np.sin(2*np.pi*freq*t)*(1-np.exp(-t*70))*np.exp(-t*decay)
def noise(dur,low,high):
 n=int(dur*RATE);f=np.fft.rfftfreq(n,1/RATE);s=np.fft.rfft(rng.normal(0,1,n));mask=np.minimum(1,np.maximum(0,(f-low)/max(1,low*.2)))*np.minimum(1,np.maximum(0,(high-f)/max(1,high*.2)));a=np.fft.irfft(s*mask,n);return a/(np.std(a)+1e-8)
def make(pool,root):
 x=np.zeros((N,2),dtype=np.float64)
 def put(y,start,pan=0):
  a=int(start*RATE);n=min(len(y),N-a)
  if n<=0:return
  x[a:a+n,0]+=y[:n]*np.sqrt((1-pan)/2);x[a:a+n,1]+=y[:n]*np.sqrt((1+pan)/2)
 t=np.arange(N)/RATE;env=np.minimum(t/.8,1)*np.clip((6.8-t)/1.1,0,1)
 for ratio in [1,1.5,2,3]:put(np.sin(2*np.pi*root*ratio*t+.07*np.sin(t*2))*env*.022/ratio,0,ratio/4-.5)
 # Metal contact, weight of the gate, a swell of air, and the opening impact.
 put(tone(root*2,2.3,2.7,.14)+tone(root*2*2.71,2.3,4,.035),.3,-.2)
 dur=2.5;u=np.arange(int(dur*RATE))/RATE
 put(noise(dur,45,1800)*np.sin(np.pi*u/dur)**2*.046,1.,0)
 put(noise(1.4,300,6000)*np.linspace(0,1,int(RATE*1.4))**2*.09,1.45,.25)
 put(tone(52,1.4,4,.27),2.8,0)
 put(noise(.8,80,800)*np.exp(-np.arange(int(.8*RATE))/RATE*7)*.08,2.8,-.1)
 if pool=='cultivation':
  # Layered low growl and high airy harmonics accompany the dragon's approach.
  u=np.arange(int(1.7*RATE))/RATE;freq=76+36*np.sin(u*1.6);phase=2*np.pi*np.cumsum(freq)/RATE
  y=sum(np.sin(phase*k)/k for k in range(1,8))*np.sin(np.pi*u/1.7)**1.4*.043
  put(y,3.15,-.2);put(noise(1.7,900,5000)*np.sin(np.pi*u/1.7)**2*.022,3.15,.25)
 elif pool=='dragon_knight':
  for start in [3.1,3.55,4.1]:put(tone(44,1,5,.20)+noise(1,100,2300)*np.exp(-np.arange(RATE)/RATE*10)*.1,start)
 elif pool=='summer':
  for i in range(14):put(tone(root*(3+i%5),.65,8,.04),2.6+i*.16,(-1)**i*.65)
 else:
  for i,ratio in enumerate([2,3,4,6,8]):put(tone(root*ratio,1.3,2.8,.055),2.85+i*.24,(-1)**i*.4)
 # Accelerating ascent lands at exactly the image's 6.0-second bloom.
 u=np.arange(int(1.25*RATE))/RATE;phase=2*np.pi*(220*u+1100*u*u/2.5)
 put((np.sin(phase)*.035+noise(1.25,600,7000)*.018)*np.linspace(0,1,len(u))**1.4,4.75)
 for k,ratio in enumerate([2,2.5,3,4]):put(tone(root*ratio,1.,3,.075),5.98+k*.018,(-1)**k*.25)
 put(tone(60,1.,5,.18),5.98)
 # Short stereo reflections leave impact transients clear.
 original=x.copy()
 for delay,gain in [(.071,.17),(.137,.13),(.233,.08),(.381,.05)]:
  d=int(delay*RATE);x[d:]+=original[:-d,::-1]*gain
 fade=np.clip((DURATION-np.arange(N)/RATE)/.35,0,1);x*=fade[:,None]
 peak=np.max(np.abs(x));x*=.72/max(peak,1e-9)
 with wave.open(str(OUT/(pool+'.wav')),'wb') as w:w.setnchannels(2);w.setsampwidth(2);w.setframerate(RATE);w.writeframes((x*32767).astype('<i2').tobytes())
 return {'pool':pool,'peak_dbfs':float(20*np.log10(np.max(np.abs(x)))),'rms_dbfs':float(20*np.log10(np.sqrt(np.mean(x*x)))),'cues':{'gate':1.,'open':2.8,'theme':3.15,'ascend':4.75,'reveal':5.98}}
rows=[make(p,f) for p,f in [('map',110),('cultivation',130.8128),('dragon_knight',73.416),('summer',146.832)]]
(OUT/'mix_manifest.json').write_text(json.dumps(rows,indent=2));print(json.dumps(rows))
# Quantitative reference soundtrack envelopes: speech/music may also contribute.
ff=Path('output/lottery_cinematic_20260929/ffmpeg.txt').read_text().strip();stats=[]
for p in sorted(Path('output/lottery_cinematic_20260929').glob('ref_*.mp3')):
 raw=subprocess.check_output([ff,'-loglevel','error','-i',str(p),'-f','f32le','-ar','16000','-ac','1','pipe:1']);a=np.frombuffer(raw,dtype='<f4');windows=[float(np.sqrt(np.mean(a[i:i+1600]**2))) for i in range(0,len(a),1600)]
 stats.append({'file':p.name,'window_seconds':.1,'rms':windows})
(OUT/'reference_envelopes.json').write_text(json.dumps(stats))
