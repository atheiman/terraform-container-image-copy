terraform {
  required_version = ">= 1.0"
}

# Check each destination tag and return explicit digest metadata.
data "external" "check_destination" {
  for_each = local.copy_operations_map

  program = ["bash", "-c", <<-EOT
    ${local.source_login_script}
    ${local.dest_login_script}

    source_digest="$(crane digest "${each.value.source_ref}" 2>/dev/null || true)"
    dest_digest="$(crane digest "${each.value.dest_ref}" 2>/dev/null || true)"
    echo "{\"src_digest\":\"$source_digest\",\"dest_digest\":\"$dest_digest\"}"
  EOT
  ]
}

# Check each additional destination tag and return explicit digest metadata.
data "external" "check_additional_tag_destination" {
  for_each = local.tag_operations_map

  program = ["bash", "-c", <<-EOT
    ${local.dest_login_script}

    source_digest="$(crane digest "${each.value.source_dest_ref}" 2>/dev/null || true)"
    dest_digest="$(crane digest "${each.value.dest_ref}" 2>/dev/null || true)"
    echo "{\"src_digest\":\"$source_digest\",\"dest_digest\":\"$dest_digest\"}"
  EOT
  ]
}

# Copy images to the destination when missing.
resource "terraform_data" "copy" {
  for_each = local.copy_operations_map

  # After image copy this value will change from "false" to "true", triggering the provisioner to
  # run again on the second plan. The provisioner script handles this and only uploads if
  # data.external.check_destination reported the destination image doesn't exist. There is no way in
  # terraform to say "only replace this "
  triggers_replace = jsonencode({
    src_digest  = trimspace(data.external.check_destination[each.key].result.src_digest)
    dest_digest = trimspace(data.external.check_destination[each.key].result.dest_digest)
  })

  provisioner "local-exec" {
    interpreter = ["bash", "-euo", "pipefail", "-c"]
    environment = {
      SRC_DIGEST  = trimspace(data.external.check_destination[each.key].result.src_digest)
      DEST_DIGEST = trimspace(data.external.check_destination[each.key].result.dest_digest)
      SOURCE_REF  = each.value.source_ref
      DEST_REF    = each.value.dest_ref
    }
    command = <<-EOT
      # Skip only when destination already points to the same digest as source.
      if [ -n "$${DEST_DIGEST}" ] && [ "$${SRC_DIGEST}" = "$${DEST_DIGEST}" ]; then
        echo "Skipping copy operation, already exists and matches source digest: '$${DEST_REF}' (digest '$${DEST_DIGEST}')"
        exit 0
      fi

      ${local.source_login_script}
      ${local.dest_login_script}

      echo "Copying '$${SOURCE_REF}' -> '$${DEST_REF}'"
      crane copy "$${SOURCE_REF}" "$${DEST_REF}"
    EOT
  }
}

# Apply additional tags after the source-tag copy exists in destination.
resource "terraform_data" "tag" {
  for_each = local.tag_operations_map

  # Do not apply additional tags until copies into the destination have been completed.
  depends_on = [terraform_data.copy]

  triggers_replace = jsonencode({
    src_digest  = trimspace(data.external.check_additional_tag_destination[each.key].result.src_digest)
    dest_digest = trimspace(data.external.check_additional_tag_destination[each.key].result.dest_digest)
  })

  provisioner "local-exec" {
    interpreter = ["bash", "-euo", "pipefail", "-c"]
    environment = {
      SRC_DIGEST      = trimspace(data.external.check_additional_tag_destination[each.key].result.src_digest)
      DEST_DIGEST     = trimspace(data.external.check_additional_tag_destination[each.key].result.dest_digest)
      SOURCE_DEST_REF = each.value.source_dest_ref
      DEST_REF        = each.value.dest_ref
      DEST_TAG        = each.value.dest_tag
    }
    command = <<-EOT
    # Skip only when destination already points to the same digest as source.
    if [ -n "$${DEST_DIGEST}" ] && [ "$${SRC_DIGEST}" = "$${DEST_DIGEST}" ]; then
      echo "Skipping tag operation, already exists and matches source digest: '$${DEST_REF}' (digest '$${DEST_DIGEST}')"
      exit 0
    fi

    ${local.dest_login_script}

    echo "Tagging '$${SOURCE_DEST_REF}' as '$${DEST_TAG}'"
    crane tag "$${SOURCE_DEST_REF}" "$${DEST_TAG}"
    EOT
  }
}

# Compute the set of undeclared tags to prune during the plan phase so they are visible in the
# plan diff before the apply-time deletion runs.
data "external" "prune_undeclared_tags" {
  count = var.prune_undeclared_tags ? 1 : 0

  program = ["bash", "-c", <<-EOT
    ${local.dest_login_script}

    # Tags this configuration declares, newline-delimited for exact grep matching.
    expected="${join("\n", local.expected_dest_tags)}"

    # crane ls returns non-zero if the repo does not exist yet; treat that as no tags.
    existing="$(crane ls "${var.destination_repository}" 2>/dev/null || true)"

    to_delete=""
    for tag in $existing; do
      if ! printf '%s\n' "$expected" | grep -qxF "$tag"; then
        to_delete="$to_delete $tag"
      fi
    done

    # Trim leading whitespace and emit the delete set as a JSON string value.
    to_delete="$(echo "$to_delete" | sed 's/^ *//')"
    echo "{\"tags_to_delete\":\"$to_delete\"}"
  EOT
  ]
}

# Remove destination tags that are not declared in the configuration (either deleted from the
# configuration, or added to the target repository outside of this terraform module).
resource "terraform_data" "prune_undeclared_tags" {
  count = var.prune_undeclared_tags ? 1 : 0

  # Run last, after all copies and additional tags have been applied.
  depends_on = [terraform_data.copy, terraform_data.tag]

  # The delete set computed during plan by data.external.prune_undeclared_tags. As triggers_replace it both
  # surfaces the exact tags in the plan diff (as "forces replacement") and re-runs the create-time
  # provisioner whenever that set changes.
  triggers_replace = { tags_to_delete = trimspace(data.external.prune_undeclared_tags[count.index].result.tags_to_delete) }

  provisioner "local-exec" {
    interpreter = ["bash", "-euo", "pipefail", "-c"]
    environment = {
      # Space-separated list of tags to delete, exactly as shown in the plan.
      TAGS_TO_DELETE = self.triggers_replace.tags_to_delete
      DEST_REPO      = var.destination_repository
    }
    command = <<-EOT
      if [ -z "$${TAGS_TO_DELETE}" ]; then
        echo "No undeclared tags to prune in '$${DEST_REPO}'"
        exit 0
      fi

      ${local.dest_login_script}

      for tag in $${TAGS_TO_DELETE}; do
        echo "Deleting undeclared tag: '$${DEST_REPO}:$${tag}'"
        crane delete "$${DEST_REPO}:$${tag}"
      done
    EOT
  }
}
