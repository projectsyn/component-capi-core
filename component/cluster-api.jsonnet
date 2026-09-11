// main template for capi-core
local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';

local capi = import 'lib/capi-core.libsonnet';

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
    // NOTE(sg): Somehow the upstream replacements don't take our `namespace`
    // override into account? For now, we replicate the namespace replacements
    // here to workaround this issue.
    replacements: [
      {
        source: {
          fieldPath: '.metadata.namespace',
          group: 'cert-manager.io',
          kind: 'Certificate',
          name: 'serving-cert',
          version: 'v1',
        },
        targets: [
          {
            fieldPaths: [
              '.metadata.annotations.[cert-manager.io/inject-ca-from]',
            ],
            options: {
              create: true,
              delimiter: '/',
            },
            select: {
              kind: 'ValidatingWebhookConfiguration',
            },
          },
          {
            fieldPaths: [
              '.metadata.annotations.[cert-manager.io/inject-ca-from]',
            ],
            options: {
              create: true,
              delimiter: '/',
            },
            select: {
              kind: 'MutatingWebhookConfiguration',
            },
          },
          {
            fieldPaths: [
              '.metadata.annotations.[cert-manager.io/inject-ca-from]',
            ],
            options: {
              create: true,
              delimiter: '/',
            },
            select: {
              kind: 'CustomResourceDefinition',
            },
          },
        ],
      },
      {
        source: {
          fieldPath: '.metadata.namespace',
          kind: 'Service',
          name: 'webhook-service',
          version: 'v1',
        },
        targets: [
          {
            fieldPaths: [
              '.spec.dnsNames.0',
              '.spec.dnsNames.1',
            ],
            options: {
              create: true,
              delimiter: '.',
              index: 1,
            },
            select: {
              group: 'cert-manager.io',
              kind: 'Certificate',
              version: 'v1',
            },
          },
        ],
      },
    ],
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
} + capi.kustomize_crd_clusterctl_label_patch
