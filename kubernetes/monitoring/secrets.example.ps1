# Copy to secrets.local.ps1 in this directory. Fill the password yourself.
# The local file is excluded from Git and from the application build context.
$env:GRAFANA_ADMIN_USER = 'admin'
$env:GRAFANA_ADMIN_PASSWORD = 'REPLACE_WITH_A_LONG_UNIQUE_PASSWORD'
