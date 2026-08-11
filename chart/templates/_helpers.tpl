{{/*
Expand the name of the chart.
*/}}
{{- define "opencode.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "opencode.fullname" -}}
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
Chart name and version.
*/}}
{{- define "opencode.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels.
*/}}
{{- define "opencode.labels" -}}
helm.sh/chart: {{ include "opencode.chart" . }}
{{ include "opencode.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels.
*/}}
{{- define "opencode.selectorLabels" -}}
app.kubernetes.io/name: {{ include "opencode.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
ServiceAccount name.
*/}}
{{- define "opencode.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "opencode.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Container image reference.
*/}}
{{- define "opencode.image" -}}
{{- printf "%s:%s" .Values.image.repository .Values.image.tag }}
{{- end }}

{{/*
Default pod anti-affinity (soft): prefer spreading replicas across nodes.
*/}}
{{- define "opencode.podAntiAffinity" -}}
preferredDuringSchedulingIgnoredDuringExecution:
  - weight: 100
    podAffinityTerm:
      topologyKey: kubernetes.io/hostname
      labelSelector:
        matchLabels:
          {{- include "opencode.selectorLabels" . | nindent 10 }}
{{- end }}

{{/*
ConfigMap name.
*/}}
{{- define "opencode.configName" -}}
{{- printf "%s-config" (include "opencode.fullname" .) }}
{{- end }}

{{/*
Secret name: user-provided, basic-auth secret, or generated.
*/}}
{{- define "opencode.secretName" -}}
{{- if .Values.auth.existingSecret }}
{{- .Values.auth.existingSecret }}
{{- else }}
{{- printf "%s-secret" (include "opencode.fullname" .) }}
{{- end }}
{{- end }}

{{/*
PVC name.
*/}}
{{- define "opencode.pvcName" -}}
{{- if .Values.persistence.existingClaim }}
{{- .Values.persistence.existingClaim }}
{{- else }}
{{- printf "%s-pvc" (include "opencode.fullname" .) }}
{{- end }}
{{- end }}
