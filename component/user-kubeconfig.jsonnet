local com = import 'lib/commodore.libjsonnet';
local esp = import 'lib/espejote.libsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';

local inv = kap.inventory();
local params = inv.parameters.capi_core;

// NOTE(sg): Assumption that CAPI cluster name will always match Project Syn
// cluster name.
local clusterName = inv.parameters.cluster.name;
local caddyResourceName = 'user-kubeconfig';
local caddyPort = 8000;

local caddyConfig = {
  admin: {
    disabled: true,
  },
  apps: {
    http: {
      servers: {
        srv0: {
          listen: [ ':%d' % caddyPort ],
          routes: [
            // for the container health check
            {
              match: [
                {
                  path: [
                    '/healthz',
                  ],
                },
              ],
              handle: [
                {
                  body: 'OK',
                  handler: 'static_response',
                  status_code: 200,
                },
              ],
            },
            {
              match: [
                {
                  header: { Accept: [ 'application/yaml' ] },
                  path: [ '/' ],
                },
              ],
              handle: [
                {
                  handler: 'static_response',
                  headers: { Location: [ '/kubeconfig' ] },
                  status_code: 302,
                },
              ],
            },
            {
              handle: [
                { handler: 'encode' },
                {
                  handler: 'templates',
                  file_root: '/data',
                },
                {
                  handler: 'file_server',
                  hide: [ 'caddy.json' ],
                  root: '/data',
                },
              ],
            },
          ],
        },
      },
    },
  },
};

// user kubeconfig renderer and server config: JsonnetLibrary that forwards
// user-supplied and internal config to the Espejote ManagedResource.
local jsonnetlib = esp.jsonnetLibrary('capi-kubeconfig-ca-manager', params.namespace) {
  spec: {
    data: {
      'config.json': std.manifestJson({
        caddyResourceName: caddyResourceName,
        namespace: params.namespace,
        apiURL: params.kubeconfig.apiURL,
        oidcIssuerURL: if params.kubeconfig.oidc.issuerURL == '' then
          error
            '\n\n[capi-core] Parameter `kubeconfig.oidc.issuerURL` must not be empty '
            + 'when the user kubeconfig server is enabled (`kubectl.serverURL != ""`)'
        else
          params.kubeconfig.oidc.issuerURL,
        oidcClientId: if params.kubeconfig.oidc.clientId == '' then
          error
            '\n\n[capi-core] Parameter `kubeconfig.oidc.clientId` must not be empty '
            + 'when the user kubeconfig server is enabled (`kubectl.serverURL != ""`)'
        else
          params.kubeconfig.oidc.clientId,
      }),
      'caddy.json': std.manifestJsonMinified(caddyConfig),
      'index.html': importstr 'assets/user-kubeconfig-index.html',
    },
  },
};

// kubeconfig renderer: Espejote ManagedResource which generates the ConfigMap
// for the caddy deployment (see below).
local sa = kube.ServiceAccount('capi-kubeconfig-ca-manager') {
  metadata+: {
    namespace: params.namespace,
  },
};

local managedresource = esp.managedResource('capi-kubeconfig-ca-manager', params.namespace) {
  spec: {
    context: [
      {
        name: 'kubeconfig',
        resource: {
          apiVersion: 'v1',
          kind: 'Secret',
          // NOTE(sg): This secret name is hard-coded as
          // `<cluster name>-kubeconfig` in cluster API.
          name: '%s-kubeconfig' % clusterName,
        },
      },
    ],
    triggers: [
      {
        name: 'kubeconfig',
        watchContextResource: {
          name: 'kubeconfig',
        },
      },
      {
        name: 'jsonnetlib',
        watchResource: {
          apiVersion: jsonnetlib.apiVersion,
          kind: jsonnetlib.kind,
          namespace: jsonnetlib.metadata.namespace,
          name: jsonnetlib.metadata.name,
        },
      },
    ],
    serviceAccountRef: {
      name: sa.metadata.name,
    },
    template: importstr 'espejote-templates/kubeconfig-ca-manager.jsonnet',
  },
};

