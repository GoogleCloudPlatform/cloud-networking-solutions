{{/*
  prettify the yaml snippet with correct indentation depending on empty vs
  non-empty value to generate the valid yaml content
      @param e - current object
      @param n - nindent value
*/}}
{{- define "prettifyToYaml" -}}
{{- if .e -}}
{{- toYaml .e  | nindent .n -}}
{{- else -}}
{{- toYaml .e -}}
{{- end -}}
{{- end -}}

{{/*
  tryFileContent.get returns file content otherwise error if file is empty or unreachable
    @param files - .Files object
    @param f - string filepath
*/}}
{{- define "tryFileContent.get" -}}
{{- $tr := (trimPrefix "./" .f) -}}
{{- $c := .files.Get $tr -}}
{{- if empty $c -}}
{{- fail (printf "'%s' is either an empty file or unreachable" $tr) -}}
{{- else -}}
{{- $c -}}
{{- end -}}
{{- end -}}
