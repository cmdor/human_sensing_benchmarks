import 'dart:html' as html;

String? webLocalStorageGetString(String key) => html.window.localStorage[key];

void webLocalStorageSetString(String key, String value) {
  html.window.localStorage[key] = value;
}

void webLocalStorageRemove(String key) {
  html.window.localStorage.remove(key);
}

