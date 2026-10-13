/* Browser-only compatibility. No game source, server state or reward mutation. */
'use strict';
const parchmentText=Object.getOwnPropertyDescriptor(Panel.prototype,'text');
Object.defineProperty(Panel.prototype,'text',{
 configurable:true,
 get:function(){return this.type==='TextEntry'?this.el.value:parchmentText.get.call(this);},
 set:function(value){parchmentText.set.call(this,value);}
});
const parchmentPanelEvent=Panel.prototype.SetPanelEvent;
Panel.prototype.SetPanelEvent=function(name,callback){
 parchmentPanelEvent.call(this,name,callback);
 if(this.type==='TextEntry'&&name==='ontextentrychange'){
  if(this.__parchmentInput)this.el.removeEventListener('input',this.__parchmentInput);
  this.__parchmentInput=event=>this.events.ontextentrychange(event);
  this.el.addEventListener('input',this.__parchmentInput);
 }
};
