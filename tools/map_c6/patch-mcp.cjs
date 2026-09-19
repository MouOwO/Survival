// Compatibility fix for dota2-mcp 1.6.0 and this installed Source 2 client.
// The relay can discard an early GUI VFCS while connecting; reconnects also
// need a fresh handshake. Keep the actual VConsole GUI gate in place.
const fs=require('fs'),path=require('path');
const base=process.env.DOTA2_MCP_INSTALL||path.join(require('os').homedir(),'.codex/tools/dota2-mcp/node_modules');
const dir=path.join(base,'dota2-mcp/dist/tools');
function patch(file,from,to){
 const p=path.join(dir,file),text=fs.readFileSync(p,'utf8');
 if(text.includes(to)){console.log(file+': already patched');return;}
 if(!text.includes(from))throw Error('Unsupported upstream version: '+file);
 if(!fs.existsSync(p+'.original'))fs.copyFileSync(p,p+'.original');
 fs.writeFileSync(p,text.replace(from,to));console.log(file+': patched');
}
patch('vcon-bridge.js','this.emit("connected");',
 'this.buffer = Buffer.alloc(0);\n                this.socket.write(Buffer.concat([buildHeader("VFCS", 1), Buffer.from([0])]));\n                this.emit("connected");');
patch('vcon-relay.js','this.dotaClient.rawWrite(frame);',
 'if (frame.toString("ascii", 0, 4) !== "VFCS") this.dotaClient.rawWrite(frame);');
