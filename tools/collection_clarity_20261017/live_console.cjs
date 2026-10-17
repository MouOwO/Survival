'use strict';
// Local native console only. Suppress engine history and credential-like lines.
const {ConsoleSession}=require('../map_c6/console-session.cjs');
const crypto=require('node:crypto'),fs=require('node:fs');
async function main(){
 const command=process.argv[2];if(!command||/[\r\n\0]/.test(command))throw Error('One explicit console command required');
 const s=new ConsoleSession({port:29000,timeoutMs:6000,historyTimeoutMs:15000,retainOutput:false});
 try{await s.connect();const marker='COLLECTION_CLARITY_'+crypto.randomBytes(12).toString('hex');
 const r=await s.send([{name:'console_send',arguments:{commands:command+'\necho '+marker}}],marker,150);
 const clean=r.output.split(/\r?\n/).filter(line=>!/(?:token|password|secret|authorization|credential)/i.test(line)).join('\n');
 if(process.argv[3])fs.writeFileSync(process.argv[3],clean);else process.stdout.write(clean);
 console.log(JSON.stringify({native:true,matched:r.expected_output_received,command,historyNotPrinted:true}));
 }finally{await s.close();}
}
main().catch(e=>{console.error(e.message);process.exitCode=1;});
