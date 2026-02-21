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
    "type=gha,scope=main",
    "type=gha,scope=${CACHE_SCOPE}-plugins-sayt-ci",
  ] : []
  cache-to = CACHE_SCOPE != "" ? [
    "type=gha,mode=max,scope=${CACHE_SCOPE}-plugins-sayt-ci"
  ] : []
}

# GHA cache for inner compose targets (run inside CI via dind.sh).
# Unconditional because they only execute within a Dockerfile RUN step
# where ACTIONS_CACHE_URL is always available via host.env.
target "inner-cache" {
  matrix = {
    svc = [
      "release-build", "release-server", "integrate-it",
      "test-alpine", "test-curlimages", "test-wolfi", "test-wolfi-nonroot",
      "test-ubuntu", "test-ubuntu-nonroot", "test-powershell", "integrate",
    ]
  }
  name       = svc
  cache-from = ["type=gha,scope=sayt-${svc}"]
  cache-to   = ["type=gha,mode=max,scope=sayt-${svc}"]
}
