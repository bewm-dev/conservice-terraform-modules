module "resources" {
  source = "git::https://github.com/conservice-ai/conservice-terraform-modules.git//modules/conservice-app-resources?ref=conservice-app-resources/v1.8.0"

  app_name        = "my-app"
  env             = var.env
  region          = var.region
  cluster_name    = var.cluster_name
  aws_account_id  = var.aws_account_id
  tf_state_bucket = var.tf_state_bucket

  team      = "my-team"
  domain    = "billing"
  portfolio = "billing"

  databases = {
    my_app = {
      service_role = "my_app_svc"
      team_role    = "my_app_read"
      extensions   = ["pgcrypto", "uuid-ossp"]
      admin_groups = ["aws-db-my-team-admin"]
    }
  }

  buckets = {
    data    = {}
    exports = { versioning = false }
  }

  queues = {
    events = { max_receive_count = 5, visibility_timeout = 60 }
  }

  secrets = {
    config   = { description = "Application configuration values" }
    api-keys = { description = "External API keys" }
  }

  pod_identity = {
    namespace       = "my-app"
    service_account = "my-app"
  }

  ci_role = {
    github_org = "conservice-ai"
    repo_name  = "conservice-app-my-app"
  }

  tags = { Repo = "conservice-app-my-app" }
}
