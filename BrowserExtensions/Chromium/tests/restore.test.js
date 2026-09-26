import test from "node:test";
import assert from "node:assert/strict";
import { TabRestorer } from "../TabRestorer.js";
const connection = "00000000-0000-0000-0000-000000000001";
const command = { expiresAt: Date.now() + 9000, version: 1, kind: "restoreTab", id: "00000000-0000-0000-0000-000000000002", connection, tabID: 7, url: "https://example.com/docs" };
function fixture(tabs = [], windows = []) {
  const mutations = [];
  return { mutations, api: {
    tabs: {
      get: async id => { const tab = tabs.find(tab => tab.id === id); if (!tab) throw Error(); return tab; },
      query: async () => tabs,
      update: async (...args) => mutations.push(["tab", ...args]),
      create: async (...args) => mutations.push(["createTab", ...args])
    }, windows: {
      get: async id => { const window = windows.find(window => window.id === id); if (!window) throw Error(); return window; },
      getAll: async () => windows,
      update: async (...args) => mutations.push(["window", ...args]),
      create: async (...args) => mutations.push(["createWindow", ...args])
    }
  } };
}
const publicTab = { id: 7, windowId: 4, incognito: false, url: command.url, active: false };
const publicWindow = { id: 4, incognito: false, type: "normal" };

test("reuses only the matching public tab and duplicate requests perform no further mutation", async () => {
  const {api, mutations} = fixture([publicTab], [publicWindow]);
  const restorer = new TabRestorer(api);
  const results = await Promise.all([restorer.restore(command, connection), restorer.restore(command, connection)]);
  assert.deepEqual(results.map(result => result.outcome), ["focused", "focused"]);
  assert.deepEqual(mutations, [["tab",7,{active:true}], ["window",4,{focused:true}]]);
});
test("a reused tab identifier never navigates an unrelated tab", async () => {
  const {api, mutations} = fixture([{...publicTab,url:"https://unrelated.example/"}], [publicWindow]);
  assert.equal((await new TabRestorer(api).restore(command, connection)).outcome, "reopened");
  assert.equal(mutations[0][0], "createTab");
});
test("private tabs and private current windows are neither focused nor reused", async () => {
  const {api, mutations} = fixture([{...publicTab,incognito:true}], [{...publicWindow,incognito:true}]);
  assert.equal((await new TabRestorer(api).restore(command, connection)).outcome, "reopened");
  assert.deepEqual(mutations, [["createWindow",{url:command.url,incognito:false,focused:true,type:"normal"}]]);
});
test("unsafe URLs and stale connections perform no browser operations", async () => {
  const restorer = new TabRestorer({});
  for (const url of ["file:///secret", "javascript:alert(1)", "https://user:pass@example.com/", command.url+"?secret", command.url+"#secret"]) {
    assert.equal((await restorer.restore({...command,url}, connection)).outcome, "refused");
  }
  assert.equal((await restorer.restore(command, "00000000-0000-0000-0000-000000000003")).outcome,"refused");
});
test("a reused request ID with a different URL is refused", async () => {
  const {api, mutations} = fixture([], []);
  const restorer = new TabRestorer(api);
  await restorer.restore(command, connection);
  assert.equal((await restorer.restore({...command,url:"https://another.example/"}, connection)).outcome,"refused");
  assert.equal(mutations.length,1);
});

test("native request bursts are bounded and API failures are acknowledged", async () => {
  let release;
  const api = {tabs:{query:()=>new Promise(resolve=>{release=resolve;})},windows:{getAll:async()=>{throw Error("closed");}}};
  const restorer = new TabRestorer(api);
  const requests = [];
  for (let index=0; index<16; index++) {
    const id = `00000000-0000-0000-0000-${String(index+10).padStart(12,"0")}`;
    requests.push(restorer.restore({...command,id,tabID:undefined},connection));
  }
  assert.equal((await restorer.restore({...command,id:"00000000-0000-0000-0000-000000000099"},connection)).outcome,"busy");
  for (let index=0; index<16; index++) {
    await new Promise(resolve=>setImmediate(resolve));
    release([]);
    assert.equal((await requests[index]).outcome,"failed");
  }
});

test("expired and disconnected requests perform no mutations", async () => {
  const {api,mutations}=fixture([],[]);
  assert.equal((await new TabRestorer(api).restore({...command,expiresAt:Date.now()-1},connection)).outcome,"refused");
  assert.equal((await new TabRestorer(api,()=>false).restore(command,connection)).outcome,"refused");
  assert.deepEqual(mutations,[]);
});
