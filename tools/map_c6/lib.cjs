const fs = require('fs');
const path = require('path');

function endOf(text, start, left = '{', right = '}') {
  let depth = 0, quoted = false, escaped = false;
  for (let i = start; i < text.length; i++) {
    const c = text[i];
    if (quoted) { if (escaped) escaped = false; else if (c === '\\') escaped = true; else if (c === '"') quoted = false; continue; }
    if (c === '"') quoted = true;
    else if (c === left) depth++;
    else if (c === right && --depth === 0) return i + 1;
  }
  throw new Error('Unbalanced DMX');
}
function blocks(text, type) {
  const out = []; let cursor = 0;
  while ((cursor = text.indexOf('"' + type + '"', cursor)) >= 0) {
    const start = cursor, open = text.indexOf('{', cursor), end = endOf(text, open);
    out.push({start, end, text: text.slice(start, end)}); cursor = end;
  }
  return out;
}
function array(text, key) {
  const re = new RegExp('"' + key + '" "\\w+_array"\\s*\\[([^\\]]*)\\]');
  const match = text.match(re); if (!match) throw new Error('Missing array ' + key);
  return [...match[1].matchAll(/"([^"\r\n]*)"/g)].map(x => x[1]);
}
function setArray(text, key, values) {
  const re = new RegExp('("' + key + '" "\\w+_array"\\s*)\\[[^\\]]*\\]');
  if (!re.test(text)) throw new Error('Missing array ' + key);
  const body = '[\n' + values.map(v => '"' + v + '"').join(',\n') + '\n]';
  return text.replace(re, (_, head) => head + body);
}
function value(text, key) {
  return text.match(new RegExp('"'+key+'" "(?:string|int|bool|vector3|qangle|color|float)" "([^"\r\n]*)"'))?.[1];
}
function setValue(text, key, val) {
  return text.replace(new RegExp('("'+key+'" "(?:string|int|bool|vector3|qangle|color|float)" ")[^"\r\n]*(")'), (_,a,b) => a+val+b);
}
function records(values) {
  const out=[]; for(let p=0;p<values.length;) { const n=+values[p++]; if(n<0||p+n>values.length)throw new Error('Invalid record');out.push(values.slice(p,p+n));p+=n; } return out;
}
class Vpk {
  constructor(filename) {
    this.filename=filename; const b=fs.readFileSync(filename); const version=b.readUInt32LE(4), size=b.readUInt32LE(8);
    if(b.readUInt32LE(0)!==0x55aa1234)throw new Error('Bad VPK');
    let p=version===2?28:12; this.dataStart=p+size; this.entries=new Map();
    const str=()=>{const end=b.indexOf(0,p);const s=b.toString('utf8',p,end);p=end+1;return s;};
    let ext,dir,name;
    while((ext=str()))while((dir=str()))while((name=str())) {
      const preload=b.readUInt16LE(p+4), archive=b.readUInt16LE(p+6), offset=b.readUInt32LE(p+8), length=b.readUInt32LE(p+12);p+=18;
      this.entries.set((dir===' '?'':dir+'/')+name+'.'+ext,{archive,offset,length,preload:Buffer.from(b.subarray(p,p+preload))});p+=preload;
    }
  }
  read(key) {
    const e=this.entries.get(key);if(!e)throw new Error('Missing VPK resource '+key);
    const file=e.archive===0x7fff?this.filename:this.filename.replace(/_dir\.vpk$/,'_'+String(e.archive).padStart(3,'0')+'.vpk');
    const fd=fs.openSync(file,'r'), buf=Buffer.alloc(e.length);
    fs.readSync(fd,buf,0,e.length,e.offset+(e.archive===0x7fff?this.dataStart:0));fs.closeSync(fd);
    return Buffer.concat([e.preload,buf]);
  }
}
module.exports={endOf,blocks,array,setArray,value,setValue,records,Vpk};
