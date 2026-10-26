{{/*
_helpers.tpl: named templates used by every file in templates/.
Files starting with _ never produce Kubernetes objects.
*/}}

{{/* tasktracker.name: the chart name, or nameOverride. */}}
{{- define "tasktracker.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
tasktracker.fullname: base name for every object.
If the release name already contains the chart name (tasktracker-dev),
the release name is used alone, so names do not become tasktracker-dev-tasktracker.
*/}}
{{- define "tasktracker.fullname" -}}
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

{{- define "tasktracker.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/* tasktracker.environment: required, so nothing renders without it. */}}
{{- define "tasktracker.environment" -}}
{{- required "environment must be set (dev or prod)" .Values.environment }}
{{- end }}

{{/*
Selector labels. These must never change after the first install because
Deployment.spec.selector is immutable. Each tier adds "tier: <name>" next to them.
*/}}
{{- define "tasktracker.selectorLabels" -}}
app.kubernetes.io/name: {{ include "tasktracker.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/* Full label set for every object. Same "app: task-tracker" label as A1. */}}
{{- define "tasktracker.labels" -}}
helm.sh/chart: {{ include "tasktracker.chart" . }}
{{ include "tasktracker.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: task-tracker
app.kubernetes.io/environment: {{ include "tasktracker.environment" . | quote }}
app: task-tracker
{{- end }}

{{/* Object names for each tier. A1 used db-svc / backend-svc; here they follow the release. */}}
{{- define "tasktracker.dbName" -}}
{{- printf "%s-db" (include "tasktracker.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- define "tasktracker.backendName" -}}
{{- printf "%s-backend" (include "tasktracker.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- define "tasktracker.frontendName" -}}
{{- printf "%s-frontend" (include "tasktracker.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- define "tasktracker.configName" -}}
{{- printf "%s-config" (include "tasktracker.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/* Secret name: an existing Secret if given, otherwise the one this chart creates. */}}
{{- define "tasktracker.secretName" -}}
{{- if .Values.credentials.existingSecret }}
{{- .Values.credentials.existingSecret }}
{{- else }}
{{- printf "%s-db-credentials" (include "tasktracker.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}

{{/* Image reference for a tier: "repo:tag", tag falls back to appVersion. */}}
{{- define "tasktracker.image" -}}
{{- $img := index .root.Values.images .tier }}
{{- printf "%s:%s" $img.repository ($img.tag | default .root.Chart.AppVersion) }}
{{- end }}
