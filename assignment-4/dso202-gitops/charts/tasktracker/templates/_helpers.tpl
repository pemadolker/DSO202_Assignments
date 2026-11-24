{{/*
=============================================================================
File        : charts/tasktracker/templates/_helpers.tpl
Assignment  : DSO202 Assignment 4
Descriptor  : Unit III 3.2 - Helm named templates
Purpose     : Named templates used by every file in templates/. Files that
              start with _ never produce Kubernetes objects. Kept from
              Assignment 3; the Secret helper now only reads existingSecret
              and the image helper no longer falls back to appVersion.
=============================================================================
*/}}

{{/* tasktracker.name: the chart name, or nameOverride. */}}
{{- define "tasktracker.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
tasktracker.fullname: base name for every object.
Argo CD uses the fixed release name "tasktracker" in both environments, and
the release name already contains the chart name, so every object is called
tasktracker-<tier>. The namespace is what tells dev and staging apart.
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

{{/*
Selector labels. These must never change after the first sync because
Deployment and StatefulSet selectors are immutable. Each tier adds
"tier: <name>" next to them.
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
{{- with .Values.environment }}
dso202/environment: {{ . | quote }}
{{- end }}
app: task-tracker
{{- end }}

{{/* Object names for each tier. */}}
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

{{/*
Requirement C3: the name of the Secret the Pods read. There is no fallback,
because the chart never renders a Secret of its own.
*/}}
{{- define "tasktracker.secretName" -}}
{{- required "credentials.existingSecret must be set (C3: the chart does not create Secrets)" .Values.credentials.existingSecret }}
{{- end }}

{{/*
Requirement C1: image reference for a tier, "repository:tag". Both parts
come from values; no tag is written here and there is no default.
*/}}
{{- define "tasktracker.image" -}}
{{- $img := index .root.Values.images .tier }}
{{- $tag := required (printf "images.%s.tag must be set in the environment values file" .tier) $img.tag }}
{{- printf "%s:%s" $img.repository $tag }}
{{- end }}

{{/*
Requirement C2: renders an env map from values as plain env entries.
range over a map is sorted by key, so the output order never changes and
Argo CD does not see a false difference.
*/}}
{{- define "tasktracker.extraEnv" -}}
{{- range $name, $value := . }}
- name: {{ $name }}
  value: {{ $value | quote }}
{{- end }}
{{- end }}
