{{/*
Expand the name of the chart.
*/}}
{{- define "proxmox-talos-cluster.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
If release name contains chart name it will be used as a full name.
*/}}
{{- define "proxmox-talos-cluster.fullname" -}}
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
{{- define "proxmox-talos-cluster.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "proxmox-talos-cluster.labels" -}}
helm.sh/chart: {{ include "proxmox-talos-cluster.chart" . }}
{{ include "proxmox-talos-cluster.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
cluster.x-k8s.io/cluster-name: {{ include "proxmox-talos-cluster.clusterName" . }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "proxmox-talos-cluster.selectorLabels" -}}
app.kubernetes.io/name: {{ include "proxmox-talos-cluster.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Cluster name. Every CAPI object is named after it, so it is decoupled from
the release naming: set cluster.name to keep it stable across renames.
*/}}
{{- define "proxmox-talos-cluster.clusterName" -}}
{{- default (include "proxmox-talos-cluster.fullname" .) .Values.cluster.name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
ProxmoxMachineTemplate spec for a machine shape.
Takes (dict "root" $ "machine" $machine "what" "controlPlane.machine").
*/}}
{{- define "proxmox-talos-cluster.machineSpec" -}}
{{- $m := .machine -}}
{{- if and (not $m.templateID) (not $m.templateSelector) }}
{{- fail (printf "%s: set templateID or templateSelector" .what) }}
{{- end }}
{{- if and $m.templateID $m.templateSelector }}
{{- fail (printf "%s: templateID and templateSelector are mutually exclusive" .what) }}
{{- end }}
{{- with $m.templateID }}
templateID: {{ . }}
{{- end }}
{{- with $m.templateSelector }}
templateSelector:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with $m.sourceNode }}
sourceNode: {{ . }}
{{- end }}
{{- with $m.allowedNodes }}
allowedNodes:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with $m.storage }}
storage: {{ . }}
{{- end }}
{{- with $m.pool }}
pool: {{ . }}
{{- end }}
{{- with $m.tags }}
tags:
  {{- toYaml . | nindent 2 }}
{{- end }}
numCores: {{ $m.cpu.cores }}
numSockets: {{ $m.cpu.sockets }}
memoryMiB: {{ $m.memoryMiB }}
disks:
  bootVolume:
    disk: {{ $m.disk.device }}
    sizeGb: {{ $m.disk.sizeGb }}
