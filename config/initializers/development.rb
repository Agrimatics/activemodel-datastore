if Rails.env.development? or Rails.env.test?
  # See here: https://github.com/lostisland/faraday/wiki/Setting-up-SSL-certificates
  ENV['SSL_CERT_FILE'] = '/usr/local/etc/openssl/certs/Equifax_Secure_Certificate_Authority.pem'
end

# Local cloud datastore configuration
if Rails.env.development?
  ENV['DATASTORE_HOST'] = 'http://localhost:8180'
end

if Rails.env.test?
  ENV['DATASTORE_HOST'] = 'http://localhost:8181'
end
