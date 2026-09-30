# frozen_string_literal: true

# Runs every detection pattern for one upgrade hop against a Rails app and
# prints the findings as a table: same inputs, same output, every run. This is
# the scripted form of Workflow 05 (detect breaking changes). It replaces the
# per-pattern Grep loop, which drifts between sessions and silently skips
# patterns when the list is long.
#
# Usage, from the app root:
#
#   ruby <skill>/detection-scripts/scan_patterns.rb             # hop from Gemfile.lock
#   ruby <skill>/detection-scripts/scan_patterns.rb --target 7.0
#   ruby <skill>/detection-scripts/scan_patterns.rb --patterns path/to/rails-70-patterns.yml
#   ruby <skill>/detection-scripts/scan_patterns.rb --summary   # summary table only
#   ruby <skill>/detection-scripts/scan_patterns.rb --only VAR1,VAR2   # detail for these patterns only
#   ruby <skill>/detection-scripts/scan_patterns.rb --explain VAR1     # what a pattern means + its guide entry
#   ruby <skill>/detection-scripts/scan_patterns.rb --format json --output tmp/pattern-scan.json
#   ruby <skill>/detection-scripts/scan_patterns.rb --self-test
#
# Without --target or --patterns, the current Rails version is read from the
# app's Gemfile.lock and the target is the next hop in version-guides/
# (4.0 -> 4.1). When that hop has no patterns file (6.0 -> 6.1), or no guide
# starts at the current version (3.1), the script stops instead of scanning
# another hop's patterns under the wrong label.
#
# Runs with the app's own Ruby, so it stays Ruby 2.1 compatible: stdlib only,
# no `&.`, no `<<~`, no `String#match?`, no `Array#sum`, no `Dir.children`.
#
# How matching works, and why:
#
# 1. A pattern is matched against FILE CONTENT, not one line at a time. A call
#    split across lines is reachable when the pattern is written to reach it
#    (`[^)]*` and `\s*` cross newlines, `[^\n]*` and `.` do not). A line-based
#    grep can never see those sites, so its counts are a floor.
# 2. One row per SITE, keyed on where the match ends. The end is the offending
#    token and is the line reported. Two matches ending at the same offset are
#    one site; two sites sharing a line are two rows. A site that spans lines
#    is reported as file:start-end and quotes both ends, since the offending
#    token can sit on either one.
# 3. `exclude:` is tested on the lines the match spans. A site is suppressed
#    only when every match reaching it was excluded. Suppressed sites are
#    counted and listed with --show-suppressed, because `exclude:` can drop a
#    real hit that shares a line with the excluded form.
# 4. A match may not span more than MAX_SPAN_LINES, so a loose pattern cannot
#    rope two unrelated calls together.
# 5. An entry whose search_paths resolve to no files is UNSCANNED, never zero
#    hits (except a path-based entry, rule 7, where an absent path is the
#    clean answer), and an entry whose every site was dropped by exclude: is
#    "suppressed", never clean. "Could not scan" and "scanned clean" are
#    different answers.
# 6. Packwerk packs, engines and components are searched too: a search_path
#    like "app/models/" also reaches packs/*/app/models/. node_modules, vendor,
#    tmp, log, coverage are skipped at the app root and at each pack or engine
#    root (app/models/log/ is app code), node_modules, .git and .bundle at any
#    depth, unless a search_path names them.
# 7. An entry with an empty `pattern:` is path-based: it fires when any file
#    exists under its search_paths (e.g. vendor/plugins/).

require "yaml"
require "json"
require "optparse"
require "fileutils"

PATTERNS_DIR = File.expand_path("patterns", __dir__)
PRIORITIES = %w[high_priority medium_priority low_priority].freeze
PRIORITY_LABEL = { "high_priority" => "HIGH", "medium_priority" => "MEDIUM", "low_priority" => "LOW" }.freeze
FIX_BEFORE_BUMP = %w[breaking deprecation].freeze
KINDS = %w[breaking deprecation migration optional].freeze

MAX_SPAN_LINES = 60
# More sites than this on one line means a generated or minified file. Those
# collapse into one row that states the count.
MAX_SITES_PER_LINE = 4
MAX_TEXT = 100

IGNORED_DIRS = %w[node_modules vendor tmp log coverage .git .bundle].freeze
# Skipped at any depth: never app code wherever they sit (a pack keeps its
# webpack build at app/webpack/node_modules/).
IGNORED_ANYWHERE = %w[node_modules .git .bundle].freeze
# Skipped only at the app root or a pack/engine root: app/models/log/ and
# app/controllers/vendor/ are app code.
IGNORED_AT_ROOT = %w[vendor tmp log coverage].freeze
MODULAR_ROOT_SEEDS = %w[packs engines components].freeze
MODULAR_ROOT_MARKERS = ["package.yml", "*.gemspec", "lib/*/engine.rb"].freeze
MAX_MODULAR_ROOT_DEPTH = 2
# Files that describe the app's own environment. A pack or engine ships its
# own copy describing a different bundle, so these never expand into packs.
ENVIRONMENT_MANIFESTS = %w[
  Gemfile Gemfile.lock Gemfile.next Gemfile.next.lock
  .ruby-version .tool-versions .node-version
  Dockerfile Procfile Rakefile config.ru
  package.json package-lock.json yarn.lock
  config/database.yml config/cable.yml config/storage.yml
].freeze

