locals {
  # browse repo image tags here: https://gallery.ecr.aws/docker/library/busybox
  source_repo = "public.ecr.aws/docker/library/busybox"
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
    "1.38" = ["1", "latest"] # apply additional tags to this image tag
    "1.37" = []
  }
}
