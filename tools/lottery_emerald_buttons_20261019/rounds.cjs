'use strict';

// Cumulative review rounds. Each subsequent entry keeps the preceding refinements.
module.exports = [
 {
  id:'r1',name:'尺寸与原图比例',kicker:'ROUND 01 · GEOMETRY',
  description:'固定84像素高度；十连244宽、单抽220宽，按官方原图比例排齐底边。',
  css:`.draw-area{right:44px;bottom:37px;gap:20px;align-items:flex-end}
.draw-action{width:244px;height:84px;min-height:84px;max-height:84px;flex-shrink:0}
.draw-action.single{width:220px;filter:none}
.draw-pity{bottom:94px;right:2px;font-size:14px;line-height:20px}`
 },
 {
  id:'r2',name:'文字与费用层次',kicker:'ROUND 02 · TYPOGRAPHY',
  description:'标题28像素、费用18像素，券图放大到52×36，两行在固定按钮内垂直居中。',
  css:`.draw-action{display:flex;flex-direction:column;align-items:center;justify-content:center;gap:2px;padding:6px 12px}
.draw-label{font-size:28px;line-height:32px;height:32px;min-height:32px;letter-spacing:2px;flex-shrink:0}
.draw-cost{font-size:18px;line-height:26px;height:36px;min-height:36px;gap:8px;color:#e1e9db;flex-shrink:0;align-items:center}
.draw-cost img{width:52px;height:36px;max-width:none;max-height:none;object-fit:contain;flex-shrink:0}`
 },
 {
  id:'r3',name:'翡翠层次与高光',kicker:'ROUND 03 · MATERIAL',
  description:'保留官方绿纹底图，十连更醒目、单抽更安静；高光只作用在底图，文字与券图保持清晰。',
  css:`.draw-action,.draw-action:hover:not(:disabled),.draw-action.ten:hover:not(:disabled){background-image:none!important;background-color:transparent!important;filter:none!important;border-color:#719978;box-shadow:0 4px 10px #0008,inset 0 1px 0 #ffffff14;isolation:isolate;transition:border-color .12s,box-shadow .12s,transform .08s}
.draw-action::before{content:"";position:absolute;inset:0;background-image:var(--official-button-image,none);background-size:100% 100%;background-position:center;filter:brightness(.92);z-index:-1;transition:filter .12s;pointer-events:none}
.draw-action.single{border-color:#6a8276;box-shadow:0 3px 8px #0008}
.draw-action.single::before{filter:brightness(.88) saturate(.75)}
.draw-action:hover:not(:disabled){border-color:#b8d3ab;box-shadow:0 4px 12px #0009,inset 0 1px 0 #ffffff20}
.draw-action:hover:not(:disabled)::before{filter:brightness(.975)}
.draw-action.single:hover:not(:disabled)::before{filter:brightness(.933) saturate(.75)}
.draw-label{color:#f2efdf;text-shadow:0 1px 2px #08120c,0 0 3px #08120c;-webkit-text-stroke:.3px #111e16;paint-order:stroke fill}
.button-glass::after{background:#f0ffe51f}`
 },
 {
  id:'r4',name:'完整交互状态',kicker:'ROUND 04 · INTERACTION',
  description:'补齐悬停、按下、键盘焦点、票券不足与开启中状态，状态变化保持按钮尺寸与文字位置稳定。',
  css:`.draw-action.preview-hover{border-color:#b8d3ab;box-shadow:0 4px 12px #0009,inset 0 1px 0 #ffffff20}
.draw-action.preview-hover::before{filter:brightness(.975)}
.draw-action.single.preview-hover::before{filter:brightness(.933) saturate(.75)}
.draw-action:active:not(:disabled),.draw-action.preview-pressed{transform:translateY(1px);border-color:#8ab58f;box-shadow:0 1px 3px #000a,inset 0 2px 5px #0006}
.draw-action:active:not(:disabled)::before,.draw-action.preview-pressed::before{filter:brightness(.865)}
.draw-action.single:active:not(:disabled)::before,.draw-action.single.preview-pressed::before{filter:brightness(.827) saturate(.75)}
.draw-action:focus-visible,.draw-action.preview-focus{outline:2px solid #d0ebba;outline-offset:3px}
.draw-action:disabled,.draw-action.preview-disabled,.draw-action.preview-busy{opacity:1;cursor:default;border-color:#4d6359;box-shadow:0 2px 5px #0007;transform:none}
.draw-action:disabled::before,.draw-action.preview-disabled::before{filter:grayscale(.8) brightness(.62)}
.draw-action:disabled .draw-label,.draw-action.preview-disabled .draw-label{color:#b2beb2;text-shadow:0 1px 2px #07100c}
.draw-action:disabled .draw-cost,.draw-action.preview-disabled .draw-cost{color:#a9b4aa}
.draw-action:disabled .draw-cost img{filter:grayscale(.65) brightness(.8)}
.draw-action:disabled .button-glass::after{animation:none}
.draw-action.preview-busy::before,.draw-action[aria-busy="true"]::before{filter:saturate(.65) brightness(.76)}
.draw-action.preview-busy .draw-label,.draw-action[aria-busy="true"] .draw-label{color:#d6e4d2}`
 },
 {
  id:'r5',name:'全界面按钮统一',kicker:'ROUND 05 · CONSISTENCY',
  description:'统一加号、关闭、底栏与结果按钮；小按钮44像素热区，弹层支持键盘焦点约束与关闭后返回。',
  css:`.wallet-plus{width:44px;height:44px;min-width:44px;border-radius:50%;border-color:#789976;background:linear-gradient(#354f3c,#1c3025);padding:6px;box-shadow:inset 0 1px 0 #d7f0c526,0 2px 5px #0009;color:#d7e8cc}
.wallet-plus img{width:30px;height:30px;object-fit:contain}
.wallet-plus:hover:not(:disabled){background:linear-gradient(#405e47,#243c2c);border-color:#b7d2a8}
.window-close{width:44px;height:44px;right:17px;top:15px;padding:6px;opacity:.85;border:1px solid transparent}
.window-close img{width:32px;height:32px;object-fit:contain}
.window-close:hover:not(:disabled){border-color:#a7c9a344;background:#d8f2c515;opacity:1}
.footer-action{height:44px;padding:0 14px;font-size:16px;color:#cbd8cb;border:1px solid transparent;transition:background-color .12s,border-color .12s}
.footer-action img{width:22px;height:22px;object-fit:contain;opacity:.85}
.footer-action:hover:not(:disabled){background:#c4e0bb12;border-color:#9dbf9844;color:#edf1df}
.skip-control{height:44px;font-size:16px;gap:10px;padding:0 6px}
.skip-control input{width:22px;height:22px;border-color:#829e7e;background:#0c1d14}
.skip-control input:checked{border-color:#bad6ab;background:#39523c}
.wallet-plus:active:not(:disabled),.window-close:active:not(:disabled),.footer-action:active:not(:disabled),.game-modal-close:active:not(:disabled){transform:translateY(1px)}
.wallet-plus:focus-visible,.window-close:focus-visible,.footer-action:focus-visible,.game-modal-close:focus-visible,.skip-control input:focus-visible{outline:2px solid #d0ebba;outline-offset:3px}
.result-buttons{gap:20px}
.result-buttons button{position:relative;height:84px;width:244px;padding:6px 12px;font-size:28px;line-height:32px;letter-spacing:2px;background:none!important;filter:none;isolation:isolate;border-color:#719978;color:#f2efdf;text-shadow:0 1px 2px #08120c,0 0 3px #08120c;transition:transform .08s,border-color .12s}
.result-buttons button[data-confirm-results]{width:220px;border-color:#6a8276}
.result-buttons button::before{content:"";position:absolute;inset:0;background-image:var(--official-button-image,none);background-size:100% 100%;filter:brightness(.92);z-index:-1;pointer-events:none;transition:filter .12s}
.result-buttons button[data-confirm-results]::before{filter:brightness(.88) saturate(.75)}
.result-buttons button:hover:not(:disabled){filter:none;border-color:#b8d3ab}
.result-buttons button:hover:not(:disabled)::before{filter:brightness(.975)}
.result-buttons button[data-confirm-results]:hover:not(:disabled)::before{filter:brightness(.933) saturate(.75)}
.result-buttons button:active:not(:disabled){transform:translateY(1px)}
.result-buttons button:active:not(:disabled)::before{filter:brightness(.865)}
.result-buttons button:focus-visible{outline:2px solid #d0ebba;outline-offset:3px}
.game-modal{background:#122019fa}
.game-modal-header{background:#1b2e23eb}
.game-modal-close{width:44px;height:44px;font-size:32px;line-height:32px;padding:6px;color:#d0dfc9}
.game-modal-close:hover:not(:disabled){background:#d8f2c515;color:#f2f4e6}
.animation-skip{height:44px;min-width:116px;padding:8px 18px;font-size:16px;border-color:#829e7e;background:#12271ce8}
.topup-options button{min-height:44px;background:#2a4432;border-color:#819d7b}
.topup-options button:hover:not(:disabled){background:#36573f;border-color:#b7d2a8}`
 }
];