local role = kube.Role('capi-kubeconfig-ca-manager') {
  metadata+: {
    namespace: params.namespace,
  },
  rules: [
    {
      apiGroups: [ '' ],
      resources: [ 'secrets' ],
      resourceNames: [ '%s-kubeconfig' % clusterName ],
      verbs: [ 'get', 'list', 'watch' ],
    },
    {
      apiGroups: [ 'espejote.io' ],
      resources: [ 'jsonnetlibraries' ],
      resourceNames: [ jsonnetlib.metadata.name ],
      verbs: [ 'get', 'list', 'watch' ],
    },
    {
      apiGroups: [ '' ],
      resources: [ 'configmaps' ],
      resourceNames: [ caddyResourceName ],
      verbs: [ 'create', 'update', 'patch' ],
    },
    {
      apiGroups: [ 'apps' ],
      resources: [ 'deployments' ],
      resourceNames: [ caddyResourceName ],
      verbs: [ 'patch' ],
    },
  ],
};

local rolebinding = kube.RoleBinding('capi-kubeconfig-ca-manager') {
  metadata+: {
    namespace: params.namespace,
  },
  roleRef_: role,
  subjects_: [ sa ],
};

// user-kubeconfig server: Caddy deployment which serves an explanatory index
// page and the kubeconfig and CA certificate from the ConfigMap rendered by
// Espejote.
local server_sa = kube.ServiceAccount(caddyResourceName) {
  metadata+: {
    namespace: params.namespace,
  },
};

local caddy_deployment = kube.Deployment(caddyResourceName) {
  metadata+: {
    namespace: params.namespace,
  },
  spec+: {
    revisionHistoryLimit: 4,
    template+: {
      spec+: {
        default_container:: 'caddy',
        serviceAccountName: server_sa.metadata.name,
        securityContext: {
          runAsNonRoot: true,
          // caddy image uses 1001
          runAsUser: 1001,
          runAsGroup: 1001,
          fsGroup: 1001,
        },
        containers_:: {
          caddy: kube.Container('caddy') {
            image: '%(registry)s/%(repository)s:%(tag)s' % params.images.caddy,
            command: [ 'caddy', 'run', '--config', '/data/caddy.json' ],
            env_: {
              CLUSTER_NAME: clusterName,
            },
            ports_: {
              api: {
                protocol: 'TCP',
                containerPort: caddyPort,
              },
            },
            securityContext: {
              allowPrivilegeEscalation: false,
              capabilities: {
                add: [ 'NET_BIND_SERVICE' ],
                drop: [ 'ALL' ],
              },
              seccompProfile: {
                type: 'RuntimeDefault',
              },
              privileged: false,
            },
            livenessProbe: {
              failureThreshold: 3,
              httpGet: {
                path: '/healthz',
                port: caddyPort,
              },
              initialDelaySeconds: 1,
              periodSeconds: 10,
              successThreshold: 1,
              timeoutSeconds: 1,
            },
            readinessProbe: {
              failureThreshold: 3,
              httpGet: {
                path: '/healthz',
                port: caddyPort,
              },
              initialDelaySeconds: 1,
              periodSeconds: 10,
              successThreshold: 1,
              timeoutSeconds: 1,
            },
            volumeMounts_: {
              data: {
                mountPath: '/data',
                readOnly: true,
              },
            },
          },
        },
        volumes_: {
          data: {
            configMap: {
              defaultMode: std.parseOctal('0440'),
              name: caddyResourceName,
            },
          },
        },
      },
    },
  },
};

local service = kube.Service(caddyResourceName) {
  metadata+: {
    namespace: params.namespace,
  },
  target_pod:: caddy_deployment.spec.template,
  spec+: {
    ports: [
      {
        name: 'http',
        port: 8000,
        targetPort: caddyPort,
        protocol: 'TCP',
      },
    ],
  },
};

local ingress =
  kube.Ingress(caddyResourceName) +
  com.makeMergeable(params.kubeconfig.ingress) {
    metadata+: {
      // NOTE(sg): we ignore user-provided name and namespace
      name: caddyResourceName,
      namespace: params.namespace,
    },
    spec+: {
      // NOTE(sg): we ignore any user-provided ingress rules.
      rules: [
        {
          host: params.kubeconfig.serverURL,
          http: {
            paths: [
              {
                path: '/',
                pathType: 'Prefix',
                backend: service.name_port,
              },
            ],
          },
        },
      ],
    },
  };

if params.kubeconfig.serverURL != '' then {
  '20_kubeconfig_ca_manager': [
    managedresource,
    jsonnetlib,
    sa,
    role,
    rolebinding,
  ],
  '20_user_kubeconfig_server': [
    server_sa,
    caddy_deployment,
    service,
    ingress,
  ],
} else {}
