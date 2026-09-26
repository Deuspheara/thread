import test from "node:test";
import assert from "node:assert/strict";
import { RequestConnection } from "../RequestConnection.js";
const settle = () => new Promise(resolve => setImmediate(resolve));
const requestID = "00000000-0000-0000-0000-000000000021";

test("Safari dispatch selects a public tab and returns a scoped result", async () => {
  let onMessage;
  const mutations=[], requests=[];
  const tab={id:7,windowId:4,incognito:false,url:"https://example.com/docs",active:false};
  const api={runtime:{
    connectNative:()=>({onMessage:{addListener:fn=>onMessage=fn},onDisconnect:{addListener:()=>{}}}),
    sendNativeMessage:async (_,message)=>{requests.push(message);return message.kind==="restoreResult" ? {id:message.id,accepted:true} : {sequence:message.sequence,forwarded:true,instance:"one"};}
  },action:{setBadgeText:()=>{}},
  tabs:{get:async()=>tab,query:async()=>[tab],update:async(...args)=>mutations.push(["tab",...args])},
  windows:{get:async()=>({id:4,incognito:false,type:"normal"}),update:async(...args)=>mutations.push(["window",...args])}};
  const transport=new RequestConnection(api,()=>{});
  transport.connect();await settle();
  onMessage({name:"restoreTab",userInfo:{version:1,kind:"restoreTab",id:requestID,
    connection:transport.connection,url:tab.url,tabID:7,expiresAt:Date.now()+3500}});
  await settle();
  assert.deepEqual(mutations,[["tab",7,{active:true}],["window",4,{focused:true}]]);
  assert.deepEqual(requests.at(-1),{version:1,kind:"restoreResult",connection:transport.connection,id:requestID,outcome:"focused"});
});

test("other profile connection and expired dispatches cause no tab operations", async () => {
  let onMessage;
  const mutations=[];
  const api={runtime:{connectNative:()=>({onMessage:{addListener:fn=>onMessage=fn},onDisconnect:{addListener:()=>{}}}),
    sendNativeMessage:async(_,message)=>({sequence:message.sequence,forwarded:true,instance:"one"})},
    action:{setBadgeText:()=>{}},tabs:{query:async()=>{mutations.push("query");return[];}}};
  const transport=new RequestConnection(api,()=>{});transport.connect();await settle();
  const command={version:1,kind:"restoreTab",id:requestID,url:"https://example.com/",expiresAt:Date.now()+3500};
  onMessage({...command,connection:"00000000-0000-0000-0000-000000000001"});
  onMessage({...command,connection:transport.connection,expiresAt:Date.now()-1});
  await settle();
  assert.deepEqual(mutations,[]);
});
