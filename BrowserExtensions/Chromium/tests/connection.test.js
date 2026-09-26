import test from "node:test";
import assert from "node:assert/strict";
import { NativeConnection } from "../NativeConnection.js";

test("changed app socket generation triggers a fresh inventory on the existing native port", () => {
  let onMessage;
  let snapshots=0;
  const sent=[];
  const port={onMessage:{addListener:fn=>onMessage=fn},onDisconnect:{addListener:()=>{}},postMessage:message=>sent.push(message)};
  const api={runtime:{connectNative:()=>port},action:{setBadgeText:()=>{}}};
  const connection=new NativeConnection(api,"chrome",()=>snapshots++);
  connection.connect();
  onMessage({forwarded:true,instance:"first"});
  onMessage({forwarded:true,instance:"first"});
  onMessage({forwarded:true,instance:"restarted"});
  assert.equal(snapshots,2);
  assert.equal(sent[0].kind,"connected");
});

test("restore messages execute separately from observation acknowledgments", async () => {
  let onMessage;
  const sent=[], mutations=[], badges=[];
  const port={onMessage:{addListener:fn=>onMessage=fn},onDisconnect:{addListener:()=>{}},postMessage:message=>sent.push(message)};
  const api={runtime:{connectNative:()=>port},action:{setBadgeText:value=>badges.push(value)},
    tabs:{query:async()=>[]},windows:{getAll:async()=>[],create:async value=>mutations.push(value)}};
  const connection=new NativeConnection(api,"chrome",()=>{});
  connection.connect();
  const request={version:1,kind:"restoreTab",id:"00000000-0000-0000-0000-000000000004",
    connection:sent[0].connection,url:"https://example.com/",expiresAt:Date.now()+3500};
  onMessage(request);
  await new Promise(resolve=>setImmediate(resolve));
  assert.equal(mutations.length,1);
  assert.deepEqual(sent[1],{version:1,kind:"restoreResult",connection:request.connection,id:request.id,outcome:"reopened"});
  assert.equal(badges.length,0);
});
