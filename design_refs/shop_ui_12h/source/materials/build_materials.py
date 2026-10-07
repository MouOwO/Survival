from pathlib import Path
base=Path(__file__).parent

def write(name,w,h,body):
 (base/(name+'.svg')).write_text(f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}">{body}</svg>')

for state in ['normal','hover','selected']:
 active=state!='normal'
 rim='#c2a76b' if active else '#9fafa8'
 write('product_'+state,296,348,f'''<defs>
 <linearGradient id="base" x1="0" y1="0" x2=".85" y2="1"><stop stop-color="#fbfaf3"/><stop offset=".52" stop-color="#f2f4ed"/><stop offset="1" stop-color="#e7ede5"/></linearGradient>
 <radialGradient id="light" cx=".25" cy=".12" r=".88"><stop stop-color="#ffffff" stop-opacity=".8"/><stop offset="1" stop-color="#ffffff" stop-opacity="0"/></radialGradient>
 <linearGradient id="rim" x1="0" y1="0" x2=".7" y2="1"><stop stop-color="{'#f5ddab' if active else '#e6e9db'}"/><stop offset=".46" stop-color="{rim}"/><stop offset="1" stop-color="{'#9e834e' if active else '#8faaa5'}"/></linearGradient>
 <filter id="grain"><feTurbulence type="fractalNoise" baseFrequency=".77" numOctaves="2" seed="31"/><feColorMatrix type="saturate" values="0"/></filter>
 <clipPath id="clip"><rect x="2" y="2" width="292" height="344" rx="7"/></clipPath>
 </defs>
 <rect x=".8" y=".8" width="294.4" height="346.4" rx="8" fill="url(#base)" stroke="url(#rim)" stroke-width="1.6"/>
 <rect x="3" y="3" width="290" height="342" rx="6" fill="url(#light)" stroke="#fffffa" stroke-width="1" stroke-opacity=".9"/>
 <g clip-path="url(#clip)"><rect width="296" height="348" filter="url(#grain)" opacity=".038" style="mix-blend-mode:multiply"/></g>
 <path d="M8 333v5q0 3 4 3h272q4 0 4-4v-5" fill="none" stroke="#758f87" stroke-opacity=".16"/>
 <path d="M16 16h12M16 16v12M280 16h-12M280 16v12" fill="none" stroke="{rim}" stroke-width=".9" opacity=".48"/>
 <path d="M16 282h110m44 0h110" stroke="#aebcaf" opacity=".52"/><path d="M140 282l8-3 8 3-8 3z" fill="#b7a574" opacity=".55"/>
 <path d="M17 283h107m48 0h107" stroke="#fffdf2" opacity=".9"/>
 ''')

write('art_well',264,224,'''<defs>
 <radialGradient id="mist" cx=".48" cy=".5" r=".6"><stop stop-color="#d7e4df" stop-opacity=".7"/><stop offset=".6" stop-color="#dee8df" stop-opacity=".35"/><stop offset="1" stop-color="#eaf0e6" stop-opacity="0"/></radialGradient>
 <radialGradient id="shadow"><stop stop-color="#294b51" stop-opacity=".23"/><stop offset=".5" stop-color="#4a6665" stop-opacity=".09"/><stop offset="1" stop-color="#476563" stop-opacity="0"/></radialGradient>
 <linearGradient id="hair" x1="0" y1="0" x2="0" y2="1"><stop stop-color="#93aba6" stop-opacity="0"/><stop offset=".5" stop-color="#a5b8ac" stop-opacity=".27"/><stop offset="1" stop-color="#93aba6" stop-opacity="0"/></linearGradient>
 </defs><ellipse cx="132" cy="116" rx="129" ry="107" fill="url(#mist)"/>
 <circle cx="132" cy="110" r="92" fill="none" stroke="url(#hair)" stroke-width=".8"/><circle cx="132" cy="110" r="86" fill="none" stroke="url(#hair)" stroke-width=".5"/>
 <ellipse cx="132" cy="192" rx="85" ry="19" fill="url(#shadow)"/>
''')
write('price_strip',264,42,'''<defs><linearGradient id="p" x1="0" y1="0" x2="0" y2="1"><stop stop-color="#c5d3c7" stop-opacity=".25"/><stop offset=".4" stop-color="#dce5d9" stop-opacity=".28"/><stop offset="1" stop-color="#f6f7ed" stop-opacity=".1"/></linearGradient></defs><rect x="2" y="1" width="260" height="39" rx="3" fill="url(#p)"/><path d="M12 1h240" stroke="#a4b8ad" opacity=".28"/><path d="M12 2h240" stroke="#fffef4" opacity=".75"/><path d="M12 39h240" stroke="#fffff3" opacity=".24"/>''')
write('hover_shade',264,224,'''<defs>
 <linearGradient id="v" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="white" stop-opacity="0"/><stop offset=".27" stop-color="white" stop-opacity="0"/><stop offset=".49" stop-color="white" stop-opacity=".76"/><stop offset=".7" stop-color="white"/><stop offset=".86" stop-color="white"/><stop offset="1" stop-color="white" stop-opacity="0"/></linearGradient>
 <linearGradient id="h"><stop stop-color="white" stop-opacity="0"/><stop offset=".13" stop-color="white" stop-opacity=".65"/><stop offset=".3" stop-color="white"/><stop offset=".7" stop-color="white"/><stop offset=".87" stop-color="white" stop-opacity=".65"/><stop offset="1" stop-color="white" stop-opacity="0"/></linearGradient>
 <mask id="m"><rect width="264" height="224" fill="url(#v)"/></mask><mask id="n"><rect width="264" height="224" fill="url(#h)"/></mask>
 </defs><g mask="url(#m)"><rect width="264" height="224" fill="#173d46" opacity=".91" mask="url(#n)"/></g>''')
