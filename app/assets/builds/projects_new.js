// app/javascript/projects_new.js
jQuery(function() {
  $("#project_template").on("change", (event) => templateChange(event));
});
function templateChange(event) {
  const choice = $(`#project_template option[value="${event.target.value}"]`)[0];
  if (choice === void 0) {
    return;
  }
  const name = choice.label;
  const description = choice.dataset.description;
  const icon = choice.dataset.icon;
  $("#project_name").val(name);
  $("#project_description").val(description);
  $("#product_icon_select").val(icon);
  $("#product_icon_select").trigger("change");
}
//# sourceMappingURL=projects_new.js.map
