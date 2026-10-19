'use strict';

// Installed Valve CSS is the evidence; HTML below is an isolated browser adaptation.
// No game scripts, engine actions, network requests, or production assets are run.
const fs = require('node:fs');

function buildComponents({ cssPath }) {
  const source = fs.readFileSync(cssPath, 'utf8');
  const lines = source.split(/\r?\n/);
  const sourcePath = 'panorama/styles/dotastyles.css';
  const find = (selector) => {
    const index = lines.findIndex((line) => line.trim() === selector);
    if (index < 0) throw new Error('Official CSS selector missing: ' + selector);
    return index;
  };
  const block = (selector) => {
    const start = find(selector);
    let opened = false, depth = 0;
    for (let i = start; i < lines.length; i++) {
      for (const char of lines[i]) {
        if (char === '{') { opened = true; depth++; }
        if (char === '}') depth--;
      }
      if (opened && depth === 0) return lines.slice(start, i + 1).join('\n');
    }
    throw new Error('Unclosed official CSS block: ' + selector);
  };
  const range = (from, until) => {
    const start = find(from), end = find(until);
    if (end <= start) throw new Error('Invalid official CSS range');
    return lines.slice(start, end).join('\n').trimEnd();
  };
  const records = [];
  const add = ({ title, kind, selector, css, xml, description, style, body }) => {
    const id = 'C' + String(records.length + 1).padStart(2, '0');
    const scope = '.valve-demo-' + id;
    const scoped = style.replaceAll('$', scope);
    records.push({
      id, title, kind, description: description + ' 浏览器示意，Panorama 的排版、字体和状态以游戏内渲染为准。',
      officialSource: sourcePath + ':' + (find(selector) + 1), selector, css,
      xml: '<!-- 在布局的 styles 中引入 file://{resources}/styles/dotastyles.css -->\n' + xml,
      demoHtml: '<style>' + scoped + '</style><div class="valve-demo-' + id + '" style="font:18px/1.5 Arial,Microsoft YaHei,sans-serif;color:#d2d6d1;max-width:100%;box-sizing:border-box">' + body + '</div>',
    });
  };

  const palettes = [
    { name: '', title: '灰蓝斜面按钮', normal: ['#373d45', '#4d5860'], hover: ['#4c5561', '#6c7d88'], active: ['#393939', '#555555'], border: ['#555555','#404040','#333333','#494949'] },
    { name: 'Green', title: '绿色斜面按钮', normal: ['#2a481f', '#226326'], hover: ['#226528', '#288a36'], active: ['#1f3d25','#2b562c'], border: ['#355639','#214123','#1e371e','#2c4d30'] },
    { name: 'DarkGreen', title: '深绿斜面按钮', normal: ['#1a2c13','#18441b'], hover: ['#17421b','#185321'], active: ['#132416','#183019'], border: ['#223524','#132615','#091009','#2c4d30'] },
    { name: 'Bronze', title: '铜金斜面按钮', normal: ['#b9894c','#dca157'], hover: ['#dda45a','#fcb965'], active: ['#4d391f','#9b713c'], border: ['#e0a75e','#8f6b3c','#8d683a','#dca35b'] },
    { name: 'Plus', title: 'Dota Plus 金色按钮', normal: ['#877f4f','#a79c5b'], hover: ['#a79d63','#c2b56b'], active: ['#877f4f','#a79c5b'], border: ['#b4a442','#756f45','#635e3b','#aea463'] },
  ];
  for (const p of palettes) {
    const selector = '.ButtonBevel' + (p.name ? '.' + p.name : '');
    const css = ['.ButtonBevel', ...(p.name ? [selector] : []), '.ButtonBevel:enabled:hover', ...(p.name ? [selector + ':enabled:hover'] : []), '.ButtonBevel:disabled', '.ButtonBevel:disabled Label', '.ButtonBevel:active', ...(p.name ? [selector + ':active'] : []), '.ButtonBevel Label', '.ButtonBevel:active Label'].map(block).join('\n\n');
    add({ title: p.title, kind: '按钮', selector, css, description: '官方 ButtonBevel' + (p.name ? ' ' + p.name : '') + ' 样式。可悬停、按下，右侧展示禁用状态。',
      xml: '<Button class="ButtonBevel' + (p.name ? ' ' + p.name : '') + '">\n  <Label text="确认" />\n</Button>',
      style: '${display:flex;gap:12px;align-items:center;flex-wrap:wrap} $ button{font:inherit;min-width:192px;min-height:36px;padding:4px 10px;color:#fff;letter-spacing:2px;background:linear-gradient(' + p.normal.join(',') + ');border:1px solid;border-color:' + p.border.join(' ') + ';box-shadow:0 0 4px #0005;text-shadow:2px 2px 0 #000;cursor:pointer;transition:background .05s} $ button:hover:not(:disabled){background:linear-gradient(' + p.hover.join(',') + ')} $ button:active:not(:disabled){background:linear-gradient(' + p.active.join(',') + ');transform:translateY(1px)} $ button:disabled{filter:grayscale(1);opacity:.55;color:#333;cursor:default}',
      body: '<button type="button">确认</button><button type="button" disabled>不可用</button>',
    });
  }

  add({ title: '蓝色文字按钮', kind: '按钮', selector: '.TextButton', css: range('.TextButton', '.TreasureGrantButton'), description: '官方 TextButton，适合次要操作与查看详情。', xml: '<Button class="TextButton">\n  <Label text="查看详情" />\n</Button>',
    style: '$ button{font:inherit;border:0;background:transparent;color:#6BCAFF;padding:4px 8px;border-radius:3px;cursor:pointer;transition:color .1s,transform .05s} $ button:hover{color:#fff} $ button:active{transform:translateY(1px)}', body: '<button type="button">查看详情</button>' });
  add({ title: '关闭按钮', kind: '按钮', selector: '.CloseButton', css: range('.CloseButton', '.MaximizeButton'), description: '官方 CloseButton。原生图标依赖 control_icons/x_close_grey_psd，示例用矢量线条表达轮廓；可在素材目录选择原图。', xml: '<Button class="CloseButton" />',
    style: '$ button{position:relative;width:50px;height:50px;margin:4px;padding:0;border:0;background:transparent;color:#888;cursor:pointer} $ button::before,$ button::after{content:"";position:absolute;top:24px;left:13px;width:24px;height:2px;background:currentColor;transform:rotate(45deg)} $ button::after{transform:rotate(-45deg)} $ button:hover{color:#bbb} $ button:active{color:#fff;transform:scale(.84)}', body: '<button type="button" aria-label="关闭"></button>' });
  add({ title: '复选框 / 开关', kind: '选择', selector: 'ToggleButton,CycleButton,DOTASettingsCheckbox', css: range('ToggleButton,CycleButton,DOTASettingsCheckbox', 'ToggleButton.ExpandCollapseToggleButton'), description: '原生 ToggleButton 的 TickBox，选中时为明亮填充方框。可点选。', xml: '<ToggleButton text="显示提示" selected="true" />',
    style: '$ label{display:flex;gap:8px;align-items:center;padding:1px 4px;cursor:pointer;letter-spacing:.3px} $ input{appearance:none;width:18px;height:18px;margin:0;border:2px solid #5e686966;background:#000;box-shadow:0 0 1px 3px #0005;cursor:pointer} $ input:checked{background:linear-gradient(#e7f6f5,#a0d6d7);border:3px solid #000;box-shadow:0 0 8px #5b62bf77} $ label:hover input:not(:checked){border-color:#697879}', body: '<label><input type="checkbox" checked>显示提示</label>' });
  add({ title: '单选框', kind: '选择', selector: 'RadioButton', css: range('RadioButton', '.ButtonBevel'), description: '官方 RadioButton 圆形选择框。演示为同组二选一。', xml: '<Panel style="flow-children: right;">\n  <RadioButton group="QualityChoice" text="标准" selected="true" />\n  <RadioButton group="QualityChoice" text="高清" />\n</Panel>',
    style: '${display:flex;gap:18px;flex-wrap:wrap} $ label{display:flex;gap:4px;align-items:center;cursor:pointer} $ input{appearance:none;min-width:20px;height:20px;margin:0;border:2px solid #5e686966;border-radius:50%;background:#000;cursor:pointer} $ input:checked{border:3px solid #000;background:radial-gradient(circle,#e7f6f5,#333399);box-shadow:0 0 6px #5b62bf77} $ label:hover{color:#f5f5f5}', body: '<label><input type="radio" name="valve-C09-choice" checked>标准</label><label><input type="radio" name="valve-C09-choice">高清</label>' });
  add({ title: '下拉菜单', kind: '选择', selector: 'DropDown,DOTASettingsEnumDropDown', css: range('DropDown,DOTASettingsEnumDropDown', 'VerticalScrollBar,HTMLVerticalScrollBar'), description: '官方 DropDown 的容器、选项与展开样式。浏览器弹出列表由本机浏览器绘制。', xml: '<DropDown selected="choice_all">\n  <Label id="choice_all" text="全部分类" />\n  <Label id="choice_owned" text="已拥有" />\n  <Label id="choice_new" text="未拥有" />\n</DropDown>',
    style: '$ select{font:24px Arial,Microsoft YaHei,sans-serif;width:320px;max-width:100%;height:41px;padding:4px 8px;color:#ddd;border:2px solid #5e686966;background:linear-gradient(#292e2e,#191e1e);box-shadow:0 0 1px 3px #0005;cursor:pointer} $ option{color:#ddd;background:#192020}', body: '<select aria-label="分类"><option>全部分类</option><option>已拥有</option><option>未拥有</option></select>' });
  add({ title: '文本输入框', kind: '输入', selector: 'TextEntry', css: range('TextEntry', '.TextEntryIMECandidateRow'), description: '官方 TextEntry 的常态、禁用和占位文字规则。可输入文字。', xml: '<TextEntry placeholder="输入名称" />',
    style: '$ input{font:20px Arial,Microsoft YaHei,sans-serif;box-sizing:border-box;width:352px;max-width:100%;height:36px;padding:5px 7px 3px;color:#fff;border:1px solid #444;background:linear-gradient(#111,#222);border-radius:0} $ input::placeholder{color:#555;font-size:18px} $ input:focus::placeholder{opacity:0}', body: '<input type="text" placeholder="输入名称" aria-label="名称">' });
  add({ title: '横向滑块', kind: '输入', selector: 'Slider,RangeSlider', css: range('Slider,RangeSlider', '.PreGame #PreGameLabel'), description: '官方 HorizontalSlider 的轨道、进度、滑块与悬停样式。可拖动。', xml: '<Slider class="HorizontalSlider" direction="horizontal" min="0" max="1" value="0.55" />',
    style: '$ input{appearance:none;display:block;width:320px;max-width:100%;height:16px;box-sizing:border-box;margin:10px 0;background:linear-gradient(to right,#222,#444f52);border:2px solid #5e686966;border-radius:0;cursor:pointer} $ input::-webkit-slider-thumb{appearance:none;width:16px;height:30px;border:0;border-radius:13%;background:radial-gradient(circle at 45% 45%,#91a5b9,#444f52);box-shadow:1px 1px 13px #000} $ input::-moz-range-thumb{width:16px;height:30px;border:0;border-radius:13%;background:radial-gradient(circle at 45% 45%,#91a5b9,#444f52)} $ input::-webkit-slider-thumb:hover{background:radial-gradient(circle at 45% 45%,#b8c5d3,#444f52)}', body: '<input type="range" min="0" max="100" value="55" aria-label="音量">' });
  add({ title: '进度条', kind: '进度', selector: 'ProgressBar', css: range('ProgressBar', '.GuildPage .ProgressBarLeft'), description: '官方 ProgressBar 基础黑底和 ProgressBarLeft 半透明填充，不附加公会或活动配色。', xml: '<ProgressBar min="0" max="1" value="0.65" />',
    style: '$ .bar{position:relative;width:320px;max-width:100%;height:22px;border-radius:8px;background:#000;overflow:hidden} $ .fill{width:65%;height:100%;background:#fff3}', body: '<div class="bar" role="progressbar" aria-label="进度" aria-valuenow="65" aria-valuemin="0" aria-valuemax="100"><div class="fill"></div></div>' });
  add({ title: '纵向滚动条', kind: '滚动', selector: 'VerticalScrollBar,HTMLVerticalScrollBar', css: range('VerticalScrollBar,HTMLVerticalScrollBar', 'HorizontalScrollBar,HTMLHorizontalScrollBar'), description: '官方 VerticalScrollBar 的 8 像素宽度和深灰滑块。内容溢出时由 Panorama 自动创建，无需手工摆放滑块。', xml: '<Panel style="width: 320px; height: 120px; overflow: squish scroll;">\n  <Panel style="width: 100%; height: 340px; flow-children: down;">\n    <Label text="滚动内容" />\n  </Panel>\n</Panel>',
    style: '$ .viewport{width:320px;max-width:100%;height:120px;overflow-y:scroll;background:#11181b;scrollbar-width:thin;scrollbar-color:#566767 transparent} $ .viewport::-webkit-scrollbar{width:8px} $ .viewport::-webkit-scrollbar-thumb{background:#566767;border-top:1px solid #aaaaaa22} $ .viewport::-webkit-scrollbar-thumb:hover{background:#788b8b} $ .row{padding:7px 12px;border-bottom:1px solid #ffffff0a}', body: '<div class="viewport" tabindex="0">' + ['第一行','第二行','第三行','第四行','第五行','第六行','第七行','第八行'].map(t=>'<div class="row">'+t+'</div>').join('') + '</div>' });
  add({ title: '横向滚动条', kind: '滚动', selector: 'HorizontalScrollBar,HTMLHorizontalScrollBar', css: range('HorizontalScrollBar,HTMLHorizontalScrollBar', 'VerticalScrollBar,VerticalScrollBar .ScrollThumb,HorizontalScrollBar,HorizontalScrollBar .ScrollThumb HTMLHorizontalScrollBar,HTMLHorizontalScrollBar .ScrollThumb,HTMLVerticalScrollBar,HTMLVerticalScrollBar .ScrollThumb'), description: '官方 HorizontalScrollBar。示例展示超宽内容和底部滑块。', xml: '<Panel style="width: 320px; height: 100px; overflow: scroll squish;">\n  <Panel style="width: 700px; height: 75px;" />\n</Panel>',
    style: '$ .viewport{width:320px;max-width:100%;height:100px;overflow-x:scroll;background:#11181b;scrollbar-width:thin;scrollbar-color:#566767 transparent} $ .viewport::-webkit-scrollbar{height:8px} $ .viewport::-webkit-scrollbar-thumb{background:#566767;border-top:1px solid #aaaaaa22} $ .row{display:flex;gap:12px;width:700px;padding:12px;box-sizing:border-box} $ .item{display:flex;align-items:center;justify-content:center;width:100px;height:50px;background:#263438;border:1px solid #5e686966}', body: '<div class="viewport" tabindex="0"><div class="row">' + ['01','02','03','04','05','06'].map(t=>'<div class="item">'+t+'</div>').join('') + '</div></div>' });
  add({ title: '上下文菜单', kind: '菜单', selector: 'SimpleContextMenu .ContextMenuBody', css: range('SimpleContextMenu .ContextMenuBody', 'ProgressBar'), description: '官方 SimpleContextMenu 的深色菜单容器、菜单按钮和禁用颜色。此处常驻展开，未调用任何游戏菜单或业务逻辑。', xml: '<SimpleContextMenu>\n  <Panel class="ContextMenuBody">\n    <Button><Label text="查看详情" /></Button>\n    <Button><Label text="添加收藏" /></Button>\n    <Button enabled="false"><Label text="不可用" /></Button>\n  </Panel>\n</SimpleContextMenu>',
    style: '$ .menu{width:230px;max-width:100%;box-sizing:border-box;padding:5px;background:#212828;border:2px solid #000;box-shadow:4px 4px 4px #0009} $ button{font:inherit;display:block;width:100%;padding:6px 10px;margin:0;text-align:left;border:1px solid #000;background:#0004;color:#a5ada2;cursor:pointer;transition:background .2s} $ button:hover:enabled{background:#0008;color:#fff} $ button:disabled{color:#444;cursor:default}', body: '<div class="menu"><button type="button">查看详情</button><button type="button">添加收藏</button><button type="button" disabled>不可用</button></div>' });

  if (records.length !== 16 || new Set(records.map(r=>r.id)).size !== records.length) throw new Error('Unexpected native component inventory');
  return records;
}

module.exports = { buildComponents };
