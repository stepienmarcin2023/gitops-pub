variable "prefix" {
  type = string
}

variable "node_type" {
  type = string
}

variable "node_count" {
  type    = number
  default = 1
}

variable "elastic_ip_allocation_ids" {
  type    = list(string)
  default = []
}

variable "ami_id" {
  type    = string
  default = null
}

variable "iam_instance_policy_arns" {
  type    = list(string)
  default = []
}

variable "iam_permissions_boundary_arn" {
  type    = string
  default = null
}

variable "iam_identifier_path" {
  type    = string
  default = null
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "security_group_ids" {
  type    = list(string)
  default = []
}

variable "ssh_key_name" {
  type    = string
  default = null
}

variable "disk_type" {
  type    = string
  default = "gp3"
}

variable "disk_size" {
  type    = string
  default = "100"
}

variable "disk_iops" {
  type    = number
  default = null
}

variable "disk_encrypt" {
  type    = bool
  default = false
}

variable "disk_kms_key_arn" {
  type    = string
  default = null
}

variable "data_disks" {
  type    = any
  default = []
}

variable "label_secondaries" {
  type    = bool
  default = false
}

variable "geo_site" {
  type    = string
  default = null
}

variable "geo_deployment" {
  type    = string
  default = null
}

variable "subnet_ids" {
  type    = list(string)
  default = null
}

variable "additional_tags" {
  type    = map(any)
  default = {}
}

variable "disk_delete_on_termination" {
  type    = bool
  default = null
}
