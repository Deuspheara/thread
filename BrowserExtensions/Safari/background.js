import { RequestConnection } from "./RequestConnection.js";
import { TabObserver } from "./TabObserver.js";

let observer;
const transport = new RequestConnection(browser, () => observer.resynchronize());
observer = new TabObserver(browser, transport);
observer.start();
browser.action.onClicked.addListener(() => transport.reconnect());
transport.connect();
