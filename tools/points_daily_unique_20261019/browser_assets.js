/* Preview transport only: preserve production s2r backgrounds and alpha masks. */
'use strict';
const pointsOriginalCssValue=cssValue;
cssValue=function(value){
 if(typeof value==='string')value=value.replace(/s2r:\/\/panorama\/images\/[^"')\s]+\.vtex(?:_c)?/g,uri=>PREVIEW_ASSET_PATHS[uri]||uri);
 return pointsOriginalCssValue(value);
};
// Panorama opacityMask has the same alpha-mask role in this isolated preview.
Object.defineProperty(CSSStyleDeclaration.prototype,'opacityMask',{
 configurable:true,
 set(value){this.maskImage=value;this.webkitMaskImage=value;this.maskSize='100% 100%';this.maskRepeat='no-repeat';},
 get(){return this.maskImage;}
});
