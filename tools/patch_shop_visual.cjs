module.exports=function(source){
 if(source.includes('R.SurvivalShopWindow'))return source;
 source=source.replace('function updateEntryCard(card, entry) {','function updateEntryCard(card, entry) {\n        if(card && card.__rhShopBuy)U.State.Set(card.__rhShopBuy,{enabled:entry.purchasable===1});');
 source=source.replace(/        updateModeText\(\);\r?\n        setOpenState\(true\);/g,'        updateModeText();\n        var R=GameUI.CustomUIConfig().RemainingHandoff;if(R)R.SurvivalShopWindow();\n        setOpenState(true);');
 const anchor='            updateEntryCard(card, entry);';
 const insert=`            var R=GameUI.CustomUIConfig().RemainingHandoff;
            if(R)R.SurvivalShopCard(card,entry,function(){purchase(entryById(card.GetAttributeString("entry_id","")));});
`;
 if(!source.includes(anchor))throw Error('Shop card render anchor missing');
 return source.replace(anchor,insert+anchor);
};
