variable "CACHE_SCOPE" {
  default = ""
}

target "ci" {
  context = "."
  dockerfile = "Dockerfile"
  target = "ci"
  network = "host"
  secret = [
    "id=host.env,env=HOST_ENV",
  ]
  cache-from = CACHE_SCOPE != "" ? [
    "type=gha,version=2,scope=main",
    "type=gha,version=2,scope=${CACHE_SCOPE}-plugins-sayt-ci",
  ] : []
  cache-to = CACHE_SCOPE != "" ? [
    "type=gha,version=2,mode=max,scope=${CACHE_SCOPE}-plugins-sayt-ci,ignore-error=true"
  ] : []
}

# GHA cache for inner compose targets (run inside CI via docker-bridge.sh).
# Unconditional because they only execute within a Dockerfile RUN step
# where ACTIONS_RESULTS_URL is always available via host.env.
target "inner-cache" {
  matrix = {
    svc = [
      "release-build", "release-server", "integrate-it",
      "test-alpine", "test-curlimages", "test-wolfi", "test-wolfi-nonroot",
      "test-ubuntu", "test-ubuntu-nonroot", "test-powershell", "integrate",
    ]
  }
  name       = svc
  cache-from = ["type=gha,version=2,scope=sayt-${svc}"]
  cache-to   = ["type=gha,version=2,mode=max,scope=sayt-${svc},ignore-error=true"]
}
