local com = import 'lib/commodore.libjsonnet';

local inv = com.inventory();
local params = inv.parameters.capi_core;

local kustomizeDir = std.extVar('output_path');

local substitute(vars, input) =
  // Build a convenient lookup object:
  // { VAR: "foo", OTHER: "bar" }
  local varMap = {
    [v.name]: std.toString(v.value)
    for v in vars
  };

  // Resolve the contents of one placeholder:
  //   VAR          -> value of VAR
  //   VAR:=default -> value of VAR, or "default"
  local resolvePlaceholder(expr) =
    local colon = std.findSubstr(':=', expr);
    local hasDefault = std.length(colon) > 0;
    local splitAt = if hasDefault then colon[0] else null;
    local name =
      if hasDefault then
        std.substr(expr, 0, splitAt)
      else
        expr;
    local default =
      if hasDefault then
        std.substr(expr, splitAt + 2, std.length(expr))
      else
        null;

    if std.objectHas(varMap, name) then
      varMap[name]
    else if hasDefault then
      default
    else
      error 'Variable not set: ' + name;

  // Replace placeholders in a string.
  local substituteString(s) =
    local starts = std.findSubstr('${', s);

    if std.length(starts) == 0 then
      s
    else
      local start = starts[0];
      local rest = std.substr(s, start + 2, std.length(s));
      local ends = std.findSubstr('}', rest);

      // No closing "}" -> leave the remainder untouched.
      if std.length(ends) == 0 then
        s
      else
        local end = ends[0];
        local before = std.substr(s, 0, start);
        local expr = std.substr(rest, 0, end);
        local after = std.substr(rest, end + 1, std.length(rest));

        before
        + resolvePlaceholder(expr)
        + substituteString(after);

  // Recursively walk arbitrary Jsonnet values.
  local walk(x) =
    if std.type(x) == 'object' then
      {
        [key]: walk(x[key])
        for key in std.objectFields(x)
      }
    else if std.type(x) == 'array' then
      [walk(v) for v in x]
    else if std.type(x) == 'string' then
      substituteString(x)
    else
      x;

  walk(input);
  
com.fixupDir(
  kustomizeDir,
  function(obj)
    substitute(params.variables, obj)
)