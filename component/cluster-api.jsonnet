// main template for capi-core
local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local inv = kap.inventory();
// The hiera parameters for the component
local params = inv.parameters.capi_core;

local capi_version =
  local verparts = std.split(params.images['cluster-api'].tag[1:], '.');
  local parseOrError(val, typ) =
    local parsed = std.parseJson(val);
    if std.isNumber(parsed) then
      parsed
    else
      error
        'Failed to parse %s version "%s" as number' % [
          typ,
          val,
        ];
  {
    major: parseOrError(verparts[0], 'major'),
    minor: parseOrError(verparts[1], 'minor'),
  };
local manifest_path = if capi_version.major > 1
                         || capi_version.major == 1
                            && capi_version.minor > 13 then
  'core/config/default'
else
  'config/default';

com.Kustomization(
  'https://github.com/kubernetes-sigs/cluster-api/' + manifest_path,
  params.images['cluster-api'].tag,
  {
    'gcr.io/k8s-staging-cluster-api/cluster-api-controller': {
      local image = params.images['cluster-api'],
      newTag: image.tag,
      newName: '%(registry)s/%(image)s' % image,
    },
  },
  {
    namespace: params.namespace,
    labels+: [
      {
        pairs: {
          'app.kubernetes.io/managed-by': 'commodore',
        },
      },
    ],
    patchesStrategicMerge: [ 'rm-namespace.yaml' ],
  },
) {
  'rm-namespace': [
    {
      '$patch': 'delete',
      apiVersion: 'v1',
      kind: 'Namespace',
      metadata: {
        name: 'capi-system',
      },
    },
  ],
}
