{
  kustomize_patch_crd_clusterctl_label: {
    patch: {
      path: 'clusterctl-label.yaml',
      target: {
        group: 'apiextensions.k8s.io',
        version: 'v1',
        kind: 'CustomResourceDefinition',
      },
    },
    patch_file: {
      'clusterctl-label': {
        apiVersion: 'apiextensions.k8s.io/v1',
        kind: 'CustomResourceDefinition',
        metadata: {
          name: 'REPLACE_ME',
          labels: {
            'clusterctl.cluster.x-k8s.io': '',
          },
        },
      },
    },
  },

  capiApiVersion: 'v1beta2',

  _Resource(apiGroup, kind, name): {
    apiVersion: '%s/%s' % [ apiGroup, $.capiApiVersion ],
    kind: kind,
    metadata: {
      name: name,
    },
  },

  Cluster(name):
    $._Resource('cluster.x-k8s.io', 'Cluster', name),
  MachineDeployment(name):
    $._Resource('cluster.x-k8s.io', 'MachineDeployment', name),
  ClusterResourceSet(name):
    $._Resource('addons.cluster.x-k8s.io', 'ClusterResourceSet', name),
}
