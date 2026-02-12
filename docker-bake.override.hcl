variable "CACHE_FROM" {
  default = ""
}

variable "CACHE_TO" {
  default = ""
}

target "ci" {
  context = "."
  dockerfile = "Dockerfile"
  target = "ci"
  network = "host"
  contexts = {
    devserver = "../devserver"
  }
  secret = [
    "id=host.env,env=HOST_ENV",
  ]
  cache-from = CACHE_FROM != "" ? split(";", CACHE_FROM) : []
  cache-to = CACHE_TO != "" ? split(";", CACHE_TO) : []
}
