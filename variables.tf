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

variable "prune_undeclared_tags" {
  description = <<-EOT
    When true, delete any tags in the destination repository that are not declared
    in the 'tags' variable. This runs on every apply after all copies and additional
    tags are applied.

    "Undeclared" covers both tags previously managed by this module but since removed
    from 'tags', and tags added manually outside of the Terraform workflow.

    WARNING: This deletes any tag in the destination repository not declared in 'tags',
    including tags pushed by other tooling. Disable this if the destination repository
    is shared.
  EOT
  type        = bool
  default     = true
}

variable "destination_login_command" {
  description = <<-EOT
    Command to authenticate to the destination registry. If the destination repository is an ECR
    registry, the aws-cli ECR registry login command will be generated automatically, but setting
    this variable will override the generated command.

    Example: "echo 'mypassword' | crane auth login --username user --password-stdin myregistry.example.com"

    Be aware that this command will be run in a bash shell exactly as it is received. Trust the source that is configuring this variable value.
  EOT
  type        = string
  default     = ""
}
