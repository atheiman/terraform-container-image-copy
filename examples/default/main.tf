locals {
  source_repo = "ghcr.io/containerd/busybox"
}

resource "aws_ecr_repository" "repo" {
  name                 = "test/${local.source_repo}"
  image_tag_mutability = "MUTABLE"
  force_delete         = true
}

module "mirror" {
  source = "../../"

  source_repository      = local.source_repo
  destination_repository = aws_ecr_repository.repo.repository_url

  tags = {
    "1.32" = ["latest"]
    "1.36" = []
  }
}
