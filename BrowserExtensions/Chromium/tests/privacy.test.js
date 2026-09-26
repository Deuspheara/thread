import test from "node:test";
import assert from "node:assert/strict";
import { sanitizedTab } from "../privacy.js";
import { TabObserver } from "../TabObserver.js";
const tab = { id: 1, windowId: 2, incognito: false, active: true, url: "https://example.com/docs?q=secret#token", title: "Docs" };

test("strips queries and fragments before transport", () => {
  assert.equal(sanitizedTab(tab).url, "https://example.com/docs");
});
test("private, unknown privacy, credentials and unsafe URLs fail closed", () => {
  for (const value of [{...tab, incognito:true}, {...tab, incognito:undefined}, {...tab, url:"https://user:password@example.com/"},
    {...tab,url:"file:///secret"}, {...tab,url:"javascript:alert(1)"}, {...tab,url:"chrome://settings/"}]) assert.equal(sanitizedTab(value), null);
});
test("observer never transmits private tab identity or metadata", async () => {
  const sent=[];
  const api={tabs:{get:async()=>({...tab,incognito:true})},windows:{get:async()=>({focused:true,incognito:true})}};
  const observer=new TabObserver(api,{send:(...args)=>sent.push(args)});
  await observer.observe(1,"activated"); observer.close(1);
  assert.deepEqual(sent,[["focusCleared"]]);
});
test("navigation to excluded URL closes previously observed resource", async () => {
  const sent=[];
  let current=tab;
  const api={tabs:{get:async()=>current},windows:{get:async()=>({focused:true,incognito:false})}};
  const observer=new TabObserver(api,{send:(...args)=>sent.push(args)});
  await observer.observe(1,"activated");
  current={...tab,url:"chrome://settings/"};
  await observer.observe(1,"updated");
  assert.deepEqual(sent.map(x=>x[0]),["opened","activated","closed","focusCleared"]);
  assert.equal(sent[0][1].url,"https://example.com/docs");
});
test("private window focus sends only a neutral clear event", async () => {
  const sent=[];
  const observer=new TabObserver({windows:{getLastFocused:async()=>({focused:true,incognito:true,id:999})}},
    {send:(...args)=>sent.push(args)});
  await observer.focus();
  assert.deepEqual(sent,[["focusCleared"]]);
});
test("recovery snapshot republishes every safe tab under the new connection", async () => {
  const sent=[];
  const other={...tab,id:8,active:false};
  const api={tabs:{query:async()=>[tab,other],get:async id=>id===1?tab:other},
    windows:{get:async()=>({focused:true,incognito:false}),getLastFocused:async()=>({focused:false,incognito:false})}};
  const observer=new TabObserver(api,{send:(...args)=>sent.push(args)});
  observer.known.add(1); observer.known.add(8);
  observer.resynchronize();
  while(observer.draining) await new Promise(resolve=>setImmediate(resolve));
  assert.deepEqual(sent.filter(x=>x[0]==="opened").map(x=>x[1].tabID),[1,8]);
});

test("switching to another application preserves recent public context without new browser activity", async () => {
  const sent=[];
  const observer=new TabObserver({windows:{getLastFocused:async()=>({focused:false,incognito:false})}},
    {send:(...args)=>sent.push(args)});
  await observer.focus();
  assert.deepEqual(sent,[]);
});
