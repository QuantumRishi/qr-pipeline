# HashiCorp Vault Policy for Admin Operations
# Path: vault/policies/qr-admin.hcl

# Full access to QR secrets
path "secret/data/qr/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "secret/metadata/qr/*" {
  capabilities = ["read", "list", "delete"]
}

# Manage transit keys
path "transit/keys/qr-*" {
  capabilities = ["create", "read", "update", "delete"]
}

# Issue and manage PKI certificates
path "pki/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# Manage policies (except root)
path "sys/policies/acl/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# Manage auth methods
path "auth/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# View audit logs
path "sys/audit" {
  capabilities = ["read", "list"]
}

path "sys/audit/*" {
  capabilities = ["read"]
}
