'use strict';
const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const core=fs.readFileSync(process.argv[2]||'panorama/src/scripts/custom_game/combat_stats.js','utf8'),runner=fs.readFileSync(process.argv[3]||'tools/capture_extreme_scene.cjs','utf8');
function between(s,a,b){const start=s.indexOf(a),end=s.indexOf(b,start);assert(start>=0&&end>start);return s.slice(start,end);}
const emitted=[],env={customConfig:{},Date:{now:()=>12345},$: {Msg:(...parts)=>emitted.push(parts.join(''))}};
vm.createContext(env);vm.runInContext(between(core,'    function toolsProbeChecksum(','    function registerToolsProbeCommands('),env);
const parserEnv={Buffer};vm.createContext(parserEnv);vm.runInContext(between(runner,'function probeChecksum(','function bridgeState(){'),parserEnv);
const parse=(text,expected={})=>parserEnv.probeJson(text,'report',expected),nonce='0123456789abcdef01234567',id='1_2_1791490768938',serial=3,expected={nonce,commandId:id,captureSerial:serial};
const small={enabled:false,commandId:id,captureSerial:serial,rows:[{name:'short 汉字😀',ms:3}],contextActive:true,elapsedMs:10};
env.emitToolsProbeReport('CLIENT_CALLBACK_PROBE',small,nonce);assert.equal(emitted.length,1);assert(Buffer.byteLength(emitted[0])<8000);assert.deepEqual(JSON.parse(JSON.stringify(parse(emitted.join('\n'),expected))),small,'short ordinary JSON stays compatible');assert(emitted[0].includes('\\u'),'Unicode is losslessly escaped to make byte bounds deterministic');
assert.equal(parse(emitted[0],{commandId:'9_9_99'}),null);assert.equal(parse(emitted[0],{captureSerial:99}),null);
const large=Object.freeze({...small,diagnostics:{nativeHotpaths:{style:{firstMismatch:{actual:'undefined',expected:'left'}}}},rows:Array.from({length:80},(_,i)=>({name:'callback_'+i,source:'汉字😀\\"'.repeat(110),count:12345}))});
emitted.length=0;env.emitToolsProbeReport('CLIENT_CALLBACK_PROBE',large,nonce);const lines=[...emitted],footer=JSON.parse(lines.at(-1).slice('[CLIENT_CALLBACK_PROBE] '.length)),dataLines=lines.slice(0,-1);
assert.equal(footer.chunked,true);assert.equal(footer.nonce,nonce);assert.equal(footer.commandId,id);assert.equal(footer.captureSerial,serial);assert.equal(dataLines.length,footer.count);assert(footer.count>2);
for(const line of lines){assert(Buffer.byteLength(line,'utf8')<=8192);assert(/^[\x20-\x7e]+$/.test(line));}
assert(dataLines.every(line=>line.startsWith('[CLIENT_CALLBACK_PROBE_CHUNK] ')));assert(lines.at(-1).startsWith('[CLIENT_CALLBACK_PROBE] '),'normal response prefix is only emitted AFTER the final block');
const full=lines.join('\n');assert.deepEqual(JSON.parse(JSON.stringify(parse(full,expected))),large,'reassembly retains every long source/Unicode/mismatch value');
assert.deepEqual(JSON.parse(JSON.stringify(parse([...dataLines].reverse().concat(lines.at(-1)).join('\n'),expected))),large,'indexed blocks can arrive in any order before completion');
assert.equal(parse(dataLines.join('\n'),expected),null,'missing completion rejected');assert.equal(parse(lines.slice(1).join('\n'),expected),null,'missing first block rejected');assert.equal(parse(lines.slice(0,-2).concat(lines.at(-1)).join('\n'),expected),null,'missing last block rejected');assert.equal(parse([dataLines[0],...lines].join('\n'),expected),null,'duplicate block rejected');assert.equal(parse([...lines,lines.at(-1)].join('\n'),expected),null,'duplicate completion rejected');assert.equal(parse([...lines, dataLines[0]].join('\n'),expected),null,'blocks after completion rejected');
const chunkPrefix='[CLIENT_CALLBACK_PROBE_CHUNK] ';
function mutateChunk(field,value){const modified=[...lines],chunk=JSON.parse(modified[0].slice(chunkPrefix.length));chunk[field]=value;modified[0]=chunkPrefix+JSON.stringify(chunk);return modified.join('\n');}
for(const [field,value]of [['nonce','f'.repeat(24)],['commandId','9_9_99'],['captureSerial',99],['count',99],['chars',99],['checksum','ffffffff'],['index',-1],['protocol','wrong'],['data','x'.repeat(3001)]])assert.equal(parse(mutateChunk(field,value),expected),null,field+' mismatch rejected');
assert.equal(parse(mutateChunk('data',JSON.parse(dataLines[0].slice(chunkPrefix.length)).data.replace('false','true ')),expected),null,'same-length altered data fails checksum');
assert.equal(parse(full,{...expected,nonce:'f'.repeat(24)}),null);assert.equal(parse(full,{...expected,captureSerial:5}),null);assert.equal(parse(full,{...expected,commandId:'9_9_99'}),null);
assert.equal(parse(dataLines[0].slice(0,-7)+'\n'+lines.slice(1).join('\n'),expected),null,'truncated chunk rejected');assert.equal(parse('[CLIENT_CALLBACK_PROBE] '+JSON.stringify(small).slice(0,-1)),null,'old engine-truncated single line rejected');
assert.equal(parse('[CLIENT_CALLBACK_PROBE] '+JSON.stringify(small)+'\n'+full,expected),null,'mixed report formats rejected');
const extraLarge={...small,data:'x'.repeat(524288)};assert.throws(()=>env.emitToolsProbeReport('CLIENT_CALLBACK_PROBE',extraLarge,nonce),/exceeds bounded transport/);
console.log('TOOLS_PROBE_CHUNKS_PASS: <=8KB bytes, Unicode, short compatibility, final fence, current nonce/ID/serial, bounded reassembly, missing/duplicate/mixed/truncated/tampered rejection');