full: {{ $m.clone.full }}
{{- if and $m.clone.full $m.clone.format }}
format: {{ $m.clone.format }}
{{- end }}
network:
  networkDevices:
    - name: net0
      bridge: {{ $m.network.bridge }}
      model: {{ $m.network.model }}
      {{- with $m.network.vlan }}
      vlan: {{ . }}
      {{- end }}
      {{- with $m.network.mtu }}
      mtu: {{ . }}
      {{- end }}
      defaultIPv4: true
      {{- if .root.Values.proxmox.ipv6Pool }}
      defaultIPv6: true
      {{- end }}
    {{- with $m.network.additionalDevices }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
{{- if and $m.vmIDRange.start $m.vmIDRange.end }}
vmIDRange:
  start: {{ $m.vmIDRange.start }}
  end: {{ $m.vmIDRange.end }}
{{- end }}
# Talos does not run cloud-init; the provider ID is injected through metadata
checks:
  skipCloudInitStatus: true
  skipQemuGuestAgent: {{ $m.checks.skipQemuGuestAgent }}
metadataSettings:
  providerIDInjection: true
{{- end }}

{{/*
Talos config fields shared by the control plane and worker configs.
*/}}
{{- define "proxmox-talos-cluster.talosConfigCommon" -}}
{{- with .Values.talos.version }}
talosVersion: {{ . }}
{{- end }}
{{- with .Values.talos.hostnameSource }}
hostname:
  source: {{ . }}
{{- end }}
{{- end }}

{{/*
Control plane ProxmoxMachineTemplate name. Templates are immutable in CAPI,
so the name carries a hash of the spec and changes roll the machines.
*/}}
{{- define "proxmox-talos-cluster.controlPlaneMachineSpec" -}}
{{- include "proxmox-talos-cluster.machineSpec" (dict "root" . "machine" .Values.controlPlane.machine "what" "controlPlane.machine") }}
{{- end }}

{{- define "proxmox-talos-cluster.controlPlaneMachineTemplateName" -}}
{{- $hash := include "proxmox-talos-cluster.controlPlaneMachineSpec" . | sha256sum | trunc 8 -}}
{{- printf "%s-control-plane-%s" (include "proxmox-talos-cluster.clusterName" .) $hash -}}
{{- end }}

{{/*
Deep merge of two maps, returned as YAML (use `| fromYaml`): keys present in
.dst win, nested maps are merged, lists are replaced.

Sprig's merge/mergeOverwrite treat false, 0 and "" as unset and would replace
them, so overrides like `clone.full: false` need this key-based merge.
*/}}
{{- define "proxmox-talos-cluster.deepMerge" -}}
{{- $out := deepCopy .dst -}}
{{- range $k, $v := .src }}
{{- if not (hasKey $out $k) }}
{{- $_ := set $out $k $v }}
{{- else if and (kindIs "map" $v) (kindIs "map" (get $out $k)) }}
{{- $_ := set $out $k (include "proxmox-talos-cluster.deepMerge" (dict "dst" (get $out $k) "src" $v) | fromYaml) }}
{{- end }}
{{- end }}
{{- toYaml $out }}
{{- end }}

{{/*
Resolved worker pool: the pool entry deep-merged over workers.defaults.
Takes (dict "root" $ "pool" $rawPool) and returns YAML (use `| fromYaml`).
*/}}
{{- define "proxmox-talos-cluster.workerPool" -}}
{{- $_ := required "workers.pools[].name is required" .pool.name -}}
{{- include "proxmox-talos-cluster.deepMerge" (dict "dst" .pool "src" .root.Values.workers.defaults) -}}
{{- end }}

{{/*
The helpers below take (dict "root" $ "pool" $resolvedPool).
*/}}
{{- define "proxmox-talos-cluster.workerDeploymentName" -}}
{{- printf "%s-%s" (include "proxmox-talos-cluster.clusterName" .root) .pool.name | trunc 63 | trimSuffix "-" -}}
{{- end }}

{{- define "proxmox-talos-cluster.workerMachineSpec" -}}
{{- include "proxmox-talos-cluster.machineSpec" (dict "root" .root "machine" .pool.machine "what" (printf "workers.pools[%s].machine" .pool.name)) }}
{{- end }}

{{- define "proxmox-talos-cluster.workerMachineTemplateName" -}}
{{- $hash := include "proxmox-talos-cluster.workerMachineSpec" . | sha256sum | trunc 8 -}}
{{- printf "%s-%s" (include "proxmox-talos-cluster.workerDeploymentName" .) $hash -}}
{{- end }}

{{/*
Talos strategic patch for a worker pool.
*/}}
{{- define "proxmox-talos-cluster.workerTalosPatch" -}}
{{- $workers := .root.Values.workers -}}
{{- $talos := .root.Values.talos -}}
machine:
  {{- with .pool.nodeLabels }}
  nodeLabels:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with .pool.nodeTaints }}
  nodeTaints:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with $workers.sysctls }}
  sysctls:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with $workers.kernelModules }}
  kernel:
    modules:
      {{- toYaml . | nindent 6 }}
  {{- end }}
  {{- if or $talos.kubelet.extraArgs $workers.kubeletExtraMounts }}
  kubelet:
    {{- with $talos.kubelet.extraArgs }}
    extraArgs:
      {{- toYaml . | nindent 6 }}
    {{- end }}
    {{- with $workers.kubeletExtraMounts }}
    extraMounts:
      {{- toYaml . | nindent 6 }}
    {{- end }}
  {{- end }}
  {{- with $talos.timeServers }}
  time:
    servers:
      {{- toYaml . | nindent 6 }}
  {{- end }}
  install:
    disk: {{ $talos.install.disk }}
    {{- with $talos.install.extraKernelArgs }}
    extraKernelArgs:
      {{- toYaml . | nindent 6 }}
    {{- end }}
{{- end }}

