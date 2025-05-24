// app/javascript/path_selector/path_selector_data_table.js
var PathSelectorTable = class {
  _table = null;
  tableId = void 0;
  filesPath = void 0;
  breadcrumbId = void 0;
  initialDirectory = void 0;
  selectButtonId = void 0;
  inputFieldId = void 0;
  modalId = void 0;
  showHidden = void 0;
  showFiles = void 0;
  constructor(options) {
    this.tableId = options.tableId;
    this.filesPath = options.filesPath;
    this.breadcrumbId = options.breadcrumbId;
    this.initialDirectory = options.initialDirectory;
    this.selectButtonId = options.selectButtonId;
    this.inputFieldId = options.inputFieldId;
    this.modalId = options.modalId;
    this.showHidden = options.showHidden === "true";
    this.showFiles = options.showFiles === "true";
    this.initDataTable();
    this.reloadTable(this.initialUrl());
    $(`#${this.tableId} tbody`).on("click", "tr", (event) => {
      this.clickRow(event);
    });
    $("#favorites").on("click", "li", (event) => {
      this.clickRow(event);
    });
    $(`#${this.breadcrumbId}`).on("click", "li", (event) => {
      this.clickBreadcrumb(event);
    });
    $(`#${this.selectButtonId}`).on("click", (event) => {
      this.selectPath(event);
    });
  }
  initDataTable() {
    this._table = $(`#${this.tableId}`).DataTable({
      autoWidth: false,
      language: {
        search: "Filter:"
      },
      order: [[0, "asc"], [1, "asc"]],
      rowId: "id",
      paging: false,
      scrollCollapse: true,
      select: {
        style: "os",
        className: "selected",
        toggleable: true,
        selector: "td:not(:first-child)"
      },
      dom: "<'row'<'col-sm-12'f>><'row'<'col-sm-12'<'dt-status-bar'<'datatables-status float-right'><'transfers-status'>>>><'row'<'col-sm-12'tr>>",
      columns: [
        {
          data: "type",
          render: (data, _type, _row, _meta) => data == "d" ? '<span title="directory" class="fa fa-folder gold"><span class="sr-only">directory</span></span>' : '<span title="file" class="fa fa-file black"><span class="sr-only">file</span></span>'
        },
        {
          name: "name",
          data: "name",
          className: "text-break",
          render: (data, _type, _row, _meta) => {
            return `<span>${data}</span>`;
          }
        }
      ],
      createdRow: function(row, data, _dataIndex) {
        row.classList.add("clickable");
        row.dataset["apiUrl"] = data.url;
        row.dataset["pathType"] = data.type;
      }
    });
  }
  async reloadTable(url) {
    try {
      $(this.tableWrapper()).hide();
      $("#loading-icon").show();
      const response = await fetch(url, { headers: { "Accept": "application/json" }, cache: "no-store" });
      const data = await this.dataFromJsonResponse(response);
      $(`#${this.breadcrumbId}`).html(data.path_selector_breadcrumbs_html);
      this._table.clear();
      this._table.rows.add(data.files);
      this.setLastVisited(data.path);
      this._table.draw();
      this.resetTable();
    } catch (err) {
      this.resetTable();
      if (err.message.match("Permission denied")) {
        $("#forbidden-warning").removeClass("d-none");
        $("#forbidden-warning").trigger("focus");
      }
      console.log(err);
    }
  }
  resetTable() {
    $("#loading-icon").hide();
    $(this.tableWrapper()).show();
    $("#forbidden-warning").addClass("d-none");
  }
  dataFromJsonResponse(response) {
    return new Promise((resolve, reject) => {
      Promise.resolve(response).then((response2) => response2.ok ? Promise.resolve(response2) : Promise.reject(new Error(response2.statusText))).then((response2) => response2.json()).then((data) => this.filterFileResponse(data)).then((data) => data.error_message ? Promise.reject(new Error(data.error_message)) : resolve(data)).catch((e) => reject(e));
    });
  }
  clickRow(event) {
    const row = $(event.target).closest("tr").get(0) || event.target;
    const url = row.dataset["apiUrl"];
    const pathType = row.dataset["pathType"];
    this.activateFavorite(row);
    if (pathType == "f") {
      const path = url.replace(this.filesPath, "").replaceAll("//", "/");
      this.setLastVisited(path, pathType);
    } else {
      this.reloadTable(url);
    }
  }
  activateFavorite(currentlyClicked) {
    $("li.active").each((_idx, ele) => {
      ele.classList.remove("active");
    });
    if (currentlyClicked.tagName == "LI") {
      currentlyClicked.classList.add("active");
    }
  }
  clickBreadcrumb(event) {
    const path = event.target.id;
    this.activateFavorite(event.target);
    this.reloadTable(path);
  }
  selectPath(_event) {
    const last = this.getLastVisited();
    const inputField = document.getElementById(this.inputFieldId);
    inputField.value = last.path;
    $(`#${this.modalId}`).modal("hide");
  }
  storageKey() {
    const underscore_path = window.location.pathname.replaceAll("/", "_");
    return `${this.tableId}${underscore_path}_last_visited`;
  }
  tableWrapper() {
    return `#${this.tableId}_wrapper`;
  }
  getLastVisited() {
    const lastVisited = localStorage.getItem(this.storageKey());
    if (lastVisited === null) {
      return { path: this.initialDirectory, type: "d" };
    } else {
      return JSON.parse(lastVisited);
    }
  }
  setLastVisited(path, pathType = "d") {
    const item = { path, type: pathType };
    if (path) {
      localStorage.setItem(this.storageKey(), JSON.stringify(item));
    }
  }
  initialUrl() {
    const last = this.getLastVisited();
    let path = void 0;
    if (last.type == "f") {
      path = last.path.split("/").slice(0, -1).join("/");
    } else {
      path = last.path;
    }
    if (path.startsWith("/")) {
      return `${this.filesPath}${path}`;
    } else {
      return `${this.filesPath}/${path}`;
    }
  }
  filterFileResponse(data) {
    const filteredFiles = data.files.filter((file) => {
      const isHidden = file.name.startsWith(".");
      const isFile = file.type == "f";
      if (isHidden && isFile) {
        return this.showHidden && this.showFiles;
      } else if (isHidden) {
        return this.showHidden;
      } else if (isFile) {
        return this.showFiles;
      } else {
        return true;
      }
    });
    data.files = filteredFiles;
    return data;
  }
};
export {
  PathSelectorTable
};
//# sourceMappingURL=path_selector_data_table.js.map
