require "yast/rake"

Yast::Tasks.submit_to(ENV["YAST_SUBMIT"] ? ENV["YAST_SUBMIT"].to_sym : :casp10)

Yast::Tasks.configuration do |conf|
  #lets ignore license check for now
  conf.skip_license_check << /.*/
end
