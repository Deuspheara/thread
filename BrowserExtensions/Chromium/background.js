import { NativeConnection } from "./NativeConnection.js";
import { TabObserver } from "./TabObserver.js";
import { browserKind } from "./privacy.js";

let observer;
const transport = new NativeConnection(chrome, browserKind(navigator), () => {
  observer.resynchronize();
});
observer = new TabObserver(chrome, transport);
observer.start();
chrome.action.onClicked.addListener(() => transport.reconnect());
transport.connect();
