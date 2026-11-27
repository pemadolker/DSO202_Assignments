{{- /*
=============================================================================
File        : charts/tasktracker/templates/_helpers.tpl
Assignment  : DSO202 Assignment 4
Descriptor  : Unit III 3.2 - Helm named templates
Purpose     : Names, labels and image references shared by every template.
              Files starting with "_" never produce Kubernetes objects.
=============================================================================
*/ -}}

{{/* Chart name, or nameOverride. */}}
{{- define "tasktracker.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Base name for every object. Argo CD uses the fixed release name "tasktracker"
(Listings 14 and 15), which already contains the chart name, so objects are
called tasktracker-db, tasktracker-backend, ... in both namespaces.
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
Selector labels. Never changed after the first sync, because
Deployment/StatefulSet spec.selector is immutable. Each tier adds "tier".
*/}}
{{- define "tasktracker.selectorLabels" -}}
app.kubernetes.io/name: {{ include "tasktracker.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Full label set. No version label: the image tag differs per tier and per
environment, so one chart-wide version label would be misleading.
*/}}
{{- define "tasktracker.labels" -}}
helm.sh/chart: {{ include "tasktracker.chart" . }}
{{ include "tasktracker.selectorLabels" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: task-tracker
app: task-tracker
{{- end }}

{{/* Object names per tier. */}}
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
C3: name of the credentials Secret. There is no fallback and no Secret
template: if the environment file does not name a Secret, rendering fails.
*/}}
{{- define "tasktracker.secretName" -}}
{{- required "credentials.existingSecret must name the Secret created from the SealedSecret" .Values.credentials.existingSecret }}
{{- end }}

{{/*
C1: "repository:tag" for a tier. Both come from values; the tag has no
default (not even appVersion), so a release is always an explicit values change.
Usage: include "tasktracker.image" (dict "root" . "tier" "backend")
*/}}
{{- define "tasktracker.image" -}}
{{- $img := index .root.Values.images .tier }}
{{- $repo := required (printf "images.%s.repository is required" .tier) $img.repository }}
{{- $tag := required (printf "images.%s.tag is required (set it in environments/<env>/values.yaml)" .tier) $img.tag }}
{{- printf "%s:%s" $repo (toString $tag) }}
{{- end }}

{{/*
C2: render a map of extra variables as plain env entries, sorted by name so
the output is the same on every render. Usage: include "tasktracker.extraEnv" .Values.backend.env
*/}}
{{- define "tasktracker.extraEnv" -}}
{{- range $name, $value := . }}
- name: {{ $name }}
  value: {{ $value | toString | quote }}
{{- end }}
{{- end }}