{{- define "proxmox-talos-cluster.workerTalosConfigTemplateName" -}}
{{- $patch := include "proxmox-talos-cluster.workerTalosPatch" . -}}
{{- $common := include "proxmox-talos-cluster.talosConfigCommon" .root -}}
{{- $extra := .root.Values.workers.extraPatches | default list | toYaml -}}
{{- $hash := printf "%s%s%s" $patch $common $extra | sha256sum | trunc 8 -}}
{{- printf "%s-%s" (include "proxmox-talos-cluster.workerDeploymentName" .) $hash -}}
{{- end }}

{{/*
Talos strategic patch for control plane nodes.
*/}}
{{- define "proxmox-talos-cluster.controlPlaneTalosPatch" -}}
{{- $cp := .Values.controlPlane -}}
{{- $talos := .Values.talos -}}
{{- $apiServerArgs := dict -}}
{{- if $cp.oidc.enabled }}
{{- $_ := set $apiServerArgs "oidc-issuer-url" (required "controlPlane.oidc.issuerURL is required when OIDC is enabled" $cp.oidc.issuerURL) }}
{{- $_ := set $apiServerArgs "oidc-client-id" (required "controlPlane.oidc.clientID is required when OIDC is enabled" $cp.oidc.clientID) }}
{{- $_ := set $apiServerArgs "oidc-username-claim" $cp.oidc.usernameClaim }}
{{- $_ := set $apiServerArgs "oidc-username-prefix" $cp.oidc.usernamePrefix }}
{{- $_ := set $apiServerArgs "oidc-groups-claim" $cp.oidc.groupsClaim }}
{{- $_ := set $apiServerArgs "oidc-groups-prefix" $cp.oidc.groupsPrefix }}
{{- end }}
{{- $apiServerArgs = mergeOverwrite $apiServerArgs ($cp.apiServer.extraArgs | default dict) -}}
machine:
  {{- with $talos.kubelet.extraArgs }}
  kubelet:
    extraArgs:
      {{- toYaml . | nindent 6 }}
  {{- end }}
  {{- with $talos.timeServers }}
  time:
    servers:
      {{- toYaml . | nindent 6 }}
  {{- end }}
  {{- if $cp.talosAPIAccess.enabled }}
  features:
    kubernetesTalosAPIAccess:
      enabled: true
      allowedRoles:
        {{- toYaml $cp.talosAPIAccess.allowedRoles | nindent 8 }}
      allowedKubernetesNamespaces:
        {{- toYaml $cp.talosAPIAccess.allowedKubernetesNamespaces | nindent 8 }}
  {{- end }}
  install:
    disk: {{ $talos.install.disk }}
    {{- with concat ($talos.install.extraKernelArgs | default list) ($cp.extraKernelArgs | default list) }}
    extraKernelArgs:
      {{- toYaml . | nindent 6 }}
    {{- end }}
  {{- if $cp.vip.enabled }}
  network:
    interfaces:
      {{- if $cp.vip.interface }}
      - interface: {{ $cp.vip.interface }}
      {{- else }}
      - deviceSelector:
          physical: true
      {{- end }}
        dhcp: false
        vip:
          ip: {{ .Values.cluster.controlPlaneEndpoint.host }}
  {{- end }}
cluster:
  proxy:
    disabled: {{ not .Values.cluster.kubeProxy.enabled }}
  network:
    cni:
      name: {{ .Values.cluster.cni.name }}
  {{- with $apiServerArgs }}
  apiServer:
    extraArgs:
      {{- toYaml . | nindent 6 }}
  {{- end }}
{{- end }}
