# Detects partials that may rely on Rails 3.2 "magic" local variables.
#
# In Rails 3.2, rendering a partial auto-defined a local variable named after
# the partial (set to nil if no object/collection was passed). Rails 4.0
# removed this behavior — only `collection:`, `object:`, or `locals:` define
# the variable now. Partials relying on the implicit variable will raise
# `undefined local variable or method` errors.
#
# Usage:
#   ruby detection-scripts/detect-partial-magic-vars.rb [search_dir]
#   # defaults to app/views

require 'find'

SEARCH_DIR = ARGV[0] || 'app/views'
EXTENSIONS = %w[.html.erb .html.haml .html.slim]

def partial_file?(file)
  base = File.basename(file)
  EXTENSIONS.any? { |ext| base.start_with?('_') && base.end_with?(ext) }
end

def extract_partial_name(file)
  File.basename(file).match(/^_(.*?)\./)[1]
end

Find.find(SEARCH_DIR) do |path|
  next unless File.file?(path) && partial_file?(path)

  partial_name = extract_partial_name(path)
  content = File.read(path)

  if content.match?(/\s#{Regexp.escape(partial_name)}\s/)
    puts "[!] '#{path}' references variable '#{partial_name}' -- verify render calls"
  end
end
