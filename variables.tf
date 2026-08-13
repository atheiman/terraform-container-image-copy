variable "source_repository" {
  description = "Full source image repository reference without tag (e.g., 'docker.io/library/alpine', 'ghcr.io/org/image', 'quay.io/repo/image')"
  type        = string
}

variable "destination_repository" {
  description = "Full destination repository URI (e.g., '111111111111.dkr.ecr.us-east-1.amazonaws.com/docker.io/alpine', 'myregistry.example.com/alpine')"
  type        = string
}

variable "tags" {
  description = <<-EOT
    Map of source tags to copy. Each key is the source tag to pull, and the value
    is a list of destination tags to push. Use an empty list to push with the same
    tag as the source.

    Example:
      {
        "3.22" = []          # pushes as 3.22
        "3.23" = ["latest"]  # pushes as 3.23 AND latest
      }
  EOT
  type        = map(list(string))
}

variable "destination_login_command" {
  description = <<-EOT
    Command to authenticate to the destination registry. Only used when the
    destination is NOT an ECR registry (ECR login is handled automatically).
    The command should authenticate crane to the destination registry.

    Example: "echo 'mypassword' | crane auth login --username user --password-stdin myregistry.example.com"
  EOT
  type        = string
  default     = ""
}
