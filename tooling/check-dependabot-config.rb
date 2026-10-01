#!/usr/bin/env ruby

require "yaml"
require "psych"

REPOSITORY_ROOT = File.expand_path("..", __dir__)
CONFIG_PATH = File.join(REPOSITORY_ROOT, ".github", "dependabot.yml")
GROUP_NAME = "routine-minor-patch"

EXPECTED_UPDATES = [
  {
    "ecosystem" => "opentofu",
    "directory" => "/infra/tofu/hetzner",
    "day" => "monday",
    "time" => "03:00",
    "files" => ["infra/tofu/hetzner/main.tf", "infra/tofu/hetzner/.terraform.lock.hcl"],
  },
  {
    "ecosystem" => "docker-compose",
    "directory" => "/infra/compose",
    "day" => "monday",
    "time" => "06:00",
    "files" => ["infra/compose/compose.yml"],
  },
  {
    "ecosystem" => "github-actions",
    "directory" => "/",
    "day" => "tuesday",
    "time" => "03:00",
    "files" => [".github/workflows"],
  },
  {
    "ecosystem" => "opentofu",
    "directory" => "/infra/tofu/hetzner/benchmark",
    "day" => "tuesday",
    "time" => "06:00",
    "files" => ["infra/tofu/hetzner/benchmark/main.tf", "infra/tofu/hetzner/benchmark/.terraform.lock.hcl"],
  },
  {
    "ecosystem" => "npm",
    "directory" => "/",
    "day" => "wednesday",
    "time" => "03:00",
    "files" => ["package.json", "pnpm-lock.yaml"],
  },
  {
    "ecosystem" => "mix",
    "directory" => "/apps/server",
    "day" => "thursday",
    "time" => "03:00",
    "files" => ["apps/server/mix.exs", "apps/server/mix.lock"],
  },
  {
    "ecosystem" => "swift",
    "directory" => "/apps/ios",
    "day" => "friday",
    "time" => "03:00",
    "files" => ["apps/ios/Package.swift", "apps/ios/Package.resolved"],
  },
].freeze

EXPECTED_ROOT_KEYS = %w[version updates].freeze
EXPECTED_UPDATE_KEYS = %w[
  package-ecosystem directory schedule open-pull-requests-limit cooldown groups
].freeze
EXPECTED_SCHEDULE_KEYS = %w[interval day time timezone].freeze
EXPECTED_COOLDOWN_KEYS = %w[default-days].freeze
EXPECTED_GROUP_KEYS = %w[applies-to update-types].freeze

def exact_keys?(value, expected, label, errors)
  unless value.is_a?(Hash)
    errors << "#{label} must be a mapping"
    return false
  end

  actual = value.keys
  unless actual.all? { |key| key.is_a?(String) }
    errors << "#{label} keys must be strings"
    return false
  end

  extras = actual - expected
  missing = expected - actual
  errors << "#{label} has unreviewed keys: #{extras.sort.join(', ')}" unless extras.empty?
  errors << "#{label} is missing keys: #{missing.sort.join(', ')}" unless missing.empty?
  extras.empty? && missing.empty?
end

def duplicate_mapping_keys(node, location = "document")
  return [] if node.nil?

  problems = []
  if node.is_a?(Psych::Nodes::Mapping)
    seen = {}
    node.children.each_slice(2) do |key_node, value_node|
      if key_node.is_a?(Psych::Nodes::Scalar)
        key = key_node.value
        problems << "#{location} repeats mapping key #{key.inspect}" if seen.key?(key)
        seen[key] = true
      end
      problems.concat(duplicate_mapping_keys(key_node, location))
      problems.concat(duplicate_mapping_keys(value_node, "#{location}.#{key_node.respond_to?(:value) ? key_node.value : 'key'}"))
    end
  else
    children = node.children if node.respond_to?(:children)
    Array(children).each { |child| problems.concat(duplicate_mapping_keys(child, location)) }
  end
  problems
end

def parse_yaml(source)
  syntax_tree = Psych.parse_stream(source)
  duplicates = duplicate_mapping_keys(syntax_tree)
  return [nil, duplicates] unless duplicates.empty?

  document = YAML.safe_load(
    source,
    permitted_classes: [],
    permitted_symbols: [],
    aliases: false,
  )
  [document, []]
