/* Browser-only compatibility. No game source, server state or reward mutation. */
'use strict';
const collectionText=Object.getOwnPropertyDescriptor(Panel.prototype,'text');
Object.defineProperty(Panel.prototype,'text',{
 configurable:true,
 get:function(){return this.type==='TextEntry'?this.el.value:collectionText.get.call(this);},
 set:function(value){collectionText.set.call(this,value);}
});
const collectionPanelEvent=Panel.prototype.SetPanelEvent;
Panel.prototype.SetPanelEvent=function(name,callback){
 collectionPanelEvent.call(this,name,callback);
 if(this.type==='TextEntry'&&name==='ontextentrychange'){
  if(this.__collectionInput)this.el.removeEventListener('input',this.__collectionInput);
  this.__collectionInput=event=>this.events.ontextentrychange(event);
  this.el.addEventListener('input',this.__collectionInput);
 }
};
