# db/seeds.rb is idempotent. Bootstrap admin credentials come from ENV.fetch — missing envs fail loudly.

bootstrap_email = ENV.fetch("ADMIN_BOOTSTRAP_EMAIL")
bootstrap_name  = ENV.fetch("ADMIN_BOOTSTRAP_NAME")

if defined?(Admin)
  Admin.find_or_create_by!(email: bootstrap_email) do |admin|
    admin.name = bootstrap_name
  end
end
