# -----------------------------------------------------------------------------
# conservice-app-database
#
# Creates a PostgreSQL database with IAM-authenticated roles inside a shared
# Aurora cluster. The cluster is provisioned by SRE (terraform-aws-modules/
# rds-aurora/aws); this module creates app-scoped resources inside it.
#
# Auth chain: Google → Identity Center → IAM → rds-db:connect (no passwords)
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
# Service Role (application pod via IAM auth)
# -----------------------------------------------------------------------------

resource "postgresql_role" "service" {
  name  = var.service_role
  login = true

  skip_reassign_owned = true
}

# Grant rds_iam AFTER database creation. The provider temporarily grants the
# DB owner role to itself for CREATE DATABASE. If the owner has rds_iam,
# the master user gets routed through PAM auth and password connections fail.
resource "postgresql_grant_role" "service_iam" {
  role       = postgresql_role.service.name
  grant_role = "rds_iam"

  depends_on = [postgresql_database.this]
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
# Team Read-Only Role (developers via SSO → IAM auth)
# -----------------------------------------------------------------------------

resource "postgresql_role" "team" {
  count = var.team_role != "" ? 1 : 0

  name  = var.team_role
  login = true

  skip_reassign_owned = true
}

resource "postgresql_grant_role" "team_iam" {
  count = var.team_role != "" ? 1 : 0

  role       = postgresql_role.team[0].name
  grant_role = "rds_iam"

  depends_on = [postgresql_database.this]
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

  skip_reassign_owned = true
}

resource "postgresql_grant_role" "additional_readers_iam" {
  for_each = toset(var.additional_readonly_roles)

  role       = postgresql_role.additional_readers[each.key].name
  grant_role = "rds_iam"
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
# Admin Groups (Identity Center group → IAM auth)
# -----------------------------------------------------------------------------

resource "postgresql_role" "admin_groups" {
  for_each = toset(var.admin_groups)

  name    = each.key
  login   = true
  inherit = true

  skip_reassign_owned = true
}

resource "postgresql_grant_role" "admin_groups_service" {
  for_each = toset(var.admin_groups)

  role       = postgresql_role.admin_groups[each.key].name
  grant_role = postgresql_role.service.name
}

resource "postgresql_grant_role" "admin_groups_iam" {
  for_each = toset(var.admin_groups)

  role       = postgresql_role.admin_groups[each.key].name
  grant_role = "rds_iam"
}

# -----------------------------------------------------------------------------
# Read-Only Groups (Identity Center group → IAM auth)
# -----------------------------------------------------------------------------

resource "postgresql_role" "readonly_groups" {
  for_each = toset(var.readonly_groups)

  name    = each.key
  login   = true
  inherit = true

  skip_reassign_owned = true
}

resource "postgresql_grant_role" "readonly_groups_iam" {
  for_each = toset(var.readonly_groups)

  role       = postgresql_role.readonly_groups[each.key].name
  grant_role = "rds_iam"
}

resource "postgresql_grant" "readonly_groups_schema" {
  for_each = toset(var.readonly_groups)

  role        = postgresql_role.readonly_groups[each.key].name
  database    = postgresql_database.this.name
  schema      = "public"
  object_type = "schema"
  privileges  = ["USAGE"]
}

resource "postgresql_grant" "readonly_groups_tables" {
  for_each = toset(var.readonly_groups)

  role        = postgresql_role.readonly_groups[each.key].name
  database    = postgresql_database.this.name
  schema      = "public"
  object_type = "table"
  privileges  = ["SELECT"]
}

resource "postgresql_default_privileges" "readonly_groups_tables" {
  for_each = toset(var.readonly_groups)

  role     = postgresql_role.readonly_groups[each.key].name
  database = postgresql_database.this.name
  schema   = "public"
  owner    = postgresql_role.service.name

  object_type = "table"
  privileges  = ["SELECT"]
}

# -----------------------------------------------------------------------------
# Individual Admin Users (Google identity → IAM auth)
# Escape hatch for one-off access (break-glass, contractors). Prefer groups.
# -----------------------------------------------------------------------------

resource "postgresql_role" "admin_users" {
  for_each = toset(var.admin_users)

  name    = each.key
  login   = true
  inherit = true

  skip_reassign_owned = true
}

resource "postgresql_grant_role" "admin_users_service" {
  for_each = toset(var.admin_users)

  role       = postgresql_role.admin_users[each.key].name
  grant_role = postgresql_role.service.name
}

resource "postgresql_grant_role" "admin_users_iam" {
  for_each = toset(var.admin_users)

  role       = postgresql_role.admin_users[each.key].name
  grant_role = "rds_iam"
}

# -----------------------------------------------------------------------------
# Individual Read-Only Users (Google identity → IAM auth)
# Escape hatch for one-off access. Prefer groups.
# -----------------------------------------------------------------------------

resource "postgresql_role" "readonly_users" {
  for_each = toset(var.readonly_users)

  name    = each.key
  login   = true
  inherit = true

  skip_reassign_owned = true
}

resource "postgresql_grant_role" "readonly_users_iam" {
  for_each = toset(var.readonly_users)

  role       = postgresql_role.readonly_users[each.key].name
  grant_role = "rds_iam"
}

resource "postgresql_grant" "readonly_users_schema" {
  for_each = toset(var.readonly_users)

  role        = postgresql_role.readonly_users[each.key].name
  database    = postgresql_database.this.name
  schema      = "public"
  object_type = "schema"
  privileges  = ["USAGE"]
}

resource "postgresql_grant" "readonly_users_tables" {
  for_each = toset(var.readonly_users)

  role        = postgresql_role.readonly_users[each.key].name
  database    = postgresql_database.this.name
  schema      = "public"
  object_type = "table"
  privileges  = ["SELECT"]
}

resource "postgresql_default_privileges" "readonly_users_tables" {
  for_each = toset(var.readonly_users)

  role     = postgresql_role.readonly_users[each.key].name
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
