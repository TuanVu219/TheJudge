class_name NetworkConfig
extends RefCounted

## Centralized network configuration for THE JUDGE.
## Manages environment-based WebSocket server addresses (local development vs production web deployment).

## Default WebSocket address for local development (Godot editor / Desktop).
const LOCAL_SERVER_URL := "ws://127.0.0.1:8080"

## Production WebSocket server address (Web browser deployment).
## ==============================================================================
## >>> INSERT YOUR DEPLOYED RENDER WEBSOCKET URL HERE AFTER DEPLOYMENT <<<
## Example: "wss://thejudge-server.onrender.com"
## ==============================================================================
const PRODUCTION_SERVER_URL := "wss://thejudge.onrender.com"

## Placeholder marker used to detect unconfigured production deployment.
const PRODUCTION_PLACEHOLDER_SUBSTRING := "YOUR-RENDER-SERVICE"

## Setting override path in ProjectSettings for testing/runtime configuration.
const PROJECT_SETTING_PRODUCTION_URL := "network/config/production_server_url"


## Returns true if running in a Web export (HTML5 / WebAssembly browser).
static func is_web() -> bool:
	return OS.has_feature("web")


## Returns the configured production server URL (checks ProjectSettings override first).
static func get_production_server_url() -> String:
	if ProjectSettings.has_setting(PROJECT_SETTING_PRODUCTION_URL):
		var custom_url: String = str(ProjectSettings.get_setting(PROJECT_SETTING_PRODUCTION_URL)).strip_edges()
		if not custom_url.is_empty():
			return custom_url
	return PRODUCTION_SERVER_URL


## Returns true if a valid production Render URL has been configured.
static func is_production_configured() -> bool:
	var prod_url := get_production_server_url().strip_edges()
	if prod_url.is_empty():
		return false
	if prod_url.contains(PRODUCTION_PLACEHOLDER_SUBSTRING):
		return false
	return true


## Returns the environment-appropriate default server URL.
## Local dev: "ws://127.0.0.1:8080"
## Web build: configured production URL or placeholder
static func get_default_server_url(force_web: Variant = null) -> String:
	var check_web: bool = is_web() if force_web == null else bool(force_web)
	if check_web:
		return get_production_server_url()
	return LOCAL_SERVER_URL


## Normalizes user-entered URL (adds scheme if missing, adds default local port if needed).
static func normalize_server_url(raw_url: String, force_web: Variant = null) -> String:
	var check_web: bool = is_web() if force_web == null else bool(force_web)
	var clean := raw_url.strip_edges()
	if clean.is_empty():
		return get_default_server_url(check_web)

	# If the input already contains a scheme (e.g. http://, ftp://, ws://), don't prepend
	if not clean.contains("://"):
		if check_web:
			clean = "wss://" + clean
		else:
			clean = "ws://" + clean

	# If it's a bare local IP/hostname without port or path, append :8080 default
	var scheme_split := clean.split("://")
	if scheme_split.size() == 2:
		var host_part: String = scheme_split[1]
		if not host_part.contains(":") and not host_part.contains("/"):
			if host_part == "127.0.0.1" or host_part == "localhost" or host_part.begins_with("192.168."):
				clean = clean + ":8080"

	return clean


## Validates a server URL according to the target environment rules.
## Rejects empty URLs, unconfigured placeholders, invalid schemes, and insecure ws:// in web mode.
static func validate_server_url(url: String, force_web: Variant = null) -> Dictionary:
	var check_web: bool = is_web() if force_web == null else bool(force_web)
	var clean := url.strip_edges()

	if clean.is_empty():
		return {
			"valid": false,
			"error": "Server address cannot be empty.",
			"code": "EMPTY_URL"
		}

	if clean.contains(PRODUCTION_PLACEHOLDER_SUBSTRING):
		return {
			"valid": false,
			"error": "Production server URL has not been configured yet. Please configure the Render service URL.",
			"code": "UNCONFIGURED_PRODUCTION"
		}

	if not clean.begins_with("ws://") and not clean.begins_with("wss://"):
		return {
			"valid": false,
			"error": "Server address must begin with ws:// or wss://",
			"code": "INVALID_SCHEME"
		}

	var host_part := clean.substr(clean.find("://") + 3).strip_edges()
	if host_part.is_empty() or host_part.begins_with(":") or host_part.begins_with("/"):
		return {
			"valid": false,
			"error": "Server address must include a valid host or IP address.",
			"code": "MISSING_HOST"
		}

	if check_web and clean.begins_with("ws://"):
		return {
			"valid": false,
			"error": "Browser games require secure WebSocket (wss://). Insecure ws:// is blocked on HTTPS.",
			"code": "INSECURE_BROWSER_SCHEME"
		}

	return {
		"valid": true,
		"error": "",
		"code": "OK",
		"url": clean
	}
