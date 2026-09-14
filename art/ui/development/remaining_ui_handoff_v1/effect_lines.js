function formatArchiveEffects(value) {
    var source=String(value||'').replace(/\r\n?/g,'\n'),depth=0,out='';
    for(var i=0;i<source.length;i++){
        var c=source.charAt(i);
        if(c==='('||c==='（'||c==='['||c==='【')depth++;
        if(c===')'||c==='）'||c===']'||c==='】')depth=Math.max(0,depth-1);
        // Preserve numeric grouping (1,000), decimals and parenthetical qualifiers.
        if(!depth&&(c==='；'||c===';'||c==='|'||c==='\n')){out+='\n';continue;}
        if(!depth&&(c==='，'||c===',')&&!(c===','&&/\d/.test(source.charAt(i-1))&&/\d/.test(source.charAt(i+1)))){out+='\n';continue;}
        if(!depth&&/[ \t]/.test(c)&&/[0-9%％）)]/.test(out.slice(-1))){
            var next=i;while(/[ \t]/.test(source.charAt(next))&&next<source.length)next++;
            if(/[\u3400-\u9fffA-Za-z]/.test(source.charAt(next))){out+='\n';i=next-1;continue;}
        }
        out+=c;
    }
    return out.split('\n').map(function(line){return line.replace(/^\s+|\s+$/g,'');}).filter(function(line){return !!line;}).join('\n');
}
if(typeof module!=='undefined'&&module.exports)module.exports=formatArchiveEffects;
