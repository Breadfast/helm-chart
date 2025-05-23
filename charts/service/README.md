# service

![Version: 0.2.54](https://img.shields.io/badge/Version-0.2.54-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square)

A Helm chart for Kubernetes

**Homepage:** <https://github.com/Breadfast/helm-chart>

## Maintainers

| Name | Email | Url |
| ---- | ------ | --- |
| DevOps-team | <devops@breadfast.com> |  |

## Source Code

* <https://github.com/Breadfast/helm-chart>

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| argorollouts.dynamicStableScale | bool | `true` |  |
| argorollouts.enabled | bool | `false` |  |
| argorollouts.steps[0].setWeight | int | `20` |  |
| argorollouts.steps[1].pause.duration | string | `"1m"` |  |
| argorollouts.steps[2].setWeight | int | `60` |  |
| argorollouts.steps[3].pause | object | `{}` |  |
| autoscaling.enabled | bool | `false` |  |
| containerEnv | map | `[]` | Environment variable map |
| cronJob | bool | `{"create":false}` | If true, Creates CronJob resource |
| datadog | bool | `{"enabled":false}` | If true, Add datadog labels to pods and deployments |
| deploymentLabels | object | `{}` |  |
| destinationRule.enabled | bool | `false` |  |
| destinationRule.trafficPolicy | object | `{}` |  |
| entrypointOverride | bool | `{"enabled":false}` | If true, Override to the Entrypoint |
| extraService.enabled | bool | `false` |  |
| extraService.port | int | `9113` |  |
| extraService.portName | string | `"extraport"` |  |
| extraService.targetPort | int | `9113` |  |
| extraService.type | string | `"ClusterIP"` |  |
| fullnameOverride | string | `""` |  |
| gcpVolumeMounts | bool | `{"enabled":false}` | If true, add annotation o enable GCP Volume Mounts (GCSFuse) |
| goreplay.args[0] | string | `"-input-raw"` |  |
| goreplay.args[1] | string | `"any:80"` |  |
| goreplay.args[2] | string | `"--output-file"` |  |
| goreplay.args[3] | string | `"/traffic/requests-%Y-%m-%d-%H.log"` |  |
| goreplay.args[4] | string | `"-verbose"` |  |
| goreplay.args[5] | string | `"2"` |  |
| goreplay.args[6] | string | `"--output-file-append"` |  |
| goreplay.enabled | bool | `false` |  |
| goreplay.gcpbucketName | string | `"goreplay-non-prod"` |  |
| goreplay.image | string | `"us-central1-docker.pkg.dev/prj-n-floating-623c/apps/goreplay:latest"` |  |
| image.pullPolicy | string | `"IfNotPresent"` |  |
| image.repository | string | `"repo/image"` |  |
| image.tag | string | `""` |  |
| imagePullSecrets | list | `[]` |  |
| ingress | bool | `{"enabled":false}` | If true, Creats Ingress DNS name to expose the service publicly |
| livenessProbe | object | `{}` |  |
| multiIngress | bool | `{"enabled":false}` | If true, Creats Multible Ingresses DNS name to expose the service publicly |
| nameOverride | string | `""` |  |
| nodeSelectorLabels | object | `{}` | Provide node groups selector |
| nodeTolerations | list | `[]` | Node Tolerations. Tolerations allow the scheduler to schedule pods with matching taints |
| pdb.enabled | bool | `false` |  |
| pdb.minAvailable | string | `"60%"` |  |
| podAffinity | object | `{}` | Pod affinity rule. Default affinity rule is set to make sure pods are not deployed on the same node |
| podAnnotations | object | `{}` |  |
| podAntiAffinity | object | `{}` |  |
| podLabels | object | `{}` |  |
| podSecurityContext | object | `{}` |  |
| readinessProbe | object | `{}` |  |
| replicaCount | int | `1` |  |
| resources | object | `{}` |  |
| rollingStrategy | string | `"RollingUpdate"` | Specify deployment rolling strategy: https://kubernetes.io/docs/concepts/workloads/controllers/deployment/#strategy |
| securityContext | object | `{}` |  |
| service.name | string | `"http"` | Service port name when single port service |
| service.port | int | `80` | Kubernetes service port when single port service |
| service.ports | list | `[]` | Used when the service container requires multiple ports. The port parameter will be ignored if this is set.    Example:       - name: http         port: 8069         targetPort: 8069       - name: websocket         port: 8072         targetPort: 8072       - name: xmlrpc         port: 8071         targetPort: 8071 |
| service.targetPort | int | `80` |  |
| service.type | string | `"ClusterIP"` | Service type, can be either `ClusterIP`, `NodePort`, `LoadBalancer` or `ExternalName` |
| serviceAccount.annotations | object | `{}` | If not set and create is true, a name is generated using the fullname template |
| serviceAccount.create | bool | `false` | If true, creates service account |
| serviceAccount.name | string | `""` |  |
| startupProbe | object | `{}` |  |
| vaultAgent | bool | `{"enabled":false}` | If true, It will inject Vault Agent to get secrets from Vault |
| virtualService.enabled | bool | `false` |  |
| virtualService.hosts | list | `[]` |  |
| virtualService.http | object | `{}` |  |
| volumeMounts | list | `[]` | List of volumes to attach |
| volumes | list | `[]` | To add GCP Bucket as volume, use the following format - name: volume-name   csi:     driver: gcsfuse.csi.storage.gke.io     volumeAttributes:       bucketName: gcp-bucket-name       mountOptions: "implicit-dirs"       gcsfuseLoggingSeverity: warning |

----------------------------------------------
Autogenerated from chart metadata using [helm-docs v1.14.2](https://github.com/norwoodj/helm-docs/releases/v1.14.2)
