"""Run the unchanged native transport suite with VIP contract edge cases."""
from pathlib import Path
import subprocess
import json

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'design_refs/vip_recharge_20261016/validation'
OUT.mkdir(parents=True, exist_ok=True)
source = (ROOT / 'tools/endless_leaderboard_20261016/test_transport.lua').read_text(encoding='utf-8-sig')
extra = '''
check("VIP grade and actual medal pass independently without private recharge", function()
    request();local value=result(3)
    value.entries[1].vip_level,value.entries[1].vip_medal_level=12,0
    value.entries[2].vip_level,value.entries[2].vip_medal_level=2,1
    value.entries[1].vip_recharge_total_fen=1250000
    callbacks[1].success(value)
    assert(#sent==5)
    assert(sent[2].data.row.vip_level==12 and sent[2].data.row.vip_medal_level==0)
    assert(sent[3].data.row.vip_level==2 and sent[3].data.row.vip_medal_level==1)
    assert(sent[4].data.row.vip_level==0 and sent[4].data.row.vip_medal_level==0)
    assert(sent[2].data.row.vip_recharge_total_fen==nil)
end)
check("invalid VIP grade rejects the whole response", function()
    for _,bad in ipairs({-1,13,1.5,"2",true,{},0/0}) do
        reset();request();local value=result(3);value.entries[2].vip_level=bad
        callbacks[1].success(value);assert(#sent==1 and sent[1].data.phase=="error")
    end
end)
check("invalid medal rejects the whole response", function()
    for _,bad in ipairs({-1,11,1.5,"1",true,{},0/0}) do
        reset();request();local value=result(3);value.entries[2].vip_medal_level=bad
        callbacks[1].success(value);assert(#sent==1 and sent[1].data.phase=="error")
    end
end)
'''
source = source.replace('print("ENDLESS_LEADERBOARD_TRANSPORT_PASS " .. checks .. " groups")',
                        extra + '\nprint("VIP_LEADERBOARD_TRANSPORT_PASS " .. checks .. " groups")')
path = OUT / 'transport_fixture.lua'
path.write_text(source, encoding='utf-8')
result = subprocess.run([r'C:\Program Files\lua\bin\lua5.1.exe', str(path)], cwd=ROOT,
                        capture_output=True, text=True, creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
(OUT / 'transport.txt').write_text(result.stdout + result.stderr, encoding='utf-8')
assert result.returncode == 0, result.stdout + result.stderr
assert 'VIP_LEADERBOARD_TRANSPORT_PASS 14 groups' in result.stdout
print(json.dumps({'status': 'PASS', 'native_lua_groups': 14, 'output': str(OUT / 'transport.txt')}))
