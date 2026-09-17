// Preserve registry and map identities across independently reloaded layouts.
// Page extensions (daily, shop, etc.) must survive a shared-registry reload.
module.exports = function(data) {
    return '(function(){var cfg=GameUI.CustomUIConfig(),next=' + JSON.stringify(data) +
        ';var current=cfg.SurvivalUIRegistry||{};Object.keys(next).forEach(function(key){' +
        'if(key==="assets"||key==="aliases"||key==="projectPaths"){var map=current[key]||(current[key]={});' +
        'Object.keys(next[key]).forEach(function(id){map[id]=next[key][id];});}' +
        'else current[key]=next[key];});cfg.SurvivalUIRegistry=current;})();\n';
};