class Scanner
  attr_reader :root

  def initialize(root)
    @root = root
    @text = {}
    @candidates = {}
    @modular_roots = {}
    @modular_members = {}
  end

  def modular_roots(dir = root)
    @modular_roots[dir] ||= begin
      prefix = File.join(dir, "")
      discovered = (1..MAX_MODULAR_ROOT_DEPTH).flat_map do |depth|
        MODULAR_ROOT_MARKERS.flat_map do |marker|
          Dir.glob(File.join(dir, *Array.new(depth + 1, "*"), marker)).map do |f|
            f[prefix.length..-1].split("/").first(depth).join("/")
          end
        end
      end
      discovered = discovered.reject { |m| m.split("/").any? { |seg| IGNORED_DIRS.include?(seg) } }
      (MODULAR_ROOT_SEEDS + discovered).uniq.select { |m| File.directory?(File.join(dir, m)) }.sort
    end
  end

  # { root_name => [member dirs] }, walking root -> member -> nested root.
  # Walking instead of globbing `**` keeps engine dummy apps and node_modules
  # copies of app/ out of the scan.
  def modular_members
    @modular_members[root] ||= begin
      members = {}
      modular_roots.each do |m|
        found = []
        queue = [File.join(root, m)]
        until queue.empty?
          dir = queue.shift
          entries = begin
            Dir.entries(dir).sort.reject { |e| e == "." || e == ".." }
          rescue SystemCallError
            []
          end
          entries.each do |name|
            next if IGNORED_DIRS.include?(name)
            member = File.join(dir, name)
            next if File.symlink?(member) || !File.directory?(member)
            found << member
            queue.concat(modular_roots(member).map { |n| File.join(member, n) })
          end
        end
        members[m] = found
      end
      members
    end
  end

  def text_file?(path)
    return @text[path] if @text.key?(path)
    @text[path] = begin
      head = File.binread(path, 8192)
      head.nil? || !head.include?("\x00".dup.force_encoding("BINARY"))
    rescue StandardError
      false
    end
  end

  def expand(path)
    if File.file?(path)
      [path]
    elsif File.directory?(path)
      Dir.glob(File.join(path, "**", "*")).sort.select { |f| File.file?(f) }
    else
      []
    end
  end

  # `rel` is a file path relative to the root its search_path was joined to
  # (the app root, or a pack or engine root).
  def ignored?(rel)
    dirs = rel.split("/")[0..-2]
    return false if dirs.empty?
    IGNORED_AT_ROOT.include?(dirs.first) || dirs.any? { |d| IGNORED_ANYWHERE.include?(d) }
  end

  def resolve(base, sp)
    path = File.join(base, sp)
    files = File.exist?(path) ? expand(path) : Dir.glob(path.chomp("/")).sort.flat_map { |m| expand(m) }
    # A search_path that names an ignored dir (vendor/plugins/) gets it.
    return files if ignored?(File.join(sp, "x"))
    prefix = File.join(base, "")
    files.reject { |f| ignored?(f.start_with?(prefix) ? f[prefix.length..-1] : f) }
  end

  def candidate_files(sp)
    @candidates[sp] ||= begin
      bases = [root]
      unless ENVIRONMENT_MANIFESTS.include?(sp)
        modular_members.each do |m, dirs|
          next if sp == m || sp.start_with?("#{m}/")
          bases.concat(dirs)
        end
      end
      bases.flat_map { |base| resolve(base, sp) }.uniq
    end
  end

  def relative(file)
    file.sub(/\A#{Regexp.escape(File.join(root, ""))}/, "").sub(%r{\A\./}, "")
  end

  # Returns { files_scanned:, hits: [[file, line, text]], suppressed: [...] }.
  def scan(entry)
    files = Array(entry["search_paths"]).flat_map { |sp| candidate_files(sp) }.uniq.select { |f| text_file?(f) }
    return path_only(entry, files) if entry["pattern"].to_s.strip.empty?

    pattern = Regexp.new(entry["pattern"])
    exclude = entry["exclude"].to_s.empty? ? nil : Regexp.new(entry["exclude"])
    hits = []
    suppressed = []
    files.each do |file|
      content = begin
        File.read(file)
      rescue StandardError
        next
      end
      # Scrub rather than skip: skipping a file with one bad byte reports it
      # as scanned clean.
      content = content.scrub("?") unless content.valid_encoding?
      scan_content(content, pattern, exclude).each do |line, text, excluded, start|
        (excluded ? suppressed : hits) << [relative(file), line, text, start]
      end
    end
    { :files_scanned => files.length, :hits => hits, :suppressed => suppressed }
  end

  def path_only(entry, files)
    hits = Array(entry["search_paths"]).map do |sp|
      n = candidate_files(sp).length
      n > 0 ? [sp, nil, "#{n} file(s) present"] : nil
    end.compact
    { :files_scanned => files.length, :hits => hits, :suppressed => [], :path_only => true }
  end

  def scan_content(content, pattern, exclude)
    sites = {}
    pos = 0
    line_off = 0
    line_no = 0
    while pos <= content.length && (md = safe_match(pattern, content, pos))
      b = md.begin(0)
      e = md.end(0)
      line_no += content[line_off...b].count("\n")
      line_off = b
      # Anchor on the last non-whitespace character matched: a trailing `\s*`
      # may cross a newline and point at an unrelated line.
      tail = e > b ? e - 1 : b
      tail -= 1 while tail > b && content[tail] =~ /\s/
      end_line = line_no + content[b..tail].to_s.count("\n")
      span_ok = (end_line - line_no) < MAX_SPAN_LINES
      excluded = false
      if span_ok && exclude
        span = content[bol(content, b)...eol(content, tail)].to_s
        excluded = !(span =~ exclude).nil?
      end
      # An over-long match retries one character later, so a real site inside
      # the span it would have swallowed is still found.
      pos = if !span_ok
              b + 1
            elsif excluded && end_line > line_no
              eol(content, b) + 1
            else
              e > b ? e : b + 1
            end
      next unless span_ok

      # A multi-line site reports its whole span and quotes both ends: the
      # offending token can sit on either one (`link_to ... confirm:` ends on
      # it, `update_all(` followed by the conditions starts on it).
      end_text = content[bol(content, tail)...eol(content, tail)].to_s.strip
      site = sites[e] ||= if end_line > line_no
                            start_text = content[bol(content, b)...eol(content, b)].to_s.strip
                            { :line => end_line + 1, :start => line_no + 1, :excluded => true,
                              :text => "#{start_text[0, MAX_TEXT / 2]} ... #{end_text[0, MAX_TEXT / 2]}" }
                          else
                            { :line => end_line + 1, :excluded => true, :text => end_text[0, MAX_TEXT] }
                          end
      site[:excluded] &&= excluded
    end

    by_line = {}
    sites.keys.sort.each { |k| (by_line[sites[k][:line]] ||= []) << sites[k] }
    rows = []
    by_line.keys.sort.each do |ln|
      group = by_line[ln]
      if group.length > MAX_SITES_PER_LINE
        rows << [ln, "#{group.first[:text][0, 60]} (#{group.length} matches on this line)", group.all? { |g| g[:excluded] }]
      else
        group.each { |s| rows << [ln, s[:text], s[:excluded], s[:start]] }
      end
    end
    rows
  end

  def bol(content, off)
    i = off.zero? ? nil : content.rindex("\n", off - 1)
    i ? i + 1 : 0
  end

  def eol(content, off)
    content.index("\n", off) || content.length
  end

  def safe_match(pattern, content, pos)
    pattern.match(content, pos)
  rescue ArgumentError, Encoding::CompatibilityError
    nil
  end
end

# ---------------------------------------------------------------------------
# Hop resolution

def version_key(v)
  v.split(".").map(&:to_i)
end

def available_versions
  Dir[File.join(PATTERNS_DIR, "rails-*-patterns.yml")].map do |f|
    digits = File.basename(f)[/rails-(\d+)-patterns\.yml/, 1]
    digits ? "#{digits[0..-2]}.#{digits[-1]}" : nil
  end.compact.sort_by { |v| version_key(v) }
end

GUIDES_DIR = File.expand_path("../version-guides", __dir__)

# The hop after `current` according to the version guides (6.0 -> 6.1), or
# nil when no guide starts at `current`. The guides, not the patterns files,
# define the hops: 6.1 has a guide and no patterns file.
def guide_hop(current)
  g = Dir[File.join(GUIDES_DIR, "upgrade-#{current}-to-*.md")].first
  g ? File.basename(g)[/-to-(\d+\.\d+)\.md\z/, 1] : nil
end

# The version guide whose hop ends at `target`, or nil.
def guide_for(target)
  Dir[File.join(GUIDES_DIR, "upgrade-*-to-#{target}.md")].first
end

# The version a hop to `target` starts from (7.0 -> "6.1"), or nil.
def guide_from(target)
  g = guide_for(target)
  g ? File.basename(g)[/\Aupgrade-(\d+\.\d+)-to-/, 1] : nil
end

# [[heading, first_line, last_line]] for every "## " and "#### " heading, so a
# reader can open one entry by line range instead of loading the whole guide.
def guide_index(path)
  lines = File.readlines(path, :encoding => "UTF-8")
  heads = []
  fence = false
  lines.each_with_index do |l, i|
    fence = !fence if l.start_with?("```")
    next if fence
    heads << [l.sub(/\A#+\s*/, "").strip, i + 1, l[/\A#+/].length] if l =~ /\A(##|####) /
  end
  heads.each_with_index.map do |(h, start, level), i|
    nxt = heads[(i + 1)..-1].find { |_, _, lv| lv <= level }
    [h, start, nxt ? nxt[1] - 1 : lines.length]
  end
end

# { variable_name => { :heading, :first, :last } } for every breaking-change
# entry whose `**Pattern:**` marker names it (the first line under the
# heading, see CLAUDE.md "Version guides"). A guide with no markers yet
# returns {}, and callers fall back to the heading index.
def guide_markers(path)
  return {} unless path && File.file?(path)
  lines = File.readlines(path, :encoding => "UTF-8")
  # Line indexes of every heading outside a code fence. An entry ends at the
  # next heading of any level, so a `### 🟡 MEDIUM PRIORITY` after the last
  # HIGH entry is not part of that entry.
  heads = []
  fence = false
  lines.each_with_index do |l, i|
    fence = !fence if l.start_with?("```")
    heads << i if !fence && l =~ /\A#+ /
  end
  found = {}
  section = nil
  heads.each_with_index do |i, n|
    l = lines[i]
    section = l.strip if l.start_with?("## ")
    next unless l.start_with?("#### ") && section == "## Breaking Changes"
    marker = lines[(i + 1)..-1].find { |x| !x.strip.empty? }.to_s[/\A\*\*Pattern:\*\*\s*(.*)/, 1]
    next unless marker
    last = heads[n + 1] ? heads[n + 1] : lines.length
    heading = l.sub(/\A#+\s*/, "").strip
    marker.scan(/`([A-Z0-9_]+)`/).flatten.each do |v|
      found[v] ||= { :heading => heading, :first => i + 1, :last => last }
    end
  end
  found
end

# The entry's own lines, without the trailing rule and blank lines.
def guide_entry_text(path, entry)
  body = File.readlines(path, :encoding => "UTF-8")[(entry[:first] - 1)..(entry[:last] - 1)]
  body.pop while body.any? && (body.last.strip.empty? || body.last.strip == "---")
  body.join
end

def guide_rel(path)
  path.sub(%r{\A.*/(version-guides/)}, '\1')
end

# Adds :guide_entry ({ :file, :heading, :first, :last } or nil) to each result.
def attach_guide_entries(results, target)
  guide = guide_for(target)
  markers = guide_markers(guide)
  results.each do |r|
    m = markers[r[:variable]]
    r[:guide_entry] = m ? m.merge(:file => guide_rel(guide)) : nil
  end
  results
end

# --explain: what one pattern means and where its guide entry is, without
# scanning the app. When the guide names the pattern in a `**Pattern:**`
# marker, the entry itself is printed; otherwise the guide's heading index.
def render_explain(patterns_path, target, vars)
  doc = YAML.load_file(patterns_path)["upgrade_findings"] || {}
  entries = {}
  PRIORITIES.each { |p| Array(doc[p]).each { |e| entries[e["variable_name"]] = [p, e] } }
  unknown = vars - entries.keys
  abort("scan_patterns: --explain names no pattern in #{File.basename(patterns_path)}: #{unknown.join(', ')}") unless unknown.empty?
  out = []
  guide = guide_for(target)
  markers = guide_markers(guide)
  vars.each do |v|
    pr, e = entries[v]
    out << "## #{e['name']} (`#{v}`)"
    out << ""
    out << "- Kind: #{e['kind']} · Priority: #{PRIORITY_LABEL[pr]}"
    out << "- Explanation: #{e['explanation']}"
    out << "- Fix: #{e['fix']}"
    Array(e["prereqs"]).each { |q| out << "- Prereq: #{q['gem']} >= #{q['min_version']} (#{q['reason']}#{q['when'] ? "; when #{q['when']}" : ''})" }
    out << ""
    next unless (m = markers[v])
    out << "### Guide entry: `#{guide_rel(guide)}` lines #{m[:first]}-#{m[:last]}"
    out << ""
    out << guide_entry_text(guide, m)
    out << ""
  end
  unmarked = vars.reject { |v| markers[v] }
  if unmarked.empty?
    # Every pattern asked about has its entry printed above.
  elsif guide
    rel = guide_rel(guide)
    out << "## Guide entries in `#{rel}`"
    out << ""
    out << "Read only the entry you need, by line range. The entry for a pattern is usually the one whose title names the same API."
    out << ""
    guide_index(guide).each { |h, a, b| out << "- #{a}-#{b}: #{h}" }
  else
    out << "No version guide ends at Rails #{target}."
  end
  out.join("\n") + "\n"
end

def patterns_file_for(version)
  File.join(PATTERNS_DIR, "rails-#{version.delete('.')}-patterns.yml")
end

def lock_rails_version(lockfile)
  return nil unless File.file?(lockfile)
  File.read(lockfile)[/^    rails \((\d+\.\d+)[^)]*\)/, 1]
end

def normalize_target(t)
  t = t.to_s.strip
  t = "#{t[0..-2]}.#{t[-1]}" if t =~ /\A\d{2,3}\z/
  t = t[/\A\d+\.\d+/] || t
  t
end

# ---------------------------------------------------------------------------
# Rendering

def md_cell(s)
  s.to_s.gsub("|", "\\|").gsub("`", "'")
end

def site_ref(file, line, start = nil)
  return file unless line
  start && start != line ? "#{file}:#{start}-#{line}" : "#{file}:#{line}"
end

def render_markdown(meta, results, opts)
  out = []
  out << "# Pattern scan: Rails #{meta[:from] || '?'} -> #{meta[:to]}"
  out << ""
  out << "- Patterns: `#{meta[:patterns_rel]}` (#{results.length} entries)"
  out << "- Root: `#{meta[:root]}`"
  out << "- Hop source: #{meta[:hop_source]}"
  out << "- Modular roots: #{meta[:modular_roots].empty? ? 'none found' : meta[:modular_roots].join(', ')}"
  out << ""

  found = results.reject { |r| r[:hits].empty? }
  out << "## Summary"
  out << ""
  if found.empty?
    out << "No pattern matched."
  else
    out << "| Bucket | Priority | Kind | Pattern | Variable | Sites | Files |"
    out << "|--------|----------|------|---------|----------|------:|------:|"
    found.each do |r|
      files = site_files(r).length
      out << "| #{r[:bucket_label]} | #{PRIORITY_LABEL[r[:priority]]} | #{r[:kind]} | #{md_cell(r[:name])} | `#{r[:variable]}` | #{r[:hits].length} | #{files} |"
    end
  end
  out << ""
  counts = KINDS.map { |k| "#{found.count { |r| r[:kind] == k }} #{k}" }.join(", ")
  total_sites = found.inject(0) { |t, r| t + r[:hits].length }
  affected = found.flat_map { |r| site_files(r) }.uniq.length
  out << "#{found.length} of #{results.length} patterns matched: #{total_sites} site(s) in #{affected} file(s). By kind: #{counts}."
  zero = results.select { |r| status_of(r) == "clean" }
  all_suppressed = results.select { |r| r[:hits].empty? && !r[:suppressed].empty? }
  unscanned = results.select { |r| status_of(r) == "unscanned" }
  suppressed = results.reject { |r| r[:suppressed].empty? }
  out << "#{zero.length} scanned clean, #{unscanned.length} UNSCANNED, #{suppressed.length} with sites suppressed by `exclude:` " \
         "(#{all_suppressed.length} with every site suppressed, which is not the same as clean)."

  unless opts[:summary]
    [["Fix before bump", true], ["Fix when ready", false]].each do |label, before|
      group = found.select { |r| FIX_BEFORE_BUMP.include?(r[:kind]) == before }
      group = group.select { |r| opts[:only].include?(r[:variable]) } if opts[:only]
      next if group.empty?
      out << ""
      out << "## #{label} (#{group.length})"
      group.each do |r|
        out << ""
        out << "### #{PRIORITY_LABEL[r[:priority]]} · #{r[:kind]} · #{r[:name]} (`#{r[:variable]}`), #{r[:hits].length} site(s)"
        out << ""
        out << "Fix: #{r[:fix]}" if r[:fix]
        if (g = r[:guide_entry])
          out << ""
          out << "Guide: \"#{g[:heading]}\", `#{g[:file]}` lines #{g[:first]}-#{g[:last]} (or `--explain #{r[:variable]}`)"
        end
        out << ""
        out << "| Location | Code |"
        out << "|----------|------|"
        r[:hits].each { |f, l, t, st| out << "| #{md_cell(site_ref(f, l, st))} | `#{md_cell(t)}` |" }
      end
    end
  end

  unless zero.empty?
    out << ""
    out << "## Scanned clean"
    out << ""
    zero.each do |r|
    note = r[:path_only] ? "path absent" : "#{r[:files_scanned]} files scanned"
    out << "- `#{r[:variable]}` #{r[:name]} (#{note})"
  end
  end

  unless suppressed.empty?
    out << ""
    out << "## Suppressed by exclude"
    out << ""
    out << "These sites matched `pattern:` and were then dropped by `exclude:`. Most are already migrated. " \
           "Check the ones where the excluded form can sit on the same line as a real hit#{opts[:show_suppressed] ? '' : ' (re-run with --show-suppressed to list them)'}."
    out << ""
    suppressed.each do |r|
      note = r[:hits].empty? ? " (every site suppressed: check that the exclude does not also drop real hits)" : ""
      out << "- `#{r[:variable]}`: #{r[:suppressed].length} site(s), exclude `#{md_cell(r[:exclude])}`#{note}"
      next unless opts[:show_suppressed]
      r[:suppressed].each { |f, l, t, st| out << "  - #{site_ref(f, l, st)} `#{md_cell(t)}`" }
    end
  end

  unless unscanned.empty?
    out << ""
    out << "## UNSCANNED"
    out << ""
    out << "The search_paths of these entries resolved to no files in this app. This means \"could not scan\", " \
           "not \"scanned clean\". Confirm the paths do not exist here, or search the app's real layout by hand."
    out << ""
    unscanned.each { |r| out << "- `#{r[:variable]}` #{r[:name]}: #{Array(r[:search_paths]).inspect}" }
  end

  out.join("\n") + "\n"
end

# Files with a line-level site. Path-only sites (a directory that exists, no
# line) are not files, so markdown and JSON count the same way.
def site_files(r)
  r[:hits].select { |h| h[1] }.map(&:first).uniq
end

def status_of(r)
  if !r[:hits].empty? then "found"
  elsif !r[:suppressed].empty? then "suppressed"
  # A path-based entry (pattern: "") asks whether the path exists, so an
  # absent path is its clean answer, not a failure to scan.
  elsif r[:files_scanned].zero? && !r[:path_only] then "unscanned"
  else "clean"
  end
end

def render_json(meta, results)
  found = results.select { |r| status_of(r) == "found" }
  by_kind = {}
  KINDS.each { |k| by_kind[k] = found.count { |r| r[:kind] == k } }
  JSON.pretty_generate(
    "from" => meta[:from], "to" => meta[:to], "patterns" => meta[:patterns_rel],
    "root" => meta[:root], "modular_roots" => meta[:modular_roots],
    # What the upgrade report's counts come from, so nobody recounts by hand.
    "summary" => {
      "patterns_checked" => results.length,
      "patterns_fired" => found.length,
      "sites" => found.inject(0) { |t, r| t + r[:hits].length },
      "files" => found.flat_map { |r| site_files(r) }.uniq.length,
      "by_kind" => by_kind,
      "unscanned" => results.select { |r| status_of(r) == "unscanned" }.map { |r| r[:variable] },
      "suppressed" => results.select { |r| status_of(r) == "suppressed" }.map { |r| r[:variable] }
    },
    "findings" => results.map do |r|
      {
        "name" => r[:name], "variable_name" => r[:variable], "kind" => r[:kind],
        "priority" => r[:priority], "bucket" => r[:bucket],
        "explanation" => r[:explanation], "fix" => r[:fix], "prereqs" => r[:prereqs],
        "files_scanned" => r[:files_scanned],
        "status" => status_of(r),
        # true when the entry fires on a path existing (pattern: ""); its sites
        # have "line" => null and "file" is the search path.
        "path_only" => r[:path_only] ? true : false,
        # The version-guide entry whose **Pattern:** marker names this
        # pattern, or null while the guide has no markers.
        "guide_entry" => r[:guide_entry] && {
          "file" => r[:guide_entry][:file], "heading" => r[:guide_entry][:heading],
          "lines" => [r[:guide_entry][:first], r[:guide_entry][:last]]
        },
        "sites" => r[:hits].map { |f, l, t, st| { "file" => f, "line" => l, "start_line" => st || l, "text" => t } },
        "suppressed" => r[:suppressed].map { |f, l, t, st| { "file" => f, "line" => l, "start_line" => st || l, "text" => t } }
      }
    end
  ) + "\n"
end

def run_scan(patterns_path, root)
  doc = YAML.load_file(patterns_path)
  findings = doc.is_a?(Hash) ? doc["upgrade_findings"] : nil
  abort("scan_patterns: #{patterns_path} has no upgrade_findings") unless findings.is_a?(Hash)
  scanner = Scanner.new(root)
  results = []
  PRIORITIES.each do |priority|
    Array(findings[priority]).each do |entry|
      r = scanner.scan(entry)
      bucket = FIX_BEFORE_BUMP.include?(entry["kind"]) ? "fix_before_bump" : "fix_when_ready"
      results << {
        :name => entry["name"], :variable => entry["variable_name"], :kind => entry["kind"],
        :priority => priority, :bucket => bucket,
        :bucket_label => bucket == "fix_before_bump" ? "Fix before bump" : "Fix when ready",
        :explanation => entry["explanation"], :fix => entry["fix"], :prereqs => entry["prereqs"],
        :exclude => entry["exclude"], :search_paths => entry["search_paths"],
        :files_scanned => r[:files_scanned], :hits => r[:hits], :suppressed => r[:suppressed],
        :path_only => r[:path_only]
      }
    end
  end
  # Bucket first, then priority, then the file's own order.
  order = results.each_with_index.map { |r, i| [r, i] }
  results = order.sort_by do |r, i|
    [r[:bucket] == "fix_before_bump" ? 0 : 1, PRIORITIES.index(r[:priority]), i]
  end.map(&:first)
  [results, scanner.modular_roots]
end

# ---------------------------------------------------------------------------
# Self-test

def self_test
  require "tmpdir"
  failures = []
  check = lambda { |desc, ok| failures << desc unless ok }
  Dir.mktmpdir do |dir|
    w = lambda do |rel, body|
      path = File.join(dir, rel)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, body)
    end
    w.call("app/models/a.rb", "scope :recent, where(x: 1)\nscope :ok, -> { all }\n")
    w.call("app/views/show.html.erb", "<%= link_to 'x', y_path, confirm: 'sure?' %>\n")
    w.call("app/multi.rb", "rel.count(conditions: c)\nrel.count(\n  conditions: c,\n  joins: :a\n)\n")
    w.call("app/twice.rb", "match \"/a\" and match \"/b\"\n")
    w.call("app/routes_like.rb", "match \"/a\", via: :get\nmatch \"/b\"\n")
    w.call("packs/p1/package.yml", "enforce_privacy: true\n")
    w.call("packs/p1/app/models/b.rb", "scope :old, where(y: 2)\n")
    w.call("packs/p1/app/webpack/node_modules/x/c.rb", "scope :vendored, where(z: 3)\n")
    w.call("vendor/plugins/foo/init.rb", "# plugin\n")
    w.call("app/controllers/vendor/orders_controller.rb", "x.update_attributes(y)\n")
    w.call("app/models/log/entry.rb", "x.update_attributes(y)\n")
    w.call("vendor/bundle/gems/g/lib/g.rb", "x.update_attributes(y)\n")
    w.call("app/long.rb", "a.count(\n" + ("x\n" * 70) + "y.count(conditions: 1)\n")
    w.call("Gemfile.lock", "GEM\n  specs:\n    rails (4.0.13)\n")
    File.binwrite(File.join(dir, "app/badbyte.rb"), "rel.count(conditions: a)\n\xff\xfe\nrel.count(conditions: b)\n")

    s = Scanner.new(dir)
    r = s.scan("pattern" => "scope\\s+:\\w+,\\s*where", "exclude" => "", "search_paths" => ["app/models/"])
    check.call("reaches packs/*/app/models and skips node_modules (want 2 hits, got #{r[:hits].length})", r[:hits].length == 2)
    r = s.scan("pattern" => "confirm:", "exclude" => "", "search_paths" => ["app/views/"])
    check.call("scans non-.rb files", r[:hits].length == 1)
    r = s.scan("pattern" => "\\.count\\([^)]*conditions:", "exclude" => "", "search_paths" => ["app/multi.rb"])
    check.call("finds single-line and multi-line sites (got #{r[:hits].length})", r[:hits].length == 2)
    check.call("multi-line site reports its span and quotes both ends (got #{r[:hits][1].inspect})",
               r[:hits][1] && r[:hits][1][1] == 3 && r[:hits][1][3] == 2 && r[:hits][1][2] == "rel.count( ... conditions: c,")
    r = s.scan("pattern" => "match\\s+\"", "exclude" => "", "search_paths" => ["app/twice.rb"])
    check.call("two sites on one line are two rows", r[:hits].length == 2)
    r = s.scan("pattern" => "match\\s+\"", "exclude" => "via:", "search_paths" => ["app/routes_like.rb"])
    check.call("exclude suppresses and counts", r[:hits].length == 1 && r[:suppressed].length == 1)
    r = s.scan("pattern" => "update_attributes", "exclude" => "", "search_paths" => ["app/", "lib/"])
    check.call("vendor/ and log/ below the root are app code (got #{r[:hits].map(&:first).inspect})",
               r[:hits].map(&:first).sort == ["app/controllers/vendor/orders_controller.rb", "app/models/log/entry.rb"])
    r = s.scan("pattern" => "update_attributes", "exclude" => "", "search_paths" => ["vendor/"])
    check.call("a search_path naming vendor/ still scans it", r[:hits].length == 1)
    r = s.scan("pattern" => "\\.count\\([^)]*conditions:", "exclude" => "", "search_paths" => ["app/long.rb"])
    check.call("an over-long match does not hide the site inside it (got #{r[:hits].inspect})",
               r[:hits].length == 1 && r[:hits][0][1] == 72)
    r = s.scan("pattern" => "anything", "exclude" => "", "search_paths" => ["engines/"])
    check.call("missing path is unscanned", r[:files_scanned].zero? && r[:hits].empty?)
    r = s.scan("pattern" => "", "exclude" => "", "search_paths" => ["vendor/plugins/"])
    check.call("empty pattern is path-based and honours a named vendor path", r[:hits].length == 1)
    r = s.scan("pattern" => "", "exclude" => "", "search_paths" => ["engines/plugins/"])
    check.call("a path-based entry with the path absent is clean, not unscanned", status_of(r) == "clean")
    check.call("a path-only site is not counted as a file", site_files(s.scan("pattern" => "", "exclude" => "", "search_paths" => ["vendor/plugins/"])).empty?)
    r = s.scan("pattern" => "\\.count\\([^)]*conditions:", "exclude" => "", "search_paths" => ["app/badbyte.rb"])
    check.call("invalid byte keeps the file's hits", r[:hits].length == 2)
    check.call("reads the hop from Gemfile.lock", lock_rails_version(File.join(dir, "Gemfile.lock")) == "4.0")
  end
  check.call("the 6.0 hop is 6.1 per the guides, not the next patterns file", guide_hop("6.0") == "6.1")
  check.call("no guide starts at 3.1, so there is no hop to fall back to", guide_hop("3.1").nil?)
  check.call("the hop to 7.0 starts at 6.1", guide_from("7.0") == "6.1")
  # Every shipped guide indexes to well-formed ranges, and a `# BEFORE` comment
  # inside a code fence is not taken for a heading.
  Dir[File.join(GUIDES_DIR, "upgrade-*.md")].each do |g|
    idx = guide_index(g)
    check.call("#{File.basename(g)}: every index range starts before it ends", idx.all? { |_, a, b| a <= b })
    check.call("#{File.basename(g)}: no code-fence line indexed", idx.none? { |h, _, _| h =~ /\A(BEFORE|AFTER)\b/ })
  end
  ex = render_explain(patterns_file_for("4.1"), "4.1", ["DEFAULT_SCOPE"])
  check.call("--explain prints the pattern and the guide entry index",
             ex.include?("`DEFAULT_SCOPE`") && ex.include?("upgrade-4.0-to-4.1.md") && ex =~ /^- \d+-\d+: `default_scope` Chains/)
  # A guide with **Pattern:** markers (7.2) links each pattern to its entry;
  # a guide without them (4.1) links nothing and --explain keeps the index.
  m72 = guide_markers(guide_for("7.2"))
  rv = m72["RUBY_VERSION"]
  check.call("reads the 7.2 markers (got #{rv.inspect})",
             rv && rv[:heading] == "Ruby Version Requirement" && rv[:first] < rv[:last])
  check.call("a guide without markers links nothing", guide_markers(guide_for("4.1")).empty?)
  check.call("a none marker names no pattern", !m72.values.any? { |x| x[:heading] =~ /alias_attribute/ })
  mc = m72["MIGRATION_CHECK_PENDING_REMOVED"]
  check.call("an entry ends before the next priority heading (got #{mc.inspect})",
             mc && guide_entry_text(guide_for("7.2"), mc) !~ /PRIORITY/)
  ex72 = render_explain(patterns_file_for("7.2"), "7.2", ["RUBY_VERSION"])
  check.call("--explain prints the marked guide entry, not the index",
             ex72.include?("### Guide entry:") && ex72.include?("required_ruby_version") && ex72 !~ /^## Guide entries in/)
  r72 = attach_guide_entries([{ :variable => "RUBY_VERSION" }, { :variable => "NOT_A_PATTERN" }], "7.2")
  check.call("attaches the guide entry to a result",
             r72[0][:guide_entry] && r72[0][:guide_entry][:file] == "version-guides/upgrade-7.1-to-7.2.md" && r72[1][:guide_entry].nil?)
  check.call("normalizes 41 and 4.1.2", normalize_target("41") == "4.1" && normalize_target("4.1.2") == "4.1")

  # Every shipped patterns file must load and scan without raising.
  Dir.mktmpdir do |dir|
    available_versions.each do |v|
      begin
        res, roots = run_scan(patterns_file_for(v), dir)
        j = JSON.parse(render_json({ :to => v, :modular_roots => roots }, res))
        ok = j["summary"]["patterns_checked"] == res.length && j["findings"].all? { |x| x.key?("explanation") }
        failures << "rails-#{v.delete('.')}-patterns.yml: JSON summary or explanation missing" unless ok
      rescue StandardError => e
        failures << "rails-#{v.delete('.')}-patterns.yml raised #{e.class}: #{e.message}"
      end
    end
  end

  if failures.empty?
    puts "scan_patterns: self-test OK"
    exit 0
  end
  failures.each { |f| warn "FAIL: #{f}" }
  exit 1
end

# ---------------------------------------------------------------------------
# CLI

if $PROGRAM_NAME == __FILE__
  opts = { :root => ".", :format => "markdown" }
  OptionParser.new do |o|
    o.banner = "Usage: ruby scan_patterns.rb [--target X.Y | --patterns FILE] [--root DIR] [options]"
    o.on("--target VERSION", "target Rails version, e.g. 7.0 (default: next hop after Gemfile.lock)") { |v| opts[:target] = v }
    o.on("--patterns FILE", "scan with this patterns file instead") { |v| opts[:patterns] = v }
    o.on("--root DIR", "app root (default: .)") { |v| opts[:root] = v }
    o.on("--format FORMAT", %w[markdown json], "markdown (default) or json") { |v| opts[:format] = v }
    o.on("--summary", "print the summary table only, no per-site detail") { opts[:summary] = true }
    o.on("--only VARS", "per-site detail only for these variable_names (comma-separated)") { |v| opts[:only] = v.split(",").map(&:strip) }
    o.on("--explain VARS", "print these patterns' explanation, fix, prereqs and guide entry (or the guide's entry index while it has no markers), without scanning") { |v| opts[:explain] = v.split(",").map(&:strip) }
    o.on("--show-suppressed", "list the sites dropped by each entry's exclude:") { opts[:show_suppressed] = true }
    o.on("--output FILE", "write to FILE instead of stdout (creates its directory; removed first, written only on success)") { |v| opts[:output] = v }
    o.on("--self-test", "run built-in assertions and exit") { opts[:self_test] = true }
  end.parse!

  self_test if opts[:self_test]

  # Remove the old output before anything can abort, so a failed run never
  # leaves a stale or half-written file for the next workflow to read.
  output = opts[:output] ? File.expand_path(opts[:output]) : nil
  File.delete(output) if output && File.file?(output)

  root = File.expand_path(opts[:root])
  abort("scan_patterns: --root #{opts[:root].inspect} is not a directory") unless File.directory?(root)
  current = lock_rails_version(File.join(root, "Gemfile.lock"))

  if opts[:patterns]
    patterns = File.expand_path(opts[:patterns])
    abort("scan_patterns: #{opts[:patterns]} not found") unless File.file?(patterns)
    target = YAML.load_file(patterns)["version"].to_s
    hop_source = "--patterns"
  else
    if opts[:target]
      target = normalize_target(opts[:target])
      hop_source = "--target"
    else
      abort("scan_patterns: no Gemfile.lock with rails in #{root}; pass --target X.Y") unless current
      target = guide_hop(current)
      unless target
        abort("scan_patterns: no version guide starts at Rails #{current}, so the next hop is unknown. " \
              "Pass --target X.Y to scan a hop on purpose. Available patterns: #{available_versions.join(', ')}")
      end
      unless File.file?(patterns_file_for(target))
        abort("scan_patterns: the next hop is Rails #{current} -> #{target}, which has no patterns file. " \
              "Detect it from the version guide by hand, or pass --target X.Y to scan another hop on purpose.")
      end
      hop_source = "Gemfile.lock pins rails #{current}; next hop is #{target}"
    end
    patterns = patterns_file_for(target)
    unless File.file?(patterns)
      abort("scan_patterns: no patterns file for Rails #{target}. Available: #{available_versions.join(', ')}")
    end
  end

  if opts[:explain]
    print render_explain(patterns, target, opts[:explain])
    exit 0
  end

  results, roots = run_scan(patterns, root)
  attach_guide_entries(results, target)
  if opts[:only]
    unknown = opts[:only] - results.map { |r| r[:variable] }
    unless unknown.empty?
      abort("scan_patterns: --only names no pattern in #{File.basename(patterns)}: #{unknown.join(', ')} " \
            "(use the variable_name, e.g. #{results.first && results.first[:variable]})")
    end
  end
  # The hop's start comes from the guide that ends at the target, so --target
  # 7.0 on a 4.0 app reads 6.1 -> 7.0, not 4.0 -> 7.0. Gemfile.lock is the
  # fallback when no guide ends there.
  meta = {
    :from => guide_from(target) || current, :to => target, :root => root, :hop_source => hop_source, :modular_roots => roots,
    :patterns_rel => patterns.sub(%r{\A.*/(detection-scripts/)}, '\1')
  }
  text = opts[:format] == "json" ? render_json(meta, results) : render_markdown(meta, results, opts)
  if output
    FileUtils.mkdir_p(File.dirname(output))
    tmp = "#{output}.tmp#{Process.pid}"
    File.write(tmp, text)
    File.rename(tmp, output)
    $stderr.puts "scan_patterns: wrote #{output}"
  else
    print text
  end
end
