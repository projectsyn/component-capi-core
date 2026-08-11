local capi = import 'lib/capi.libjsonnet';
local com = import 'lib/commodore.libjsonnet';
local inv = com.inventory();
local params = inv.parameters.capi_core;

local kustomizeDir = std.extVar('output_path');

com.fixupDir(
  kustomizeDir,
  function(obj)
    capi.substituteVariables(params.variables, obj)
)
