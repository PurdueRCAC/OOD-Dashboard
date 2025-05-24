// app/javascript/config.js
"use strict;";
var CONFIG_ID = "ood_config";
function configData() {
  return document.getElementById(CONFIG_ID).dataset;
}
function maxFileSize() {
  const cfgData = configData();
  if (cfgData["maxFileSize"].length == 0) {
    return parseInt(1073742e4, 10);
  } else {
    const maxFileSize2 = cfgData["maxFileSize"];
    return parseInt(maxFileSize2, 10);
  }
}
function transfersPath() {
  const cfgData = configData();
  const transfersPath2 = cfgData["transfersPath"];
  return transfersPath2;
}
function jobsInfoPath() {
  const cfgData = configData();
  return cfgData["jobsInfoPath"];
}
function csrfToken() {
  const csrf_token = document.querySelector('meta[name="csrf-token"]').content;
  return csrf_token;
}
function uppyLocale() {
  const cfgData = configData();
  return JSON.parse(cfgData["uppyLocale"]);
}
function isBCDynamicJSEnabled() {
  const cfgData = configData();
  return cfgData["bcDynamicJs"] == "true";
}
export {
  csrfToken,
  isBCDynamicJSEnabled,
  jobsInfoPath,
  maxFileSize,
  transfersPath,
  uppyLocale
};
//# sourceMappingURL=config.js.map
