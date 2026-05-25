# Rake task: route_spec_coverage
# Scans app/ for API routes (strings matching /api/...) and reports whether each route
# appears in spec files under spec/.

desc "Generate route->spec coverage report"
task :route_spec_coverage do
  endpoints = []
  Dir.glob('app/**/*').each do |f|
    next unless File.file?(f)
    begin
      # read binary and coerce to UTF-8, replacing invalid/undef bytes
      text = File.open(f, 'rb', &:read).force_encoding('UTF-8').encode('UTF-8', invalid: :replace, undef: :replace)
    rescue => e
      warn "Could not read #{f}: #{e}"
      next
    end
    # capture quoted endpoints like '/api/v1/projects' or "/api/v1/auth/authenticate"
    text.scan(/['\"](\/api\/[^\s'\"]+)['\"]/).each { |m| endpoints << m[0] }
    # capture some unquoted literal usages
    text.scan(%r{(/api/v[0-9]+/[A-Za-z0-9_\-\/:@?&=+%]+)}).each { |m| endpoints << m[0] }
  end

  endpoints.uniq!
  specs = Dir.glob('spec/**/*.rb')
  report = {}

  endpoints.sort.each do |ep|
    covered = specs.any? { |s| File.read(s).include?(ep) }
    report[ep] = covered ? 'covered' : 'MISSING'
  end

  puts "Route coverage report (route -> status):"
  report.each { |ep, status| puts "#{status.ljust(7)}  #{ep}" }

  missing = report.select { |_, v| v == 'MISSING' }.keys
  puts "\nSummary: #{report.size} endpoints, #{report.size - missing.size} covered, #{missing.size} missing"

  if missing.any?
    puts "\nMissing endpoints (appear in app/ but not referenced in spec/):"
    missing.each { |m| puts " - #{m}" }
  else
    puts "\nAll discovered endpoints are referenced in spec files."
  end
end
