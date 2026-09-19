"""Execute a local prototype script through the installed Blender MCP server."""
import asyncio, os, sys, json
from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client
async def main():
    path=os.path.abspath(sys.argv[1])
    code='__file__='+repr(path)+'\n'+open(path,encoding='utf-8-sig').read()
    params=StdioServerParameters(command='C:/Users/li/.local/bin/blender-mcp.exe',env=dict(os.environ,DISABLE_TELEMETRY='true'))
    async with stdio_client(params) as (r,w):
        async with ClientSession(r,w) as session:
            await session.initialize()
            result=await session.call_tool('execute_blender_code',{'code':code,'user_prompt':'创建并保存哥特风主城模型原型供预览'})
            for c in result.content:
                if hasattr(c,'text'): print(c.text)
            if result.isError:sys.exit(1)
asyncio.run(main())
