# HashiCorp Vault Policy for QuantumRishi
# Path: vault/policies/qr-deploy.hcl

# Allow reading common secrets
path "secret/data/qr/common/*" {
  capabilities = ["read"]
}

# Allow reading production secrets
path "secret/data/qr/prod/*" {
  capabilities = ["read"]
}

# Allow reading staging secrets
path "secret/data/qr/staging/*" {
  capabilities = ["read"]
}

# Allow using transit encryption
path "transit/encrypt/qr-encrypt" {
  capabilities = ["update"]
}

path "transit/decrypt/qr-encrypt" {
  capabilities = ["update"]
}

# Allow reading PKI certificates
path "pki/issue/qr-internal" {
  capabilities = ["create", "update"]
}

# Deny access to secret metadata (prevents listing)
path "secret/metadata/*" {
  capabilities = ["deny"]
}
