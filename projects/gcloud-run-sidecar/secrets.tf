locals {
  orion_runtime_sa = "serviceAccount:${data.google_project.project.number}-compute@developer.gserviceaccount.com"

  # Keys are not secret; values are. for_each cannot iterate a sensitive map.
  orion_secret_keys = nonsensitive(toset(keys(var.orion_secrets)))

  # Refuse the same Orion name in both maps (would duplicate Cloud Run env entries).
  orion_key_overlap = setintersection(local.orion_secret_keys, toset(keys(var.orion_env)))
}

check "orion_env_keys_exclusive" {
  assert {
    condition     = length(local.orion_key_overlap) == 0
    error_message = "Keys must not appear in both orion_secrets and orion_env: ${join(", ", local.orion_key_overlap)}"
  }
}

resource "google_secret_manager_secret" "orion" {
  for_each  = local.orion_secret_keys
  project   = var.project_id
  secret_id = "orion-${lower(replace(each.key, "_", "-"))}"

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "orion" {
  for_each    = local.orion_secret_keys
  secret      = google_secret_manager_secret.orion[each.key].id
  secret_data = var.orion_secrets[each.key]
}

resource "google_secret_manager_secret_iam_member" "orion_accessor" {
  for_each  = google_secret_manager_secret.orion
  project   = var.project_id
  secret_id = each.value.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = local.orion_runtime_sa
}
