{{/*
Expand the name of the chart.
*/}}
{{- define "application.name" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "application.fullname" -}}
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
{{- define "application.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "application.labels" -}}
helm.sh/chart: {{ include "application.chart" . }}
{{ include "application.selectorLabels" . }}
{{- if .Chart.AppVersion }}
{{- if .Values.appVersion}}
app.kubernetes.io/version: {{ .Values.appVersion | quote }}
{{- end }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "application.selectorLabels" -}}
app.kubernetes.io/name: {{ include "application.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "application.serviceAccountName" -}}
{{- if .Values.serviceAccount.enabled }}
{{- default (include "application.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Create the name of the config map
*/}}
{{- define "application.configMapName" -}}
{{- if .Values.configmap.name }}
{{- .Values.configmap.name }}
{{- else }}
{{-  printf "%s-config" (include "application.fullname" .) }}
{{- end }}
{{- end }}

{{/*
Renders a value that contains template.
Usage:
{{ include "tplvalues.render" ( dict "value" .Values.path.to.the.Value "context" $) }}
*/}}
{{- define "tplvalues.render" -}}
	{{- if typeIs "string" .value }}
		{{- tpl .value .context }}
	{{- else }}
		{{- tpl (.value | toYaml) .context }}
	{{- end }}
{{- end -}}%

{{- define "application.serviceaccountAnnotations" }}
{{ include "tplvalues.render" ( dict "value" .Values.serviceAccount.annotations "context" $) }}
{{- end }}


{{/*
Define a timestamp generator helper
*/}}
{{- define "add.timestamp" -}}
{{ now | date "20060102150405" }}
{{- end }}

{{/*
Define default image repository
*/}}
{{- define "image.repository" -}}
{{- default .Values.image.repository -}}
{{- end -}}

{{/*
Helper function to render probes. This handles either exec or httpGet probes.
*/}}
{{- define "renderProbe" -}}
{{- $probe := . -}}
{{- if eq $probe.type "http"  }}
httpGet:
{{ toYaml $probe.httpGet | indent 2 }}
{{- else if eq $probe.type "exec" }}
exec:
{{ toYaml $probe.exec | indent 2 }}
{{- else if eq $probe.type "grpc" }}
grpc:
{{ toYaml $probe.grpc | indent 2 }}
{{- end }}
failureThreshold: {{ $probe.failureThreshold }}
initialDelaySeconds: {{ $probe.initialDelaySeconds }}
periodSeconds: {{ $probe.periodSeconds }}
successThreshold: {{ $probe.successThreshold }}
timeoutSeconds: {{ $probe.timeoutSeconds }}
{{- end }}

{{/*
Helper function to check which prometheusAnnotations to use - defaults or custom
if prometheusAnnotations exists as empty map - should not add them
*/}}
{{- define "shouldUsePrometheusAnnotations" -}}
{{- if hasKey .Values "prometheusAnnotations" -}}
	{{- if not (empty .Values.prometheusAnnotations) -}}
	true
	{{- else -}}
	false
	{{- end -}}
{{- else -}}
	true
{{- end -}}
{{- end -}}
