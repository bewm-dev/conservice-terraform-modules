# -----------------------------------------------------------------------------
# Conservice Aurora Database Module (App-Level Guardrail)
#
# Creates a PostgreSQL database with IAM-authenticated roles for service
# and team access. Consumed by app teams via infra/database.tf.
#
# This module connects to a shared Aurora cluster using master credentials
# and creates app-scoped resources inside it. The cluster itself is
# provisioned by the platform aws-aurora module.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Database
# -----------------------------------------------------------------------------

resource "postgresql_database" "this" {
  name              = var.database_name
  owner             = postgresql_role.service.name
  encoding          = var.encoding
  lc_collate        = var.lc_collate
  lc_ctype          = var.lc_ctype
  connection_limit  = var.connection_limit
  allow_connections = true
}

# -----------------------------------------------------------------------------
# Service Role (used by the application pod via IAM auth)
# -----------------------------------------------------------------------------

resource "postgresql_role" "service" {
  name  = var.service_role
  login = true
  roles = ["rds_iam"]

  # No password — IAM auth only
  skip_reassign_owned = true
}

resource "postgresql_grant" "service_schema" {
  role        = postgresql_role.service.name
  database    = postgresql_database.this.name
  schema      = "public"
  object_type = "schema"
  privileges  = ["USAGE", "CREATE"]
}

resource "postgresql_grant" "service_tables" {
  role        = postgresql_role.service.name
  database    = postgresql_database.this.name
  schema      = "public"
  object_type = "table"
  privileges  = var.app_permissions
}

resource "postgresql_grant" "service_sequences" {
  role        = postgresql_role.service.name
  database    = postgresql_database.this.name
  schema      = "public"
  object_type = "sequence"
  privileges  = ["USAGE", "SELECT"]
}

# Default privileges — new tables/sequences created by this role
# automatically get the right grants
resource "postgresql_default_privileges" "service_tables" {
  role     = postgresql_role.service.name
  database = postgresql_database.this.name
  schema   = "public"
  owner    = postgresql_role.service.name

  object_type = "table"
  privileges  = var.app_permissions
}

resource "postgresql_default_privileges" "service_sequences" {
  role     = postgresql_role.service.name
  database = postgresql_database.this.name
  schema   = "public"
  owner    = postgresql_role.service.name

  object_type = "sequence"
  privileges  = ["USAGE", "SELECT"]
}

# -----------------------------------------------------------------------------
# Team Read-Only Role (used by developers via SSO → IAM auth)
# -----------------------------------------------------------------------------

resource "postgresql_role" "team" {
  count = var.team_role != "" ? 1 : 0

  name  = var.team_role
  login = true
  roles = ["rds_iam"]

  skip_reassign_owned = true
}

resource "postgresql_grant" "team_schema" {
  count = var.team_role != "" ? 1 : 0

  role        = postgresql_role.team[0].name
  database    = postgresql_database.this.name
  schema      = "public"
  object_type = "schema"
  privileges  = ["USAGE"]
}

resource "postgresql_grant" "team_tables" {
  count = var.team_role != "" ? 1 : 0

  role        = postgresql_role.team[0].name
  database    = postgresql_database.this.name
  schema      = "public"
  object_type = "table"
  privileges  = var.team_permissions
}

# Default privileges — new tables created by the service role
# automatically grant read access to the team role
resource "postgresql_default_privileges" "team_tables" {
  count = var.team_role != "" ? 1 : 0

  role     = postgresql_role.team[0].name
  database = postgresql_database.this.name
  schema   = "public"
  owner    = postgresql_role.service.name

  object_type = "table"
  privileges  = var.team_permissions
}

# -----------------------------------------------------------------------------
# Additional Read-Only Roles (cross-team access)
# -----------------------------------------------------------------------------

resource "postgresql_role" "additional_readers" {
  for_each = toset(var.additional_readonly_roles)

  name  = each.key
  login = true
  roles = ["rds_iam"]

  skip_reassign_owned = true
}

resource "postgresql_grant" "additional_readers_schema" {
  for_each = toset(var.additional_readonly_roles)

  role        = postgresql_role.additional_readers[each.key].name
  database    = postgresql_database.this.name
  schema      = "public"
  object_type = "schema"
  privileges  = ["USAGE"]
}

resource "postgresql_grant" "additional_readers_tables" {
  for_each = toset(var.additional_readonly_roles)

  role        = postgresql_role.additional_readers[each.key].name
  database    = postgresql_database.this.name
  schema      = "public"
  object_type = "table"
  privileges  = ["SELECT"]
}

resource "postgresql_default_privileges" "additional_readers_tables" {
  for_each = toset(var.additional_readonly_roles)

  role     = postgresql_role.additional_readers[each.key].name
  database = postgresql_database.this.name
  schema   = "public"
  owner    = postgresql_role.service.name

  object_type = "table"
  privileges  = ["SELECT"]
}

# -----------------------------------------------------------------------------
# Extensions
# -----------------------------------------------------------------------------

resource "postgresql_extension" "this" {
  for_each = toset(var.extensions)

  name     = each.key
  database = postgresql_database.this.name
}
