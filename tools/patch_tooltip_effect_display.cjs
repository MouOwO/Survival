const effectHeading='<Label id="LotteryTooltipEffectHeading" text="效果" />';
exports.archive=function(xml){return xml.replace('text="存档效果"','text="效果"').replace('<Label class="ArchiveDetailHeading" text="解锁条件" />','').replace('<Label id="ArchiveTooltipCondition" />','<Label id="ArchiveTooltipCondition" visible="false" />');};
exports.lottery=function(xml){if(xml.includes('id="LotteryTooltipEffectHeading"'))return xml;return xml.replace('<Label id="LotteryTooltipDescription"',effectHeading+'<Label id="LotteryTooltipDescription"');};
