'use strict';
const path=require('node:path');
const {browser}=require('../commerce_points_20261016/cdp.cjs');
const out=path.resolve(__dirname,'../../output/daily_native_icons_20261017');
(async()=>{
    const b=await browser();
    try {
        await b.call('Emulation.setDeviceMetricsOverride',{width:1600,height:1440,deviceScaleFactor:1,mobile:false});
        await b.go(path.join(out,'comparison.html'));
        const check=await b.run('({images:document.images.length,missing:[...document.images].filter(i=>!i.complete||!i.naturalWidth).map(i=>i.src),height:document.documentElement.scrollHeight})');
        if(check.missing.length)throw Error('Missing native previews: '+JSON.stringify(check.missing));
        await b.shot(path.join(out,'comparison.png'),{x:0,y:0,width:1600,height:check.height});
        console.log(JSON.stringify({kind:'offline_browser_comparison',png:path.join(out,'comparison.png'),...check}));
    } finally { b.close(); }
})().catch(error=>{console.error(error);process.exitCode=1;});
