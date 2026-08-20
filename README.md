# terraform-container-image-copy

Terraform module to copy container image tags from a source repository to a destination repository.

For each source tag, the module copies the image once to the same destination tag, then applies any additional destination tags using `crane tag`.

Requires [`crane`](https://github.com/google/go-containerregistry/blob/main/cmd/crane/README.md#installation) and `bash` installed and available on `$PATH` where `terraform` executes.

The image repository can be any `crane` supported registry. If the destination is an ECR repository, [an aws-cli command will be executed to login to the ECR registry](https://docs.aws.amazon.com/AmazonECR/latest/userguide/registry_auth.html#:~:text=get%2Dlogin%2Dpassword%20(AWS%20CLI)). This functionality can be disabled by explicitly setting var `destination_login_command` to a no-op shell command (like the `true` command): `destination_login_command = "true"`.

The same login handling is available for the source registry. If the source is an ECR repository, the aws-cli ECR login command is generated and run automatically before reading from or copying the source. Set var `source_login_command` to provide an explicit login command (this overrides the generated ECR command), for example when the source is a private non-ECR registry. Unlike the destination, the source login is lenient: if no login command is available and the registry is not already authenticated, `crane` accesses the source anonymously rather than failing. This keeps public source registries (`docker.io`, `public.ecr.aws`, `ghcr.io`, etc.) working with no configuration.

Note - after the module successfully copies an image tag into the destination repository (or applies an additional tag to a copied image), the next `terraform plan` with no changes to the configuration will incorrectly report the image tag still needs to be copied into the destination repo. The image tag already exists in the destination repo, and the apply provisioner script will correctly no-op. In the apply log output, you will see no-op messages like `Skipping copy operation` or `Skipping tag operation`. This second-plan incorrect evaluation is a limitation of [`terraform_data.triggers_replace`](https://developer.hashicorp.com/terraform/language/resources/terraform-data#triggers_replace). After the second `terraform apply`, the module will correctly evaluate if the destination repo contains all the desired tags, and only report a copy is needed if a destination image tag is missing.
