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
