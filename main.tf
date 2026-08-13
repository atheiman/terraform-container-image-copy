terraform {
  required_version = ">= 1.0"
}

# Check each destination tag and return explicit digest metadata.
data "external" "check_destination" {
  for_each = local.copy_operations_map

  program = ["bash", "-c", <<-EOT
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
    }
    command = <<-EOT
      # Skip only when destination already points to the same digest as source.
      if [ -n "$${DEST_DIGEST}" ] && [ "$${SRC_DIGEST}" = "$${DEST_DIGEST}" ]; then
        echo "Skipping copy operation, already exists and matches source digest: '${each.value.dest_ref}' (digest '$${DEST_DIGEST}')"
        exit 0
      fi

      ${local.dest_login_script}

      echo "Copying '${each.value.source_ref}' -> '${each.value.dest_ref}'"
      crane copy \
        "${each.value.source_ref}" \
        "${each.value.dest_ref}"
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
      SRC_DIGEST  = trimspace(data.external.check_additional_tag_destination[each.key].result.src_digest)
      DEST_DIGEST = trimspace(data.external.check_additional_tag_destination[each.key].result.dest_digest)
    }
    command = <<-EOT
    # Skip only when destination already points to the same digest as source.
    if [ -n "$${DEST_DIGEST}" ] && [ "$${SRC_DIGEST}" = "$${DEST_DIGEST}" ]; then
      echo "Skipping tag operation, already exists and matches source digest: '${each.value.dest_ref}' (digest '$${DEST_DIGEST}')"
      exit 0
    fi

    ${local.dest_login_script}

    echo "Tagging '${each.value.source_dest_ref}' as '${each.value.dest_tag}'"
    crane tag "${each.value.source_dest_ref}" "${each.value.dest_tag}"
    EOT
  }
}