rescue Psych::Exception, ArgumentError => error
  [nil, ["invalid or unsafe YAML: #{error.message.lines.first.to_s.strip}"]]
end

def update_identity(update)
  [update["package-ecosystem"], update["directory"]]
end

def validate_config(config, repository_root: REPOSITORY_ROOT, check_files: true)
  errors = []
  return ["configuration must be a mapping"] unless config.is_a?(Hash)

  exact_keys?(config, EXPECTED_ROOT_KEYS, "configuration", errors)
  errors << "version must be 2" unless config["version"] == 2
  updates = config["updates"]
  unless updates.is_a?(Array)
    errors << "updates must be a list"
    return errors
  end

  expected_by_identity = EXPECTED_UPDATES.to_h do |expected|
    [[expected["ecosystem"], expected["directory"]], expected]
  end
  actual_identities = []
  schedule_slots = []

  updates.each_with_index do |update, index|
    label = "updates[#{index}]"
    next unless exact_keys?(update, EXPECTED_UPDATE_KEYS, label, errors)

    ecosystem = update["package-ecosystem"]
    directory = update["directory"]
    unless ecosystem.is_a?(String) && directory.is_a?(String)
      errors << "#{label} ecosystem and directory must be strings"
      next
    end

    identity = [ecosystem, directory]
    actual_identities << identity
    expected = expected_by_identity[identity]
    unless expected
      errors << "#{label} has unreviewed ecosystem/directory #{ecosystem.inspect} at #{directory.inspect}"
      next
    end

    schedule = update["schedule"]
    if exact_keys?(schedule, EXPECTED_SCHEDULE_KEYS, "#{label}.schedule", errors)
      unless schedule["interval"] == "weekly" &&
             schedule["day"] == expected["day"] &&
             schedule["time"] == expected["time"] &&
             schedule["timezone"] == "UTC"
        errors << "#{label}.schedule must be weekly on #{expected['day']} at #{expected['time']} UTC"
      end
      slot = [schedule["day"], schedule["time"], schedule["timezone"]]
      if schedule_slots.include?(slot)
        errors << "#{label}.schedule duplicates slot #{slot.join(' ')}"
      end
      schedule_slots << slot
    end

    unless update["open-pull-requests-limit"] == 1
      errors << "#{label}.open-pull-requests-limit must be 1"
    end

    cooldown = update["cooldown"]
    if exact_keys?(cooldown, EXPECTED_COOLDOWN_KEYS, "#{label}.cooldown", errors) &&
       cooldown["default-days"] != 3
      errors << "#{label}.cooldown.default-days must be 3"
    end

    groups = update["groups"]
    if exact_keys?(groups, [GROUP_NAME], "#{label}.groups", errors)
      group = groups[GROUP_NAME]
      if exact_keys?(group, EXPECTED_GROUP_KEYS, "#{label}.groups.#{GROUP_NAME}", errors)
        unless group["applies-to"] == "version-updates"
          errors << "#{label}.groups.#{GROUP_NAME} must apply only to version-updates"
        end
        unless group["update-types"] == %w[minor patch]
          errors << "#{label}.groups.#{GROUP_NAME} must group exactly minor and patch updates"
        end
      end
    end

    if check_files
      expected["files"].each do |relative_path|
        absolute_path = File.join(repository_root, relative_path)
        exists = relative_path == ".github/workflows" ?
          Dir.glob(File.join(absolute_path, "*.{yml,yaml}")).any? :
          File.file?(absolute_path)
        errors << "#{label} has no checked-in manifest/lockfile at #{relative_path}" unless exists
      end
    end
  end

  repeated = actual_identities.group_by(&:itself).select { |_identity, items| items.length > 1 }.keys
  repeated.each do |ecosystem, directory|
    errors << "duplicate ecosystem/directory pair #{ecosystem.inspect} at #{directory.inspect}"
  end

  expected_identities = expected_by_identity.keys
  (expected_identities - actual_identities.uniq).each do |ecosystem, directory|
    errors << "missing ecosystem/directory pair #{ecosystem.inspect} at #{directory.inspect}"
  end

  errors
end

