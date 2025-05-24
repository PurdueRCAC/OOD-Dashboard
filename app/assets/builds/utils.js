// app/javascript/utils.js
function cssBadgeForState(state) {
  switch (state) {
    case "completed":
      return "badge-success";
    case "running":
      return "badge-primary";
    case "queued":
      return "badge-info";
    case "queued_held":
      return "badge-warning";
    case "suspended":
      return "badge-warning";
    default:
      return "badge-warning";
  }
}
function capitalizeFirstLetter(string) {
  return string.charAt(0).toUpperCase() + string.slice(1);
}
export {
  capitalizeFirstLetter,
  cssBadgeForState
};
//# sourceMappingURL=utils.js.map
