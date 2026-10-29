const fs=require('fs'),vm=require('vm'),assert=require('assert');
const cfg={},nodes={description:{}};
const context={GameUI:{CustomUIConfig:()=>cfg},byId:id=>nodes[id]};
vm.createContext(context);
vm.runInContext(fs.readFileSync('panorama/src/scripts/custom_game/common/archive_text.js','utf8'),context);
const text=cfg.SurvivalArchiveText;
assert(text);
const raw='<br> - N10解锁<br>获得 <font color="#f5c65e">神器碎片</font>\\n下一行';
const expected='\n - N10解锁\n获得 <font color="#f5c65e">神器碎片</font>\n下一行';
assert.strictEqual(text.Rich(raw),expected);
assert.strictEqual(text.Plain(raw),'\n - N10解锁\n获得 神器碎片\n下一行');
assert.strictEqual(text.Rich("<font color='#74c8f2'>蓝色</font>"),'<font color="#74c8f2">蓝色</font>');
assert.strictEqual(text.Rich('<font color="red" size="100">字</font><img src="bad">'), '字');
assert.strictEqual(text.Rich('A & B &lt; C'), 'A &amp; B &lt; C');
assert.strictEqual(text.Rich('<font color="#b680ee">未关闭'),'<font color="#b680ee">未关闭</font>');
for(const filename of ['ability_tooltip.js','hud_takeover.js']){
    const source=fs.readFileSync('panorama/src/scripts/custom_game/'+filename,'utf8');
    const start=source.indexOf('    function setText(id, value, archiveRich) {');
    const end=source.indexOf('    function localize(',start);
    assert(start>=0&&end>start,filename);
    cfg.SurvivalTypography={ReadableText:value=>'正常排版:'+String(value)};
    vm.runInContext(source.slice(start,end),context);
    context.setText('description',raw,true);
    assert.strictEqual(nodes.description.html,true,filename);
    assert.strictEqual(nodes.description.text,expected,filename);
    context.setText('description','英雄普通说明',false);
    assert.strictEqual(nodes.description.html,false,filename+' must clear archive markup mode');
    assert.strictEqual(nodes.description.text,filename==='ability_tooltip.js'?'正常排版:英雄普通说明':'英雄普通说明');
}
for(const filename of ['survival_hud.xml','archive.xml']){
    const source=fs.readFileSync('panorama/src/layout/custom_game/'+filename,'utf8');
    const helper=source.indexOf('scripts/custom_game/common/archive_text.js');
    assert(helper>=0,filename+' must include rich text helper');
    const consumer=source.indexOf('scripts/custom_game/ability_tooltip.js');
    if(consumer>=0)assert(helper<consumer,filename+' helper loads before ability renderer');
}
console.log('ARCHIVE_RICH_TEXT_PASS: actual primary/legacy renderer, real newlines, safe quality font colors, unknown tags removed, normal-unit reset and helper load order');
