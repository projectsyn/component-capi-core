// main template for capi-core
local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local inv = kap.inventory();
// The hiera parameters for the component
local params = inv.parameters.capi_core;

com.Kustomization(
  'https://github.com/kubernetes-sigs/cluster-api/' + params.kustomize.manifest_path + '/' + params.kustomize.target,
  params.images['cluster-api'].tag,
  {},
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