# Description contrast comes from the single feathered overlay, not a second opaque stripe.
write('effect_backing',264,48,'')
write('card_cloud',264,224,'''<g fill="none" stroke="#a8bfb2" stroke-width=".8" opacity=".22"><path d="M-12 80c24-10 37 6 26 20-10 11-24-4-14-11m-8 25c38-15 42 10 62 3 16-6 5-25-5-18M180 15c20-8 26 6 16 11-10 4-10-8-5-8m-3 15c21-7 31 7 45-2 15-9-3-22-10-12M211 181c19-6 36 12 24 22-9 6-19-4-12-9m-13 20c21-11 43 1 66-7"/></g>''')
write('card_shadow',320,376,'''<defs><filter id="s" x="-20%" y="-20%" width="140%" height="140%"><feGaussianBlur stdDeviation="4.5"/></filter></defs><rect x="14" y="17" width="292" height="344" rx="8" fill="#31535b" opacity=".14" filter="url(#s)"/>''')
write('card_halo',320,376,'''<defs><filter id="g" x="-20%" y="-20%" width="140%" height="140%"><feGaussianBlur stdDeviation="2.8"/></filter></defs><rect x="12" y="8" width="296" height="348" rx="8" stroke="#deb566" stroke-width="2" fill="none" opacity=".43" filter="url(#g)"/>''')
write('content_transition',1280,96,'''<defs><linearGradient id="mist" x1="0" y1="0" x2="0" y2="1"><stop stop-color="#f4f6ed" stop-opacity="0"/><stop offset=".32" stop-color="#f4f6ed" stop-opacity=".82"/><stop offset=".68" stop-color="#f1f4eb" stop-opacity=".68"/><stop offset="1" stop-color="#f1f4eb" stop-opacity="0"/></linearGradient></defs><rect width="1280" height="96" fill="url(#mist)"/>''')
write('sidebar_seam',24,808,'''<defs><linearGradient id="fog"><stop stop-color="#e8efdf" stop-opacity="0"/><stop offset=".26" stop-color="#d9e6d7" stop-opacity=".12"/><stop offset=".32" stop-color="#91a7a3" stop-opacity=".4"/><stop offset=".4" stop-color="#eeeeda" stop-opacity=".9"/><stop offset=".52" stop-color="#f9f9ed" stop-opacity=".65"/><stop offset="1" stop-color="#e1e9dd" stop-opacity="0"/></linearGradient></defs><rect width="24" height="808" fill="url(#fog)"/><path d="M7.5 0v808" stroke="#a8b8aa" stroke-width=".7" opacity=".65"/><path d="M9 0v808" stroke="#fffced" stroke-width=".6" opacity=".6"/>''')

for state in ['normal','hover','pressed']:
 top,bottom=('#6d9d98','#3c7179') if state=='normal' else ('#80b5ab','#4b8588') if state=='hover' else ('#426f70','#2e585f')
 name='buy_button'+('' if state=='normal' else '_'+state)
 write(name,188,46,f'''<defs><linearGradient id="b" x1="0" y1="0" x2="0" y2="1"><stop stop-color="{top}"/><stop offset="1" stop-color="{bottom}"/></linearGradient><radialGradient id="l" cx=".4" cy="0" r="1"><stop stop-color="#e8f2d9" stop-opacity=".16"/><stop offset="1" stop-color="#e8f2d9" stop-opacity="0"/></radialGradient></defs><path d="M5 1h178l4 4v36l-4 4H5l-4-4V5z" fill="url(#b)" stroke="#dbcfa1" stroke-width="1"/><path d="M5 1h178l4 4v36l-4 4H5l-4-4V5z" fill="url(#l)"/><path d="M6 3h176M3 6v32" stroke="#f3f6de" stroke-opacity=".48"/><path d="M6 43h176M185 7v31" stroke="#1d4855" stroke-opacity=".4"/>''')
