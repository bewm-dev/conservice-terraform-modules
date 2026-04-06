output "database_name" {
  description = "Name of the created database"
  value       = postgresql_database.this.name
}

output "service_role_name" {
  description = "Name of the service role (for IAM policy rds-db:connect resource)"
  value       = postgresql_role.service.name
}

output "team_role_name" {
  description = "Name of the team read-only role (empty if not created)"
  value       = var.team_role != "" ? postgresql_role.team[0].name : ""
}

output "additional_reader_role_names" {
  description = "Names of additional read-only roles"
  value       = [for name, role in postgresql_role.additional_readers : role.name]
}

output "admin_user_names" {
  description = "Names of individual admin user roles"
  value       = [for name, role in postgresql_role.admin_users : role.name]
}

output "readonly_user_names" {
  description = "Names of individual read-only user roles"
  value       = [for name, role in postgresql_role.readonly_users : role.name]
}

output "all_iam_role_names" {
  description = "All IAM-authenticated role names (for building rds-db:connect IAM policies)"
  value = concat(
    [postgresql_role.service.name],
    var.team_role != "" ? [postgresql_role.team[0].name] : [],
    [for name, role in postgresql_role.additional_readers : role.name],
    [for name, role in postgresql_role.admin_users : role.name],
    [for name, role in postgresql_role.readonly_users : role.name],
  )
}
