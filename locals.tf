locals {
  # Source registry host (everything before the first /)
  source_registry = split("/", var.source_repository)[0]

  # Detect if source is an ECR registry
  source_is_ecr = can(regex("^[0-9]+\\.dkr\\.ecr\\.[a-z0-9-]+\\.(amazonaws\\.com|amazonaws\\.com\\.cn)$", local.source_registry))

  # Extract AWS region from ECR registry URI when applicable
  source_ecr_region = local.source_is_ecr ? regex("dkr\\.ecr\\.([a-z0-9-]+)\\.", local.source_registry)[0] : ""

  # Generate ECR login command for convenience so user does not need to provide it
  source_ecr_login_command = "aws ecr get-login-password --region \"${local.source_ecr_region}\" | crane auth login --username AWS --password-stdin \"${local.source_registry}\""

  # Destination registry host (everything before the first /)
  dest_registry = split("/", var.destination_repository)[0]

  # Detect if destination is an ECR registry
  dest_is_ecr = can(regex("^[0-9]+\\.dkr\\.ecr\\.[a-z0-9-]+\\.(amazonaws\\.com|amazonaws\\.com\\.cn)$", local.dest_registry))

  # Extract AWS region from ECR registry URI when applicable
  dest_ecr_region = local.dest_is_ecr ? regex("dkr\\.ecr\\.([a-z0-9-]+)\\.", local.dest_registry)[0] : ""

  # Generate ECR login command for convenience so user does not need to provide it
  dest_ecr_login_command = "aws ecr get-login-password --region \"${local.dest_ecr_region}\" | crane auth login --username AWS --password-stdin \"${local.dest_registry}\""

  # Copy operations run once per source tag: source -> destination with the same tag.
  copy_operations = [
    for source_tag, _ in var.tags : {
      source_tag = source_tag
      source_ref = "${var.source_repository}:${source_tag}"
      dest_ref   = "${var.destination_repository}:${source_tag}"
      key        = source_tag
    }
  ]

  # Additional destination tags are applied after the copy via remote tagging.
  tag_operations = flatten([
    for source_tag, extra_tags in var.tags : [
      for dest_tag in distinct(extra_tags) : {
        source_tag      = source_tag
        source_dest_ref = "${var.destination_repository}:${source_tag}"
        dest_ref        = "${var.destination_repository}:${dest_tag}"
        dest_tag        = dest_tag
        key             = "${source_tag}:${dest_tag}"
      } if dest_tag != source_tag
    ]
  ])

  copy_operations_map = { for op in local.copy_operations : op.key => op }
  tag_operations_map  = { for op in local.tag_operations : op.key => op }

  # Complete set of destination tags this configuration manages. Every source tag is
  # copied under the same tag, plus any additional destination tags. Any tag present in
  # the destination repo but absent from this list is considered undeclared and removed.
  expected_dest_tags = distinct(flatten([
    for source_tag, extra_tags in var.tags : concat([source_tag], extra_tags)
  ]))

  source_login_command = var.source_login_command != "" ? var.source_login_command : local.source_is_ecr ? local.source_ecr_login_command : ""

  destination_login_command = var.destination_login_command != "" ? var.destination_login_command : local.dest_is_ecr ? local.dest_ecr_login_command : ""

  # Login script for the source registry, reused by the check and copy steps.
  # Priority: source_login_command (if provided) > auto ECR login > anonymous (no-op)
  # Sources are frequently public, so when no login command is available we skip login and
  # let crane access the source anonymously rather than failing.
  # All output is redirected to stderr to keep stdout clean for data.external JSON.
  source_login_script = <<-EOT
    %{if local.source_login_command != ""}
    # Only log in to source registry if not already authenticated
    if ! crane auth get '${local.source_registry}' >/dev/null 2>&1; then
      echo "Logging in to ${local.source_registry}..." >&2
      ${local.source_login_command} >&2
    fi
    %{else}
    # No source_login_command provided; crane will access the source anonymously.
    :
    %{endif}
  EOT

  # Login script reused by both the check and copy steps.
  # Priority: destination_login_command (if provided) > auto ECR login > no-op
  # All output is redirected to stderr to keep stdout clean for data.external JSON.
  dest_login_script = <<-EOT
    # Only log in to destination registry if not already authenticated
    if ! crane auth get '${local.dest_registry}' >/dev/null 2>&1; then
      echo "Logging in to ${local.dest_registry}..." >&2
      %{if local.destination_login_command != ""}
      ${local.destination_login_command} >&2
      %{else}
      echo "ERROR: Not authenticated to '${local.dest_registry}' and no destination_login_command provided" >&2
      exit 1
      %{endif}
    fi
  EOT
}
