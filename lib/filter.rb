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
          if self.column_names.include?(field)
            value           = fields[field]             
            field_filters   = default.merge(fields_filters[field] || {}).symbolize_keys
            
            if not value.blank? or field_filters[:use_blank]
              filter = field_filters[:type].to_sym
              if TYPES.keys.include?(filter)
                conditions << "`#{field}` #{TYPES[filter]} ?"
                case filter
                  when :li then values << "%#{value}%"
                  when :ll then values << "%#{value}"
                  when :rl then values << "#{value}%"
                  else  values << value
                end          
              end
            end
          end          
        end  # for
        filters.delete(model_name)
        args.delete(model_name)
      end
      
      options[:joins] ||= []
      for reflection_name in self.reflections.keys.map(&:to_s)
        # some params of this reflection has been sent
        reflection_fields = args[reflection_name]
        if reflection_fields.is_a?(Hash)          
          model = reflection_name.singularize.camelcase.constantize rescue nil
          if model
            reflection_filters = filters[reflection_name] || {}
            for field in reflection_fields.keys
              field_filters = default.merge(reflection_filters[field] || {}).symbolize_keys
              value = reflection_fields[field]
              if model.column_names.include?(field) and (not value.blank? or field_filters[:use_blank])
                type_filter = field_filters[:type].to_sym
                if TYPES.keys.include?(type_filter)
                  conditions << "`#{reflection_name.pluralize}`.`#{field}` #{TYPES[type_filter]} ?"
                  case type_filter
                    when :li then values << "%#{value}%"
                    when :ll then values << "%#{value}"
                    when :rl then values << "#{value}%"
                    else  values << value
                  end
                  # load association unless already loaded
                  options[:joins] << reflection_name.to_sym  unless options[:joins].include?(reflection_name)
                end
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
        name, value = field_name_and_value(klass, field)
        method_name = "#{type}_tag"
        [self.send(method_name, name, value, html_options)] + filter_options(klass, field, options)        
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
      [select_tag(name, options_for_select(options[:values] || [], value))] + filter_options(klass, field, options)
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