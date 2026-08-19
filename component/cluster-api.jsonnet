// main template for capi-core
local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local inv = kap.inventory();
// The hiera parameters for the component
local params = inv.parameters.capi_core;

local manifest_path = 'config/default';

com.Kustomization(
  'https://github.com/kubernetes-sigs/cluster-api/' + manifest_path,
  params.images['cluster-api'].tag,
  {
    'registry.k8s.io/cluster-api/cluster-api-controller': {
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
