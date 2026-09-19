// Local MCP client for this already-running Codex session. Persistent Codex
// registration uses the same installed server; no private relay protocol here.
const fs=require('fs'),path=require('path'),{pathToFileURL}=require('url');
const install=process.env.DOTA2_MCP_INSTALL||path.join(require('os').homedir(),'.codex/tools/dota2-mcp/node_modules');
(async()=>{
 const {Client}=await import(pathToFileURL(path.join(install,'@modelcontextprotocol/sdk/dist/esm/client/index.js')));
 const {StdioClientTransport}=await import(pathToFileURL(path.join(install,'@modelcontextprotocol/sdk/dist/esm/client/stdio.js')));
 const client=new Client({name:'survival-map-local-client',version:'1.0.0'});
 const transport=new StdioClientTransport({command:process.execPath,args:[path.join(install,'dota2-mcp/dist/index.js')],env:{...process.env,DOTA2_VCON_AUTO_OPEN_VCONSOLE:'0'},stderr:'pipe'});
 transport.stderr?.on('data',b=>process.stderr.write(b));
 try {
  await client.connect(transport);
  const input=process.argv[2]?JSON.parse(fs.readFileSync(process.argv[2],'utf8').replace(/^\uFEFF/,'')):[{name:'dota_status',arguments:{}}];
  const results=[];
  for(const call of input){
   call.arguments??={};
   const result=call.name==='list_tools'?await client.listTools():await client.callTool(call,undefined,{timeout:180000});
   console.log(JSON.stringify({tool:call.name,result}));
   results.push(result);
   if(result.isError)throw new Error(`MCP tool failed: ${call.name}`);
  }
  const expectIndex=process.argv.indexOf('--expect');
  if(expectIndex>=0){
   const expected=process.argv[expectIndex+1];
   if(!expected||!results.some(r=>(r.content||[]).some(c=>c.type==='text'&&c.text.split(/\r?\n/).some(line=>line.trim()===expected))))
    throw new Error('Expected game response was not received: '+expected);
  }
 }finally{await client.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
