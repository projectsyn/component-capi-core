local kap = import 'lib/kapitan.libjsonnet';
local inv = kap.inventory();
local params = inv.parameters.capi_core;
local argocd = import 'lib/argocd.libjsonnet';

local app = argocd.App('capi-core', params.namespace) {
  spec+: {
    syncOptions+: [
      'ServerSideApply=true',
    ],
  },
};

local appPath =
  local project = std.get(std.get(app, 'spec', {}), 'project', 'syn');
  if project == 'syn' then 'apps' else 'apps-%s' % project;

{
  ['%s/capi-core' % appPath]: app,
}