def expected_configuration
  {
    "version" => 2,
    "updates" => EXPECTED_UPDATES.map do |expected|
      {
        "package-ecosystem" => expected["ecosystem"],
        "directory" => expected["directory"],
        "schedule" => {
          "interval" => "weekly",
          "day" => expected["day"],
          "time" => expected["time"],
          "timezone" => "UTC",
        },
        "open-pull-requests-limit" => 1,
        "cooldown" => { "default-days" => 3 },
        "groups" => {
          GROUP_NAME => {
            "applies-to" => "version-updates",
            "update-types" => %w[minor patch],
          },
        },
      }
    end,
  }
end

def deep_copy(value)
  Marshal.load(Marshal.dump(value))
end

def self_test
  baseline = expected_configuration
  errors = validate_config(baseline, check_files: false)
  raise "valid policy rejected: #{errors.join('; ')}" unless errors.empty?

  cases = [
    ["unknown ecosystem/directory", ->(config) { config["updates"][0]["package-ecosystem"] = "docker" }, "unreviewed ecosystem/directory"],
    ["missing required entry", ->(config) { config["updates"].pop }, "missing ecosystem/directory pair"],
    ["duplicate entry", ->(config) { config["updates"] << deep_copy(config["updates"][0]) }, "duplicate ecosystem/directory pair"],
    ["unreviewed extra entry", ->(config) { extra = deep_copy(config["updates"][0]); extra["package-ecosystem"] = "docker"; config["updates"] << extra }, "unreviewed ecosystem/directory"],
    ["non-weekly schedule", ->(config) { config["updates"][0]["schedule"]["interval"] = "daily" }, "must be weekly"],
    ["duplicate schedule slot", ->(config) { config["updates"][1]["schedule"] = deep_copy(config["updates"][0]["schedule"]) }, "duplicates slot"],
    ["wrong schedule slot", ->(config) { config["updates"][0]["schedule"]["time"] = "04:00" }, "must be weekly"],
    ["unbounded routine PR limit", ->(config) { config["updates"][0]["open-pull-requests-limit"] = 0 }, "must be 1"],
    ["missing cooldown default", ->(config) { config["updates"][0]["cooldown"] = {} }, "missing keys: default-days"],
    ["wrong cooldown", ->(config) { config["updates"][0]["cooldown"]["default-days"] = 5 }, "must be 3"],
    ["major updates grouped", ->(config) { config["updates"][0]["groups"][GROUP_NAME]["update-types"] = %w[major minor patch] }, "group exactly minor and patch"],
    ["security updates grouped", ->(config) { config["updates"][0]["groups"][GROUP_NAME]["applies-to"] = "security-updates" }, "only to version-updates"],
    ["unknown updater option", ->(config) { config["updates"][0]["allow"] = [] }, "unreviewed keys"],
  ]

  cases.each do |name, mutate, expected_message|
    fixture = deep_copy(baseline)
    mutate.call(fixture)
    result = validate_config(fixture, check_files: false)
    unless result.any? { |message| message.include?(expected_message) }
      raise "#{name} was not refused for #{expected_message.inspect}: #{result.join('; ')}"
    end
  end

  _invalid, invalid_errors = parse_yaml("version: [\n")
  raise "invalid YAML was not rejected" if invalid_errors.empty?
  _duplicate, duplicate_errors = parse_yaml("version: 2\nversion: 2\nupdates: []\n")
  raise "duplicate YAML keys were not rejected" if duplicate_errors.empty?
  _alias, alias_errors = parse_yaml("defaults: &defaults {version: 2}\ncopy: *defaults\n")
  raise "YAML aliases were not rejected" if alias_errors.empty?

  puts "Dependabot policy self-test passed: valid=1 refusals=#{cases.length + 3}"
end

def main
  if ARGV == ["--help"]
    puts "Usage: ruby tooling/check-dependabot-config.rb [--self-test]"
    return 0
  end
  if ARGV == ["--self-test"]
    self_test
    return 0
  end
  unless ARGV.empty?
    warn "Usage: ruby tooling/check-dependabot-config.rb [--self-test]"
    return 2
  end

  source = File.read(CONFIG_PATH)
  config, parse_errors = parse_yaml(source)
  errors = parse_errors + validate_config(config)
  if errors.empty?
    puts "Dependabot policy valid: entries=#{EXPECTED_UPDATES.length} routine_pr_cap_per_entry=1"
    return 0
  end

  errors.each { |error| warn "Dependabot policy check failed: #{error}" }
  1
rescue SystemCallError => error
  warn "Dependabot policy check failed: #{error.message}"
  1
end

exit(main)
