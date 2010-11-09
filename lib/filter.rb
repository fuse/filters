module Filter
  module Model
    TYPES = {
      :eq => '=',
      :ne => '!=',
      :li => 'LIKE',
      :ll => 'LIKE',
      :rl => 'LIKE',
      :gt => '>',
      :lt => '<',
      :ge => '>=',
      :le => '<='
    }.freeze

    ALL = ':*'

    def filter(args = {}, options = {})
      self.find(:all, options.merge(:conditions => build_conditions(args, options)))
    end

    def filter_count(args = {}, options = {})
      self.count(options.merge(:conditions => build_conditions(args, options)))
    end

    private
    def build_conditions(params = {}, options = {})
      args        = params.dup
      default     = { :use_blank => false, :type => :eq }
      model_name  = self.name.underscore
      # fields values
      fields      = args[model_name]  || {}
      # fields filters
      filters     = args[:filters]    || {}
      conditions  = []
      values      = []

      if fields.any?
        fields_filters  = filters[model_name] || {}
        for field in fields.keys
          # Check if the field reference an other. Exemple: we want all object whose
          # created_at field is > 01/01/09 and < 01/31/09. We have to use two fields
          # with different names, referencing the same table's field.
          related_field = (fields_filters[field] || {})["reference"] || field
          if self.column_names.include?(related_field)
            value           = fields[field]
            field_filters   = default.merge(fields_filters[field] || {}).symbolize_keys
            # Skip filter if the value is blank and we don't care about blank or if we use
            # blank and the value match the special ALL value.
            unless (!field_filters[:use_blank] and value.blank?) or (field_filters[:use_blank] and ALL == value)
              filter = field_filters[:type].to_sym
              if TYPES.keys.include?(filter)
                conditions << "`#{self.table_name}`.`#{related_field}` #{TYPES[filter]} ?"
                case filter
                  when :li then values << "%#{value}%"
                  when :ll then values << "%#{value}"
                  when :rl then values << "#{value}%"
                  else  values << value
                end
              end
            end
          end
        end
        filters.delete(model_name)
        args.delete(model_name)
      end

      options[:joins] ||= []
      for reflection_key in self.reflections.keys
        reflection_name = reflection_key.to_s
        reflection_fields = args[reflection_name]
        # some params of this reflection has been sent
        if reflection_fields.is_a?(Hash)
          reflection = self.reflections[reflection_key]
          reflection_filters = filters[reflection_name] || {}

          for field in reflection_fields.keys
            field_filters = default.merge(reflection_filters[field] || {}).symbolize_keys
            value = reflection_fields[field]
            if reflection.klass.column_names.include?(field) and (not value.blank? or field_filters[:use_blank])
              type_filter = field_filters[:type].to_sym
              if TYPES.keys.include?(type_filter)
                conditions << "`#{reflection.table_name}`.`#{field}` #{TYPES[type_filter]} ?"
                case type_filter
                  when :li then values << "%#{value}%"
                  when :ll then values << "%#{value}"
                  when :rl then values << "#{value}%"
                  else  values << value
                end
                # load association unless already loaded
                options[:joins] << reflection_key  unless options[:joins].include?(reflection_key)
              end
            end
          end
        end
      end

      conditions.join(' AND ').to_a + values
    end
  end

  module View
    TYPES = [ :text_field, :hidden_field, :text_area, :select, :radio_button, :check_box ].freeze

    (TYPES - [:select]).each do |type|
      # Ruby 1.8 doesn't support default parameters for block
      define_method "filter_#{type}" do |klass, field, *args|
        options       = args.shift || {}
        html_options  = args.shift || {}
        name, value   = field_name_and_value(klass, field)
        method_name   = "#{type}_tag"

        if :check_box == type
          [self.send(method_name, name, value, !value.blank?, { :value => "1" }.merge(html_options))] + filter_options(klass, field, options)
        elsif :radio_button == type
          original_value = options[:value]
          raise ArgumentError, "You shoud set a value to the radio button." unless original_value
          self.send(method_name, name, original_value, value == original_value, html_options)
        else
          [self.send(method_name, name, value, html_options)] + filter_options(klass, field, options)
        end
      end
    end

    def filter(type, klass, field, options = {}, html_options = {})
      if TYPES.include?(type)
        method_name = "filter_#{type}"
        self.send(method_name, klass, field, options, html_options) if method_exists?(method_name)
      else
        raise ArgumentError, "Unknown tag."
      end
    end

    def filter_select(klass, field, options = {}, html_options = {})
      name, value = field_name_and_value(klass, field)
      # Convert to an integer if it is (id)
      value = value =~ /^\d+$/ ? value.to_i : value
      [select_tag(name, options_for_select(options[:values] || [], value), html_options)] + filter_options(klass, field, options)
    end

    private
    def field_value(klass, field)
      params[klass][field] rescue ""
    end

    def field_name(klass, field)
      "#{klass}[#{field}]"
    end

    def field_name_and_value(klass, field)
      [field_name(klass, field), field_value(klass, field)]
    end

    def filter_options(klass, field, options)
      return [] unless options

      option_basename = "filters[#{klass}][#{field}]"
      # delete values key for select
      options.delete(:values)
      options.keys.inject([]) { |nodes, key|
        nodes << hidden_field_tag("#{option_basename}[#{key}]", options[key])
      }
    end
  end
end

ActiveRecord::Base.send :extend, Filter::Model
ActionView::Base.send :include, Filter::View
