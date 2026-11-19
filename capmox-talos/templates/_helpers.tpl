{{/*
Expand the name of the chart.
*/}}
{{- define "capmox-talos.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "capmox-talos.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "capmox-talos.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Cluster name used by CAPI to associate owned objects (Machines,
MachineSets, infrastructure resources) with their parent Cluster.
Kept as a dedicated helper so this identity can evolve independently
of the release naming, while every reference stays in sync.
*/}}
{{- define "capmox-talos.clusterName" -}}
{{- include "capmox-talos.fullname" . }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "capmox-talos.labels" -}}
helm.sh/chart: {{ include "capmox-talos.chart" . }}
{{ include "capmox-talos.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "capmox-talos.selectorLabels" -}}
app.kubernetes.io/name: {{ include "capmox-talos.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}


{{- define "capmox-talos.proxmoxMachineTemplateSpec" -}}
templateID: {{ .templateID }}
numCores: {{ .cpu.cores | default 2}}
numSockets: {{ .cpu.sockets | default 1}}
sourceNode: {{ .pveNode | default "pve" }}
disks:
  bootVolume:
    disk: {{ .storage.bootDisk | default "scsi0" }}
    sizeGb: {{ .storage.bootDiskSize | default 20 }}
format: {{ .storage.format | default "qcow2" }}
full: {{ .storage.fullClone | default true }}
memoryMiB: {{ .memoryMiB | default 2048 }}
network:
  networkDevices:
  - bridge: {{ .network.bridge | default "vmbr0" }}
    model: virtio
    name: net0
    vlan: {{ .network.vlan }}
    defaultIPv4: {{ .network.defaultIPv4 | default true }}
vmIDRange:
  start: {{ .vmIDRange.start | default 1000 }} 
  end: {{ .vmIDRange.end | default 1099 }} 
checks:
  skipCloudInitStatus: true
metadataSettings:
  providerIDInjection: true
{{- end }}

{{- define "capmox-talos.controlPlaneMachineTemplateName" -}}
{{- $specYaml := include "capmox-talos.proxmoxMachineTemplateSpec" .Values.controlPlane.machine -}}
{{- $hash := $specYaml | sha256sum | trunc 8 -}}
{{- printf "%s-%s-%s" (include "capmox-talos.fullname" .) "control-plane" $hash -}}
{{- end }}


{{- define "capmox-talos.workerMachineTemplateName" -}}
{{- $specYaml := include "capmox-talos.proxmoxMachineTemplateSpec" .pool -}}
{{- $hash := $specYaml | sha256sum | trunc 8 -}}
{{- printf "%s-%s-%s" (include "capmox-talos.fullname" .root) .pool.name $hash -}}
{{- end }}

{{- define "capmox-talos.talosConfigTemplatePatches" -}}
{{- $labels := merge dict (.pool.nodeLabels | default dict) (.root.Values.workers.nodeLabels | default dict) -}}
machine:
  nodeLabels:
    {{- with $labels }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
  {{- with .pool.nodeTaints }}
  nodeTaints:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  sysctls:
    vm.nr_hugepages: "1024"
  kernel:
    modules:
      - name: nvme_tcp
      - name: vfio_pci
      - name: uio_pci_generic
  kubelet:
    extraArgs:
      cloud-provider: external
      rotate-server-certificates: "true"
    extraMounts:
      - destination: /var/mnt/longhorn
        type: bind
        source: /var/mnt/longhorn
        options:
          - bind
          - rshared
          - rw
  install:
    disk: /dev/sda
    extraKernelArgs:
      - net.ifnames=0
{{- end }}


{{- define "capmox-talos.talosConfigTemplateName" -}}
{{- $basePatch := include "capmox-talos.talosConfigTemplatePatches" . -}}
{{- $extraPatches := .root.Values.workers.extraPatches | default list | toYaml -}}
{{- $hash := printf "%s%s" $basePatch $extraPatches | sha256sum | trunc 8 -}}
{{- printf "%s-worker-config-%s" (include "capmox-talos.fullname" .root) $hash -}}
{{- end }}
