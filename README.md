# Canyon / NextChat / Humanitec

This is a lightly-reskinned version of NextChat. It downloads and runs the latest humctl and canyon-cli when the container starts.

It takes as environment variables a HUMANITEC_TOKEN, a GOOGLE_API_KEY, ENABLE_MCP (set this to "TRUE" otherwise the MCP server won't start) a DEFAULT_MODEL (works with "gemini-2.5-pro-preview-03-25"), and a GCP_SERVICE_ACCOUNT_KEY_JSON (a service account key as JSON, to authenticate the Canyon CLI to interact with the Humanitec bucket the HTML renders live in. This is probably not ideal).

Also running on GCP.
