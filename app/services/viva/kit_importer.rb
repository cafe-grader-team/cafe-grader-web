require 'yaml'

module Viva
  # Imports a viva-scenario kit (a directory with `manifest.yml`, one scenario
  # .md + one examiner-briefing .md per problem, and an optional shared conduct
  # profile, optional shared grounding texts) into viva_exam Problems.
  # Idempotent: existing problems are matched by `name` and updated in place;
  # the conduct tag is matched by tag name; grounding materials by title.
  # Report-first: only mutates when apply: true.
  #
  # Manifest shape (see course-prep/<course>/viva/<batch>/manifest.yml):
  #
  #   conduct_tag: {name: DS-viva-conduct-2569, file: _conduct.md}   # optional
  #   defaults:    {viva_soft_cap: 10, viva_hard_cap: 15, viva_daily_limit: 5, available: false}
  #   problems:
  #     - name: v69_x            # Problem#name (unique key)
  #       full_name: "Viva: X"
  #       scenario: 01-x.scenario.md   # -> problem.description (sent verbatim to the examiner)
  #       briefing: 01-x.briefing.md   # -> problem.viva_prompt (must contain a `# Rubric` heading)
  #       viva_soft_cap / viva_hard_cap / viva_daily_limit / available   # optional overrides
  #
  #   grounding:                                  # optional, shared reference texts
  #     - title: "DS: STL usage, decks 01-07"     # GroundingMaterial#title (unique key)
  #       file: _grounding-stl.md                 # -> body (markdown; re-sent to the LLM every turn)
  #       description: "..."                      # optional
  #       problems: [v69_x, v69_y]                # attach to these manifest problems (add-only)
  #
  # `available` is applied on CREATE only — instructors flip it in the UI as
  # the course reaches each scenario's topic; re-importing never un-publishes.
  # Grounding links are add-only too: an import never detaches material an
  # instructor attached by hand (e.g. a `-sol` PDF).
  class KitImporter
    UPDATABLE = %w[full_name description viva_prompt viva_soft_cap viva_hard_cap viva_daily_limit].freeze

    attr_reader :errors

    def initialize(dir, apply: false, io: $stdout)
      @dir = Pathname.new(dir)
      @apply = apply
      @io = io
      @errors = []
      @touched = []
    end

    def run
      manifest = load_manifest
      @io.puts(@apply ? "== APPLYING kit #{manifest['batch']} from #{@dir} ==" : "== DRY RUN kit #{manifest['batch']} from #{@dir} (report only; run with APPLY=1 to execute) ==")
      defaults = manifest['defaults'] || {}

      ActiveRecord::Base.transaction do
        conduct = upsert_conduct(manifest['conduct_tag'])
        Array(manifest['problems']).each { |entry| upsert_problem(entry, defaults, conduct) }
        kit_names = Array(manifest['problems']).map { |e| e['name'].to_s }
        Array(manifest['grounding']).each { |spec| upsert_grounding(spec, kit_names) }
        post_check
        raise ActiveRecord::Rollback unless @apply && @errors.empty?
      end

      if @errors.any?
        @io.puts "== #{@errors.size} error(s); nothing applied ==" if @apply
        @errors.each { |e| @io.puts "ERROR     #{e}" }
      else
        @io.puts '== done =='
      end
      @errors.empty?
    end

    private

    def load_manifest
      path = @dir.join('manifest.yml')
      raise ArgumentError, "no manifest.yml in #{@dir}" unless path.file?
      YAML.safe_load(path.read, permitted_classes: [Date], aliases: true) || {}
    end

    def read_file(name, what)
      path = @dir.join(name.to_s)
      unless path.file?
        @errors << "#{what} file missing: #{path}"
        return nil
      end
      path.read.strip
    end

    # Shared examiner persona → a viva_conduct Tag (params holds the text).
    def upsert_conduct(spec)
      return nil if spec.blank?
      text = read_file(spec['file'], 'conduct')
      return nil if text.nil?

      tag = Tag.find_or_initialize_by(name: spec['name'])
      if tag.new_record?
        tag.assign_attributes(kind: :viva_conduct, public: false, params: text,
                              description: spec['description'] || 'Shared viva examiner conduct profile')
        @io.puts "CONDUCT   create tag '#{tag.name}' (#{text.length} chars)"
        tag.save!
      elsif !tag.viva_conduct?
        @errors << "tag '#{tag.name}' exists with kind=#{tag.kind}, refusing to re-kind it"
        return nil
      elsif tag.params.to_s.strip == text
        @io.puts "CONDUCT   unchanged tag '#{tag.name}'"
      else
        @io.puts "CONDUCT   update tag '#{tag.name}' (#{tag.params.to_s.length} -> #{text.length} chars)"
        tag.update!(params: text)
      end
      tag
    end

    def upsert_problem(entry, defaults, conduct)
      name = entry['name'].to_s
      scenario = read_file(entry['scenario'], "scenario for #{name}")
      briefing = read_file(entry['briefing'], "briefing for #{name}")
      return if scenario.nil? || briefing.nil?

      attrs = {
        'full_name' => entry['full_name'].presence || name,
        'description' => scenario,
        'viva_prompt' => briefing,
        'viva_soft_cap' => entry.fetch('viva_soft_cap', defaults['viva_soft_cap'] || 10),
        'viva_hard_cap' => entry.fetch('viva_hard_cap', defaults['viva_hard_cap'] || 15),
        'viva_daily_limit' => entry.fetch('viva_daily_limit', defaults['viva_daily_limit'])
      }

      problem = Problem.find_by(name: name)
      if problem.nil?
        create_problem(name, attrs, entry.fetch('available', defaults['available'] || false), conduct)
      elsif !problem.viva_exam?
        @errors << "problem '#{name}' exists but is not a viva_exam (compilation_type=#{problem.compilation_type}); refusing to overwrite"
      else
        update_problem(problem, attrs, conduct)
      end
    end

    def create_problem(name, attrs, available, conduct)
      problem = Problem.new(attrs.merge(name: name, compilation_type: :viva_exam, available: available,
                                        date_added: Date.current, test_allowed: true, output_only: false))
      # Mirror ProblemsController#quick_create: a dataset-less problem is
      # invisible to the manage views, so give it a default live dataset.
      problem.save!
      ds = problem.datasets.create!(name: problem.get_next_dataset_name)
      problem.update!(live_dataset: ds)
      link_conduct(problem, conduct)
      @touched << problem
      @io.puts "CREATE    problem '#{name}' (#{describe(attrs)}, available=#{available})"
    rescue ActiveRecord::RecordInvalid => e
      @errors << "problem '#{name}': #{e.record.errors.full_messages.join('; ')}"
    end

    def update_problem(problem, attrs, conduct)
      changed = UPDATABLE.select { |k| normalize(problem[k]) != normalize(attrs[k]) }
      linked = link_conduct(problem, conduct)
      @touched << problem
      if changed.empty? && !linked
        @io.puts "UNCHANGED problem '#{problem.name}'"
      else
        problem.update!(attrs.slice(*changed)) if changed.any?
        notes = changed.dup
        notes << 'conduct linked' if linked
        @io.puts "UPDATE    problem '#{problem.name}' — #{notes.join(', ')}"
      end
    rescue ActiveRecord::RecordInvalid => e
      @errors << "problem '#{problem.name}': #{e.record.errors.full_messages.join('; ')}"
    end

    # Returns true when a link was added.
    def link_conduct(problem, conduct)
      return false if conduct.nil? || problem.tags.include?(conduct)
      problem.tags << conduct
      true
    end

    # Shared reference text → a GroundingMaterial (matched by title), attached
    # to the named kit problems. Only problems declared in this manifest may be
    # targeted — a typo must fail the import, not silently attach nothing.
    def upsert_grounding(spec, kit_names)
      title = spec['title'].to_s.strip
      if title.blank?
        @errors << 'grounding entry without a title'
        return
      end
      body = read_file(spec['file'], "grounding '#{title}'")
      return if body.nil?
      targets = Array(spec['problems']).map(&:to_s)
      unknown = targets - kit_names
      if unknown.any?
        @errors << "grounding '#{title}' names problems not in this manifest: #{unknown.join(', ')}"
        return
      end

      gm = GroundingMaterial.find_or_initialize_by(title: title)
      attrs = { 'body' => body }
      attrs['description'] = spec['description'] if spec.key?('description')
      if gm.new_record?
        gm.assign_attributes(attrs)
        gm.save!
        @io.puts "GROUNDING create '#{title}' (#{body.length} chars ≈ #{gm.compute_estimated_tokens} tokens, re-sent every turn)"
      else
        changed = attrs.keys.select { |k| normalize(gm[k]) != normalize(attrs[k]) }
        if changed.empty?
          @io.puts "GROUNDING unchanged '#{title}'"
        else
          gm.update!(attrs.slice(*changed))
          @io.puts "GROUNDING update '#{title}' — #{changed.join(', ')} (≈ #{gm.compute_estimated_tokens} tokens)"
        end
      end

      linked = targets.select { |name| link_grounding(Problem.find_by(name: name), gm) }
      if linked.any?
        @io.puts "GROUNDING attach '#{title}' -> #{linked.join(', ')}"
      else
        @io.puts "GROUNDING links unchanged '#{title}' (#{targets.size} problem(s))"
      end
    rescue ActiveRecord::RecordInvalid => e
      @errors << "grounding '#{title}': #{e.record.errors.full_messages.join('; ')}"
    end

    # Returns true when a link was added. nil problem = its upsert already
    # failed and recorded an error; nothing to attach to.
    def link_grounding(problem, gm)
      return false if problem.nil? || problem.grounding_materials.include?(gm)
      problem.grounding_materials << gm
      true
    end

    def normalize(v)
      v.is_a?(String) ? v.strip : v
    end

    def describe(attrs)
      "scenario #{attrs['description'].length} chars, briefing #{attrs['viva_prompt'].length} chars, " \
        "caps #{attrs['viva_soft_cap']}/#{attrs['viva_hard_cap']}, daily #{attrs['viva_daily_limit'].inspect}"
    end

    # Every problem this import touched must be startable (blank briefing /
    # missing `# Rubric` heading are the structural checks the platform
    # enforces). Scoped to touched problems so a pre-existing broken viva
    # elsewhere in the DB does not block an unrelated kit.
    def post_check
      @touched.each do |p|
        errs = p.reload.viva_setup_errors
        @errors << "post-check problem '#{p.name}': #{errs.join('; ')}" if errs.any?
      end
    end
  end
end
