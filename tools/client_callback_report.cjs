'use strict';
// Safe command-family and nonce/chunk decoder reused from capture_extreme_scene.
function currentClientProbe(logText){
  const lines=String(logText).split(/\r?\n/);
  for(let index=lines.length-1;index>=0;index--){
    const at=lines[index].indexOf('[TOOLS_PROBE_COMMANDS] ');
    if(at<0)continue;
    let value;try{value=JSON.parse(lines[index].slice(at+23));}catch{continue;}
    if(!value||value.api!=='SurvivalClientCallbackProbe')continue;
    // Never fall back to an older advertisement or execute arbitrary commands
    // from a console line. Only this known API's exact safe command family.
    if(typeof value.commandId!=='string'||!/^\d+_\d+_\d+$/.test(value.commandId)
      ||value.commandId.length>96||!value.commands)throw Error('Invalid current client probe advertisement');
    for(const [action,stem] of [['start','probe'],['report','report'],['stop','stop']]){
      const command=value.commands[action];
      if(typeof command!=='string'||!/^\w+$/.test(command)
        ||command!=='survival_client_callback_'+stem+'_v2_'+value.commandId){
        throw Error('Invalid current client probe command');
      }
    }
    return {api:value.api,commandId:value.commandId,commands:{...value.commands}};
  }
  throw Error('Current client probe commands were not advertised');
}
function probeChecksum(text){
  let hash=2166136261;
  for(let i=0;i<text.length;i++)hash=((hash^text.charCodeAt(i))*16777619)>>>0;
  return ('00000000'+hash.toString(16)).slice(-8);
}
function probeJson(output,kind,expected={}){
  const prefix=kind==='start'?'[CLIENT_CALLBACK_PROBE] started ':'[CLIENT_CALLBACK_PROBE] ';
  const chunkPrefix='[CLIENT_CALLBACK_PROBE_CHUNK] ',normal=[],chunks=[];
  try{
    for(const line of output.split(/\r?\n/)){
      const isChunk=kind==='report'&&line.startsWith(chunkPrefix);
      if(!isChunk&&!line.startsWith(prefix))continue;
      const text=line.slice(isChunk?chunkPrefix.length:prefix.length);
      if(!text.startsWith('{'))continue;
      if(isChunk&&(normal.length||Buffer.byteLength(line,'utf8')>8192))return null;
      const value=JSON.parse(text);
      (isChunk?chunks:normal).push(value);
    }
    if(kind==='start')return normal.length===1?normal[0]:null;
    if(normal.length!==1)return null;
    const footer=normal[0];
    if(!chunks.length&&footer.chunked!==true){
      if((expected.commandId&&footer.commandId!==expected.commandId)
        ||(expected.captureSerial!==undefined&&expected.captureSerial!==null&&footer.captureSerial!==expected.captureSerial))return null;
      return footer; // Existing short report.
    }
    if(footer.chunked!==true||footer.protocol!=='survival_probe_chunks_v1'
      ||typeof footer.nonce!=='string'||!/^(?:[0-9a-f]{24}|manual_\d+_\d+)$/.test(footer.nonce)
      ||typeof footer.commandId!=='string'||!/^\d+_\d+_\d+$/.test(footer.commandId)||footer.commandId.length>96
      ||!Number.isSafeInteger(footer.captureSerial)||footer.captureSerial<0
      ||!Number.isSafeInteger(footer.count)||footer.count<1||footer.count>175
      ||!Number.isSafeInteger(footer.chars)||footer.chars<1||footer.chars>524288
      ||footer.count!==Math.ceil(footer.chars/3000)||!/^[0-9a-f]{8}$/.test(footer.checksum)
      ||(expected.nonce&&footer.nonce!==expected.nonce)
      ||(expected.commandId&&footer.commandId!==expected.commandId)
      ||(expected.captureSerial!==undefined&&expected.captureSerial!==null&&footer.captureSerial!==expected.captureSerial)
      ||chunks.length!==footer.count)return null;
    const ordered=new Array(footer.count);
    for(const chunk of chunks){
      if(chunk.protocol!==footer.protocol||chunk.nonce!==footer.nonce||chunk.commandId!==footer.commandId
        ||chunk.captureSerial!==footer.captureSerial||chunk.count!==footer.count||chunk.chars!==footer.chars||chunk.checksum!==footer.checksum
        ||!Number.isSafeInteger(chunk.index)||chunk.index<0||chunk.index>=footer.count||ordered[chunk.index]!==undefined
        ||typeof chunk.data!=='string'||chunk.data.length<1||chunk.data.length>3000||/[^\x20-\x7e]/.test(chunk.data)
        ||chunk.data.length!==(chunk.index===footer.count-1?footer.chars-3000*chunk.index:3000))return null;
      ordered[chunk.index]=chunk.data;
    }
    const text=ordered.join('');
    if(text.length!==footer.chars||probeChecksum(text)!==footer.checksum)return null;
    const value=JSON.parse(text);
    if(value.commandId!==footer.commandId||value.captureSerial!==footer.captureSerial)return null;
    return value;
  }catch{return null;}
}

module.exports={currentClientProbe,probeJson,probeChecksum};
