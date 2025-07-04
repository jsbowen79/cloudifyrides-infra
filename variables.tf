variable "aws_region" {
  default = "us-east-1"
}

variable "ubuntu_ami" {
  default = "ami-08c40ec9ead489470"
}

variable "gh_pat" {
  description = "GitHub Personal Access Token"
  type        = string
  sensitive   = true
}

variable "github_username" {
  description = "GitHub username used for cloning private repositories"
  type        = string
}
