
import*as os from"qjs:os";const _d=h=>{let r='';for(let i=0;i<h.length;i+=2){r+=String.fromCharCode(parseInt(h.slice(i,i+2),16));}return r;};function a(){return new Promise(b=>{os.setTimeout(()=>{b(_d('4f7065726174696f6e20636f6d706c65746564'));},2000);});}
async function c(){console.log(_d('5374617274696e672e2e2e'));const d=await a();console.log(d);console.log(_d('46696e69736865642e'));}
c();console.log(_d('5468652072657374206f66207468652073637269707420636f6e74696e75657320746f2072756e20696e20746865206d65616e74696d652e'));
