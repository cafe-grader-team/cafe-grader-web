# Original from http://snippets.dzone.com/posts/show/4468 by MichaelBoutros
#
# Optimized version which uses to_yaml for content creation and checks
# that models are ActiveRecord::Base models before trying to fetch
# them from database.
namespace :db do
  namespace :fixtures do
    desc 'Dumps all models into fixtures.'
    task :dump => :environment do
      puts "rails root = #{Rails.root}"
      models = Dir.glob(Rails.root.to_s + '/app/models/**.rb').map do |s|
        Pathname.new(s).basename.to_s.gsub(/\.rb$/,'').camelize
      end

      puts "Found models: " + models.join(', ')

      models.each do |m|
        model = m.constantize
        next unless model.ancestors.include?(ActiveRecord::Base)

        puts "Dumping model: " + m
        entries = model.all.order(id: :asc)

        increment = 1

        model_file = Rails.root.to_s + '/test/fixtures2/' + m.underscore.pluralize + '.yml'
        File.open(model_file, 'w') do |f|
          entries.each do |a|
            attrs = a.attributes
            attrs.delete_if{|k,v| v.blank?}

            output = {m + '_' + increment.to_s => attrs}
            f << output.to_yaml.gsub(/^--- \n/,'') + "\n"

            increment += 1
          end
        end
      end
    end
  end
end
