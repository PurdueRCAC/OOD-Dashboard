// app/javascript/dynamic_forms.js
var idPrefix = void 0;
var shortNameRex = void 0;
var formTokens = [];
var optionForHandlerCache = {};
var minMaxHandlerCache = [];
var setHandlerCache = [];
var hideHandlerCache = {};
var minMaxLookup = {};
var setValueLookup = {};
var hideLookup = {};
var mcRex = /[-_]([a-z])|([_-][0-9])|([\/])/g;
var initializing = true;
function idWithPrefix(name) {
  return `${idPrefix}_${name.toLowerCase()}`;
}
function shortId(elementId) {
  const match = elementId.match(shortNameRex);
  if (match.length >= 1) {
    return match[1];
  } else {
    return "";
  }
  ;
}
function mountainCaseWords(str) {
  const lower = str.toLowerCase();
  const first = lower.charAt(0).toUpperCase();
  const rest = lower.slice(1).replace(mcRex, function(_all, letter, prefixedNumber, slash) {
    if (letter) {
      return letter.toUpperCase();
    } else if (prefixedNumber) {
      return prefixedNumber.replace("_", "-");
    } else if (slash) {
      return "_";
    }
  });
  return `${first}${rest}`;
}
function snakeCaseWords(str) {
  if (str === void 0)
    return void 0;
  let snakeCase = "";
  str.split("").forEach((c, index) => {
    if (c === "-" || c === "_") {
      snakeCase += "_";
    } else if (index == 0) {
      snakeCase += c.toLowerCase();
    } else if (c == c.toUpperCase() && isNaN(c)) {
      const nextIsUpper = index + 1 !== str.length ? str[index + 1] === str[index + 1].toUpperCase() : true;
      const nextIsNum = !isNaN(str[index + 1]);
      if ((str[index - 1] === "_" || nextIsUpper) && !nextIsNum) {
        snakeCase += c.toLowerCase();
      } else {
        snakeCase += `_${c.toLowerCase()}`;
      }
    } else {
      snakeCase += c;
    }
  });
  return snakeCase;
}
function memorizeElements(elements2) {
  elements2.each((_i, ele) => {
    formTokens.push(mountainCaseWords(shortId(ele["id"])));
    optionForHandlerCache[ele["id"]] = [];
  });
}
function makeChangeHandlers(prefix) {
  idPrefix = prefix;
  shortNameRex = new RegExp(`${idPrefix}_([\\w\\-]+)`);
  const allElements = $(`[id^=${idPrefix}]`);
  memorizeElements(allElements);
  allElements.each((_i, element) => {
    if (element["type"] == "select-one") {
      let optionSearch = `#${element["id"]} option`;
      let options = $(optionSearch);
      options.each((_i2, opt) => {
        let data = $(`${optionSearch}[value='${opt.value}']`).data();
        let keys = Object.keys(data);
        if (keys.length !== 0) {
          keys.forEach((key) => {
            if (key.startsWith("optionFor")) {
              let token = key.replace(/^optionFor/, "");
              addOptionForHandler(idFromToken(token), element["id"]);
            } else if (key.startsWith("max") || key.startsWith("min")) {
              addMinMaxForHandler(element["id"], opt.value, key, data[key]);
            } else if (key.startsWith("set")) {
              addSetHandler(element["id"], opt.value, key, data[key]);
            } else if (key.startsWith("hide")) {
              addHideHandler(element["id"], opt.value, key, data[key]);
            }
          });
        }
      });
    } else if (element["type"] == "checkbox") {
      let data = $(element).data();
      let keys = Object.keys(data);
      if (keys.length !== 0) {
        keys.forEach((key) => {
          if (key.startsWith("hide")) {
            let tokens = parseCheckedWhen(key);
            if (tokens !== void 0) {
              addHideHandler(element["id"], tokens["value"], tokens["key"], data[key]);
            }
          }
        });
      }
    }
  });
  initializing = false;
}
function addHideHandler(optionId, option, key, configValue) {
  const changeId = idFromToken(key.replace(/^hide/, ""));
  if (hideLookup[optionId] === void 0)
    hideLookup[optionId] = new Table(changeId, void 0);
  const table = hideLookup[optionId];
  table.put(changeId, option, configValue);
  if (hideHandlerCache[optionId] === void 0)
    hideHandlerCache[optionId] = [];
  if (!hideHandlerCache[optionId].includes(changeId)) {
    const changeElement = $(`#${optionId}`);
    changeElement.on("change", (event) => {
      updateVisibility(event, changeId);
    });
    hideHandlerCache[optionId].push(changeId);
  }
  updateVisibility({ target: document.querySelector(`#${optionId}`) }, changeId);
}
function addMinMaxForHandler(subjectId, option, key, configValue) {
  subjectId = String(subjectId || "");
  configValue = parseInt(configValue);
  const configObj = parseMinMaxFor(key);
  const objectId = configObj["subjectId"];
  if (objectId === void 0)
    return;
  const secondDimId = configObj["predicateId"];
  const secondDimValue = configObj["predicateValue"];
  const lookupKey = `${subjectId}_${objectId}`;
  if (minMaxLookup[lookupKey] === void 0)
    minMaxLookup[lookupKey] = new Table(subjectId, secondDimId);
  const table = minMaxLookup[lookupKey];
  table.put(option, secondDimValue, { [minOrMax(key)]: configValue });
  let cacheKey = `${objectId}_${subjectId}_${secondDimId}`;
  if (!minMaxHandlerCache.includes(cacheKey)) {
    const changeElement = $(`#${subjectId}`);
    changeElement.on("change", (event) => {
      toggleMinMax(event, objectId, secondDimId);
    });
    minMaxHandlerCache.push(cacheKey);
  }
  cacheKey = `${objectId}_${secondDimId}_${subjectId}`;
  if (secondDimId !== void 0 && !minMaxHandlerCache.includes(cacheKey)) {
    const secondEle = $(`#${secondDimId}`);
    secondEle.on("change", (event) => {
      toggleMinMax(event, objectId, subjectId);
    });
    minMaxHandlerCache.push(cacheKey);
  }
  toggleMinMax({ target: document.querySelector(`#${subjectId}`) }, objectId, secondDimId);
}
function addSetHandler(optionId, option, key, configValue) {
  const k = key.replace(/^set/, "");
  const id = String(idFromToken(k));
  if (id === "undefined")
    return;
  let cacheKey = `${id}_${optionId}`;
  if (setValueLookup[cacheKey] === void 0)
    setValueLookup[cacheKey] = new Table(optionId, void 0);
  const table = setValueLookup[cacheKey];
  table.put(option, void 0, configValue);
  if (!setHandlerCache.includes(cacheKey)) {
    const changeElement = $(`#${optionId}`);
    changeElement.on("change", (event) => {
      setValue(event, id);
    });
    setHandlerCache.push(cacheKey);
  }
  setValue({ target: document.querySelector(`#${optionId}`) }, id);
}
function setValue(event, changeId) {
  const chosenVal = event.target.value;
  const cacheKey = `${changeId}_${event.target["id"]}`;
  const table = setValueLookup[cacheKey];
  if (table === void 0)
    return;
  const changeVal = table.get(chosenVal, void 0);
  if (changeVal !== void 0) {
    const element = document.getElementById(changeId);
    if (element["type"] == "checkbox") {
      setCheckboxValue(element, changeVal);
    } else {
      element.value = changeVal;
    }
  }
}
function setCheckboxValue(checkbox, value) {
  const positiveValue = checkbox.value;
  if (value == positiveValue) {
    checkbox.checked = true;
  } else {
    checkbox.checked = false;
  }
}
var Table = class {
  constructor(x, y) {
    this.x = x;
    this.xIdxLookup = {};
    this.y = y;
    this.yIdxLookup = {};
    this.table = y === void 0 ? [] : [[]];
  }
  put(x, y, value) {
    if (!x)
      return;
    x = snakeCaseWords(x);
    y = snakeCaseWords(y);
    if (this.xIdxLookup[x] === void 0)
      this.xIdxLookup[x] = Object.keys(this.xIdxLookup).length;
    if (y && this.yIdxLookup[y] === void 0)
      this.yIdxLookup[y] = Object.keys(this.yIdxLookup).length;
    const xIdx = this.xIdxLookup[x];
    const yIdx = this.yIdxLookup[y];
    if (this.table[xIdx] === void 0) {
      this.table[xIdx] = y === void 0 ? void 0 : [];
    }
    if (yIdx === void 0) {
      if (this.table[xIdx] === void 0) {
        this.table[xIdx] = value;
      } else {
        const prev = this.table[xIdx];
        const newer = value;
        if (typeof newer == "string" && typeof prev == "string") {
          this.table[xIdx] = newer;
        } else {
          this.table[xIdx] = Object.assign(prev, newer);
        }
      }
    } else {
      if (this.table[xIdx][yIdx] === void 0) {
        this.table[xIdx][yIdx] = value;
      } else {
        const prev = this.table[xIdx][yIdx];
        const newer = value;
        if (typeof newer == "string" && typeof prev == "string") {
          this.table[xIdx][yIdx] = newer;
        } else {
          this.table[xIdx][yIdx] = Object.assign(prev, newer);
        }
      }
    }
  }
  get(x, y) {
    const xIdx = this.xIdxLookup[snakeCaseWords(x)];
    const yIdx = this.yIdxLookup[snakeCaseWords(y)];
    if (this.table[xIdx] === void 0) {
      return void 0;
    } else if (y === void 0) {
      return this.table[xIdx];
    } else {
      return this.table[xIdx][yIdx];
    }
  }
};
function updateVisibility(event, changeId) {
  const val = valueFromEvent(event);
  const id = event.target["id"];
  let changeElement = void 0;
  $(`#${changeId}`).parents().each(function(_i, parent) {
    if (parent.classList.contains("form-group")) {
      changeElement = $(parent);
    }
  });
  if (changeElement === void 0 || changeElement.length <= 0)
    return;
  const hide = hideLookup[id].get(changeId, val);
  if (hide === void 0 && !initializing) {
    changeElement.show();
  } else if (hide === true) {
    changeElement.hide();
  }
}
function valueFromEvent(event) {
  if (event.target["type"] == "checkbox") {
    return event.target.checked ? "checked" : "unchecked";
  } else {
    return event.target.value;
  }
}
function toggleMinMax(event, changeId, otherId) {
  let x = void 0, y = void 0;
  let lookupKey = `${event.target["id"]}_${changeId}`;
  if (minMaxLookup[lookupKey] === void 0) {
    lookupKey = `${otherId}_${changeId}`;
  }
  const table = minMaxLookup[lookupKey];
  if (event.target["id"] == table.x) {
    x = snakeCaseWords(event.target.value);
    y = snakeCaseWords($(`#${otherId}`).val());
  } else {
    y = snakeCaseWords(event.target.value);
    x = snakeCaseWords($(`#${otherId}`).val());
  }
  const changeElement = $(`#${changeId}`);
  const mm = table.get(x, y);
  const prev = {
    min: parseInt(changeElement.attr("min")),
    max: parseInt(changeElement.attr("max"))
  };
  ["max", "min"].forEach((dim) => {
    if (mm && mm[dim] !== void 0) {
      changeElement.attr(dim, mm[dim]);
    }
  });
  const val = clamp(parseInt(changeElement.val()), prev, mm);
  if (val !== void 0) {
    changeElement.attr("value", val);
    changeElement.val(val);
  }
}
function clamp(currentValue, previous, next) {
  if (next === void 0) {
    return void 0;
  } else if (currentValue === previous["min"]) {
    return next["min"];
  } else if (currentValue === previous["max"]) {
    return next["max"];
  } else if (currentValue <= next["min"]) {
    return next["min"];
  } else if (currentValue >= next["max"]) {
    return next["max"];
  } else {
    return void 0;
  }
}
function addOptionForHandler(causeId, targetId) {
  const changeId = String(causeId || "");
  if (changeId.length == 0 || optionForHandlerCache[causeId].includes(targetId)) {
    return;
  }
  let causeElement = $(`#${causeId}`);
  if (targetId && causeElement) {
    optionForHandlerCache[causeId].push(targetId);
    causeElement.on("change", (event) => {
      toggleOptionsFor(event, targetId);
    });
    toggleOptionsFor({ target: document.querySelector(`#${causeId}`) }, targetId);
  }
}
function parseCheckedWhen(key) {
  const tokens = key.match(/^hide(\w+)When(\w+)$/);
  if (tokens !== void 0 && tokens.length && tokens.length == 3) {
    return {
      "key": tokens[1],
      "value": tokens[2].toLowerCase() == "checked" ? "checked" : "unchecked"
    };
  } else {
    return void 0;
  }
}
function parseMinMaxFor(key) {
  let k = void 0;
  let predicateId = void 0;
  let predicateValue = void 0;
  let subjectId = void 0;
  if (key.startsWith("min")) {
    k = key.replace(/^min/, "");
  } else if (key.startsWith("max")) {
    k = key.replace(/^max/, "");
  }
  const tokens = k.match(/^(\w+)For(\w+)$/);
  if (tokens == null) {
    subjectId = idFromToken(k);
  } else if (tokens.length == 3) {
    const subject = tokens[1];
    const predicateFull = tokens[2];
    subjectId = idFromToken(subject);
    const predicateTokens = predicateFull.split(/(?=[A-Z])/);
    if (predicateTokens && predicateTokens.length >= 2) {
      if (predicateTokens.length == 2) {
        predicateId = idFromToken(predicateTokens[0]);
        predicateValue = predicateTokens[1];
      } else {
        let tokenString = "";
        let done = false;
        predicateTokens.forEach((pt, idx) => {
          if (done) {
            return;
          }
          tokenString = `${tokenString}${pt}`;
          let tokenId = idFromToken(tokenString);
          if (tokenId !== void 0) {
            done = true;
            predicateId = tokenId;
            predicateValue = predicateTokens.slice(idx + 1).join("");
          }
        });
      }
    }
  }
  return {
    "subjectId": subjectId,
    "predicateId": predicateId,
    "predicateValue": snakeCaseWords(predicateValue)
  };
}
function minOrMax(key) {
  if (key.startsWith("min")) {
    return "min";
  } else if (key.startsWith("max")) {
    return "max";
  } else {
    return null;
  }
}
function idFromToken(str) {
  elements = formTokens.map((token) => {
    let match = str.match(`^${token}{1}`);
    if (match && match.length >= 1) {
      let ele = snakeCaseWords(match[0]);
      return idWithPrefix(ele);
    }
  }).filter((id) => {
    return id !== void 0;
  });
  if (elements.length == 0) {
    return void 0;
  } else if (elements.length == 1) {
    return elements[0];
  } else if (elements.length > 1) {
    const snake_case_str = snakeCaseWords(str);
    return elements.filter((element) => {
      return element.endsWith(snake_case_str);
    })[0];
  }
}
function optionForFromToken(str) {
  return formTokens.map((token) => {
    let match = str.match(`^optionFor${token}`);
    if (match && match.length >= 1) {
      return token;
    }
  }).filter((id) => {
    return id !== void 0;
  })[0];
}
function toggleOptionsFor(_event, elementId) {
  const options = [...document.querySelectorAll(`#${elementId} option`)];
  let hideSelectedValue = void 0;
  options.forEach((option) => {
    let hide = false;
    for (let key of Object.keys(option.dataset)) {
      let optionFor = optionForFromToken(key);
      let optionForId = idFromToken(key.replace(/^optionFor/, ""));
      if (!key.startsWith("optionFor") || optionForId === void 0) {
        continue;
      }
      let optionForValue = mountainCaseWords(document.getElementById(optionForId).value);
      if (optionForValue.match(/^\d/)) {
        optionForValue = `-${optionForValue}`;
      }
      hide = option.dataset[`optionFor${optionFor}${optionForValue}`] === "false";
      if (hide) {
        break;
      }
    }
    ;
    if (hide) {
      if (option.selected) {
        option.selected = false;
        hideSelectedValue = option.textContent;
      }
      option.style.display = "none";
      option.disabled = true;
    } else {
      option.style.display = "";
      option.disabled = false;
    }
  });
  if (hideSelectedValue !== void 0) {
    let others = [...document.querySelectorAll(`#${elementId} option[value='${hideSelectedValue}']`)];
    let newSelectedOption = void 0;
    if (others.length > 1) {
      others.forEach((ele) => {
        if (ele.style.display === "") {
          newSelectedOption = ele;
          return;
        }
      });
    }
    if (newSelectedOption === void 0) {
      others = document.querySelectorAll(`#${elementId} option`);
      others.forEach((ele) => {
        if (newSelectedOption === void 0 && ele.style.display === "") {
          newSelectedOption = ele;
        }
      });
    }
    if (newSelectedOption !== void 0) {
      newSelectedOption.selected = true;
    }
  }
  document.getElementById(elementId).dispatchEvent(new Event("change", { bubbles: true }));
}
export {
  makeChangeHandlers
};
//# sourceMappingURL=dynamic_forms.js.map
